# Permadeath

> **Intent, not status.** This document describes what we mean to build and why.
> For what is actually implemented right now, read the generated
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how the engine
> works, `docs/SPEC.md`. Where this document and those disagree, they win.

**A creature that is KOed when a battle ends passes away, permanently.**

That is the whole rule, and it is deliberate: the earlier draft of this
document proposed a MaxHP-decay system (dying drains max HP until it reaches
zero, healable in between), which was dropped on 24.07.2026 as cognitive
overload — a second per-creature number for the player to track for no gain in
tension. KO-at-battle-end is legible instantly and costs the player nothing to
reason about.

## How it works

The sweep is one command, `REAP_FALLEN` (`engine/interpreter.lua`), run from the
`battle.victory` and `battle.escaped` flow phases (`data/flows.json`) — so
*when* reaping happens is data, not code. Notably `battle.defeat` does NOT
reap: the run is over anyway.

For each fallen creature the sweep either fires a **death ward** (below) or:

1. banks its EXP — `totalExp × summoner.sacrificeExpRate × (1 + SACRIFICE_EXP_RATE)`,
   the same yield rule as ritual sacrifice, so a lost creature is not a total
   write-off;
2. emits one `reap` event carrying `{target, exp, slot}`.

Removal from the party is **deferred to presentation**: `engine/scenes/battle.lua`
clears `party[slot]` one creature at a time, only once that creature's
`system.reap` animation has played. The sweep stays the single authority on who
dies; the scene decides when the player sees it.

## Death wards (`ON_PERMADEATH`)

Equipment, passives, or innate actor traits can save a creature from the sweep.
The trait's `mode` picks the behavior — all four are implemented and every
number is tunable:

| `mode` | Behavior | Consumed? |
|---|---|---|
| `relic` | Saves unconditionally, every time | never |
| `charges` | Spends one charge per save | breaks at zero |
| `ward` | Creature simply does not die | yes, on use |
| `revive` | Reaped visually, then restored | yes, on use |

Optional per-trait params, each falling back to `system.json` → `permadeath`:

- `hpFraction` — fraction of maxHp the survivor is restored to
- `charges` — starting charge count (`charges` mode)
- `levelCost` — levels lost as the price of surviving

`system.json` defaults: `reviveHpFraction: 0.25`, `defaultCharges: 1`,
`breakOnLastCharge: true`.

**Candidate ranking**: when a creature has more than one ward, the *cheapest*
save wins — `relic` before `charges` before `ward`/`revive` — so a free innate
rebirth never lets an expensive amulet shatter needlessly. Charge wards with no
charges left are skipped entirely rather than blocking a working ward.

**Charges live on the battler** (`battler.wardCharges`, keyed by
`slot:<n>` / `passive:<id>` / `actor`), never on the item — `battler.equipment[slot]`
is a shared reference to the loader's item table, so decrementing there would
drain every copy of that item in the game. Charges round-trip through saves.

Authored examples: the `rebirth` passive (Phoenix) is `relic` +
`hpFraction 0.2` + `levelCost 2`, matching its long-standing description text;
items 42–44 are a one-shot ward, a revive vial, and a 3-charge bead.

The ward fires a `ward_save` event carrying `{mode, sourceKind, item, broke,
charges, hp, levelCost}` — everything a UI needs.

## Open work

- **`ward_save` has no presentation yet.** `engine/scenes/battle.lua` handles
  `reap` but not `ward_save`, so a save is currently silent — the creature just
  survives. That file is owner-supervised, so wiring the log line
  ("`{0}` is pulled back from the brink!" / "The `{0}` shatters." — terms
  already authored in `data/terms.json`) is an owner-supervised change.
- **Ward status should be a displayed status effect** (owner direction): the
  player must be able to see a ward and its remaining charges *before*
  committing to a deeper floor. This waits on the displayed-status-effect
  system, which does not exist yet — no `states.json` entry carries display
  metadata today.
