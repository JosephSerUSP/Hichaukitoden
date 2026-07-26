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
| The eight authored CRI values were balanced against a system that never ran | Seven weapons and one actor carried `CRI` while nothing in the engine ever rolled a critical, so the values are untested guesses now live as authored (Shattered Edge +25%, Radiant Blade Flavio +20%, Wind Dancer / Water Scepter / Holy Sword Gram +15%, Silver Blade / Dark Scepter Lucille +10%, Shadow Stalker +10%, on a 5% base) | A balance pass over crit rates against the trait budgets in `item-atlas-expansion.md`, which allows ordinary +2-4%, strong +5-8%, signature +10-15% — several shipped values already exceed the signature band |
| Skill potency and MP bands against authored kits | The eight damaging skills carry provisional potencies (0.80-1.85) read off the potency table; MP costs are untouched and predate the model | Simulation against the skill-class table in `creature-parameters.md` |

## States and control

| Intent | Current mismatch | Required reusable work |
|---|---|---|
| Defend protects against magic | Closed — see below; noted here because the old `PARAM_RATE def x2` is gone and any content that assumed doubled DEF should be re-read | — |
| Ribbon's exact coverage | The mechanism exists (`STATE_CATEGORY_RATE common 0`); the item itself is unauthored, and which states earn `common` is a content decision that grows with the state roster | Author the item, and tag each new state as it lands |
| Blind, Silence, and other named cure targets | Some proposed cure targets do not yet exist as states | Author states and their reusable mechanical traits before shipping their cures |
| Magic evasion is separate from physical evasion | One `EVA` covers both, so a creature cannot be nimble against blades and helpless against spells | A second evasion channel, if the roster ever needs the distinction; RPG Maker separates them and the current creatures do not obviously require it |

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
| Monster remains are usable ingredients but never outputs | Expressible now (`craftable: false` alone), but the existing Obsidian Shard / Melted Wax / Ectoplasm are still inert `junk` | Migrate the three to real equipment/consumable forms; validate no inert `junk` remains |

## Equipment promises

| Item or family | Required behavior; do not approximate |
|---|---|
| Executioner | Execute eligible enemies below its threshold (mechanism exists; the item is unauthored) |
| Pile Bunker | Meaningful defense penetration (mechanism exists; the item is unauthored) |
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

Battle mathematics, SPEC §1.11 (26.07.2026). Unlike the item slice, this one
**changed the golden logs**; they were regenerated under owner review, not to
silence a diff.

| Was blocked | Now expressible as |
|---|---|
| Relative damage `potency * power^2 / (power + defense)` | `potency` + `power` on `hp_damage`/`hp_drain`, resolved by one shared `resolveDamage` |
| Physical uses ATK/DEF, magical uses MAT/MDF | `power` names the attacker stat; `defense` defaults to its pair and may be authored to cross them. **This is what made Golem's magical weakness real** — Holy Smite into Golem went 3 -> 15 |
| Healing bands use MAT plus target MaxHP | The two authored heals now use the agreed scale (`a.mat * 0.60 + b.maxHp * 0.15`, and 0.90/0.22 for the strong band) |
| General direct-damage rate | `DAMAGE_RATE`, multiplicative across sources; Defend is `DAMAGE_RATE 0.5` instead of doubled DEF |
| Critical damage at 1.5x, per-hit, with status handoff | Rolled in `effects.lua` so every damaging action shares one path; reported on the damage event and given its own `critical|` line in the golden log |

Common-event items, same date. The `common_event` effect raises a request that
`scene_host` defers with its scene transitions and the host honours through the
presentation seam, because CALL_COMMON_EVENT is interactive and effects run in
immediate mode -- there was no way for an effect to hand control to the graph
walker, which is why this was the one item primitive held back from the additive
slice. Unbound hosts leave the request unclaimed rather than erroring, so every
headless path keeps working. G1 fails an effect naming a missing event.

Armor penetration and Execution, same date. `PENETRATION` (and an effect-level
`penetration`) ignores a share of the defending stat before the curve;
`EXECUTION_THRESHOLD` finishes a survivor left under a fraction of Max HP, with
`EXECUTION_RESIST` subtracting from the threshold rather than rolling, so it
costs no randomness and Safety Bit is an ordinary 1.0. Neither fires on the
direct authored-damage path, for the same reason criticals do not. The two open
questions in the atlas -- whether enemy-side execution may affect player
creatures, and boss resistance policy -- are answered by data now rather than by
code: the mechanism is symmetric and the resistance is authorable.

Forced actions, same date. `FORCE_ACTION` names a skill its holder must use,
applied where the turn queue is built and at the head of the enemy AI, so one
rule binds both sides and nothing in the engine knows what "berserk" means. The
live Berserk state carries it, so the state finally behaves like the negative /
common / mental thing it is tagged as -- it had raised ATK and compelled nothing
since it was written, which made it a pure buff wearing a debuff's name. Tested
in `tests/test_forced_action.lua`; the golden fixtures cannot see this, because
no fixture applies berserk and a compelled creature that still obeys produces a
perfectly stable log.

States and control, same date (SPEC S1.10). States now carry a LIST of
categories from a registry (`negative`, `positive`, `physical`, `magical`,
`mental`, `common`), and infliction is the MZ chain: skill chance times the
attacker's `STATUS_SUCCESS` times the target's rate, that rate being the product
of every `STATE_RATE` naming the state and every `STATE_CATEGORY_RATE` naming
one of its categories. A rate of 0 is absolute immunity and a critical cannot
force it, which closes the one place the critical-status rule overreached.

`common` is an earned tag rather than an inference from `negative`, and that
distinction is load-bearing: rates multiply, so a Ribbon authored against
`negative` would also have covered `dead` and quietly made its wearer immune to
any authored death effect. A test pins it. Tested in
`tests/test_status_infliction.lua`.

Found while wiring the editor: the traits editor offered stat ids as the dataId
for ELEMENT_ADD, which is an element -- so that trait could only ever be
authored into a G1 failure through the UI. Fixed with the same lookup the new
state traits needed.

Accuracy, same date. `HIT` and `EVA` were registered and `EVA` authored on
Shadow Stalker, but nothing rolled either: every action always connected.
`APPLY_EFFECT` now rolls `HIT * (1 - EVA)` once per target before any effect
resolves, and a miss skips that target's whole effect list. This is what makes
the roster's clumsy heavy creatures expressible. It moved no golden line,
because a certain outcome takes no random draw.

Round-end HP drift, same date. `STATE_TICKS` branched on
`state.id == "regen"` / `"poison"` with rates from `system.json`. It now sums
the `HRG` trait across every source, negative being degeneration -- one trait,
both directions. That was three faults at once: two content ids hardcoded in
the engine against the first non-negotiable; `HRG` dead on the `Holy Aura`
passive and the `Mercury Crest`, both of which advertised regeneration and did
nothing; and the roster's planned regeneration unauthorable, because only the
one id the engine named could ever tick. Kirin's party-wide regeneration and
the 5-8% band in `creature-parameters.md` are now expressible. Tested in
`tests/test_state_ticks.lua`.

The `regen` state kept its live 0.1 rather than adopting its own declared 0.05,
so this is a mechanism fix and not a silent rebalance; the 5-8% band is a
balance decision that belongs with the rest of the potency pass above.

Tested in `tests/test_damage_model.lua`. The golden logs prove the battle is
*stable*; they cannot prove the curve is the *right* one, because any
consistent arithmetic produces a stable log. The unit tests pin the share
table, the pairing, and the DAMAGE_RATE algebra so a future change that keeps
G2 green by regenerating it still has to answer to the design.

## Known live-data audit rule

Before implementing each vertical slice, compare every proposed description,
name, trait, effect, and state against the live registry and handlers. Any
mismatch is added here before data authoring. A gate or unit test must enforce
the behavior once implemented.
