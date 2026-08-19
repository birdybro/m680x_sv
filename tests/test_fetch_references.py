from __future__ import annotations

from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from tools import fetch_references


ROOT = Path(__file__).resolve().parents[1]


class ReferenceManifestTests(unittest.TestCase):
    def test_repository_manifest_is_valid_and_covers_initial_families(self) -> None:
        manifest = fetch_references.load_manifest(ROOT / "docs" / "references.yml")
        families = {
            family
            for reference in manifest["references"]
            for family in reference["processor_family"]
        }
        self.assertGreaterEqual(len(manifest["references"]), 7)
        for family in (
            "MC6800",
            "MC6801",
            "MC6803",
            "MC6805",
            "MC68705",
            "HD6301",
            "HD6303",
            "HD63701",
            "HD63705",
        ):
            self.assertIn(family, families)

    def test_duplicate_reference_id_is_rejected(self) -> None:
        manifest = fetch_references.load_manifest(ROOT / "docs" / "references.yml")
        broken = deepcopy(manifest)
        broken["references"].append(deepcopy(broken["references"][0]))
        with self.assertRaisesRegex(fetch_references.ReferenceError, "duplicate reference id"):
            fetch_references.validate_manifest(broken)

    def test_parent_path_filename_is_rejected(self) -> None:
        manifest = fetch_references.load_manifest(ROOT / "docs" / "references.yml")
        broken = deepcopy(manifest)
        broken["references"][0]["downloaded_filename"] = "../manual.pdf"
        with self.assertRaisesRegex(fetch_references.ReferenceError, "unsafe"):
            fetch_references.validate_manifest(broken)

    def test_download_is_atomic_and_digest_checked(self) -> None:
        payload = b"manufacturer document test fixture\n"
        digest = hashlib.sha256(payload).hexdigest()
        reference = {
            "id": "fixture-manual",
            "processor_family": ["FIXTURE"],
            "manufacturer": "Fixture Manufacturer",
            "title": "Fixture Manual",
            "manufacturer_document_number": None,
            "revision": None,
            "publication_date": "2000",
            "source_status": "manufacturer_hosted",
            "canonical_url": "https://example.invalid/fixture.pdf",
            "archival_url": None,
            "downloaded_filename": "fixture.pdf",
            "sha256": digest,
            "subjects": ["test"],
            "derived_dependencies": ["fetcher unit test"],
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path = root / "references.yml"
            manifest_path.write_text(
                json.dumps({"schema_version": 1, "references": [reference]}),
                encoding="utf-8",
            )
            cache = root / "cache"

            present, downloaded = fetch_references.process_references(
                manifest_path, cache, opener=lambda _url: io.BytesIO(payload)
            )

            self.assertEqual((present, downloaded), (1, 1))
            self.assertEqual((cache / "fixture.pdf").read_bytes(), payload)
            self.assertEqual(list(cache.glob("*.part")), [])

    def test_existing_bad_digest_is_rejected_without_replacement(self) -> None:
        manifest = fetch_references.load_manifest(ROOT / "docs" / "references.yml")
        one_reference = deepcopy(manifest["references"][0])
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest_path = root / "references.yml"
            manifest_path.write_text(
                json.dumps({"schema_version": 1, "references": [one_reference]}),
                encoding="utf-8",
            )
            cache = root / "cache"
            cache.mkdir()
            path = cache / one_reference["downloaded_filename"]
            path.write_bytes(b"wrong")

            with self.assertRaisesRegex(fetch_references.ReferenceError, "cached digest mismatch"):
                fetch_references.process_references(manifest_path, cache)
            self.assertEqual(path.read_bytes(), b"wrong")


if __name__ == "__main__":
    unittest.main()
