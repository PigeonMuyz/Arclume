#!/usr/bin/env python3
"""Stage immutable component files locally. Never uploads or reads server credentials."""
import argparse
import gzip
import hashlib
import json
import pathlib
import shutil
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Arclume/Resources/OnlineGameDependencies"
CATALOG = SOURCE / "downloadable-resources.json"


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def reject_pointer(path):
    if path.is_file() and not path.is_symlink():
        with path.open("rb") as stream:
            if stream.read(64).startswith(b"version https://git-lfs.github.com/spec/v1"):
                raise SystemExit(f"Missing LFS content: {path.relative_to(ROOT)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "build/resource-upload")
    parser.add_argument("--write-catalog", action="store_true", help="Explicitly update the pinned App catalog")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    runtime = json.loads((SOURCE / "arclume-wine-runtime.json").read_text())
    libs = ROOT / "Arclume/Libs"
    for path in libs.rglob("*"):
        reject_pointer(path)
    lib_archive = args.output / "compatibility-libs.tar.gz"
    # Stable metadata and compression headers make the pinned hash reproducible in CI.
    with lib_archive.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as gz, tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tar:
        for path in [libs] + sorted(libs.rglob("*")):
            if path.name == ".DS_Store":
                continue
            entry = tar.gettarinfo(str(path), arcname=str(path.relative_to(libs.parent)))
            entry.uid = entry.gid = 0
            entry.uname = entry.gname = ""
            entry.mtime = 0
            entry.pax_headers = {}
            if entry.isfile():
                with path.open("rb") as stream:
                    tar.addfile(entry, stream)
            else:
                tar.addfile(entry)
    specs = [
        ("runtime", "arclume-wine", runtime["id"], runtime["version"], SOURCE / runtime["archive"]["name"], False),
        ("graphics", "d3dmetal", "d3dmetal3", "3", SOURCE / "d3dMetal3.tar.xz", False),
        ("graphics", "d3dmetal", "d3dmetal4", "4-beta2", SOURCE / "d3dMetal4.tar.xz", False),
        ("graphics", "dxmt", "dxmt", "0.80", SOURCE / "dxmt.tar.gz", False),
        ("media", "gstreamer", "gstreamer", "1.28.1", SOURCE / "gstreamer-framework.tar.xz", False),
        ("fonts", "windows-fonts", "fonts", "2026.09", SOURCE / "fonts.tar.xz", False),
        ("graphics", "nvngx", "nvngx-jx3", "2026.09", SOURCE / "nvngx-jx3.tar.xz", False),
        ("compatibility", "arclume-libs", "compatibility-libs", "2026.09.24", lib_archive, True),
    ]
    components = []
    for component_type, name, identifier, version, archive, unpack in specs:
        reject_pointer(archive)
        sha = digest(archive)
        if identifier == runtime["id"] and sha != runtime["archive"]["sha256"]:
            raise SystemExit("Wine archive differs from Runtime manifest")
        item = dict(type=component_type, name=name, id=identifier, version=version, fileName=archive.name, sha256=sha, byteCount=archive.stat().st_size, unpack=unpack)
        components.append(item)
        target = args.output / "components" / component_type / name / identifier / version / sha / archive.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(archive, target)
        notices = args.output / "licenses" / identifier / version
        notices.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "THIRD-PARTY-NOTICES.md", notices / "THIRD-PARTY-NOTICES.md")
    catalog = dict(schemaVersion=1, components=components, runtimes=[runtime], runtimeOptions=[dict(
        id=runtime["id"], provider="Arclume", strategies=[dict(delivery="precompiled", componentID=runtime["id"])])])
    # Dependency declarations are reviewed for each engine version, not copied to a new runtime.
    pinned_requirements = json.loads(CATALOG.read_text()).get("requirements", [])
    if not any(item["runtimeID"] == runtime["id"] and item["runtimeVersion"] == runtime["version"]
               for item in pinned_requirements):
        raise SystemExit("Review component requirements for this Runtime version before staging")
    catalog["requirements"] = pinned_requirements
    rendered = json.dumps(catalog, indent=2, ensure_ascii=False) + "\n"
    if args.write_catalog:
        CATALOG.write_text(rendered)
    elif json.loads(CATALOG.read_text()) != catalog:
        raise SystemExit("Staged resources do not match the pinned catalog; review before updating it")
    (args.output / "resources.json").write_text(rendered)
    print(f"Prepared {len(components)} components, {sum(item['byteCount'] for item in components)} bytes; no upload performed.")
    print(f"Catalog SHA-256: {digest(args.output / 'resources.json')}")


if __name__ == "__main__":
    main()
