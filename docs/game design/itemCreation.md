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

Menu flow: Item Creation → Select Creature → Item Creation menu.

## Implementation (live)

The whole system is the data-authored scene `1` in `data/scenes.json` — hooks,
windows, and a `calcYield` SCRIPT — with no bespoke engine Lua. Everything below
is a tunable field of that scene's `config`:

| Field | Role |
|---|---|
| `disciplines[]` | `{kind, label, stat, description}` — blacksmithing/ATK, tinkering/ASP, alchemy/MAT, cooking/MaxHP |
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

- **All 22 creatures currently have `discipline: "alchemy"`**, so the
  "diverse party for crafting access" pillar is inert. Spreading disciplines
  across the roster — deliberately *against* each creature's combat strength —
  is a content pass, not an engine change.
- Only one promotion key exists for ~5 promotion lines.
- `evolutions` entries require a `level` threshold, so a purely item-gated
  promotion path needs a dummy `level: 1`; and cost is the only gate (no
  element/discipline/flag conditions yet).
