#!/usr/bin/env python3
"""Plan or explicitly publish the single pinned CodeWeavers Wine source archive."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile

from publish_resources import ManifestError
from upload_resources import S3, check_capacity, digest, https_base, verify_public

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_METADATA = ROOT / "Arclume/Resources/nefinita-wine-source.json"
ARCHIVE_NAME = "crossover-sources-26.3.0.tar.gz"
VERSION = "26.3.0"
SHA256 = "ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872"
BYTE_COUNT = 149054023
ORIGIN_URL = "https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz"
OBJECT_PREFIX = "components/source/codeweavers-wine/org.codeweavers.wine-source"
PUBLISH_LOCK = ROOT / "build/resource-upload/.publish.lock"


def expected_object_key(version: str, sha256: str, archive: str) -> str:
    return f"{OBJECT_PREFIX}/{version}/{sha256}/{archive}"


def validate_metadata(value: dict) -> dict:
    """Validate the immutable, user-approved source package descriptor."""
    if not isinstance(value, dict):
        raise ManifestError("Invalid CodeWeavers source metadata")
    if (value.get("schemaVersion") != 1
            or value.get("version") != VERSION
            or value.get("archive") != ARCHIVE_NAME
            or value.get("sha256") != SHA256
            or value.get("byteCount") != BYTE_COUNT
            or value.get("originURL") != ORIGIN_URL):
        raise ManifestError("Metadata does not match the approved CodeWeavers source archive")

    archive = value["archive"]
    sha256 = value["sha256"]
    if (PurePosixPath(archive).name != archive or "/" in archive or "\\" in archive
            or not re.fullmatch(r"[a-f0-9]{64}", sha256)):
        raise ManifestError("Invalid source archive name or checksum")

    key = expected_object_key(value["version"], sha256, archive)
    if value.get("objectKey") != key:
        raise ManifestError("Source object key does not match its pinned identity")
    return value


def load_metadata(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        raise ManifestError("Could not read the CodeWeavers source metadata") from None
    return validate_metadata(value)


def prepare_object(archive_path: Path, metadata: dict):
    metadata = validate_metadata(metadata)
    try:
        archive = archive_path.expanduser().resolve(strict=True)
        if not archive.is_file() or archive.name != metadata["archive"]:
            raise ManifestError("Select the pinned CodeWeavers source archive")
        if archive.stat().st_size != metadata["byteCount"]:
            raise ManifestError("Source archive size does not match its pinned metadata")
        actual_sha = digest(archive)
    except OSError:
        raise ManifestError("Could not read the selected source archive") from None
    if actual_sha != metadata["sha256"]:
        raise ManifestError("Source archive checksum does not match its pinned metadata")
    asset = {"sha256": actual_sha, "byteCount": archive.stat().st_size}
    return metadata["objectKey"], archive, asset


def publish_object(item, bucket: str) -> dict:
    if not bucket:
        raise ManifestError("Configure the release bucket before uploading")
    public_base = https_base(os.environ.get("ARCLUME_RESOURCE_BASE_URL"))
    key, archive, asset = item
    staging = PUBLISH_LOCK.parent
    staging.mkdir(parents=True, exist_ok=True)
    with PUBLISH_LOCK.open("a") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ManifestError("Another local publisher is active") from None
        with tempfile.TemporaryDirectory(prefix="arclume-wine-source-") as name:
            temporary = Path(name)
            config = temporary / "aws-config"
            config.write_text("[default]\ns3 =\n    addressing_style = path\n")
            service = S3(bucket, config)
            inventory = service.inventory()
            capacity = check_capacity(inventory, {key: asset["byteCount"]})
            service.put(key, archive, asset, inventory, temporary)
            verify_public(public_base, key, asset)
    return {
        "capacity": capacity,
        "verified": [{"key": key, **asset}],
        "uploaded": True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True,
                        help="Existing crossover-sources-26.3.0.tar.gz; never downloaded by this script")
    parser.add_argument("--metadata", type=Path, default=DEFAULT_METADATA)
    parser.add_argument("--bucket", default=os.environ.get("ARCLUME_RESOURCE_BUCKET"))
    parser.add_argument("--execute", action="store_true", help="Upload and verify; omitted means dry run")
    args = parser.parse_args()

    metadata = load_metadata(args.metadata)
    item = prepare_object(args.archive, metadata)
    key, _, asset = item
    report = {
        "kind": "codeweavers-wine-source",
        "version": metadata["version"],
        "originURL": metadata["originURL"],
        "objects": 1,
        "objectKey": key,
        **asset,
        "uploaded": False,
        "verified": [],
    }
    if args.execute:
        report.update(publish_object(item, args.bucket))
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2))


if __name__ == "__main__":
    try:
        main()
    except ManifestError as error:
        # Keep output independent of local paths, credentials, and service endpoints.
        raise SystemExit(str(error)) from None
    except (OSError, subprocess.SubprocessError):
        raise SystemExit("Source publication failed; no automatic cleanup was attempted") from None
