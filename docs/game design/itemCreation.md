# Item Creation

> **Intent, not status.** This document describes what we mean to build and why.
> For what is actually implemented right now, read the generated
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how the engine
> works, `docs/SPEC.md`. Where this document and those disagree, they win.

A simplified Star Ocean 2-style system. The appeal is **breadth** — a vast
combination space that dangles item possibilities in front of the player, almost
like exploring a latent space of items. That is the design goal, and it is why
there is deliberately **no recipe table**: authored exact-match recipes would
narrow the very thing that makes the system exciting. (If recipes are ever
added, their outcomes should still be randomized.)

Each monster has access to exactly one *discipline*, and — most of the time —
it does not match its strongest stat. A diverse party is what buys you broad
Item Creation access, and a creature that excels at crafting may be poor in
battle, or vice versa. Battle performance, Item Creation aptitude, and sacrifice
value are meant to pull in different directions per species.

That pull comes from the levers the roster already has, not from a separate
"crafting aptitude" number: a creature whose *only* good stat is its discipline's
stat is a specialist (Wisp — MAT 17 and little else), and so is one that is
broadly decent but cannot evolve (Golem, Flauros). The counterweights are the
powerhouses whose discipline points at their weak side — Shadow Stalker crafts
on MDF 13 despite 38 ATK. Discipline persists across an evolution, so investing
in a crafter is not lost when it evolves.

**Candle is the archetype**: 7 HP and 7 ATK make it nearly useless in a fight,
it has no evolution to grow into, and MDF 22 makes it the best tinker on the
roster — ahead of Crimson Lord, a creature with more than twice its battle
total. Recruiting it is a crafting decision, not a combat one.

Menu flow: a creature's context menu on the map → Item Creation. The creature is
already chosen by the time the scene opens, and its single discipline follows
from it, so the scene opens directly on ingredient selection — there is no
"pick a discipline" and no "pick a creature" step.

## Implementation (live)

The whole system is the data-authored scene `1` in `data/scenes.json` — hooks,
windows, and a `calcYield` SCRIPT — with no bespoke engine Lua. The scene is
pushed with `seededCrafterIdx` (the party slot picked in the context menu);
`calcYield` reads that creature's `discipline`, looks it up in the engine
registry, and drives the pool filter, the ingredient highlight and the governing
stat from it. Its four states are ingredients → confirm → roulette → result.

**Disciplines live in `data/engine.json` → `disciplines[]`** —
`{kind, label, stat, description}`: blacksmithing/ATK, tinkering/ASP,
alchemy/MAT, cooking/MaxHP. That is the single source of truth naming
an item's `meta.craftKind` and a creature's `discipline`; G1 rejects either
naming a kind that is not registered, and the editor offers it as a dropdown
rather than a free string. `api.disciplines()` exposes it to SCRIPT.

Everything below is a tunable field of the scene's `config`:

| Field | Role |
|---|---|
| `yieldFormula` | mean ingredient `potency` + `alpha × crafterStat` |
| `penaltyFormula` | 15 for element mismatch, 20 if the crafter is under-tier |
| `anomalyFormula` | 5% chance of a 1.5× score multiplier ("CRITICAL ANOMALY") |
| `brackets[]` | score → outcome tier (Junk / Standard / Superior / Rare) |
| `alpha` | how much the crafter's stat matters vs. the ingredients |
| `timing` | roulette animation pacing |

Resolution: ingredients + crafter stat produce a score; the score picks an
outcome tier; the result is rolled from the pool of all items whose
`meta.craftKind` matches the discipline and whose `meta.tier` matches that
outcome tier (falling back to tier 0). Ingredients are consumed and the result
granted when the roulette completes.

Items carry `meta: {tier, potency, craftElement, craftKind}`; creatures carry
`discipline`.

**Promotion keys are craftable, and that is the intended path to them** — e.g.
the Chrysalis Sigil is `category: promotion_key` with full craft meta, so it
sits in the alchemy tier-3 pool. A creature's branching promotion (Brigandine's
*Seraph + Vile Apple → Lucifer*) is authored as an extra `evolutions` entry with
`cost: {item: <key>}`, and the key itself is something the player may *discover*
through Item Creation.

## Creature customization (added 24.07.2026)

Two effect types make creature-shaping items possible; both are registered in
`data/engine.json` → `effectTypes`, handled in `engine/effects.lua`, gated by
G1, and persisted by `engine/savegame.lua`:

- **`learn_skill`** — `{skill}`: permanently teaches a skill (skillbooks).
  Refused by `engine/usability.lua` if the creature already knows it, so the
  item can't be wasted; `effects.lua` also fails soft with a message.
- **`param_plus`** — `{param, value}`: permanent stat-up for any param a
  battler's `paramPlus` carries (maxHp/atk/def/mat/mdf). `maxHp` also heals by
  the gain. This is the general form of the older single-purpose `maxHp` effect.

Skillbooks and stat-up items may come from **both** sacrifice rewards and
crafting pools (owner decision) — the balance levers are therefore potency
tiers and pool composition, not source scarcity. Practically this means the
tier-3 pools are the customization jackpot, so `alpha` and `penaltyFormula` are
the difficulty dial for the whole progression curve.

## Open work

- **Crafting-related traits/passives** are the intended way to give a creature
  crafting aptitude independent of its battle stats — the trait machinery
  already does this shape for `SACRIFICE_EXP_RATE`, so a craft-yield trait code
  summed into the yield formula would follow the same pattern. Deliberately
  *not* solved with a new per-actor "aptitude" number: the existing levers
  (stat shape, evolution dead-ends, negative traits) already carry that weight.
- Only one promotion key exists for ~5 promotion lines.
- `evolutions` entries require a `level` threshold, so a purely item-gated
  promotion path needs a dummy `level: 1`; and cost is the only gate (no
  element/discipline/flag conditions yet).
