"""Offline tests for component-only staging and CLI behavior."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import upload_resources
from publish_resources import ManifestError, component_object_key


class ComponentUploadTests(unittest.TestCase):
    def make_staging(self, root):
        payload = b"isolated-component-fixture"
        sha = hashlib.sha256(payload).hexdigest()
        component = dict(
            type="runtime",
            name="test-wine",
            id="test.wine",
            version="1.0",
            fileName="wine.tar.xz",
            sha256=sha,
            byteCount=len(payload),
            unpack=False,
        )
        key = component_object_key(component)
        archive = root / key
        archive.parent.mkdir(parents=True)
        archive.write_bytes(payload)

        notice_key = "licenses/test.wine/1.0/THIRD-PARTY-NOTICES.md"
        notice = root / notice_key
        notice.parent.mkdir(parents=True)
        notice.write_bytes(b"Fixture license")
        catalog = {"schemaVersion": 1, "components": [component]}
        (root / "resources.json").write_text(json.dumps(catalog))
        return component, key, archive, notice_key, notice

    def test_stages_component_and_license_with_reviewed_hashes(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            component, component_key, archive, notice_key, notice = self.make_staging(root)

            objects = upload_resources.stage_components(root)

            self.assertEqual([item[0] for item in objects], [component_key, notice_key])
            self.assertEqual(objects[0][1], archive.resolve())
            self.assertEqual(objects[0][2], component)
            self.assertEqual(objects[1][1], notice.resolve())
            self.assertEqual(objects[1][2]["byteCount"], notice.stat().st_size)
            self.assertEqual(objects[1][2]["sha256"], hashlib.sha256(notice.read_bytes()).hexdigest())
            self.assertTrue(all(not key.startswith(("apps/", "catalogs/", "indexes/"))
                                for key, _, _ in objects))

    def test_rejects_component_whose_contents_were_changed(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            _, _, archive, _, _ = self.make_staging(root)
            archive.write_bytes(b"tampered component")

            with self.assertRaises(ManifestError):
                upload_resources.stage_components(root)

    def test_rejects_component_or_notice_symlink_that_escapes_staging(self):
        for target_kind in ("component", "notice"):
            with self.subTest(target=target_kind), tempfile.TemporaryDirectory() as name:
                base = Path(name)
                root = base / "staging"
                root.mkdir()
                _, _, archive, _, notice = self.make_staging(root)
                external = base / "outside-resource"
                external.write_bytes(b"outside staging")
                target = archive if target_kind == "component" else notice
                target.unlink()
                target.symlink_to(external)

                with self.assertRaises(ManifestError):
                    upload_resources.stage_components(root)

    def test_cli_without_execute_stages_locally_without_network(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.make_staging(root)
            report = root / "report.json"
            args = ["upload_resources.py", "--components-only", "--staging", str(root),
                    "--report", str(report)]
            blocked = AssertionError("offline components-only planning attempted network or AWS access")
            with mock.patch.object(sys, "argv", args), \
                    mock.patch.object(upload_resources, "S3", side_effect=blocked), \
                    mock.patch.object(upload_resources, "verify_public", side_effect=blocked), \
                    mock.patch.object(upload_resources.urllib.request, "urlopen", side_effect=blocked), \
                    mock.patch.object(upload_resources.subprocess, "run", side_effect=blocked), \
                    contextlib.redirect_stdout(io.StringIO()):
                upload_resources.main()

            result = json.loads(report.read_text())
            self.assertEqual(result["mode"], "components-only")
            self.assertEqual(result["objects"], 2)
            self.assertFalse(result["uploaded"])
            self.assertNotIn("release", result)
            self.assertNotIn("retention", result)

    def test_cli_rejects_retention_and_dmg_in_components_only_mode(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            dmg = root / "fixture.dmg"
            dmg.write_bytes(b"not a real disk image")
            invalid_arguments = (
                ["--components-only", "--apply-retention"],
                ["--components-only", "--dmg", str(dmg)],
            )
            for invalid in invalid_arguments:
                with self.subTest(arguments=invalid), mock.patch.object(
                        sys, "argv", ["upload_resources.py", *invalid, "--staging", str(root)]):
                    with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
                        upload_resources.main()
                    self.assertEqual(raised.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
