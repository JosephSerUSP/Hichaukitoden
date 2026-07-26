# Content-to-Engine Gap Ledger

> **Intent and implementation dependency, not status authority.** This document
> records approved content behavior that the current engine cannot yet express
> faithfully. `docs/ENGINE-STATE.md` remains authoritative for what exists;
> `docs/SPEC.md` remains authoritative for how implemented systems work.

## Purpose

Content must not be weakened to fit an incomplete primitive. If an approved
actor, item, skill, state, or promotion requires engine expansion:

1. Keep the intended content definition in its design atlas.
2. Record the mismatch here.
3. Add a reusable registry-backed primitive, never content-specific Lua.
4. Add validation and tests for the new vocabulary.
5. Author live data only in a schema-valid form; never insert ignored or
   unknown fields.
6. Do not substitute a merely similar current behavior without explicit review.

This ledger exists to prevent an authored name or description from promising
behavior that the live data does not deliver.

A row leaves this ledger when the primitive exists, is validated or tested, and
is described in `SPEC.md`. Closed rows are not deleted silently: they move to
"Closed" at the foot of this document with a pointer, so the reason the content
was once blocked stays legible.

## What is blocked on owner supervision

Most of the remaining ledger cannot be worked autonomously, and it is worth
saying why once rather than per row:

- `engine/battle.lua` and `engine/scenes/battle.lua` are owner-supervised
  (AGENTS.md). Criticals, Defend, forced actions and Strain presentation live
  there.
- The relative damage curve, the MZ status-chance chain, and the MPD step/round
  changes all alter numbers the golden gates fix byte-for-byte. G2/G3 red is a
  behavioral regression by definition, and **regenerating a golden log is an
  owner-signed action**. Those rows need the owner in the loop by construction,
  not by preference.

The items and Item Creation vocabulary is the part that is purely additive: no
existing content carries the new fields, so the gates stay green and the work
can land ahead of the balance rewrite it will eventually serve.

## Battle mathematics

| Intent | Current mismatch | Required reusable work |
|---|---|---|
| Relative damage: `potency * power^2 / (power + defense)` | HP damage currently evaluates a raw formula and multiplies by `10 / DEF`; magical damage also uses DEF | Registry-backed damage effect parameters for power source, defense source, and potency; one shared implementation for damage and drain |
| Physical actions use ATK/DEF; magical actions use MAT/MDF | Current `hp_damage` always reduces through DEF | Explicit validated stat pairing |
| Healing bands use MAT plus target MaxHP | Current heals use only their authored raw formula | Formula tokens already permit composition, but skill data and previews must use and validate the agreed scale |
| General direct-damage rate | Defend currently doubles DEF and does not protect from magic | Reusable `DAMAGE_RATE` trait respected by all direct HP damage paths |
| Armor penetration | No approved common penetration parameter | Validated effect/trait vocabulary that reduces or bypasses a defined share of defense |
| Critical damage at 1.5 times and attached-status guarantee | CRI rate exists, but ordinary HP damage does not currently apply the approved critical behavior | Shared critical resolution, event output, per-hit handling, and status handoff |

## States and control

| Intent | Current mismatch | Required reusable work |
|---|---|---|
| MZ-style status chance: skill chance times attacker success rate times target state rate | `add_status` currently rolls only its raw `chance` | Status-success and per-state-rate traits, immunity at rate zero, shared chance resolver |
| Critical damaging hit guarantees attached statuses unless immune | No critical-to-status relationship | Action/hit context passed to attached status effects |
| Berserk raises ATK and forces basic Attack | Current Berserk only raises ATK | Reusable action restriction or forced-action trait implemented through battle command selection, not a Berserk-specific branch |
| Ribbon blocks all ordinary negative states | No category-wide ordinary-negative-state immunity | State category metadata plus validated category resistance, or an equivalent general trait |
| Safety Bit protects against Execution | Execution does not yet exist | Execution resistance vocabulary separate from ordinary states |
| Blind, Silence, and other named cure targets | Some proposed cure targets do not yet exist as states | Author states and their reusable mechanical traits before shipping their cures |

## Summoner MP and MPD

| Intent | Current mismatch | Required reusable work |
|---|---|---|
| Dungeon step cost equals living manifested party MPD, with no Summoner base cost | Current movement and MPD behavior use the old scale | Shared party-MPD query in traversal events and updated Max MP scale |
| No ordinary round MPD drain | Current round-end flow drains every ally's MPD | Replace the authored round-end drain; do not retain a Lua fallback |
| Visible Strain begins after five rounds and escalates at rounds 10 and 15 | No Strain phase or presentation | Data-authored round checks, MP change, escalation messages, and cost preview |
| Max MP grows from 3000 toward 9999 through events and rare items | Session currently uses the old fixed scale | Saved permanent Max MP, event command/effect support, cap validation, UI updates |
| Equipment may rarely modify form MPD, never below 1 | Ordinary parameter-plus validation excludes MPD and form cost needs a floor | Reusable MPD rate/plus trait with explicit minimum and range preview |

## Growth and transformation

| Intent | Current mismatch | Required reusable work |
|---|---|---|
| Seeded additive growth budgets and uneven saved level packets | Current stats are recalculated from base, level, and a smooth formula | Per-instance growth seed and accumulated permanent natural gains, saved and replayable |
| Promotion preserves exact history and changes only future budgets | Current evolution reconstructs a battler from destination actor data at the same level | Transformation path that preserves accumulated parameters and swaps future growth profile |
| Item-gated promotions usually have no level requirement | Existing evolution data is level-oriented | Item-consuming promotion condition in data and UI |
| Egg hatch uses provenance-specific fixed hatch bonus | Provenance and automatic hatch outcome are not general actor data | Saved provenance, level trigger, authored outcome table, and fixed transformation bonus |
| Homunculus preview and deterministic parameter-driven destination | No general resolver | Reusable deterministic metamorphosis rules with validated eligibility and preview |
| Reversible Kappa transformation preserves identity/history | Ordinary evolution is one-way | Saved original form plus reversible transformation command |

## Items, food, and Item Creation

| Intent | Current mismatch | Required reusable work |
|---|---|---|
| Meals are field-only and often party-wide | Occasion and party targeting now exist separately; no Meal marker ties them together for UI | Meal metadata and presentation on top of `scope: field` + `target: party` |
| Favorite Food is one saved randomized exact item per creature | No per-instance Favorite Food persistence | Species pools, saved identity/discovery, reactions, and promotion persistence |
| Savor lasts an authored number of completed battles | No battle-count food state | Saved battle counter and non-refresh rule |
| Executioner and Diablos execute below an HP threshold | No reusable Execution trait | Kill-credit-aware `EXECUTION_THRESHOLD` and explicit resistance |
| Forbidden Lamp calls a common event | No approved item common-event effect | Registry-backed `common_event` item effect. Note: `CALL_COMMON_EVENT` is an *interactive* command compiled into the dialogue graph, so this cannot be an `effects.lua` branch — it has to be raised at the item-use sites, which is why it is not part of the additive slice |
| Monster remains are usable ingredients but never outputs | Expressible now (`craftable: false` alone), but the existing Obsidian Shard / Melted Wax / Ectoplasm are still inert `junk` | Migrate the three to real equipment/consumable forms; validate no inert `junk` remains |

## Equipment promises

| Item or family | Required behavior; do not approximate |
|---|---|
| Executioner | Execute eligible enemies below its threshold |
| Pile Bunker | Meaningful defense penetration |
| Healing Staff | Improve healing, not merely add White |
| Mirror Armor | Authored magical protection; no claim of reflection unless reflection is implemented |
| Fortress Plate | General direct-damage reduction with an explicit drawback |
| Ribbon | Ordinary negative-state immunity only |
| Safety Bit | Execution protection |
| Protect Ring | General direct-damage reduction |
| Angel Feather / Phoenix Pinion | Per-instance death-ward charges stored on the battler/equipment slot, never shared loader data |
| Chef Hat / Apron | Distinct immediate-food versus Savor/Favorite-Food support |
| MPD-reducing accessory | Reduce wearer MPD by one, never below one; update displayed expedition range |

## Skill-tome safety

Teaching items are dangerous in generative Item Creation because their effect
can bypass actor progression and because a generated output may inherit a skill
effect unintentionally.

Default policy:

- teaching items are excluded from generative Item Creation outputs;
- they are also excluded from ingredient selection unless an authored recipe
  explicitly needs one;
- a future recipe may deliberately create a specific tome, but this is a
  whitelist decision, not signature-driven emergence;
- learned-skill eligibility and duplicate-learning behavior must validate;
- the approximately 150-item systemic atlas does not reserve arbitrary tome
  slots before the skill roster is authored.

## Closed

Implemented, gated or unit-tested, and described in `SPEC.md` §1.9
(26.07.2026). Live registry, not intent — `ENGINE-STATE.md` remains the
authority on what exists.

| Was blocked | Now expressible as |
|---|---|
| Battle/field/both item occasion | `item.scope`, enumerated in `engine.json -> itemScopes`; G1 fails an unknown scope; editor select reads the registry |
| Fixed, percentage, and hybrid HP/MP recovery | `percent` alongside `value` on the `hp` and `mp_heal` effects |
| Rare items permanently raise Summoner Max MP | `max_mp_plus`, clamped to `system.summoner.maxMpCap`, saved with the session, refused at the cap |
| Mimic/Pandora scale item effects | `ITEM_EFFECT_RATE`, read from the recipient; skills and permanent gains deliberately untouched |
| Promotion keys cannot be Item Creation inputs or outputs | `meta.craftIngredient: false` (inputs) alongside `meta.craftable: false` (outputs); `craft.isIngredient` is the shared reading, applied to the ingredient list through the new `SET_LIST` `filter` row formula |

Tested in `tests/test_item_vocabulary.lua`; none of it is observable to G2/G3,
which is why it is unit-tested rather than left to the golden logs.

## Known live-data audit rule

Before implementing each vertical slice, compare every proposed description,
name, trait, effect, and state against the live registry and handlers. Any
mismatch is added here before data authoring. A gate or unit test must enforce
the behavior once implemented.
