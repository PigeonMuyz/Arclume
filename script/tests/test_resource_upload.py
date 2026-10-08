"""Offline release-tool contract tests. No AWS credentials or network calls."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from upload_resources import HEADROOM, ManifestError, check_capacity, https_base, stage
from publish_resources import component_object_key, validate_release_index


class ResourceUploadTests(unittest.TestCase):
    def test_quota_counts_unknown_objects_and_only_new_bytes(self):
        existing = {"unknown": {"Size": 100}, "shared": {"Size": 20}}
        self.assertEqual(check_capacity(existing, {"shared": 20, "new": 30}, 1000 + HEADROOM)["newBytes"], 30)
        with self.assertRaises(ManifestError):
            check_capacity(existing, {"new": 30}, HEADROOM + 149)

    def test_https_configuration_does_not_accept_credentials_or_query(self):
        for value in (None, "http://example.invalid", "https://user:secret@example.invalid", "https://example.invalid/?secret=x"):
            with self.assertRaises(ManifestError):
                https_base(value)
        self.assertEqual(https_base("https://example.invalid/components/"), "https://example.invalid/components")

    def test_stages_index_checksum_and_notices_without_network(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            payload = b"isolated-runtime-fixture"
            sha = hashlib.sha256(payload).hexdigest()
            component = dict(type="runtime", name="test-wine", id="test.wine", version="1.0",
                             fileName="wine.tar.xz", sha256=sha, byteCount=len(payload), unpack=False)
            key = component_object_key(component)
            archive = root / key
            archive.parent.mkdir(parents=True)
            archive.write_bytes(payload)
            notice = root / "licenses/test.wine/1.0/THIRD-PARTY-NOTICES.md"
            notice.parent.mkdir(parents=True)
            notice.write_text("Fixture license")
            catalog = dict(schemaVersion=1, components=[component], runtimes=[dict(
                id="test.wine", version="1.0", runtimeABI=1, prefixABI="test-prefix", architecture="x86_64",
                archive=dict(name="wine.tar.xz", sha256=sha))], runtimeOptions=[dict(id="test.wine", provider="test",
                strategies=[dict(delivery="precompiled", componentID="test.wine")])])
            (root / "resources.json").write_text(json.dumps(catalog))
            dmg = root / "Arclume-test.dmg"
            dmg.write_bytes(b"not a real disk image")
            args = argparse.Namespace(staging=root, dmg=dmg, app_version="2.0", app_build="13")
            index_key, index, objects = stage(args, root)
            normalized = validate_release_index(index_key, index)
            self.assertEqual(len(objects), 5)
            self.assertEqual(normalized["appChecksum"]["key"], normalized["app"]["key"] + ".sha256")
            self.assertIn("notice", normalized)
            archive.write_bytes(b"corrupt")
            with self.assertRaises(ManifestError):
                stage(args, root)


if __name__ == "__main__":
    unittest.main()
