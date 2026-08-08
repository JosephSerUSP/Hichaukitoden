"""Shared authored-data storage semantics for repository tooling.

Ordered collections use an index.json manifest because order is authored data.
Unordered registries derive identity exclusively from each record's ``id`` and
therefore need no shared manifest. Monoliths intentionally remain authoritative
while they coexist with fragments; deleting the monolith activates the split.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"authored JSON file does not exist: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in {path}: {exc}") from exc


def validate_ordered(entries: Any, stem: str, source: Path) -> list[dict[str, Any]]:
    if not isinstance(entries, list) or not entries:
        raise ValueError(f"ordered collection '{stem}' must be a non-empty array: {source}")

    seen: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        if not isinstance(entry, dict) or "id" not in entry:
            raise ValueError(f"ordered collection '{stem}' entry {index} has no id: {source}")
        key = str(entry["id"])
        if key in seen:
            raise ValueError(f"ordered collection '{stem}' has duplicate id '{key}': {source}")
        seen.add(key)
    return entries


def _ordered_manifest_files(manifest: Any, stem: str) -> list[str]:
    files = manifest.get("files") if isinstance(manifest, dict) else manifest
    if not isinstance(files, list) or not files:
        raise ValueError(f"{stem}/index.json must be an array or {{ files = [...] }}")

    seen: set[str] = set()
    for name in files:
        if not isinstance(name, str) or not name:
            raise ValueError(f"{stem}/index.json entries must be non-empty filenames")
        path = Path(name)
        if path.is_absolute() or len(path.parts) != 1 or ".." in name:
            raise ValueError(f"{stem}/index.json contains an unsafe fragment path: {name}")
        if path.suffix != ".json":
            raise ValueError(f"{stem}/index.json fragment must end in .json: {name}")
        if name in seen:
            raise ValueError(f"{stem}/index.json lists the same fragment twice: {name}")
        seen.add(name)
    return files


def load_ordered_collection(root: Path, stem: str) -> tuple[list[dict[str, Any]], str]:
    monolith = root / f"{stem}.json"
    if monolith.exists():
        return validate_ordered(read_json(monolith), stem, monolith), "monolith"

    directory = root / stem
    index_path = directory / "index.json"
    if not index_path.exists():
        raise ValueError(
            f"could not find ordered collection '{stem}' at {monolith} or {index_path}"
        )

    files = _ordered_manifest_files(read_json(index_path), stem)
    out: list[dict[str, Any]] = []
    for name in files:
        path = directory / name
        if not path.exists():
            raise ValueError(f"{stem}/index.json references a missing fragment: {path}")
        value = read_json(path)
        if isinstance(value, dict) and "id" in value:
            out.append(value)
        elif isinstance(value, list) and value:
            if not all(isinstance(entry, dict) for entry in value):
                raise ValueError(f"ordered fragment contains a non-object: {path}")
            out.extend(value)
        else:
            raise ValueError(
                f"ordered fragment is neither an object with id nor a non-empty array: {path}"
            )
    return validate_ordered(out, stem, index_path), "fragments"


def validate_registry_record(record: Any, stem: str, source: Path) -> str:
    if not isinstance(record, dict):
        raise ValueError(f"registry '{stem}' record is not an object: {source}")
    record_id = record.get("id")
    if not isinstance(record_id, str) or not record_id:
        raise ValueError(f"registry '{stem}' record must own a non-empty string id: {source}")
    return record_id


def validate_registry_monolith(value: Any, stem: str, source: Path) -> dict[str, dict[str, Any]]:
    if not isinstance(value, dict) or not value:
        raise ValueError(f"registry '{stem}' must be a non-empty object: {source}")

    out: dict[str, dict[str, Any]] = {}
    for key, record in value.items():
        record_id = validate_registry_record(record, stem, source)
        if key != record_id:
            raise ValueError(
                f"registry '{stem}' key '{key}' disagrees with record.id '{record_id}': {source}"
            )
        if record_id in out:
            raise ValueError(f"registry '{stem}' has duplicate id '{record_id}': {source}")
        out[record_id] = record
    return out


def load_registry_fragments(directory: Path, stem: str | None = None) -> dict[str, dict[str, Any]]:
    stem = stem or directory.name
    if not directory.exists():
        raise ValueError(f"registry directory does not exist: {directory}")
    if (directory / "index.json").exists():
        raise ValueError(f"registry '{stem}' must not use a shared index.json")

    files = sorted(path for path in directory.glob("*.json") if path.is_file())
    if not files:
        raise ValueError(f"registry '{stem}' has no JSON fragments: {directory}")

    out: dict[str, dict[str, Any]] = {}
    for path in files:
        record = read_json(path)
        record_id = validate_registry_record(record, stem, path)
        if record_id in out:
            raise ValueError(f"registry '{stem}' has duplicate id '{record_id}': {path}")
        out[record_id] = record
    return out


def load_registry(root: Path, stem: str) -> tuple[dict[str, dict[str, Any]], str]:
    monolith = root / f"{stem}.json"
    if monolith.exists():
        return validate_registry_monolith(read_json(monolith), stem, monolith), "monolith"
    return load_registry_fragments(root / stem, stem), "fragments"


def registry_fragment_names(records: dict[str, dict[str, Any]]) -> dict[str, str]:
    """Return deterministic storage filenames without making filenames identity.

    Safe, case-insensitively unique ids get the readable ``<id>.json`` form.
    Unsafe ids or case-fold collisions receive a stable slug plus a short hash.
    """

    folded: dict[str, int] = {}
    for record_id in records:
        key = record_id.casefold()
        folded[key] = folded.get(key, 0) + 1

    names: dict[str, str] = {}
    used: set[str] = set()
    for record_id in sorted(records):
        safe = bool(re.fullmatch(r"[A-Za-z0-9._-]+", record_id)) and record_id not in {".", ".."}
        if safe and folded[record_id.casefold()] == 1 and record_id.casefold() != "index":
            candidate = f"{record_id}.json"
        else:
            slug = re.sub(r"[^a-z0-9]+", "-", record_id.casefold()).strip("-") or "record"
            digest = hashlib.sha256(record_id.encode("utf-8")).hexdigest()[:10]
            candidate = f"{slug}--{digest}.json"

        folded_name = candidate.casefold()
        if folded_name in used:
            raise ValueError(f"registry filename collision for id '{record_id}': {candidate}")
        used.add(folded_name)
        names[record_id] = candidate
    return names


def _hash_file(hasher: "hashlib._Hash", root: Path, path: Path) -> None:
    relative = path.relative_to(root).as_posix().encode("utf-8")
    payload = path.read_bytes()
    hasher.update(len(relative).to_bytes(8, "big"))
    hasher.update(relative)
    hasher.update(len(payload).to_bytes(8, "big"))
    hasher.update(payload)


def version_token(root: Path, stem: str, kind: str) -> str:
    """Return a content-derived token covering every authoritative storage file."""

    if kind not in {"ordered", "registry"}:
        raise ValueError(f"unknown authored storage kind: {kind}")

    monolith = root / f"{stem}.json"
    hasher = hashlib.sha256()
    hasher.update(f"{kind}\0{stem}\0".encode("utf-8"))
    if monolith.exists():
        hasher.update(b"monolith\0")
        _hash_file(hasher, root, monolith)
        return hasher.hexdigest()

    directory = root / stem
    hasher.update(b"fragments\0")
    if kind == "ordered":
        index_path = directory / "index.json"
        files = _ordered_manifest_files(read_json(index_path), stem)
        _hash_file(hasher, root, index_path)
        for name in files:
            path = directory / name
            if not path.exists():
                raise ValueError(f"{stem}/index.json references a missing fragment: {path}")
            _hash_file(hasher, root, path)
    else:
        if (directory / "index.json").exists():
            raise ValueError(f"registry '{stem}' must not use a shared index.json")
        files = sorted(path for path in directory.glob("*.json") if path.is_file())
        if not files:
            raise ValueError(f"registry '{stem}' has no JSON fragments: {directory}")
        for path in files:
            _hash_file(hasher, root, path)
    return hasher.hexdigest()
