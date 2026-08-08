#!/usr/bin/env python3
"""Inventory and validate authored Unit identity references.

This tool exists for issue #147's numeric -> symbolic Unit-ID migration. It does
NOT invent symbolic IDs: deciding whether a definition is durably `pixie`,
`boss_1`, or something else is design authorship, not a slugging operation.

Examples:

    python tools/data/audit_unit_identity.py
    python tools/data/audit_unit_identity.py --json
    python tools/data/audit_unit_identity.py --mapping-template out/unit-id-map.json

The audit understands the legacy Unit-reference spellings that exist today:
`actorId`, troop/map `actor`, map `recruits`, transform-command `actor`,
evolution `evolvesTo`, Unit-owned transform metadata, and fixed new-game member `id`. As those
spellings are migrated, update this one inventory rather than letting each
migration script grow its own partial reference list.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data"

ScalarId = int | str
TRANSFORM_SENTINELS = {"hatch", "metamorph", "revert"}


@dataclass(frozen=True)
class Reference:
    file: str
    path: str
    field: str
    value: ScalarId


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"missing authored data: {path.relative_to(ROOT)}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path.relative_to(ROOT)}: {exc}") from exc


def is_id(value: Any) -> bool:
    return isinstance(value, int) or (isinstance(value, str) and value != "")


def is_unit_destination(value: Any) -> bool:
    return is_id(value) and value not in TRANSFORM_SENTINELS


def json_path(parent: str, key: str | int) -> str:
    if isinstance(key, int):
        return f"{parent}[{key}]"
    return f"{parent}.{key}"


def walk_refs(node: Any, rel: str, path: str = "$") -> Iterable[Reference]:
    """Yield generic reference fields whose semantics are Unit identity.

    `actorId` is an engine command/data vocabulary and can occur inside nested
    command lists in several resources. Bare `actor` is ambiguous, so it is
    recognized only in the legacy map/troop slot vocabulary or on an explicit
    TRANSFORM_ACTOR command. Unit-owned transform metadata is inventoried by
    `unit_definition_refs`, where its surrounding structure is known.
    """
    if isinstance(node, dict):
        if node.get("type") == "recruit_egg":
            value = node.get("value")
            if is_id(value):
                yield Reference(rel, f"{path}.value", "recruit_egg.value", value)

        command = node.get("cmd")
        for key, value in node.items():
            child = json_path(path, key)
            if key == "actorId" and is_id(value):
                yield Reference(rel, child, key, value)
            elif key == "evolvesTo" and rel == "actors.json" and is_id(value):
                yield Reference(rel, child, key, value)
            elif key == "actor" and rel in {"maps.json", "troops.json"} and is_id(value):
                yield Reference(rel, child, key, value)
            elif key == "actor" and command == "TRANSFORM_ACTOR" and is_unit_destination(value):
                yield Reference(rel, child, "transformCommand.actor", value)
            yield from walk_refs(value, rel, child)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from walk_refs(value, rel, json_path(path, index))


def unit_definition_refs(units: list[dict[str, Any]]) -> Iterable[Reference]:
    """References whose meaning comes from a Unit definition's transform schema.

    These cannot be discovered safely by treating every field named `actor` as
    a Unit reference: the English word is too generic, and autoTransforms also
    uses the string sentinels hatch/metamorph/revert as operations rather than
    identities. Keep the schema knowledge explicit here.
    """
    for unit_index, unit in enumerate(units):
        if not isinstance(unit, dict):
            continue
        base = f"$[{unit_index}]"

        for index, rule in enumerate(unit.get("autoTransforms") or []):
            if isinstance(rule, dict) and is_unit_destination(rule.get("actor")):
                yield Reference(
                    "actors.json",
                    f"{base}.autoTransforms[{index}].actor",
                    "autoTransforms.actor",
                    rule["actor"],
                )

        for index, rule in enumerate(unit.get("secretTransforms") or []):
            if isinstance(rule, dict) and is_unit_destination(rule.get("actor")):
                yield Reference(
                    "actors.json",
                    f"{base}.secretTransforms[{index}].actor",
                    "secretTransforms.actor",
                    rule["actor"],
                )

        outcomes = unit.get("hatchOutcomes") or {}
        if isinstance(outcomes, dict):
            for outcome_key, outcome in outcomes.items():
                if isinstance(outcome, dict) and is_unit_destination(outcome.get("actor")):
                    yield Reference(
                        "actors.json",
                        f"{base}.hatchOutcomes.{outcome_key}.actor",
                        "hatchOutcomes.actor",
                        outcome["actor"],
                    )

        for index, value in enumerate(unit.get("eligibleFrom") or []):
            if is_unit_destination(value):
                yield Reference(
                    "actors.json",
                    f"{base}.eligibleFrom[{index}]",
                    "eligibleFrom",
                    value,
                )


def map_recruit_refs(maps: Any) -> Iterable[Reference]:
    """Unit references in each map's direct recruitment pool."""
    if not isinstance(maps, list):
        return
    for map_index, map_record in enumerate(maps):
        if not isinstance(map_record, dict):
            continue
        recruits = map_record.get("recruits")
        if not isinstance(recruits, list):
            continue
        for recruit_index, value in enumerate(recruits):
            if is_id(value):
                yield Reference(
                    "maps.json",
                    f"$[{map_index}].recruits[{recruit_index}]",
                    "recruits",
                    value,
                )


def golden_battle_refs(fixtures: Any) -> Iterable[Reference]:
    """Unit references in deterministic G2 battle fixtures."""
    if not isinstance(fixtures, list):
        return
    for fixture_index, fixture in enumerate(fixtures):
        if not isinstance(fixture, dict):
            continue
        for encounter_index, encounter in enumerate(fixture.get("encounters") or []):
            if not isinstance(encounter, dict):
                continue
            for party_index, value in enumerate(encounter.get("party") or []):
                if is_id(value):
                    yield Reference(
                        "goldenBattles.json",
                        f"$[{fixture_index}].encounters[{encounter_index}].party[{party_index}]",
                        "golden.party",
                        value,
                    )
            for enemy_index, enemy in enumerate(encounter.get("enemies") or []):
                if not isinstance(enemy, dict):
                    continue
                value = enemy.get("actor")
                if is_id(value):
                    yield Reference(
                        "goldenBattles.json",
                        f"$[{fixture_index}].encounters[{encounter_index}].enemies[{enemy_index}].actor",
                        "golden.actor",
                        value,
                    )


def fixed_member_refs(system: Any) -> Iterable[Reference]:
    try:
        members = system["newGame"]["party"].get("fixedMembers")
    except (KeyError, TypeError, AttributeError):
        return
    if members is None:
        return
    for index, member in enumerate(members):
        if isinstance(member, dict) and is_id(member.get("id")):
            yield Reference(
                "system.json",
                f"$.newGame.party.fixedMembers[{index}].id",
                "fixedMember.id",
                member["id"],
            )


def load_units(data_dir: Path) -> tuple[list[dict[str, Any]], dict[ScalarId, dict[str, Any]], list[str]]:
    actors_path = data_dir / "actors.json"
    units = read_json(actors_path)
    if not isinstance(units, list) or not units:
        raise SystemExit("data/actors.json must currently be a non-empty array of Unit definitions")

    by_id: dict[ScalarId, dict[str, Any]] = {}
    problems: list[str] = []
    for index, unit in enumerate(units):
        if not isinstance(unit, dict):
            problems.append(f"actors.json[{index}] is not an object")
            continue
        uid = unit.get("id")
        if not isinstance(uid, str) or uid == "":
            problems.append(f"actors.json[{index}] must have a non-empty symbolic string id")
            continue
        if uid in by_id:
            problems.append(f"duplicate Unit id {uid!r} at actors.json[{index}]")
            continue
        by_id[uid] = unit
    return units, by_id, problems


def collect(data_dir: Path) -> tuple[list[dict[str, Any]], dict[ScalarId, dict[str, Any]], list[Reference], list[str]]:
    units, by_id, problems = load_units(data_dir)
    refs: list[Reference] = list(unit_definition_refs(units))

    # Scan every top-level authored JSON document for generic reference
    # spellings. Fragmented resources can be added here later by making this a
    # storage-aware enumerator; actors are intentionally still monolithic in
    # this migration-planning slice.
    for path in sorted(data_dir.glob("*.json")):
        rel = path.name
        value = read_json(path)
        refs.extend(walk_refs(value, rel))
        if rel == "maps.json":
            refs.extend(map_recruit_refs(value) or [])
        if rel == "goldenBattles.json":
            refs.extend(golden_battle_refs(value) or [])
        if rel == "system.json":
            refs.extend(fixed_member_refs(value) or [])

    for ref in refs:
        if ref.value not in by_id:
            problems.append(
                f"unresolved Unit reference {ref.value!r} at {ref.file}:{ref.path}"
            )

    refs.sort(key=lambda r: (r.file, r.path, str(r.value)))
    return units, by_id, refs, problems


def mapping_template(units: list[dict[str, Any]], refs: list[Reference]) -> dict[str, Any]:
    counts = Counter(ref.value for ref in refs)
    records = []
    for unit in units:
        uid = unit.get("id")
        if not is_id(uid):
            continue
        records.append({
            "oldId": uid,
            "newId": None,
            "name": unit.get("name"),
            "role": unit.get("role"),
            "referenceCount": counts.get(uid, 0),
        })
    return {
        "version": 1,
        "note": (
            "Fill newId by design intent. Do not mechanically slug display names; "
            "functional identities such as boss_1 may be more stable."
        ),
        "units": records,
    }


def report(units: list[dict[str, Any]], by_id: dict[ScalarId, dict[str, Any]], refs: list[Reference], problems: list[str]) -> dict[str, Any]:
    numeric = sum(1 for uid in by_id if isinstance(uid, int))
    symbolic = sum(1 for uid in by_id if isinstance(uid, str))
    fields = Counter(ref.field for ref in refs)
    files = Counter(ref.file for ref in refs)
    return {
        "unitDefinitions": len(by_id),
        "numericUnitIds": numeric,
        "symbolicUnitIds": symbolic,
        "referenceCount": len(refs),
        "referencesByField": dict(sorted(fields.items())),
        "referencesByFile": dict(sorted(files.items())),
        "problems": problems,
        "references": [asdict(ref) for ref in refs],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="print the full machine-readable inventory")
    parser.add_argument(
        "--mapping-template",
        type=Path,
        help="write an owner-fillable oldId/newId mapping skeleton; no IDs are guessed",
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=DATA,
        help="authored data root (mainly for tests; default: repository data/)",
    )
    args = parser.parse_args(argv)

    units, by_id, refs, problems = collect(args.data_dir)
    result = report(units, by_id, refs, problems)

    if args.mapping_template:
        target = args.mapping_template
        if not target.is_absolute():
            target = ROOT / target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(mapping_template(units, refs), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"wrote Unit ID mapping template: {target}")

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(
            f"Unit identity audit: {result['unitDefinitions']} definitions "
            f"({result['numericUnitIds']} numeric, {result['symbolicUnitIds']} symbolic), "
            f"{result['referenceCount']} authored references"
        )
        for field, count in result["referencesByField"].items():
            print(f"  {field}: {count}")
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        if not problems:
            print("Unit identity audit: OK")

    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
