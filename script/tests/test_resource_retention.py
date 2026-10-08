import hashlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import publish_resources as resources


def digest(label):
    return hashlib.sha256(label.encode("utf-8")).hexdigest()


def make_release(build, published_at, runtime_version, *, supported=None, shared_component=None,
                 runtime_id="io.arclume.runtime.wine", optional_assets=False):
    app_version = "2.0"
    runtime_name = f"arclume-wine-{runtime_version}-x86_64.tar.xz"
    runtime_sha = digest(f"runtime:{runtime_id}:{runtime_version}")
    runtime_component = {
        "type": "runtime",
        "name": "arclume-wine",
        "id": runtime_id,
        "version": runtime_version,
        "fileName": runtime_name,
        "sha256": runtime_sha,
        "byteCount": 100 + int(runtime_version.split(".")[-1]),
        "unpack": False,
        "versionId": None,
    }
    runtime_component["key"] = resources.component_object_key(runtime_component)

    components = [runtime_component]
    if shared_component is not None:
        components.append(shared_component)

    app_name = f"Arclume-{app_version}-{build}.dmg"
    app_sha = digest(f"app:{build}")
    app = {
        "id": "arclume",
        "version": app_version,
        "build": str(build),
        "fileName": app_name,
        "key": resources.app_object_key(app_version, str(build), app_sha, app_name),
        "sha256": app_sha,
        "byteCount": 1000 + int(build),
        "versionId": None,
    }
    catalog_sha = digest(f"catalog:{build}")
    catalog = {
        "key": resources.catalog_object_key(app_version, str(build)),
        "sha256": catalog_sha,
        "byteCount": 400 + int(build),
        "versionId": None,
    }
    runtime = {
        "id": runtime_id,
        "version": runtime_version,
        "componentKey": runtime_component["key"],
        "runtimeABI": 1,
        "prefixABI": "arclume-prefix-1",
        "architecture": "x86_64",
        "archive": {"name": runtime_name, "sha256": runtime_sha},
    }
    index = {
        "schemaVersion": 1,
        "kind": "arclume-resource-release-index",
        "publishedAt": published_at,
        "app": app,
        "catalog": catalog,
        "components": components,
        "runtimeOptions": [{
            "id": runtime_id,
            "provider": "Arclume",
            "strategies": [{"delivery": "precompiled", "componentID": runtime_id}],
        }],
        "runtimes": [runtime],
    }
    if optional_assets:
        checksum_sha = digest(f"checksum:{build}")
        notice_sha = digest(f"notice:{build}")
        index["appChecksum"] = {
            "key": app["key"] + ".sha256",
            "sha256": checksum_sha,
            "byteCount": 80 + int(build),
            "versionId": None,
        }
        index["notice"] = {
            "key": f"catalogs/{app_version}-{build}/THIRD-PARTY-NOTICES.md",
            "sha256": notice_sha,
            "byteCount": 200 + int(build),
            "versionId": None,
        }
    if supported is not None:
        index["supported"] = supported
    return resources.release_index_key(app_version, str(build)), index


def refs_from_indexes(indexes):
    refs = set()
    for key, index in indexes:
        del key
        assets = [index["app"], index["catalog"], *index["components"]]
        assets.extend(index[field] for field in ("appChecksum", "notice") if field in index)
        refs.update(resources.ObjectRef(item["key"], item.get("versionId")) for item in assets)
    return refs


class ResourceRetentionTests(unittest.TestCase):
    def test_old_supported_app_loses_dmg_but_keeps_catalog_and_components(self):
        indexes = [
            make_release(1, "2026-09-01T00:00:00Z", "1.0.1"),
            make_release(2, "2026-09-02T00:00:00Z", "1.0.2"),
            make_release(3, "2026-09-03T00:00:00Z", "1.0.3"),
            make_release(4, "2026-09-04T00:00:00Z", "1.0.4"),
        ]
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes))

        self.assertEqual(plan.keep_app_releases, ("2.0-4", "2.0-3"))
        delete_keys = {item["key"] for item in plan.delete_objects}
        old_index = resources.validate_release_index(*indexes[0])
        self.assertIn(old_index["app"]["key"], delete_keys)
        self.assertNotIn(old_index["catalog"]["key"], delete_keys)
        self.assertTrue(all(component["key"] not in delete_keys for component in old_index["components"]))

        compatibility_keys = {item["key"] for item in plan.compatibility_protected}
        self.assertIn(old_index["catalog"]["key"], compatibility_keys)
        self.assertTrue(any(component["key"] in compatibility_keys for component in old_index["components"]))
        self.assertIn(("io.arclume.runtime.wine", "1.0.4"), plan.keep_runtime_versions)
        self.assertIn(("io.arclume.runtime.wine", "1.0.2"), plan.keep_runtime_versions)
        self.assertNotIn(("io.arclume.runtime.wine", "1.0.1"), plan.keep_runtime_versions)

        output = plan.as_json()
        self.assertEqual(output["compatibilityProtected"]["count"], len(plan.compatibility_protected))
        self.assertGreater(output["compatibilityProtected"]["byteCount"], 0)
        self.assertGreater(output["retained"]["count"], 0)
        self.assertGreater(output["retained"]["byteCount"], 0)

    def test_shared_component_stays_if_any_supported_catalog_references_it(self):
        shared = {
            "type": "fonts",
            "name": "windows-fonts",
            "id": "fonts",
            "version": "2026.09",
            "fileName": "fonts.tar.xz",
            "sha256": digest("shared-fonts"),
            "byteCount": 500,
            "unpack": False,
            "versionId": None,
        }
        shared["key"] = resources.component_object_key(shared)
        indexes = [
            make_release(1, "2026-09-01T00:00:00Z", "1.0.1", shared_component=shared),
            make_release(2, "2026-09-02T00:00:00Z", "1.0.2"),
            make_release(3, "2026-09-03T00:00:00Z", "1.0.3"),
        ]
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes))
        self.assertNotIn(shared["key"], {item["key"] for item in plan.delete_objects})

    def test_unindexed_bucket_objects_are_never_deletion_candidates(self):
        indexes = [make_release(1, "2026-09-01T00:00:00Z", "1.0.1")]
        unknown = resources.ObjectRef("components/unknown/orphan")
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes) | {unknown})
        self.assertNotIn(unknown.key, {item["key"] for item in plan.delete_objects})

    def test_missing_supported_field_defaults_to_supported(self):
        indexes = [make_release(1, "2026-09-01T00:00:00Z", "1.0.1")]
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes))
        self.assertIsNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())

    def test_unknown_supported_value_blocks_all_deletion(self):
        indexes = [make_release(1, "2026-09-01T00:00:00Z", "1.0.1", supported="no")]
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes))
        self.assertIsNotNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())

    def test_no_valid_index_blocks_deletion(self):
        unknown = resources.ObjectRef("apps/arclume/unindexed.dmg")
        plan = resources.plan_retention([], {unknown})
        self.assertIsNotNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())

    def test_runtime_keep_limit_is_per_id(self):
        indexes = [
            make_release(1, "2026-09-01T00:00:00Z", "1.0.1", runtime_id="runtime.one"),
            make_release(2, "2026-09-02T00:00:00Z", "1.0.2", runtime_id="runtime.one"),
            make_release(3, "2026-09-03T00:00:00Z", "1.0.3", runtime_id="runtime.one"),
            make_release(4, "2026-09-04T00:00:00Z", "1.0.4", runtime_id="runtime.one"),
            make_release(5, "2026-09-05T00:00:00Z", "2.0.1", runtime_id="runtime.two"),
        ]
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes))
        self.assertEqual(
            {pair for pair in plan.keep_runtime_versions if pair[0] == "runtime.one"},
            {("runtime.one", "1.0.2"), ("runtime.one", "1.0.3"), ("runtime.one", "1.0.4")},
        )
        self.assertEqual(
            {pair for pair in plan.keep_runtime_versions if pair[0] == "runtime.two"},
            {("runtime.two", "2.0.1")},
        )

    def test_runtime_manifest_digest_must_match_component(self):
        index_key, index = make_release(1, "2026-09-01T00:00:00Z", "1.0.1")
        index["runtimes"][0]["archive"]["sha256"] = digest("different")
        plan = resources.plan_retention([(index_key, index)])
        self.assertIsNotNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())

    def test_old_supported_app_keeps_notice_but_retires_checksum_with_dmg(self):
        indexes = [
            make_release(1, "2026-09-01T00:00:00Z", "1.0.1", optional_assets=True),
            make_release(2, "2026-09-02T00:00:00Z", "1.0.2", optional_assets=True),
            make_release(3, "2026-09-03T00:00:00Z", "1.0.3", optional_assets=True),
        ]
        plan = resources.plan_retention(indexes, refs_from_indexes(indexes))
        old = resources.validate_release_index(*indexes[0])
        deleted = {item["key"] for item in plan.delete_objects}
        protected = {item["key"] for item in plan.compatibility_protected}

        self.assertIn(old["app"]["key"], deleted)
        self.assertIn(old["appChecksum"]["key"], deleted)
        self.assertNotIn(old["notice"]["key"], deleted)
        self.assertNotIn(old["catalog"]["key"], deleted)
        self.assertIn(old["notice"]["key"], protected)
        self.assertNotIn(old["appChecksum"]["key"], protected)
        self.assertEqual(old["appChecksum"]["key"], old["app"]["key"] + ".sha256")
        self.assertEqual(old["notice"]["key"], "catalogs/2.0-1/THIRD-PARTY-NOTICES.md")
        for latest_key, latest_index in indexes[1:]:
            latest = resources.validate_release_index(latest_key, latest_index)
            self.assertNotIn(latest["appChecksum"]["key"], deleted)
            self.assertNotIn(latest["notice"]["key"], deleted)

    def test_optional_asset_paths_are_validated(self):
        for field in ("appChecksum", "notice"):
            with self.subTest(field=field):
                index_key, index = make_release(1, "2026-09-01T00:00:00Z", "1.0.1", optional_assets=True)
                index[field]["key"] += ".unexpected"
                plan = resources.plan_retention([(index_key, index)])
                self.assertIsNotNone(plan.blocked_reason)
                self.assertEqual(plan.delete_objects, ())

    def test_runtime_option_strategy_must_reference_a_manifested_runtime(self):
        index_key, index = make_release(1, "2026-09-01T00:00:00Z", "1.0.1")
        index["runtimeOptions"][0]["strategies"][0]["componentID"] = "runtime.unknown"
        plan = resources.plan_retention([(index_key, index)])
        self.assertIsNotNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())

    def test_runtime_option_rejects_unknown_delivery_strategy(self):
        index_key, index = make_release(1, "2026-09-01T00:00:00Z", "1.0.1")
        index["runtimeOptions"][0]["strategies"][0]["delivery"] = "download-latest"
        plan = resources.plan_retention([(index_key, index)])
        self.assertIsNotNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())

    def test_runtime_option_id_must_identify_a_manifested_runtime(self):
        index_key, index = make_release(1, "2026-09-01T00:00:00Z", "1.0.1")
        index["runtimeOptions"][0]["id"] = "runtime.unknown"
        plan = resources.plan_retention([(index_key, index)])
        self.assertIsNotNone(plan.blocked_reason)
        self.assertEqual(plan.delete_objects, ())


if __name__ == "__main__":
    unittest.main()
