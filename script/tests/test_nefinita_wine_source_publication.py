"""Offline tests for the pinned CodeWeavers Wine source publisher."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import publish_nefinita_wine_source as publisher
from publish_resources import ManifestError


class NefinitaWineSourcePublicationTests(unittest.TestCase):
    def metadata(self):
        return {
            "schemaVersion": 1,
            "version": publisher.VERSION,
            "archive": publisher.ARCHIVE_NAME,
            "sha256": publisher.SHA256,
            "byteCount": publisher.BYTE_COUNT,
            "originURL": publisher.ORIGIN_URL,
            "objectKey": publisher.expected_object_key(
                publisher.VERSION, publisher.SHA256, publisher.ARCHIVE_NAME),
        }

    def test_metadata_maps_to_the_single_content_addressed_object(self):
        value = publisher.validate_metadata(self.metadata())
        self.assertEqual(value["objectKey"],
                         "components/source/codeweavers-wine/org.codeweavers.wine-source/26.3.0/"
                         "ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872/"
                         "crossover-sources-26.3.0.tar.gz")

    def test_rejects_metadata_for_another_or_modified_archive(self):
        for field, value in (("archive", "another.tar.gz"),
                             ("sha256", "0" * 64),
                             ("objectKey", "components/other.tar.gz"),
                             ("originURL", "https://example.com/source.tar.gz"),
                             ("byteCount", 1)):
            with self.subTest(field=field):
                metadata = self.metadata()
                metadata[field] = value
                with self.assertRaises(ManifestError):
                    publisher.validate_metadata(metadata)

    def test_prepare_object_checks_archive_name_size_and_checksum(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            archive = root / publisher.ARCHIVE_NAME
            with archive.open("wb") as target:
                target.truncate(publisher.BYTE_COUNT)

            with mock.patch.object(publisher, "digest", return_value=publisher.SHA256):
                key, selected, asset = publisher.prepare_object(archive, self.metadata())

            self.assertEqual(key, self.metadata()["objectKey"])
            self.assertEqual(selected, archive.resolve())
            self.assertEqual(asset, {"sha256": publisher.SHA256,
                                     "byteCount": publisher.BYTE_COUNT})

            wrong_name = root / "other.tar.gz"
            wrong_name.write_bytes(b"fixture")
            with self.assertRaises(ManifestError):
                publisher.prepare_object(wrong_name, self.metadata())

            with archive.open("wb") as target:
                target.truncate(publisher.BYTE_COUNT)
            with mock.patch.object(publisher, "digest", return_value="0" * 64):
                with self.assertRaises(ManifestError):
                    publisher.prepare_object(archive, self.metadata())

    def test_dry_run_reads_only_the_local_archive_and_never_calls_network(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            archive = root / publisher.ARCHIVE_NAME
            with archive.open("wb") as target:
                target.truncate(publisher.BYTE_COUNT)
            metadata = root / "source.json"
            metadata.write_text(json.dumps(self.metadata()))
            argv = ["publish_nefinita_wine_source.py", "--archive", str(archive),
                    "--metadata", str(metadata)]
            blocked = AssertionError("dry run attempted network or AWS access")
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.object(publisher, "digest", return_value=publisher.SHA256), \
                    mock.patch.object(publisher, "S3", side_effect=blocked), \
                    mock.patch.object(publisher, "verify_public", side_effect=blocked), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                publisher.main()

            report = json.loads(output.getvalue())
            self.assertEqual(report["objects"], 1)
            self.assertEqual(report["objectKey"], self.metadata()["objectKey"])
            self.assertEqual(report["sha256"], publisher.SHA256)
            self.assertFalse(report["uploaded"])
            self.assertEqual(report["verified"], [])
            self.assertEqual({path.name for path in root.iterdir()}, {publisher.ARCHIVE_NAME, "source.json"})

    def test_execute_checks_capacity_upload_identity_and_public_download(self):
        item = (self.metadata()["objectKey"], Path("/fixture/archive"),
                {"sha256": publisher.SHA256, "byteCount": publisher.BYTE_COUNT})
        service = mock.Mock()
        service.inventory.return_value = {"existing/object": {"Size": 10}}
        env = {"ARCLUME_RESOURCE_BASE_URL": "https://resources.example"}
        with tempfile.TemporaryDirectory() as name:
            lock_path = Path(name) / "resource-upload" / ".publish.lock"
            with mock.patch.object(publisher, "PUBLISH_LOCK", lock_path), \
                    mock.patch.dict(publisher.os.environ, env, clear=False), \
                    mock.patch.object(publisher, "S3", return_value=service) as s3, \
                    mock.patch.object(publisher, "check_capacity", return_value={"newBytes": publisher.BYTE_COUNT}) as capacity, \
                    mock.patch.object(publisher, "verify_public") as public:
                result = publisher.publish_object(item, "bucket")

        s3.assert_called_once()
        capacity.assert_called_once_with(service.inventory.return_value,
                                         {item[0]: publisher.BYTE_COUNT})
        service.put.assert_called_once()
        public.assert_called_once_with("https://resources.example", item[0], item[2])
        self.assertTrue(result["uploaded"])
        self.assertEqual(result["verified"], [{"key": item[0], **item[2]}])

    def test_execute_without_bucket_does_not_start_an_upload(self):
        with mock.patch.object(publisher, "S3") as service:
            with self.assertRaises(ManifestError):
                publisher.publish_object(("key", Path("archive"), {}), "")
        service.assert_not_called()


if __name__ == "__main__":
    unittest.main()
