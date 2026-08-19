#!/usr/bin/env python3
"""Validate and acquire the clean-room primary-reference cache."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from typing import BinaryIO, Callable
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "docs" / "references.yml"
DEFAULT_CACHE = ROOT / ".reference"
ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REQUIRED_FIELDS = {
    "id",
    "processor_family",
    "manufacturer",
    "title",
    "manufacturer_document_number",
    "revision",
    "publication_date",
    "source_status",
    "canonical_url",
    "archival_url",
    "downloaded_filename",
    "sha256",
    "subjects",
    "derived_dependencies",
}
SOURCE_STATUSES = {
    "manufacturer_hosted",
    "archival_scan_original_manufacturer_document",
}


class ReferenceError(RuntimeError):
    """Raised for invalid metadata, unsafe paths, or digest failures."""


def load_manifest(path: Path) -> dict:
    """Load the JSON-compatible YAML manifest."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReferenceError(f"cannot load reference manifest {path}: {exc}") from exc
    validate_manifest(value)
    return value


def _nonempty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _validate_url(value: object, field: str, reference_id: str) -> None:
    if value is None:
        return
    if not _nonempty_string(value):
        raise ReferenceError(f"{reference_id}: {field} must be a URL or null")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ReferenceError(f"{reference_id}: {field} must use HTTPS")


def validate_manifest(manifest: object) -> None:
    """Validate schema, uniqueness, provenance, and path safety."""
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ReferenceError("manifest schema_version must be 1")
    references = manifest.get("references")
    if not isinstance(references, list) or not references:
        raise ReferenceError("manifest must contain a non-empty references list")

    seen_ids: set[str] = set()
    seen_filenames: set[str] = set()
    for index, reference in enumerate(references):
        if not isinstance(reference, dict):
            raise ReferenceError(f"reference {index} must be an object")
        missing = REQUIRED_FIELDS - reference.keys()
        extra = reference.keys() - REQUIRED_FIELDS
        if missing:
            raise ReferenceError(f"reference {index} missing fields: {sorted(missing)}")
        if extra:
            raise ReferenceError(f"reference {index} has unknown fields: {sorted(extra)}")

        reference_id = reference["id"]
        if not isinstance(reference_id, str) or not ID_RE.fullmatch(reference_id):
            raise ReferenceError(f"reference {index} has invalid id")
        if reference_id in seen_ids:
            raise ReferenceError(f"duplicate reference id: {reference_id}")
        seen_ids.add(reference_id)

        for field in ("manufacturer", "title", "publication_date"):
            if not _nonempty_string(reference[field]):
                raise ReferenceError(f"{reference_id}: {field} must be non-empty")
        for field in ("manufacturer_document_number", "revision"):
            value = reference[field]
            if value is not None and not _nonempty_string(value):
                raise ReferenceError(f"{reference_id}: {field} must be non-empty or null")
        for field in ("processor_family", "subjects", "derived_dependencies"):
            values = reference[field]
            if (
                not isinstance(values, list)
                or not values
                or any(not _nonempty_string(value) for value in values)
            ):
                raise ReferenceError(f"{reference_id}: {field} must be non-empty strings")

        status = reference["source_status"]
        if status not in SOURCE_STATUSES:
            raise ReferenceError(f"{reference_id}: unsupported source_status {status!r}")
        _validate_url(reference["canonical_url"], "canonical_url", reference_id)
        _validate_url(reference["archival_url"], "archival_url", reference_id)
        if status == "manufacturer_hosted" and reference["canonical_url"] is None:
            raise ReferenceError(f"{reference_id}: manufacturer-hosted source needs canonical_url")
        if status.startswith("archival_") and reference["archival_url"] is None:
            raise ReferenceError(f"{reference_id}: archival source needs archival_url")

        filename = reference["downloaded_filename"]
        if (
            not _nonempty_string(filename)
            or Path(filename).name != filename
            or filename in {".", ".."}
        ):
            raise ReferenceError(f"{reference_id}: unsafe downloaded_filename")
        if filename in seen_filenames:
            raise ReferenceError(f"duplicate downloaded_filename: {filename}")
        seen_filenames.add(filename)
        if not isinstance(reference["sha256"], str) or not SHA256_RE.fullmatch(
            reference["sha256"]
        ):
            raise ReferenceError(f"{reference_id}: sha256 must be 64 lowercase hex digits")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _open_url(url: str) -> BinaryIO:
    request = Request(url, headers={"User-Agent": "m680x_sv-reference-fetcher/1"})
    return urlopen(request, timeout=60)


def _download(
    url: str,
    destination: Path,
    expected_sha256: str,
    opener: Callable[[str], BinaryIO],
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{destination.name}.", suffix=".part", dir=destination.parent,
            delete=False
        ) as output:
            temporary_name = output.name
            digest = hashlib.sha256()
            with opener(url) as source:
                while chunk := source.read(1024 * 1024):
                    output.write(chunk)
                    digest.update(chunk)
            output.flush()
            os.fsync(output.fileno())
        actual = digest.hexdigest()
        if actual != expected_sha256:
            raise ReferenceError(
                f"download digest mismatch for {destination.name}: "
                f"expected {expected_sha256}, got {actual}"
            )
        os.replace(temporary_name, destination)
        temporary_name = None
    finally:
        if temporary_name is not None:
            Path(temporary_name).unlink(missing_ok=True)


def process_references(
    manifest_path: Path = DEFAULT_MANIFEST,
    cache_dir: Path = DEFAULT_CACHE,
    *,
    check_only: bool = False,
    manifest_only: bool = False,
    opener: Callable[[str], BinaryIO] = _open_url,
) -> tuple[int, int]:
    """Validate, then check or fetch references; return (present, downloaded)."""
    manifest = load_manifest(manifest_path)
    if manifest_only:
        return (0, 0)

    present = 0
    downloaded = 0
    for reference in manifest["references"]:
        destination = cache_dir / reference["downloaded_filename"]
        if destination.is_file():
            actual = sha256_file(destination)
            if actual != reference["sha256"]:
                raise ReferenceError(
                    f"cached digest mismatch for {destination}: "
                    f"expected {reference['sha256']}, got {actual}"
                )
            present += 1
            print(f"verified  {reference['id']}")
            continue
        if check_only:
            raise ReferenceError(f"reference is not cached: {destination}")
        url = reference["canonical_url"] or reference["archival_url"]
        assert isinstance(url, str)
        print(f"fetching  {reference['id']}")
        _download(url, destination, reference["sha256"], opener)
        downloaded += 1
        present += 1
        print(f"verified  {reference['id']}")
    return (present, downloaded)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="require all files in cache")
    mode.add_argument(
        "--manifest-only", action="store_true", help="validate metadata without network or cache"
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        present, downloaded = process_references(
            args.manifest,
            args.cache_dir,
            check_only=args.check,
            manifest_only=args.manifest_only,
        )
    except ReferenceError as exc:
        print(f"reference error: {exc}", file=sys.stderr)
        return 1
    if args.manifest_only:
        print(f"reference manifest valid: {args.manifest}")
    else:
        print(f"references verified: {present}; downloaded: {downloaded}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
