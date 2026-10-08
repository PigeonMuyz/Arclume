#!/usr/bin/env python3
"""Publish only the reviewed Nefinita recipe inputs; never a checkout or DMG."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile

from upload_resources import S3, ManifestError, check_capacity, digest, encoded, https_base, verify_public

ROOT = Path(__file__).resolve().parents[1]


def object_keys(recipe):
    revision = recipe.get("revision", "")
    version = recipe.get("version", "")
    if (recipe.get("schemaVersion") != 1 or recipe.get("provider") != "Nefinita"
            or not re.fullmatch(r"[a-f0-9]{40}", revision)
            or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version)
            or not recipe.get("files")):
        raise ManifestError("Invalid pinned Nefinita recipe")
    result = {}
    for path, sha in recipe["files"].items():
        if (not path or PurePosixPath(path).is_absolute() or "\\" in path
                or any(part in ("", ".", "..") for part in path.split("/"))
                or not re.fullmatch(r"[a-f0-9]{64}", sha)):
            raise ManifestError("Invalid recipe path or checksum")
        result[path] = f"components/build-recipe/nefinita/dev.nefinita.build-recipe/{version}-{revision[:8]}/{sha}/{path}"
    return result


def stage(recipe, staging):
    objects = []
    for path, key in sorted(object_keys(recipe).items()):
        target = staging / key
        expected = recipe["files"][path]
        if not target.is_file() or digest(target) != expected:
            # Authenticated fetch is a publisher-only operation. No credentials enter the App.
            endpoint = f"repos/nefinita/mac-gamestater/contents/runtime/{path}?ref={recipe['revision']}"
            result = subprocess.run(["gh", "api", endpoint, "-H", "Accept: application/vnd.github.raw+json"],
                                    capture_output=True, timeout=120)
            if result.returncode:
                raise ManifestError(f"Could not fetch pinned input: {path}")
            if not 0 < len(result.stdout) <= 2 * 1024 * 1024 or hashlib.sha256(result.stdout).hexdigest() != expected:
                raise ManifestError(f"Pinned input checksum mismatch: {path}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(result.stdout)
        objects.append((key, target, dict(sha256=expected, byteCount=target.stat().st_size)))
    return objects


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--staging", type=Path, default=ROOT / "build/resource-upload")
    args = parser.parse_args()
    recipe = json.loads((ROOT / "Arclume/Resources/nefinita-build-recipe.json").read_text())
    args.staging.mkdir(parents=True, exist_ok=True)
    # Share the existing publisher lock. No retention or remote deletion is permitted here.
    with (args.staging / ".publish.lock").open("a") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        objects = stage(recipe, args.staging)
        report = dict(kind="nefinita-build-inputs", version=recipe["version"], revision=recipe["revision"],
                      objects=len(objects), byteCount=sum(item[2]["byteCount"] for item in objects),
                      uploaded=False, verified=[])
        report_path = args.staging / "nefinita-recipe-upload-report.json"
        if args.execute:
            bucket = os.environ.get("ARCLUME_RESOURCE_BUCKET")
            if not bucket:
                raise ManifestError("Configure the release bucket before uploading")
            base = https_base(os.environ.get("ARCLUME_RESOURCE_BASE_URL"))
            with tempfile.TemporaryDirectory(prefix="arclume-recipe-publish-") as temporary:
                temporary = Path(temporary)
                config = temporary / "aws-config"
                config.write_text("[default]\ns3 =\n    addressing_style = path\n")
                service = S3(bucket, config)
                inventory = service.inventory()
                report["capacity"] = check_capacity(inventory, {key: item["byteCount"] for key, _, item in objects})
                for key, path, item in objects:
                    service.put(key, path, item, inventory, temporary)
                    verify_public(base, key, item)
                    report["verified"].append(dict(key=key, **item))
                    report_path.write_bytes(encoded(report))
                    print(f"Verified {len(report['verified'])}/{len(objects)}: {path.name}", flush=True)
                report["uploaded"] = True
        report_path.write_bytes(encoded(report))
        print(json.dumps({key: report[key] for key in ("version", "objects", "byteCount", "uploaded")}))


if __name__ == "__main__":
    try:
        main()
    except (ManifestError, OSError, subprocess.SubprocessError):
        # Transport exceptions can contain private endpoints. Keep publisher output URL-free.
        raise SystemExit("Recipe publication failed; no remote objects were deleted. Check credentials, pinned inputs and connectivity.") from None
