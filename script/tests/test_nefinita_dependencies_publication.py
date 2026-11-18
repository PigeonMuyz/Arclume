"""Offline tests for immutable, authenticated Nefinita dependency publication."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import publish_nefinita_dependencies as publisher


class NefinitaDependencyPublicationTests(unittest.TestCase):
    def item(self):
        return dict(id="freetype", version="1.0", archive="freetype-1.0.tar.gz",
                    originURL="https://example.org/freetype-1.0.tar.gz",
                    sha256=hashlib.sha256(b"fixture").hexdigest())

    def test_locks_reject_shell_expansion_duplicates_and_commands(self):
        self.assertEqual(publisher.assignments('# comment\nA="value"\n'), {"A": "value"})
        for text in ('A="$(id)"', 'A="`id`"', 'A="one"\nA="two"', 'A=value', 'echo bad'):
            with self.subTest(text=text), self.assertRaises(publisher.ManifestError):
                publisher.assignments(text)

    def test_authentication_rejects_changed_or_symlinked_inputs(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            metadata = root / "Arclume/Resources/nefinita-build-recipe.json"
            metadata.parent.mkdir(parents=True)
            source = root / "source"
            source.mkdir()
            file = source / "script.sh"
            file.write_bytes(b"fixture")
            metadata.write_text(json.dumps({"files": {"script.sh": self.item()["sha256"]}}))
            with mock.patch.object(publisher, "ROOT", root):
                publisher.authenticated_inputs(source)
                file.write_bytes(b"changed")
                with self.assertRaises(publisher.ManifestError):
                    publisher.authenticated_inputs(source)
                file.unlink()
                file.symlink_to(metadata)
                with self.assertRaises(publisher.ManifestError):
                    publisher.authenticated_inputs(source)

    def test_descriptors_use_authenticated_locks_and_fixed_patch_revision(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            locks = root / "sources"
            locks.mkdir()
            item = self.item()
            fields = {"VERSION": "version", "ARCHIVE": "archive", "URL": "originURL", "SHA256": "sha256"}
            (locks / "FREETYPE_SOURCE.lock").write_text("\n".join(
                f'FREETYPE_{key}="{item[field]}"' for key, field in fields.items()))
            (locks / "DEPENDENCIES.lock").write_text("")
            revision = "a" * 40
            (locks / "FINEWINE_PATCHSET.lock").write_text(f'FINEWINE_PATCHSET_REVISION="{revision}"')
            with mock.patch.object(publisher, "authenticated_inputs", return_value={"revision": "pinned"}):
                recipe, result = publisher.descriptors(root)
            self.assertEqual(recipe["revision"], "pinned")
            self.assertEqual(result[0], item)
            self.assertEqual(result[1]["archive"], f"finewine-{revision}.tar.gz")
            self.assertTrue(result[1]["originURL"].endswith(revision))

    def test_verified_cache_is_reused_without_network(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            item = self.item()
            target = root / "dependency-inputs" / item["archive"]
            target.parent.mkdir()
            target.write_bytes(b"fixture")
            with mock.patch.object(publisher.subprocess, "run", side_effect=AssertionError("network")), \
                    contextlib.redirect_stderr(io.StringIO()):
                metadata, selected = publisher.stage_one(item, root, root)
            self.assertEqual(selected, target)
            self.assertEqual(metadata["byteCount"], 7)
            self.assertEqual(metadata["objectKey"],
                             f'components/source/freetype/dev.nefinita.source.freetype/1.0/{item["sha256"]}/{item["archive"]}')

    def test_bad_download_is_not_promoted_to_ready_cache(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            def download(arguments, **kwargs):
                Path(arguments[arguments.index("-o") + 1]).write_bytes(b"bad")
                return mock.Mock(returncode=0)
            with mock.patch.object(publisher.subprocess, "run", side_effect=download), \
                    self.assertRaises(publisher.ManifestError):
                publisher.stage_one(self.item(), root, root)
            self.assertFalse((root / "dependency-inputs" / self.item()["archive"]).exists())

    def test_patch_archive_must_match_authenticated_patch_hashes(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            hashes = root / "patches/finewine/PATCHES.sha256"
            hashes.parent.mkdir(parents=True)
            hashes.write_text(f'{self.item()["sha256"]}  patch.diff\n')
            archive = root / "patches.tar.gz"
            for payload, valid in ((b"fixture", True), (b"changed", False)):
                with tarfile.open(archive, "w:gz") as output:
                    member = tarfile.TarInfo("fixed-revision/patch.diff")
                    member.size = len(payload)
                    output.addfile(member, io.BytesIO(payload))
                if valid:
                    publisher.verify_patches(archive, root)
                else:
                    with self.assertRaises(publisher.ManifestError):
                        publisher.verify_patches(archive, root)

    def invoke_main(self, root, execute, manifest_matches=True):
        item = {**self.item(), "objectKey": "components/source/fixture", "byteCount": 7}
        metadata = root / "Arclume/Resources/nefinita-build-materials.json"
        metadata.parent.mkdir(parents=True)
        manifest = dict(schemaVersion=1, revision="fixed", materials=[item])
        metadata.write_text(json.dumps(manifest if manifest_matches else {}))
        args = ["publisher", "--source", str(root), "--staging", str(root / "staging")]
        if execute:
            args.append("--execute")
        service = mock.Mock()
        service.inventory.return_value = {}
        with mock.patch.object(sys, "argv", args), mock.patch.object(publisher, "ROOT", root), \
                mock.patch.object(publisher, "descriptors", return_value=({"revision": "fixed"}, [item])), \
                mock.patch.object(publisher, "stage_one", return_value=(item, root / "archive")), \
                mock.patch.object(publisher, "S3", return_value=service) as s3, \
                mock.patch.object(publisher, "check_capacity", return_value={"newBytes": 7}) as capacity, \
                mock.patch.object(publisher, "verify_public") as public, \
                mock.patch.dict(publisher.os.environ, {"ARCLUME_RESOURCE_BUCKET": "fixture-bucket",
                    "ARCLUME_RESOURCE_BASE_URL": "https://example.org"}), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            if not manifest_matches:
                with self.assertRaises(publisher.ManifestError):
                    publisher.main()
            else:
                publisher.main()
        return service, s3, capacity, public, item

    def test_staging_and_unreviewed_metadata_never_write_to_oss(self):
        for execute, matches in ((False, True), (True, False)):
            with tempfile.TemporaryDirectory() as name:
                service, s3, capacity, public, _ = self.invoke_main(Path(name), execute, matches)
                s3.assert_not_called()
                capacity.assert_not_called()
                public.assert_not_called()
                service.put.assert_not_called()

    def test_execute_checks_capacity_and_verifies_every_published_object(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            service, s3, capacity, public, item = self.invoke_main(root, True)
            s3.assert_called_once()
            capacity.assert_called_once_with({}, {item["objectKey"]: 7})
            service.put.assert_called_once()
            public.assert_called_once_with("https://example.org", item["objectKey"], item)
            receipt = json.loads((root / "staging/nefinita-dependencies-upload-report.json").read_text())
            self.assertTrue(receipt["uploaded"])
            self.assertEqual(receipt["verified"], [item["objectKey"]])
            self.assertEqual([call[0] for call in service.method_calls], ["inventory", "put"])


if __name__ == "__main__":
    unittest.main()
