#!/usr/bin/env python3
"""Deterministic comparison and decision record for Second Rite issue #168.

The comparison preserves the pre-#168 multiplicative baseline alongside three
general alternatives. The owner selected signed-net/separate on 2026-08-08;
this tool remains useful as an audit artifact and does not itself change live
combat data or runtime math.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import math
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MD = ROOT / "docs" / "reports" / "element-affinity-comparison.md"
DEFAULT_CSV = ROOT / "docs" / "reports" / "element-affinity-comparison.csv"

MODEL_ORDER = ("current", "signed_net", "signed_rms", "joint_weighted")
MODEL_LABELS = {
    "current": "Current",
    "signed_net": "Signed net / separate",
    "signed_rms": "Signed RMS / separate",
    "joint_weighted": "Weighted signed / joint",
}


def load_inputs() -> tuple[dict, dict]:
    elements = json.loads((ROOT / "data" / "elements.json").read_text(encoding="utf-8"))
    engine = json.loads((ROOT / "data" / "engine.json").read_text(encoding="utf-8"))
    rules = engine.get("elementRules") or {}
    return elements, rules


def relation(elements: dict, source: str, target: str) -> int:
    authored = elements.get(source) or {}
    if target in (authored.get("strongAgainst") or []):
        return 1
    if target in (authored.get("weakAgainst") or []):
        return -1
    return 0


def count_matches(elements: dict, sources: Iterable[str], targets: Iterable[str]) -> tuple[int, int, int]:
    strong = weak = pairs = 0
    for source in sources:
        for target in targets:
            pairs += 1
            value = relation(elements, source, target)
            if value > 0:
                strong += 1
            elif value < 0:
                weak += 1
    return strong, weak, pairs


def stack_bonus(rate: float, decay: float, count: float) -> float:
    if count <= 0:
        return 0.0
    if decay >= 1:
        return rate * count
    return rate * (1 - decay**count) / (1 - decay)


def rule(rules: dict, key: str, fallback: float) -> float:
    value = rules.get(key, fallback)
    if not isinstance(value, (int, float)):
        raise ValueError(f"elementRules.{key} must be numeric")
    return float(value)


def current_layer(strong: int, weak: int, bonus: float, decay: float, weak_mult: float, floor: float) -> float:
    multiplier = 1.0 + stack_bonus(bonus, decay, strong)
    if weak > 0:
        multiplier *= max(floor, weak_mult**weak)
    return multiplier


def signed_layer(score: float, bonus: float, decay: float, weak_mult: float, floor: float) -> float:
    if abs(score) < 1e-12:
        return 1.0
    if score > 0:
        return 1.0 + stack_bonus(bonus, decay, score)
    return max(floor, weak_mult ** (-score))


def tuning(rules: dict, prefix: str) -> tuple[float, float, float, float]:
    floor = rule(rules, "weakFloor", 0.3)
    if prefix == "skill":
        return (
            rule(rules, "skillStrongBonus", 0.5),
            rule(rules, "skillStrongDecay", 0.7),
            rule(rules, "skillWeakMultiplier", 0.65),
            floor,
        )
    return (
        rule(rules, "userStrongBonus", 0.15),
        rule(rules, "userStrongDecay", 0.8),
        rule(rules, "userWeakMultiplier", 0.9),
        floor,
    )


def current_multiplier(elements: dict, rules: dict, skill: str | None, user: list[str], target: list[str]) -> float:
    multiplier = 1.0
    if skill:
        strong, weak, _ = count_matches(elements, [skill], target)
        multiplier *= current_layer(strong, weak, *tuning(rules, "skill"))
    if user:
        strong, weak, _ = count_matches(elements, user, target)
        multiplier *= current_layer(strong, weak, *tuning(rules, "user"))
    return multiplier


def separate_signed_multiplier(
    elements: dict,
    rules: dict,
    skill: str | None,
    user: list[str],
    target: list[str],
    normalize_rms: bool,
) -> float:
    multiplier = 1.0
    if skill:
        strong, weak, pairs = count_matches(elements, [skill], target)
        score = strong - weak
        if normalize_rms and pairs > 0:
            score /= math.sqrt(pairs)
        multiplier *= signed_layer(score, *tuning(rules, "skill"))
    if user:
        strong, weak, pairs = count_matches(elements, user, target)
        score = strong - weak
        if normalize_rms and pairs > 0:
            score /= math.sqrt(pairs)
        multiplier *= signed_layer(score, *tuning(rules, "user"))
    return multiplier


def joint_weight(rules: dict) -> float:
    """Approximate the authored first-match user influence on the skill scale.

    The current positive step is +0.15 versus +0.50 for skills, while the weak
    steps are 0.90 versus 0.65. A single signed weight cannot match both sides
    exactly, so use the mean of their relative log/linear strengths. This model
    is deliberately diagnostic rather than a proposed final formula.
    """
    skill_bonus = rule(rules, "skillStrongBonus", 0.5)
    user_bonus = rule(rules, "userStrongBonus", 0.15)
    positive = user_bonus / skill_bonus if skill_bonus else 0.0
    skill_weak = rule(rules, "skillWeakMultiplier", 0.65)
    user_weak = rule(rules, "userWeakMultiplier", 0.9)
    negative = math.log(user_weak) / math.log(skill_weak) if 0 < skill_weak < 1 and 0 < user_weak < 1 else positive
    return (positive + negative) / 2


def joint_weighted_multiplier(elements: dict, rules: dict, skill: str | None, user: list[str], target: list[str]) -> float:
    score = 0.0
    if skill:
        strong, weak, _ = count_matches(elements, [skill], target)
        score += strong - weak
    if user:
        strong, weak, _ = count_matches(elements, user, target)
        score += joint_weight(rules) * (strong - weak)
    return signed_layer(score, *tuning(rules, "skill"))


def multiplier(model: str, elements: dict, rules: dict, skill: str | None, user: list[str], target: list[str]) -> float:
    if model == "current":
        return current_multiplier(elements, rules, skill, user, target)
    if model == "signed_net":
        return separate_signed_multiplier(elements, rules, skill, user, target, False)
    if model == "signed_rms":
        return separate_signed_multiplier(elements, rules, skill, user, target, True)
    if model == "joint_weighted":
        return joint_weighted_multiplier(elements, rules, skill, user, target)
    raise ValueError(f"unknown model: {model}")


def interpretation(value: float) -> str:
    if abs(value - 1.0) < 1e-9:
        return "neutral"
    if 0.95 <= value <= 1.05:
        return "near-neutral"
    if value >= 1.25:
        return "strong"
    if value > 1.0:
        return "mildly strong"
    if value <= 0.75:
        return "weak"
    return "mildly weak"


def scenarios() -> list[dict]:
    rows: list[dict] = []

    def add(group: str, case: str, user: list[str], target: list[str], skill: str | None = None) -> None:
        rows.append({"group": group, "case": case, "user": user, "target": target, "skill": skill})

    for target in ("Green", "Blue", "Red"):
        add("affinity shape", f"R -> {target}", ["Red"], [target])
    for target in ("Green", "Blue"):
        add("affinity shape", f"RR -> {target}", ["Red", "Red"], [target])
    for label, user in (
        ("RG", ["Red", "Green"]),
        ("RB", ["Red", "Blue"]),
        ("RRG", ["Red", "Red", "Green"]),
        ("RGB", ["Red", "Green", "Blue"]),
    ):
        for target in ("Red", "Green", "Blue"):
            add("affinity shape", f"{label} -> {target}", user, [target])
    add("affinity shape", "White -> Black", ["White"], ["Black"])
    add("affinity shape", "Black -> White", ["Black"], ["White"])

    for user_label, user in (
        ("R", ["Red"]),
        ("RG", ["Red", "Green"]),
        ("RGB", ["Red", "Green", "Blue"]),
    ):
        for target_label, target in (
            ("RG", ["Red", "Green"]),
            ("RB", ["Red", "Blue"]),
            ("RGB", ["Red", "Green", "Blue"]),
        ):
            add("multi-element target", f"{user_label} -> {target_label}", user, target)

    interactions = (
        ("R + Red skill -> G (agree advantage)", ["Red"], ["Green"], "Red"),
        ("R + Green skill -> B (skill wins, innate opposes)", ["Red"], ["Blue"], "Green"),
        ("R + Red skill -> B (agree disadvantage)", ["Red"], ["Blue"], "Red"),
        ("RG + Red skill -> G (matching skill + one favorable innate)", ["Red", "Green"], ["Green"], "Red"),
        ("RB + Green skill -> B (skill wins, innate opposes)", ["Red", "Blue"], ["Blue"], "Green"),
        ("RGB + Red skill -> G (broad caster, favorable skill)", ["Red", "Green", "Blue"], ["Green"], "Red"),
        ("RGB + Blue skill -> G (broad caster, unfavorable skill)", ["Red", "Green", "Blue"], ["Green"], "Blue"),
        ("White + White skill -> Black", ["White"], ["Black"], "White"),
    )
    for case, user, target, skill in interactions:
        add("skill/user interaction", case, user, target, skill)
    return rows


def evaluated_rows(elements: dict, rules: dict) -> list[dict]:
    rows = []
    for scenario in scenarios():
        for model in MODEL_ORDER:
            value = multiplier(model, elements, rules, scenario["skill"], scenario["user"], scenario["target"])
            rows.append({
                "group": scenario["group"],
                "case": scenario["case"],
                "user_elements": "+".join(scenario["user"]) or "-",
                "skill_element": scenario["skill"] or "-",
                "target_elements": "+".join(scenario["target"]) or "-",
                "model": MODEL_LABELS[model],
                "multiplier": f"{value:.6f}",
                "interpretation": interpretation(value),
            })
    return rows


def render_csv(rows: list[dict]) -> str:
    out = io.StringIO(newline="")
    fields = ("group", "case", "user_elements", "skill_element", "target_elements", "model", "multiplier", "interpretation")
    writer = csv.DictWriter(out, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue()


def cell(value: float) -> str:
    return f"{value:.3f} ({interpretation(value)})"


def render_group_table(group: str, elements: dict, rules: dict) -> str:
    lines = [
        "| Case | Current | Signed net / separate | Signed RMS / separate | Weighted signed / joint |",
        "|---|---:|---:|---:|---:|",
    ]
    for scenario in scenarios():
        if scenario["group"] != group:
            continue
        values = [multiplier(model, elements, rules, scenario["skill"], scenario["user"], scenario["target"]) for model in MODEL_ORDER]
        lines.append("| " + scenario["case"] + " | " + " | ".join(cell(value) for value in values) + " |")
    return "\n".join(lines)


def render_markdown(elements: dict, rules: dict) -> str:
    weight = joint_weight(rules)
    return f"""# Element-affinity comparison for #168

Generated by `python tools/analysis/compare_element_affinity.py` from the live
`data/elements.json` relationship graph and `data/engine.json::elementRules`.
The comparison preserves the implementation that existed when #168 was opened
(the **Current** column) alongside three candidate aggregation shapes.

**Owner decision, 2026-08-08:** choose **A — Signed net / separate**. The runtime
now resolves favorable and unfavorable relations to a signed score inside each
channel before multiplier conversion. Skill affinity and innate identity remain
separate channels; repeated alignment still expresses depth. The existing
strong/weak tuning values are intentionally unchanged in this issue.

## Models under comparison

1. **Current** is the pre-#168 baseline: skill and innate-user layers are
   separate; each layer adds diminishing strong bonuses, multiplies weak
   penalties, then the two layers multiply together.
2. **Signed net / separate — SELECTED** keeps the skill and innate-user layers
   separate, but computes `strong - weak` before converting each layer to a
   multiplier. One-sided matchups therefore retain the existing curve while
   exact opposing relations cancel to exactly `1.0` inside that layer.
3. **Signed RMS / separate** also cancels relations before multiplier math, then
   divides each layer's signed score by `sqrt(pair_count)`. Repeated alignment
   still gains intensity, but large attacker/target cross-products grow more
   slowly and breadth has less numerical leverage.
4. **Weighted signed / joint** is the deliberately more radical comparison. It
   combines skill and innate relations into one signed score before applying the
   skill curve. One innate relation is weighted at **{weight:.3f}** of one skill
   relation, derived from the present first-step skill/user tuning. This tests
   whether "what you wield" and "who you are" should cancel before either
   becomes a multiplier. It remains diagnostic, not selected.

`ELEMENT_RATE` traits are intentionally absent from these fixtures. They remain
an explicit separate modifier layer in the implementation.

## Reading labels

`neutral` means exactly `1.0`. `near-neutral` means a non-neutral value within
5% of `1.0`; this label exists specifically to expose the old readability
problem rather than hide it behind a coarse category.

## Affinity shapes

{render_group_table("affinity shape", elements, rules)}

### Immediate observations

- The old model's characteristic residue is visible in **RG -> Blue**,
  **RB -> Green**, and every **RGB -> R/G/B** case: a strong and weak relation
  multiply to `1.035` rather than cancelling.
- Signed-net makes those exact conflicts exactly neutral while preserving the
  existing `R -> G`, `R -> B`, `RR -> G`, and `RR -> B` magnitudes.
- Signed-RMS also cancels cleanly, but deliberately weakens the meaning of raw
  element-count depth: `RR -> Green` is milder than under baseline/signed-net.
- The joint model is close to the baseline mono-element innate tuning but changes
  it slightly because one common weight is used for positive and negative innate
  pressure on the skill curve.

## Multi-element defenders

{render_group_table("multi-element target", elements, rules)}

### Immediate observations

- Cross-product multiplication in the old model causes several broad-vs-broad
  results to hover near neutral without being neutral (`RG -> RGB`, `RGB -> RG`,
  `RGB -> RB`, `RGB -> RGB`).
- Both separate signed models make a perfectly balanced relationship exactly
  neutral before multiplier math.
- RMS normalization asks an additional design question: should a defender with
  more visible element icons automatically amplify the magnitude of every
  favorable/unfavorable pairing, or should breadth damp the cross-product?

## Skill / user interaction

{render_group_table("skill/user interaction", elements, rules)}

### Immediate observations

- The selected signed-net model mostly changes **mixed innate composition**, not
  the established relative importance of the skill layer. That keeps the fix
  narrow.
- A broad RGB caster becomes exactly innate-neutral, so a favorable Red skill
  into Green reads as exactly the skill's `1.5x`, rather than the old `1.552x`
  residue.
- The joint model would change agreement/conflict between skill and innate
  identity. That is the largest conceptual departure and was not selected.

## Design trade-offs

| Model | Cancellation | Repeated-depth expression | Broad/mixed identity | Skill/user roles | Main risk |
|---|---|---|---|---|---|
| Current | No | Strong | Often leaves arithmetic residue | Very clear separate channels | Player cannot predict near-neutral leftovers |
| Signed net / separate | Exact inside each layer | Strong; same one-sided curve as current | Mixed colors cancel cleanly | Preserves current two-channel doctrine | Cross-product magnitude can still grow quickly |
| Signed RMS / separate | Exact inside each layer | Present but damped | Clean cancellation; breadth naturally moderates intensity | Preserves separate channels | The square-root normalization is harder to explain diegetically |
| Weighted signed / joint | Exact in the joint score | Present | Clean cancellation across innate and skill pressure | One final elemental verdict | Reweights established skill-vs-innate semantics; calibration becomes a new design surface |

## Owner decision — 2026-08-08

**Selected: A — signed net / separate.**

The player-facing rule is intentionally simple:

> Within the creature's affinity and within the skill's affinity, count favorable
> and unfavorable relationships. Opposites cancel. The remaining depth decides
> that channel's strength. Then the creature and skill channels combine.

This gives `RG -> Blue = 1.0`, keeps `RR -> Green = 1.27`, makes RGB naturally
neutral across the RGB cycle without an RGB exception, and preserves the
existing distinction between **who the creature is** and **what it wields**.

Numeric strong/weak values are not rebalanced here. Aggregation shape is now
settled first; wider elemental damage tuning can be evaluated separately.
"""


def write_or_check(path: Path, content: str, check: bool) -> bool:
    if check:
        existing = path.read_text(encoding="utf-8") if path.exists() else None
        if existing != content:
            print(f"STALE: {path.relative_to(ROOT)}")
            return False
        return True
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    print(f"WROTE: {path.relative_to(ROOT)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if committed comparison artifacts are stale")
    args = parser.parse_args()

    elements, rules = load_inputs()
    rows = evaluated_rows(elements, rules)
    ok_md = write_or_check(DEFAULT_MD, render_markdown(elements, rules), args.check)
    ok_csv = write_or_check(DEFAULT_CSV, render_csv(rows), args.check)
    return 0 if ok_md and ok_csv else 1


if __name__ == "__main__":
    raise SystemExit(main())