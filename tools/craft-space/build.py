#!/usr/bin/env python3
"""Bake data/*.json into a standalone craft-space.html.

The Item Creation redesign derives an item's crafting signature from the
properties it already carries (type, equipType, effects, traits, cost, name)
rather than from hand-authored meta. Those derivation rules are guesswork
until they can be seen against the real database, so this prototypes them in
JS -- cheap to tune, and nothing lands in the engine until the model settles.

Run from anywhere:  python tools/craft-space/build.py
"""

import json
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DATA = ROOT / "data"

MARKER = "/*__DATA__*/{}"


def load(name):
    with open(DATA / f"{name}.json", encoding="utf-8") as fh:
        return json.load(fh)


def main():
    items = load("items")
    actors = load("actors")
    elements = load("elements")
    engine = load("engine")

    with open(HERE / "lexicon.json", encoding="utf-8") as fh:
        lexicon = {k: v for k, v in json.load(fh).items() if not k.startswith("_")}

    with open(HERE / "overrides.json", encoding="utf-8") as fh:
        ov = json.load(fh)
    grades = {g["grade"]: g["mult"] for g in ov["intensityGrades"]}
    itemGrades = ov.get("items", {})
    bad = {k: v for k, v in itemGrades.items() if v not in grades}
    if bad:
        raise SystemExit(
            "overrides.json assigns unregistered intensity grade(s): %s. "
            "Registered grades: %s"
            % (", ".join(f"{k}={v}" for k, v in bad.items()), ", ".join(grades)))
    names = {it["name"] for it in items}
    missing = sorted(set(itemGrades) - names)
    if missing:
        raise SystemExit("overrides.json names item(s) that do not exist: %s"
                         % ", ".join(missing))

    # Prototype stand-in for meta.disciplines: which crafts can PRODUCE an item.
    kinds = {d["kind"] for d in engine.get("disciplines", [])}
    itemDisc = ov.get("disciplines", {})
    missing = sorted(set(itemDisc) - names)
    if missing:
        raise SystemExit("overrides.json disciplines names item(s) that do not exist: %s"
                         % ", ".join(missing))
    for name, ds in itemDisc.items():
        bad = [d for d in ds if d not in kinds]
        if bad:
            raise SystemExit(
                "overrides.json gives %s unregistered discipline(s): %s. Registered: %s"
                % (name, ", ".join(bad), ", ".join(sorted(kinds))))

    # The five true elements: Red > Green > Blue > Red is a cycle, White <->
    # Black is an opposition, and anything else is non-elemental. The hue
    # plane and value axis are built on exactly this shape, so an unexpected
    # element would be plotted wrongly rather than obviously -- fail loud.
    TRUE = {"Red", "Green", "Blue", "White", "Black"}
    unknown = sorted(set(elements) - TRUE)
    if unknown:
        raise SystemExit(
            "data/elements.json declares element(s) the hue/value geometry has "
            "no place for: %s. Add an axis for them or remove them."
            % ", ".join(unknown))

    strong = {k: v.get("strongAgainst", []) for k, v in elements.items()}
    weak = {k: v.get("weakAgainst", []) for k, v in elements.items()}

    payload = {
        "items": [
            {
                "id": it["id"],
                "name": it["name"],
                "type": it.get("type"),
                "equipType": it.get("equipType"),
                "category": it.get("category"),
                "cost": it.get("cost", 0),
                "description": it.get("description", ""),
                "effects": it.get("effects", []),
                "traits": it.get("traits", []),
                "meta": it.get("meta", {}),
            }
            for it in items
        ],
        "actors": [
            {
                "id": a["id"],
                "name": a["name"],
                "discipline": a.get("discipline"),
                "elements": [e for e in a.get("elements", []) if e in TRUE],
                "baseParams": a.get("baseParams", {}),
            }
            for a in actors
        ],
        "disciplines": engine.get("disciplines", []),
        # Dominance-weighted blending reuses the battle affinity table. The
        # skill layer is the right analogue: one element asserting itself over
        # another, which is exactly what happens in the pot.
        "rules": {
            "strongMultiplier": 1 + engine["elementRules"]["skillStrongBonus"],
            "weakMultiplier": engine["elementRules"]["skillWeakMultiplier"],
        },
        "strong": strong,
        "weak": weak,
        "lexicon": lexicon,
        "grades": grades,
        "itemGrades": itemGrades,
        "itemDisciplines": itemDisc,
    }

    template = (HERE / "template.html").read_text(encoding="utf-8")
    if MARKER not in template:
        raise SystemExit("template.html lost its %s marker" % MARKER)

    blob = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    out = HERE / "craft-space.html"
    out.write_text(template.replace(MARKER, blob), encoding="utf-8")

    print(f"wrote {out.relative_to(ROOT)}  ({out.stat().st_size // 1024} KB)")
    print(f"  {len(payload['items'])} items, {len(payload['actors'])} actors, "
          f"{len(lexicon)} lexicon words")
    print(f"  elements: {', '.join(sorted(elements))}")
    print(f"  intensity overrides: {len(itemGrades)} of {len(items)} items")


if __name__ == "__main__":
    main()
