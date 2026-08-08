#!/usr/bin/env python3
"""Split authored JSON into deterministic ordered or registry fragments.

The default command is a dry run. Use --apply to write fragments beside the
legacy monolith. The runtime deliberately keeps reading the monolith while it
exists; --remove-source is the explicit migration boundary and should only be
used after every reader and writer understands the fragmented representation.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from authored_storage import (
    load_registry_fragments,
    read_json,
    registry_fragment_names,
    validate_ordered,
    validate_registry_monolith,
)


def slug(value: Any) -> str:
    text = str(value).strip().lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "entry"


def ordered_fragment_name(index: int, entry: dict[str, Any]) -> str:
    entry_id = entry.get("id", index)
    label = entry.get("name") or entry.get("title") or entry_id
    return f"{index:04d}-{slug(entry_id)}-{slug(label)}.json"


def planned_ordered_files(entries: list[dict[str, Any]]) -> list[str]:
    names: list[str] = []
    used: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        base = ordered_fragment_name(index, entry)
        name = base
        suffix = 2
        while name in used:
            name = base.removesuffix(".json") + f"-{suffix}.json"
            suffix += 1
        used.add(name)
        names.append(name)
    return names


def assembled_ordered(directory: Path, files: list[str]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for name in files:
        value = read_json(directory / name)
        if isinstance(value, list):
            out.extend(value)
        else:
            out.append(value)
    return out


def refuse_stale_fragments(directory: Path, expected: set[str]) -> None:
    existing = {path.name for path in directory.glob("*.json")}
    stale = sorted(existing - expected)
    if stale:
        raise ValueError(
            "refusing to leave stale fragments in "
            f"{directory}: {', '.join(stale)}; remove them explicitly"
        )


def write_ordered_split(
    source: Path, entries: list[dict[str, Any]], remove_source: bool
) -> None:
    directory = source.with_suffix("")
    directory.mkdir(parents=True, exist_ok=True)
    names = planned_ordered_files(entries)

    refuse_stale_fragments(directory, set(names) | {"index.json"})

    for name, entry in zip(names, entries, strict=True):
        (directory / name).write_text(
            json.dumps(entry, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    manifest = {
        "format": 1,
        "source": source.name,
        "files": names,
    }
    (directory / "index.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    round_trip = assembled_ordered(directory, names)
    if round_trip != entries:
        raise ValueError(f"round-trip verification failed for {source}")

    if remove_source:
        source.unlink()


def write_registry_split(
    source: Path, records: dict[str, dict[str, Any]], remove_source: bool
) -> None:
    directory = source.with_suffix("")
    directory.mkdir(parents=True, exist_ok=True)
    names = registry_fragment_names(records)

    expected = set(names.values())
    refuse_stale_fragments(directory, expected)
    if (directory / "index.json").exists():
        raise ValueError(
            f"refusing registry split because {directory / 'index.json'} exists; "
            "unordered registries do not use manifests"
        )

    for record_id in sorted(records):
        (directory / names[record_id]).write_text(
            json.dumps(records[record_id], indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    round_trip = load_registry_fragments(directory, source.stem)
    if round_trip != records:
        raise ValueError(f"round-trip verification failed for {source}")

    if remove_source:
        source.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("collection", help="data file stem, e.g. scenes or tilesets")
    parser.add_argument(
        "--kind",
        choices=("ordered", "registry"),
        default="ordered",
        help="ordered collections use index.json; registries do not",
    )
    parser.add_argument("--root", type=Path, default=Path("data"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--remove-source", action="store_true")
    args = parser.parse_args()

    source = args.root / f"{args.collection}.json"
    try:
        value = read_json(source)
        if args.kind == "ordered":
            entries = validate_ordered(value, args.collection, source)
            names = planned_ordered_files(entries)
            print(f"{source}: {len(entries)} ordered entries")
            print(f"target manifest: {source.with_suffix('') / 'index.json'}")
            for name in names:
                print(f"  {name}")
        else:
            records = validate_registry_monolith(value, args.collection, source)
            names_by_id = registry_fragment_names(records)
            print(f"{source}: {len(records)} registry records")
            print(f"target directory: {source.with_suffix('')} (no index.json)")
            for record_id in sorted(records):
                print(f"  {record_id} -> {names_by_id[record_id]}")

        if args.remove_source and not args.apply:
            raise ValueError("--remove-source requires --apply")
        if not args.apply:
            print("dry run; pass --apply to write fragments")
            return 0

        if args.kind == "ordered":
            write_ordered_split(source, entries, args.remove_source)
        else:
            write_registry_split(source, records, args.remove_source)
        mode = "activated split storage" if args.remove_source else "wrote review fragments"
        print(mode)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
