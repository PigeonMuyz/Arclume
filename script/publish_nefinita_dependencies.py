#!/usr/bin/env python3
"""Stage all authenticated Nefinita dependencies, then optionally publish immutable mirrors."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

from upload_resources import S3, ManifestError, check_capacity, digest, encoded, https_base, verify_public

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "components/source"


def assignments(text):
    result = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r'([A-Z][A-Z0-9_]*)="([^"$`\\]*)"', line)
        if not match or match[1] in result:
            raise ManifestError("Invalid authenticated source lock")
        result[match[1]] = match[2]
    return result


def authenticated_inputs(source):
    recipe = json.loads((ROOT / "Arclume/Resources/nefinita-build-recipe.json").read_text())
    source = source.resolve(strict=True)
    for name, sha in recipe["files"].items():
        path = source / name
        if path.is_symlink() or not path.resolve().is_relative_to(source) or digest(path) != sha:
            raise ManifestError("Build input differs from the pinned recipe")
    return recipe


def descriptors(source):
    recipe = authenticated_inputs(source)
    result = []
    for name in ("FREETYPE_SOURCE.lock", "DEPENDENCIES.lock"):
        lock = assignments((source / "sources" / name).read_text())
        for key in sorted(lock):
            if not key.endswith("_ARCHIVE"):
                continue
            stem = key.removesuffix("_ARCHIVE")
            identity = stem.lower().replace("_", "-")
            item = dict(id=identity, version=lock[stem + "_VERSION"], archive=lock[key],
                        originURL=lock[stem + "_URL"], sha256=lock[stem + "_SHA256"])
            if (not re.fullmatch(r"[A-Za-z0-9._-]+", item["archive"])
                    or not re.fullmatch(r"[a-f0-9]{64}", item["sha256"])):
                raise ManifestError("Invalid dependency identity")
            https_base(item["originURL"])
            result.append(item)
    patch = assignments((source / "sources/FINEWINE_PATCHSET.lock").read_text())
    revision = patch["FINEWINE_PATCHSET_REVISION"]
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ManifestError("Invalid patch revision")
    result.append(dict(id="finewine", version=revision,
                       archive=f"finewine-{revision}.tar.gz",
                       originURL=f"https://codeload.github.com/stoicswe/Endfield_FineWine/tar.gz/{revision}"))
    return recipe, result


def verify_patches(archive, source):
    # Read members without extraction. The recipe's authenticated hash list is the trust root.
    expected = {}
    for line in (source / "patches/finewine/PATCHES.sha256").read_text().splitlines():
        if line.strip():
            sha, path = line.split()
            expected[path] = sha
    import hashlib
    found = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            relative = member.name.partition("/")[2]
            if relative not in expected:
                continue
            if relative in found or not member.isfile() or member.size > 8 * 1024 * 1024:
                raise ManifestError("Invalid patch archive")
            with tar.extractfile(member) as stream:
                found[relative] = hashlib.sha256(stream.read()).hexdigest()
    if found != expected:
        raise ManifestError("Patch archive does not match the authenticated patch list")


def stage_one(item, source, staging):
    item = dict(item)
    target = staging / "dependency-inputs" / item["archive"]
    target.parent.mkdir(parents=True, exist_ok=True)
    valid = target.is_file() and (item.get("sha256") is None or digest(target) == item["sha256"])
    if not valid:
        part = target.with_suffix(target.suffix + ".part")
        result = subprocess.run(["/usr/bin/curl", "-fLsS", "--retry", "3", "--retry-all-errors",
                                 "--connect-timeout", "20", "--max-time", "600",
                                 "--proto", "=https", "--proto-redir", "=https",
                                 "-o", str(part), item["originURL"]], capture_output=True, timeout=2500)
        if result.returncode:
            raise ManifestError(f"Dependency download failed: {item['id']}")
        if item.get("sha256") and digest(part) != item["sha256"]:
            raise ManifestError(f"Dependency checksum mismatch: {item['id']}")
        part.replace(target)
    if item["id"] == "finewine":
        verify_patches(target, source)
    item["sha256"] = digest(target)
    item["byteCount"] = target.stat().st_size
    item["objectKey"] = f"{PREFIX}/{item['id']}/dev.nefinita.source.{item['id']}/{item['version']}/{item['sha256']}/{item['archive']}"
    print(f"Verified dependency: {item['id']}", file=sys.stderr, flush=True)
    return item, target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Maintainer-only authenticated recipe cache")
    parser.add_argument("--staging", type=Path, default=ROOT / "build/resource-upload")
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    recipe, items = descriptors(args.source)
    args.staging.mkdir(parents=True, exist_ok=True)
    with (args.staging / ".publish.lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        with ThreadPoolExecutor(max_workers=3) as pool:
            objects = list(pool.map(lambda item: stage_one(item, args.source, args.staging), items))
        manifest = dict(schemaVersion=1, revision=recipe["revision"], materials=[item for item, _ in objects])
        if args.execute:
            # The checked-in metadata must have been reviewed before any external writes.
            pinned = json.loads((ROOT / "Arclume/Resources/nefinita-build-materials.json").read_text())
            if manifest != pinned:
                raise ManifestError("Dependency manifest requires review before publication")
            bucket = os.environ.get("ARCLUME_RESOURCE_BUCKET")
            if not bucket:
                raise ManifestError("Configure the release bucket before uploading")
            base = https_base(os.environ.get("ARCLUME_RESOURCE_BASE_URL"))
            report = dict(kind="nefinita-dependencies", uploaded=False, verified=[])
            with tempfile.TemporaryDirectory(prefix="arclume-dependencies-") as name:
                temporary = Path(name)
                config = temporary / "aws-config"
                config.write_text("[default]\ns3 =\n    addressing_style = path\n")
                service = S3(bucket, config)
                inventory = service.inventory()
                report["capacity"] = check_capacity(inventory, {item["objectKey"]: item["byteCount"] for item, _ in objects})
                for item, file in objects:
                    service.put(item["objectKey"], file, item, inventory, temporary)
                    verify_public(base, item["objectKey"], item)
                    report["verified"].append(item["objectKey"])
                    (args.staging / "nefinita-dependencies-upload-report.json").write_bytes(encoded(report))
                    print(f"Published dependency: {item['id']}", file=sys.stderr, flush=True)
            report["uploaded"] = True
            (args.staging / "nefinita-dependencies-upload-report.json").write_bytes(encoded(report))
        print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ManifestError, OSError, ValueError, subprocess.SubprocessError) as error:
        # Never expose credential values or endpoint-bearing transport errors.
        message = str(error) if isinstance(error, ManifestError) else "Dependency publication failed; no remote cleanup performed"
        raise SystemExit(message) from None
