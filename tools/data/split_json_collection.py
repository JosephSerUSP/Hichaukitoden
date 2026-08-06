#!/usr/bin/env python3
"""Split an ordered JSON array into an indexed directory of fragments.

The default command is a dry run. Use --apply to write fragments beside the
legacy monolith. The runtime deliberately keeps reading the monolith while it
exists; --remove-source is the explicit migration boundary and should only be
used after every editor/server writer understands fragmented collections.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def slug(value: Any) -> str:
    text = str(value).strip().lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "entry"


def fragment_name(index: int, entry: dict[str, Any]) -> str:
    entry_id = entry.get("id", index)
    label = entry.get("name") or entry.get("title") or entry_id
    return f"{index:04d}-{slug(entry_id)}-{slug(label)}.json"


def load_collection(source: Path) -> list[dict[str, Any]]:
    try:
        value = json.loads(source.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"source does not exist: {source}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in {source}: {exc}") from exc

    if not isinstance(value, list):
        raise ValueError(f"{source} must contain a JSON array")
    if not value:
        raise ValueError(f"{source} is empty")
    for index, entry in enumerate(value, start=1):
        if not isinstance(entry, dict):
            raise ValueError(f"{source}[{index}] is not an object")
        if "id" not in entry:
            raise ValueError(f"{source}[{index}] has no id")
    return value


def planned_files(entries: list[dict[str, Any]]) -> list[str]:
    names: list[str] = []
    used: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        base = fragment_name(index, entry)
        name = base
        suffix = 2
        while name in used:
            name = base.removesuffix(".json") + f"-{suffix}.json"
            suffix += 1
        used.add(name)
        names.append(name)
    return names


def assembled(directory: Path, files: list[str]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for name in files:
        value = json.loads((directory / name).read_text(encoding="utf-8"))
        if isinstance(value, list):
            out.extend(value)
        else:
            out.append(value)
    return out


def write_split(source: Path, entries: list[dict[str, Any]], remove_source: bool) -> None:
    directory = source.with_suffix("")
    directory.mkdir(parents=True, exist_ok=True)
    names = planned_files(entries)

    expected = set(names) | {"index.json"}
    existing = {p.name for p in directory.glob("*.json")}
    stale = sorted(existing - expected)
    if stale:
        raise ValueError(
            "refusing to leave stale fragments in "
            f"{directory}: {', '.join(stale)}; remove them explicitly"
        )

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

    round_trip = assembled(directory, names)
    if round_trip != entries:
        raise ValueError(f"round-trip verification failed for {source}")

    if remove_source:
        source.unlink()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("collection", choices=("scenes", "maps"))
    parser.add_argument("--root", type=Path, default=Path("data"))
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--remove-source", action="store_true")
    args = parser.parse_args()

    source = args.root / f"{args.collection}.json"
    try:
        entries = load_collection(source)
        names = planned_files(entries)
        print(f"{source}: {len(entries)} entries")
        print(f"target: {source.with_suffix('') / 'index.json'}")
        for name in names:
            print(f"  {name}")

        if args.remove_source and not args.apply:
            raise ValueError("--remove-source requires --apply")
        if not args.apply:
            print("dry run; pass --apply to write fragments")
            return 0

        write_split(source, entries, args.remove_source)
        mode = "activated split collection" if args.remove_source else "wrote review fragments"
        print(mode)
        return 0
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
