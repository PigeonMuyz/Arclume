#!/usr/bin/env python3
"""Stage a release plan, or explicitly upload it using environment-only S3 credentials."""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request

from publish_resources import (
    INDEX_PREFIX, ManifestError, ObjectRef, app_object_key, catalog_object_key,
    component_object_key, plan_retention, release_index_key, validate_release_index,
)

QUOTA = 15 * 1024**3
HEADROOM = 1024 * 1024


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()


def https_base(value):
    parsed = urllib.parse.urlsplit(value or "")
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ManifestError("A valid HTTPS service configuration is required")
    return value.rstrip("/")


def check_capacity(existing, additions, quota=QUOTA):
    current = sum(item["Size"] for item in existing.values())
    incoming = sum(size for key, size in additions.items() if key not in existing)
    if current + incoming + HEADROOM > quota:
        raise ManifestError("Storage quota would be exceeded; no upload or deletion was performed")
    return {"currentBytes": current, "newBytes": incoming, "quotaBytes": quota}


class S3:
    def __init__(self, bucket, config):
        self.bucket = bucket
        self.env = dict(os.environ, AWS_CONFIG_FILE=str(config), AWS_PAGER="",
                        AWS_REQUEST_CHECKSUM_CALCULATION="when_required",
                        AWS_RESPONSE_CHECKSUM_VALIDATION="when_required")
        https_base(self.env.get("AWS_ENDPOINT_URL"))
        for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_DEFAULT_REGION"):
            if not self.env.get(key):
                raise ManifestError("Release storage credentials are not configured")
        if not shutil.which("aws"):
            raise ManifestError("Install AWS CLI before executing a release upload")

    def call(self, operation, *args):
        result = subprocess.run(["aws", "s3api", operation, "--bucket", self.bucket,
                                 *args, "--output", "json"], env=self.env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1800)
        if result.returncode:
            # AWS errors can contain endpoints and request identifiers.
            raise ManifestError(f"Storage operation failed: {operation}; no automatic cleanup attempted")
        return json.loads(result.stdout or b"{}")

    def inventory(self):
        # Avoid hidden historical versions consuming quota or ambiguous deletes.
        if self.call("get-bucket-versioning").get("Status") in ("Enabled", "Suspended"):
            raise ManifestError("Versioned buckets require a separately reviewed retention workflow")
        result = {}
        token = None
        while True:
            args = ["--no-paginate"]
            if token:
                args += ["--continuation-token", token]
            page = self.call("list-objects-v2", *args)
            for item in page.get("Contents", []):
                result[item["Key"]] = item
            if not page.get("IsTruncated"):
                return result
            token = page.get("NextContinuationToken")
            if not token:
                raise ManifestError("Incomplete storage inventory; refusing release")

    def indexes(self, inventory, temporary):
        documents = []
        for key in sorted(inventory):
            if not key.startswith(INDEX_PREFIX):
                continue
            if not key.endswith(".json") or inventory[key]["Size"] > 1024 * 1024:
                raise ManifestError("Invalid release index; refusing cleanup")
            target = temporary / "index.json"
            self.call("get-object", "--key", key, str(target))
            value = json.loads(target.read_text())
            validate_release_index(key, value)
            documents.append((key, value))
        return documents

    def verify(self, key, expected, temporary):
        target = temporary / "verify-object"
        self.call("get-object", "--key", key, str(target))
        try:
            if target.stat().st_size != expected["byteCount"] or digest(target) != expected["sha256"]:
                raise ManifestError("Remote object checksum mismatch; refusing overwrite or cleanup")
        finally:
            target.unlink(missing_ok=True)

    def put(self, key, path, expected, inventory, temporary):
        if key not in inventory:
            self.call("put-object", "--key", key, "--body", str(path),
                      "--if-none-match", "*", "--metadata", f"sha256={expected['sha256']}")
        self.verify(key, expected, temporary)

def verify_public(base, key, expected):
    url = base + "/" + urllib.parse.quote(key, safe="/")
    result = hashlib.sha256()
    count = 0
    with urllib.request.urlopen(url, timeout=120) as response:
        if response.status != 200 or urllib.parse.urlsplit(response.url).scheme != "https":
            raise ManifestError("Public download verification failed")
        while block := response.read(1024 * 1024):
            count += len(block)
            if count > expected["byteCount"]:
                raise ManifestError("Public object exceeds its pinned size")
            result.update(block)
    if count != expected["byteCount"] or result.hexdigest() != expected["sha256"]:
        raise ManifestError("Public download checksum mismatch")


def stage(args, temporary):
    staging = args.staging.resolve()
    catalog_path = staging / "resources.json"
    catalog = json.loads(catalog_path.read_text())
    dmg = args.dmg.resolve(strict=True)
    dmg_sha = digest(dmg)
    app = dict(id="arclume", version=args.app_version, build=args.app_build,
               fileName=dmg.name, sha256=dmg_sha, byteCount=dmg.stat().st_size,
               key=app_object_key(args.app_version, args.app_build, dmg_sha, dmg.name))
    cat = dict(key=catalog_object_key(args.app_version, args.app_build),
               sha256=digest(catalog_path), byteCount=catalog_path.stat().st_size)
    objects = [(app["key"], dmg, app), (cat["key"], catalog_path, cat)]
    components = []
    for item in catalog["components"]:
        key = component_object_key(item)
        path = (staging / key).resolve(strict=True)
        if not path.is_relative_to(staging):
            raise ManifestError("Staged component escapes its directory")
        if path.stat().st_size != item["byteCount"] or digest(path) != item["sha256"]:
            raise ManifestError("Staged component differs from its reviewed catalog")
        components.append(dict(item, key=key))
        objects.append((key, path, item))
    # Checksum lives beside its DMG. It is supplemental, never a trust root.
    checksum = temporary / (dmg.name + ".sha256")
    checksum.write_text(f"{dmg_sha}  {dmg.name}\n")
    checksum_ref = dict(key=app["key"] + ".sha256", sha256=digest(checksum), byteCount=checksum.stat().st_size)
    objects.append((checksum_ref["key"], checksum, checksum_ref))
    notices = staging / "licenses" / components[0]["id"] / components[0]["version"] / "THIRD-PARTY-NOTICES.md"
    notice_ref = dict(key=cat["key"].rsplit("/", 1)[0] + "/THIRD-PARTY-NOTICES.md",
                      sha256=digest(notices), byteCount=notices.stat().st_size)
    objects.append((notice_ref["key"], notices, notice_ref))
    runtimes = []
    for runtime in catalog["runtimes"]:
        match = next((item for item in components if item["id"] == runtime["id"]
                      and item["version"] == runtime["version"]
                      and item["sha256"] == runtime["archive"]["sha256"]), None)
        if match is None:
            raise ManifestError("Runtime does not match a staged component")
        runtimes.append(dict(runtime, componentKey=match["key"]))
    index = dict(schemaVersion=1, kind="arclume-resource-release-index", supported=True,
                 publishedAt=dt.datetime.now(dt.timezone.utc).isoformat(), app=app,
                 catalog=cat, components=components, runtimes=runtimes,
                 runtimeOptions=catalog["runtimeOptions"], appChecksum=checksum_ref, notice=notice_ref)
    key = release_index_key(args.app_version, args.app_build)
    validate_release_index(key, index)
    return key, index, objects


def stage_components(staging):
    """Pre-upload reviewed components without inventing an App release/index."""
    staging = staging.resolve()
    catalog = json.loads((staging / "resources.json").read_text())
    if catalog.get("schemaVersion") != 1 or not catalog.get("components"):
        raise ManifestError("Invalid staged component catalog")
    objects = []
    for item in catalog["components"]:
        key = component_object_key(item)
        path = (staging / key).resolve(strict=True)
        if not path.is_relative_to(staging):
            raise ManifestError("Staged component escapes its directory")
        if path.stat().st_size != item["byteCount"] or digest(path) != item["sha256"]:
            raise ManifestError("Staged component differs from its reviewed catalog")
        objects.append((key, path, item))
        notice_key = f"licenses/{item['id']}/{item['version']}/THIRD-PARTY-NOTICES.md"
        notice = (staging / notice_key).resolve(strict=True)
        if not notice.is_relative_to(staging):
            raise ManifestError("Staged notice escapes its directory")
        objects.append((notice_key, notice, dict(sha256=digest(notice), byteCount=notice.stat().st_size)))
    if len({key for key, _, _ in objects}) != len(objects):
        raise ManifestError("Duplicate staged component objects")
    return objects


def publish_components(args):
    objects = stage_components(args.staging)
    report = dict(mode="components-only", objects=len(objects),
                  byteCount=sum(asset["byteCount"] for _, _, asset in objects), uploaded=False)
    if args.execute:
        if not args.bucket:
            raise ManifestError("Configure the release bucket before uploading")
        with tempfile.TemporaryDirectory(prefix="arclume-components-") as name:
            temporary = Path(name)
            config = temporary / "aws-config"
            config.write_text("[default]\ns3 =\n    addressing_style = path\n    max_concurrent_requests = 2\n")
            service = S3(args.bucket, config)
            public_base = https_base(os.environ.get("ARCLUME_RESOURCE_BASE_URL"))
            with (args.staging / ".publish.lock").open("a") as lock:
                try:
                    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise ManifestError("Another local publisher is active") from None
                inventory = service.inventory()
                report["capacity"] = check_capacity(inventory, {key: asset["byteCount"] for key, _, asset in objects})
                verified = []
                for number, (key, path, asset) in enumerate(objects, 1):
                    print(f"Verifying component object {number}/{len(objects)}: {path.name}", flush=True)
                    service.put(key, path, asset, inventory, temporary)
                    verify_public(public_base, key, asset)
                    verified.append(dict(key=key, sha256=asset["sha256"], byteCount=asset["byteCount"]))
                    # Preserve an address-free receipt after every completed object.
                    report["verified"] = verified
                    args.report.parent.mkdir(parents=True, exist_ok=True)
                    args.report.write_bytes(encoded(report))
                report["uploaded"] = True
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_bytes(encoded(report))
    print(json.dumps(report, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staging", type=Path, default=Path("build/resource-upload"))
    parser.add_argument("--dmg", type=Path)
    parser.add_argument("--app-version")
    parser.add_argument("--app-build")
    parser.add_argument("--components-only", action="store_true", help="Only prepare/upload components and notices; never publishes an App index or deletes objects")
    parser.add_argument("--bucket", default=os.environ.get("ARCLUME_RESOURCE_BUCKET"))
    parser.add_argument("--execute", action="store_true", help="Upload and verify; omitted means local-only plan")
    parser.add_argument("--apply-retention", action="store_true", help="Explicitly remove only verified expired objects after upload")
    parser.add_argument("--report", type=Path, default=Path("build/resource-upload/publish-report.json"))
    args = parser.parse_args()
    if args.components_only:
        if args.apply_retention or args.dmg or args.app_version or args.app_build:
            parser.error("--components-only cannot publish an App or apply retention")
        publish_components(args)
        return
    if not all((args.dmg, args.app_version, args.app_build)):
        parser.error("App publishing requires --dmg, --app-version and --app-build")
    if args.apply_retention and not args.execute:
        parser.error("--apply-retention requires --execute")
    with tempfile.TemporaryDirectory(prefix="arclume-publish-") as directory, contextlib.ExitStack() as stack:
        temporary = Path(directory)
        index_key, index, objects = stage(args, temporary)
        report = {"release": index_key, "objects": len(objects),
                  "byteCount": sum(item[2]["byteCount"] for item in objects), "uploaded": False}
        if args.execute:
            if not args.bucket:
                raise ManifestError("Configure the release bucket before uploading")
            config = temporary / "aws-config"
            config.write_text("[default]\ns3 =\n    addressing_style = path\n    max_concurrent_requests = 2\n")
            service = S3(args.bucket, config)
            public_base = https_base(os.environ.get("ARCLUME_RESOURCE_BASE_URL"))
            # Garage's conditional-write support differs from AWS. Serialize
            # local publishers here and CI publishers with workflow concurrency;
            # do not treat an S3 If-None-Match header as a distributed lock.
            args.staging.mkdir(parents=True, exist_ok=True)
            lock = stack.enter_context((args.staging / ".publish.lock").open("a"))
            try:
                fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ManifestError("Another local publisher is active") from None
            inventory = service.inventory()
            documents = service.indexes(inventory, temporary)
            old = next((value for key, value in documents if key == index_key), None)
            if old:
                index["publishedAt"] = old["publishedAt"]
                if encoded(index) != encoded(old):
                    raise ManifestError("This release identity is immutable; increment the App build number")
            index_path = temporary / "release-index.json"
            index_path.write_bytes(encoded(index))
            index_asset = dict(sha256=digest(index_path), byteCount=index_path.stat().st_size)
            additions = {key: asset["byteCount"] for key, _, asset in objects}
            additions[index_key] = index_asset["byteCount"]
            report["capacity"] = check_capacity(inventory, additions)
            for key, path, asset in objects:
                service.put(key, path, asset, inventory, temporary)
                verify_public(public_base, key, asset)
            # The index is the commit record: last to publish, never overwritten.
            service.put(index_key, index_path, index_asset, inventory, temporary)
            report["uploaded"] = True
            current = service.inventory()
            documents = service.indexes(current, temporary)
            plan = plan_retention(documents, {ObjectRef(key) for key in current})
            report["retention"] = plan.as_json()
            if args.apply_retention:
                if plan.blocked_reason:
                    raise ManifestError("Retention is blocked; uploaded objects have been preserved")
                for item in plan.delete_objects:
                    service.verify(item["key"], item, temporary)
                # Re-read indexes before deleting. Concurrent/new references abort cleanup.
                refreshed = service.inventory()
                fresh_documents = service.indexes(refreshed, temporary)
                fresh = plan_retention(fresh_documents, {ObjectRef(key) for key in refreshed})
                if fresh.as_json() != plan.as_json():
                    raise ManifestError("Release inventory changed; cleanup cancelled")
                for item in plan.delete_objects:
                    service.call("delete-object", "--key", item["key"])
                report["deletedObjects"] = len(plan.delete_objects)
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_bytes(encoded(report))
        print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never print raw HTTP/AWS errors or credentials from the environment.
        print(str(error) if isinstance(error, ManifestError) else "Release storage operation failed; inspect local inputs and configuration.")
        raise SystemExit(1)
