#!/usr/bin/env python3
"""Publish immutable Arclume resources and plan conservative S3 retention.

The retention model below is deliberately independent of AWS. Publishing and
deletion are explicit CLI operations; importing this module performs no I/O.
"""

from __future__ import annotations

import dataclasses
import datetime as dt
import re
from collections.abc import Collection, Iterable, Mapping

APP_ID = "arclume"
INDEX_SCHEMA_VERSION = 1
INDEX_PREFIX = "indexes/apps/arclume/"
COMPONENT_PREFIX = "components"
RELEASE_INDEX_PREFIX = "indexes/apps/arclume"
SHA256_PATTERN = re.compile(r"^[a-f0-9]{64}$")
_VERSION_TOKENS = re.compile(r"\d+|[A-Za-z]+")


class ManifestError(ValueError):
    """An uploaded or staged manifest cannot safely authorize object use."""


@dataclasses.dataclass(frozen=True)
class ObjectRef:
    key: str
    version_id: str | None = None


@dataclasses.dataclass(frozen=True)
class RetentionPlan:
    keep_app_releases: tuple[str, ...]
    keep_runtime_versions: tuple[tuple[str, str], ...]
    delete_objects: tuple[dict, ...]
    blocked_reason: str | None = None
    compatibility_protected: tuple[dict, ...] = ()
    retained_object_count: int = 0
    retained_byte_count: int = 0

    def as_json(self) -> dict:
        return {
            "schemaVersion": 1,
            "blockedReason": self.blocked_reason,
            "keepAppReleases": list(self.keep_app_releases),
            "keepRuntimeVersions": [
                {"id": runtime_id, "version": version}
                for runtime_id, version in self.keep_runtime_versions
            ],
            "compatibilityProtected": {
                "count": len(self.compatibility_protected),
                "byteCount": sum(item["byteCount"] for item in self.compatibility_protected),
                "objects": list(self.compatibility_protected),
            },
            "retained": {
                "count": self.retained_object_count,
                "byteCount": self.retained_byte_count,
            },
            "delete": list(self.delete_objects),
        }


def _required_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestError(f"{field} must be a non-empty string")
    return value


def safe_segment(value: object, field: str) -> str:
    text = _required_string(value, field)
    if text in {".", ".."} or "/" in text or "\\" in text or any(ord(c) < 32 for c in text):
        raise ManifestError(f"{field} is not a safe object-key segment")
    return text


def validate_sha256(value: object, field: str = "sha256") -> str:
    text = _required_string(value, field)
    if not SHA256_PATTERN.fullmatch(text):
        raise ManifestError(f"{field} must be a lowercase SHA-256 digest")
    return text


def validate_byte_count(value: object, field: str = "byteCount") -> int:
    if type(value) is not int or value <= 0:
        raise ManifestError(f"{field} must be a positive integer")
    return value


def normalize_version_id(value: object) -> str | None:
    if value is None or value == "" or value == "null":
        return None
    if not isinstance(value, str) or any(ord(c) < 32 for c in value):
        raise ManifestError("versionId must be a non-empty printable string or null")
    return value


def component_object_key(component: Mapping[str, object]) -> str:
    fields = ["type", "name", "id", "version"]
    segments = [safe_segment(component.get(field), f"component.{field}") for field in fields]
    sha = validate_sha256(component.get("sha256"), "component.sha256")
    filename = safe_segment(component.get("fileName"), "component.fileName")
    return "/".join([COMPONENT_PREFIX, *segments, sha, filename])


def release_id(app_version: object, app_build: object) -> str:
    version = safe_segment(app_version, "app.version")
    if isinstance(app_build, bool) or not isinstance(app_build, (str, int)):
        raise ManifestError("app.build must be a string or integer")
    build = safe_segment(str(app_build), "app.build")
    return f"{version}-{build}"


def app_object_key(app_version: object, app_build: object, sha256: object, filename: object) -> str:
    identifier = release_id(app_version, app_build)
    sha = validate_sha256(sha256)
    name = safe_segment(filename, "app.fileName")
    return f"apps/{APP_ID}/{identifier}/{sha}/{name}"


def catalog_object_key(app_version: object, app_build: object) -> str:
    return f"catalogs/{release_id(app_version, app_build)}/resources.json"


def release_index_key(app_version: object, app_build: object) -> str:
    return f"{RELEASE_INDEX_PREFIX}/{release_id(app_version, app_build)}.json"


def utc_timestamp(value: object) -> dt.datetime:
    text = _required_string(value, "publishedAt")
    try:
        result = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ManifestError("publishedAt must be an ISO-8601 timestamp") from exc
    if result.tzinfo is None:
        raise ManifestError("publishedAt must include a timezone")
    return result.astimezone(dt.timezone.utc)


def _validate_asset(asset: object, field: str, expected_key: str | None = None) -> dict:
    if not isinstance(asset, Mapping):
        raise ManifestError(f"{field} must be an object")
    key = _required_string(asset.get("key"), f"{field}.key")
    if key.startswith("/") or "\\" in key or any(ord(c) < 32 for c in key) or any(part in {"", ".", ".."} for part in key.split("/")):
        raise ManifestError(f"{field}.key is not a safe object key")
    if expected_key is not None and key != expected_key:
        raise ManifestError(f"{field}.key does not match the expected layout")
    sha = validate_sha256(asset.get("sha256"), f"{field}.sha256")
    byte_count = validate_byte_count(asset.get("byteCount"), f"{field}.byteCount")
    return {
        "key": key,
        "sha256": sha,
        "byteCount": byte_count,
        "versionId": normalize_version_id(asset.get("versionId")),
    }


def all_index_objects(index: Mapping[str, object]) -> list[dict]:
    """Return exact data object refs described by a validated release index."""
    objects: list[dict] = []
    for field, kind in (("app", "app"), ("appChecksum", "appChecksum"),
                        ("catalog", "catalog"), ("notice", "notice")):
        if field not in index:
            continue
        asset = index[field]
        objects.append({"kind": kind, **asset})
    for component in index["components"]:
        asset = {key: component[key] for key in ("key", "sha256", "byteCount", "versionId")}
        objects.append({"kind": "component", **asset, "component": dict(component)})
    return objects


def validate_release_index(index_key: str, value: object) -> dict:
    """Validate the tool-owned immutable index and every path it authorizes."""
    if not isinstance(value, Mapping):
        raise ManifestError("release index must be an object")
    if type(value.get("schemaVersion")) is not int or value.get("schemaVersion") != INDEX_SCHEMA_VERSION or value.get("kind") != "arclume-resource-release-index":
        raise ManifestError("unsupported release index schema")

    app = value.get("app")
    if not isinstance(app, Mapping) or app.get("id") != APP_ID:
        raise ManifestError("release index app must identify arclume")
    version = safe_segment(app.get("version"), "app.version")
    if isinstance(app.get("build"), bool) or not isinstance(app.get("build"), (str, int)):
        raise ManifestError("app.build must be a string or integer")
    build = safe_segment(str(app.get("build")), "app.build")
    expected_index_key = release_index_key(version, build)
    if index_key != expected_index_key:
        raise ManifestError("release index key does not match its App version and build")

    app_key = app_object_key(version, build, app.get("sha256"), app.get("fileName"))
    app_asset = _validate_asset(
        {key: app.get(key) for key in ("key", "sha256", "byteCount", "versionId")},
        "app",
        app_key,
    )
    if not str(app.get("fileName", "")).lower().endswith(".dmg"):
        raise ManifestError("app.fileName must identify a DMG")

    catalog_asset = _validate_asset(
        value.get("catalog"),
        "catalog",
        catalog_object_key(version, build),
    )
    optional_assets: dict[str, dict] = {}
    if "appChecksum" in value:
        optional_assets["appChecksum"] = _validate_asset(
            value["appChecksum"], "appChecksum", app_asset["key"] + ".sha256"
        )
    if "notice" in value:
        notice_key = f"catalogs/{release_id(version, build)}/THIRD-PARTY-NOTICES.md"
        optional_assets["notice"] = _validate_asset(value["notice"], "notice", notice_key)

    raw_components = value.get("components")
    if not isinstance(raw_components, list) or not raw_components:
        raise ManifestError("components must be a non-empty array")
    components: list[dict] = []
    seen_component_keys: set[str] = set()
    for index, raw in enumerate(raw_components):
        field = f"components[{index}]"
        if not isinstance(raw, Mapping):
            raise ManifestError(f"{field} must be an object")
        component = {
            "type": safe_segment(raw.get("type"), f"{field}.type"),
            "name": safe_segment(raw.get("name"), f"{field}.name"),
            "id": safe_segment(raw.get("id"), f"{field}.id"),
            "version": safe_segment(raw.get("version"), f"{field}.version"),
            "fileName": safe_segment(raw.get("fileName"), f"{field}.fileName"),
            "sha256": validate_sha256(raw.get("sha256"), f"{field}.sha256"),
            "byteCount": validate_byte_count(raw.get("byteCount"), f"{field}.byteCount"),
            "unpack": raw.get("unpack"),
            "versionId": normalize_version_id(raw.get("versionId")),
        }
        if type(component["unpack"]) is not bool:
            raise ManifestError(f"{field}.unpack must be a boolean")
        expected_key = component_object_key(component)
        if raw.get("key") != expected_key:
            raise ManifestError(f"{field}.key does not match the component layout")
        component["key"] = expected_key
        if expected_key in seen_component_keys:
            raise ManifestError("component object keys must be unique")
        seen_component_keys.add(expected_key)
        components.append(component)

    raw_runtimes = value.get("runtimes")
    if not isinstance(raw_runtimes, list):
        raise ManifestError("runtimes must be an array")
    runtime_refs: list[dict] = []
    seen_runtime_versions: set[tuple[str, str]] = set()
    component_by_key = {component["key"]: component for component in components}
    for index, raw in enumerate(raw_runtimes):
        field = f"runtimes[{index}]"
        if not isinstance(raw, Mapping):
            raise ManifestError(f"{field} must be an object")
        runtime_id = safe_segment(raw.get("id"), f"{field}.id")
        runtime_version = safe_segment(raw.get("version"), f"{field}.version")
        archive = raw.get("archive")
        if not isinstance(archive, Mapping):
            raise ManifestError(f"{field}.archive must be an object")
        archive_name = safe_segment(archive.get("name"), f"{field}.archive.name")
        archive_sha = validate_sha256(archive.get("sha256"), f"{field}.archive.sha256")
        runtime_abi = raw.get("runtimeABI")
        prefix_abi = _required_string(raw.get("prefixABI"), f"{field}.prefixABI")
        architecture = _required_string(raw.get("architecture"), f"{field}.architecture")
        if type(runtime_abi) is not int or runtime_abi <= 0:
            raise ManifestError(f"{field}.runtimeABI must be a positive integer")
        match = next((component for component in components
                      if component["type"] == "runtime"
                      and component["id"] == runtime_id
                      and component["version"] == runtime_version
                      and component["fileName"] == archive_name
                      and component["sha256"] == archive_sha), None)
        if match is None:
            raise ManifestError(f"{field} does not reference a staged runtime component")
        if raw.get("componentKey") != match["key"]:
            raise ManifestError(f"{field}.componentKey does not match the runtime archive")
        pair = (runtime_id, runtime_version)
        if pair in seen_runtime_versions:
            raise ManifestError("runtime id and version pairs must be unique per release")
        seen_runtime_versions.add(pair)
        runtime_refs.append({
            "id": runtime_id,
            "version": runtime_version,
            "componentKey": match["key"],
            "runtimeABI": runtime_abi,
            "prefixABI": prefix_abi,
            "architecture": architecture,
            "archive": {"name": archive_name, "sha256": archive_sha},
        })

    runtime_options = value.get("runtimeOptions")
    if not isinstance(runtime_options, list):
        raise ManifestError("runtimeOptions must be an array")
    normalized_options: list[dict] = []
    seen_option_ids: set[str] = set()
    runtime_components_by_id = {
        runtime["id"]: runtime["componentKey"] for runtime in runtime_refs
    }
    for index, option in enumerate(runtime_options):
        field = f"runtimeOptions[{index}]"
        if not isinstance(option, Mapping):
            raise ManifestError(f"{field} must be an object")
        option_id = safe_segment(option.get("id"), f"{field}.id")
        if option_id not in runtime_components_by_id:
            raise ManifestError(f"{field}.id does not identify a manifested runtime")
        if option_id in seen_option_ids:
            raise ManifestError("runtimeOptions ids must be unique")
        seen_option_ids.add(option_id)
        provider = _required_string(option.get("provider"), f"{field}.provider")
        strategies = option.get("strategies")
        if not isinstance(strategies, list) or any(not isinstance(item, Mapping) for item in strategies):
            raise ManifestError(f"{field}.strategies must be an array of objects")
        normalized_strategies = []
        for strategy_index, strategy in enumerate(strategies):
            strategy_field = f"{field}.strategies[{strategy_index}]"
            if strategy.get("delivery") != "precompiled":
                raise ManifestError(f"{strategy_field}.delivery is not supported")
            component_id = safe_segment(strategy.get("componentID"), f"{strategy_field}.componentID")
            component_key = runtime_components_by_id.get(component_id)
            if component_key is None:
                raise ManifestError(f"{strategy_field}.componentID does not reference a manifested runtime component")
            normalized_strategies.append({"delivery": "precompiled", "componentID": component_id})
        normalized_options.append({"id": option_id, "provider": provider, "strategies": normalized_strategies})

    published_at = utc_timestamp(value.get("publishedAt"))
    supported = value.get("supported", True)
    if type(supported) is not bool:
        raise ManifestError("supported must be a boolean when present")
    release = {
        "schemaVersion": INDEX_SCHEMA_VERSION,
        "kind": "arclume-resource-release-index",
        "publishedAt": published_at.isoformat().replace("+00:00", "Z"),
        "supported": supported,
        "app": {"id": APP_ID, "version": version, "build": build, "fileName": safe_segment(app.get("fileName"), "app.fileName"), **app_asset},
        "catalog": catalog_asset,
        "components": components,
        "runtimeOptions": normalized_options,
        "runtimes": runtime_refs,
        **optional_assets,
    }
    return release


def _ref_from_asset(asset: Mapping[str, object]) -> ObjectRef:
    return ObjectRef(str(asset["key"]), normalize_version_id(asset.get("versionId")))


def _natural_version_key(version: str) -> tuple:
    tokens = _VERSION_TOKENS.findall(version)
    return tuple((1, int(token)) if token.isdigit() else (0, token.lower()) for token in tokens)


def plan_retention(
    index_documents: Iterable[tuple[str, object]],
    existing_objects: Collection[ObjectRef] | None = None,
    *,
    keep_app_releases: int = 2,
    keep_runtime_versions: int = 3,
) -> RetentionPlan:
    """Plan deletions only from valid tool indexes; unknown bucket objects survive."""
    if keep_app_releases < 1 or keep_runtime_versions < 1:
        raise ValueError("retention counts must be positive")

    documents = list(index_documents)
    if not documents:
        return RetentionPlan((), (), (), "no valid release indexes were found")

    validated: list[tuple[str, dict, dt.datetime]] = []
    seen_release_ids: set[str] = set()
    try:
        for index_key, document in documents:
            index = validate_release_index(index_key, document)
            release = release_id(index["app"]["version"], index["app"]["build"])
            if release in seen_release_ids:
                raise ManifestError(f"duplicate release index for {release}")
            seen_release_ids.add(release)
            validated.append((index_key, index, utc_timestamp(index["publishedAt"])))
    except (ManifestError, KeyError, TypeError) as exc:
        return RetentionPlan((), (), (), f"retention blocked by invalid release index: {exc}")

    if not validated:
        return RetentionPlan((), (), (), "no valid release indexes were found")

    ordered_apps = sorted(
        validated,
        key=lambda item: (item[2], item[1]["app"]["version"], _natural_version_key(item[1]["app"]["build"])),
        reverse=True,
    )
    retained_apps = ordered_apps[:keep_app_releases]
    retained_release_ids = tuple(
        release_id(index["app"]["version"], index["app"]["build"])
        for _, index, _ in retained_apps
    )

    runtime_seen: dict[tuple[str, str], dt.datetime] = {}
    for _, index, published_at in validated:
        for runtime in index["runtimes"]:
            pair = (runtime["id"], runtime["version"])
            runtime_seen[pair] = max(runtime_seen.get(pair, published_at), published_at)

    retained_runtime_pairs: list[tuple[str, str]] = []
    runtime_ids = sorted({runtime_id for runtime_id, _ in runtime_seen})
    for runtime_id in runtime_ids:
        versions = [
            (version, seen_at)
            for (seen_id, version), seen_at in runtime_seen.items()
            if seen_id == runtime_id
        ]
        versions.sort(key=lambda item: (item[1], _natural_version_key(item[0])), reverse=True)
        retained_runtime_pairs.extend((runtime_id, version) for version, _ in versions[:keep_runtime_versions])

    all_records: dict[ObjectRef, dict] = {}
    invalid_conflict = False
    for index_key, index, _ in validated:
        release = release_id(index["app"]["version"], index["app"]["build"])
        for asset in all_index_objects(index):
            ref = _ref_from_asset(asset)
            existing = all_records.get(ref)
            if existing and (existing["sha256"], existing["byteCount"]) != (asset["sha256"], asset["byteCount"]):
                invalid_conflict = True
                break
            if existing is None:
                all_records[ref] = {**asset, "sourceReleases": [release], "indexKeys": [index_key]}
            else:
                if release not in existing["sourceReleases"]:
                    existing["sourceReleases"].append(release)
                if index_key not in existing["indexKeys"]:
                    existing["indexKeys"].append(index_key)
        if invalid_conflict:
            break
    if invalid_conflict:
        return RetentionPlan((), (), (), "retention blocked: one object reference has conflicting hashes or sizes")

    latest_app_refs: set[ObjectRef] = set()
    for _, index, _ in retained_apps:
        latest_app_refs.update(_ref_from_asset(asset) for asset in all_index_objects(index))

    # A still-supported old App may be installed even after its DMG is retired.
    # Keep its pinned catalog and every exact component reference until support
    # is explicitly changed in a future, separately reviewed workflow.
    compatibility_refs: set[ObjectRef] = set()
    for _, index, _ in validated:
        if not index["supported"]:
            continue
        compatibility_refs.add(_ref_from_asset(index["catalog"]))
        if "notice" in index:
            compatibility_refs.add(_ref_from_asset(index["notice"]))
        compatibility_refs.update(_ref_from_asset(component) for component in index["components"])

    runtime_pair_set = set(retained_runtime_pairs)
    recent_runtime_refs: set[ObjectRef] = set()
    for _, index, _ in validated:
        component_by_key = {component["key"]: component for component in index["components"]}
        for runtime in index["runtimes"]:
            if (runtime["id"], runtime["version"]) in runtime_pair_set:
                component = component_by_key[runtime["componentKey"]]
                recent_runtime_refs.add(_ref_from_asset(component))

    retained_refs = latest_app_refs | compatibility_refs | recent_runtime_refs

    available = set(existing_objects) if existing_objects is not None else None
    delete_records = [
        record for ref, record in all_records.items()
        if ref not in retained_refs and (available is None or ref in available)
    ]
    delete_records.sort(key=lambda item: (item["key"], item.get("versionId") or ""))
    for record in delete_records:
        record["sourceReleases"] = sorted(record["sourceReleases"])
        record["indexKeys"] = sorted(record["indexKeys"])

    extant_managed = {
        ref: record for ref, record in all_records.items()
        if ref in retained_refs and (available is None or ref in available)
    }
    compatibility_only = {
        ref for ref in compatibility_refs
        if ref not in latest_app_refs and ref not in recent_runtime_refs
        and (available is None or ref in available)
    }
    compatibility_records = []
    for ref in sorted(compatibility_only, key=lambda item: (item.key, item.version_id or "")):
        record = all_records.get(ref)
        if record is not None:
            compatibility_records.append({
                "kind": record["kind"],
                "key": record["key"],
                "versionId": record.get("versionId"),
                "sha256": record["sha256"],
                "byteCount": record["byteCount"],
                "sourceReleases": sorted(record["sourceReleases"]),
            })

    return RetentionPlan(
        keep_app_releases=retained_release_ids,
        keep_runtime_versions=tuple(retained_runtime_pairs),
        delete_objects=tuple(delete_records),
        compatibility_protected=tuple(compatibility_records),
        retained_object_count=len(extant_managed),
        retained_byte_count=sum(record["byteCount"] for record in extant_managed.values()),
    )
