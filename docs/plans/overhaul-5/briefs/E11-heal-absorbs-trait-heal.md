# E11: HEAL absorbs TRAIT_HEAL

**Context:** Owner feedback 10.07.2026 item 12 (FEEDBACK.md): no dedicated
TRAIT_HEAL command — the generic HEAL command should be able to apply
trait-based healing. Same command-consolidation discipline as
CALC_CRAFT_YIELD (deprecate, migrate usages, delete).

**Role:** LOCAL ONLY — this touches the victory flow, which is exercised by
the golden battle log. Alias determinism (ORCHESTRATION §4: event emission
must stay identical) is the whole risk here.

**Current state (verify before coding):** `TRAIT_HEAL` is registered in
`data/engine.json → commands` with a handler in `engine/interpreter.lua`,
used in `data/flows.json → battle.victory` (`trait: "POST_BATTLE_HEAL"`).
The legacy fallback in `engine/scenes/battle.lua` also applies
POST_BATTLE_HEAL directly.

## Acceptance Criteria
- [ ] HEAL gains an optional `trait` param: when present, the heal amount is
      the target's rate for that trait code (via `traits.getRate`), instead
      of / in addition to evaluating `formula` — mirror TRAIT_HEAL's exact
      semantics, including its zero/absent-trait behavior (verify: does
      TRAIT_HEAL emit a heal event when the rate is 0? HEAL with trait must
      match).
- [ ] Event emission path identical: both go through `effects.apply`
      (hp_heal) exactly as today, so log events keep their shape.
- [ ] `flows.json battle.victory` migrated from TRAIT_HEAL to
      `HEAL { target, trait: "POST_BATTLE_HEAL" }`.
- [ ] TRAIT_HEAL: registry entry and interpreter handler DELETED (not
      deprecated-and-kept — the validator forbids handlerless registry
      entries, and the reverse rots; check first whether any other data
      file uses it: grep flows.json, scenes.json, events.json,
      commonEvents.json, maps.json).
- [ ] Editor command palette: TRAIT_HEAL gone; HEAL's param form exposes the
      optional trait code (reuse the trait-code picker used elsewhere if one
      exists).
- [ ] **G2 golden byte-identical.** If the migration changes even one log
      line, the semantics don't actually match — fix the implementation,
      never the log.

**Gates:** G1, G2 (byte-identical, hard requirement), G3, UI-golden.
