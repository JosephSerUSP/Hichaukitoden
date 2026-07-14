# F2: MP as the central resource (audit, not rebuild)

**Context:** Read SPEC.md S1 and S3. Two MP systems already exist
(round-end drain in `engine/battle.lua:340-374`, command-driven
`CHANGE_MP`/`DRAIN_MP`/`RESTORE_MP` in `engine/interpreter.lua:368-388`).
This brief audits and adjusts them for a post-F1 world, it does not build
MP drain from scratch. **Must land after F1.**

**Role:** owner-supervised (touches `battle.lua` again, same file F1 just
rewrote).

## Acceptance Criteria
- [x] Round-end drain confirmed correct with the summoner gone: the active
      drain is the `flows.json` `battle.round_end` flow (battle.lua returns
      early at `engine/battle.lua:252` when the flow exists); it uses
      `FOR_EACH scope:"slot_allies"` -> `scopeList` iterates only slots 1-4
      (`engine/interpreter.lua:260-269`), explicitly excluding the summoner.
      No summoner-specific branching remains. The inline legacy block in
      `battle.lua:316-351` is dead fallback code only.
- [x] MP-exhaustion damage confirmed to iterate active creatures correctly
      post-F1: the flow's `IF session.mp <= 0` block also uses `slot_allies`,
      so it hits only living active creatures.
- [x] Spell/item MP-cost call sites in `data/skills.json` audited: `mpCost`
      values are flat integers (5/15/8/0) with no formulas and no summoner-
      stat references — nothing to fix. (Note: `mpCost` is currently NOT
      consumed by the engine when a skill is cast — a pre-existing gap, not a
      summoner-specific break, so out of this audit's scope.)
- [x] MP display: owner approved a PERSISTENT bottom party HUD (console panel
      + MP readout + 2x2 party grid) shared by every scene — map, dialogue,
      town, battle — not battle-only (owner direction 14.07.2026: "the party
      gauge at the bottom should be persistent across multiple scenes... it
      disappears during dialog!"). The shared HUD IS the existing declarative
      `"party"` window (`style:"partyGrid"`, `data/engine.json` windowLayout)
      — there is exactly ONE party HUD, no second/legacy one. The 2x2 actor
      grid stays at the window's natural LEFT position; the MP readout
      (`window_renderer.drawMpReadout`, using the interpolated
      `session.displayedMp`) sits in the freed RIGHT portion. Keeping the grid
      at its natural position also keeps the map party popup (anchored to the
      grid cells via `cellOf:party`) in sync with the sprites. Every scene
      draws this same window: Map via its scene state, and battle/dialogue/town
      via `main.lua`'s `drawSharedPartyHud`.
- [x] No new balancing — costs/rates/thresholds unchanged. No value changes
      were needed.

## Implementation notes (PR design record)
- Audit found the round-end MP drain already correct post-F1; no engine
  change required for AC1-AC3/AC5.
- AC4 was expanded by owner direction from "a small readout in the battle
  strip" to "a persistent party gauge across all scenes", and then refined
  after the owner flagged that a SECOND (legacy) party HUD was overlapping the
  existing declarative one in the Scenes editor. Resolution: unify on the ONE
  declarative `"party"` window instead of adding a parallel HUD.
  - `presentation/window_renderer.lua`: added `drawMpReadout(x, y, session,
    areaW)` (uses the smoothly-interpolated `session.displayedMp`) and modified
    `drawPartyGridStyle` so the 2x2 actor grid stays at `contentX` (its natural
    left position) and the MP readout is drawn in the freed RIGHT portion of the
    window. This keeps the map party popup — which anchors to the grid cells via
    `cellOf:party` (computed at the same `contentX`) — in sync with the sprites,
    and matches the owner's requested layout (actors left, MP right). This is the
    single source of the shared HUD's visuals.
  - `main.lua`: added `drawSharedPartyHud()` — builds a minimal
    `{ winState = { party = { open = true, listId = "party" } }, windowOrder =
    { "party" } }` state and calls `window_renderer.draw(state, nil, { session,
    loader })`. Wired into the `town`, `dialogue`, and `battle` branches of
    `love.draw()` (Map already draws the same window through its scene state).
  - `presentation/renderer.lua`: removed the legacy `drawPartyHud` /
    `drawMpReadout` and their call sites in `drawBattle` / `drawDialogue` /
    `drawTown`; `drawBattle` no longer draws an inline console — the
    declarative `"party"` window is the HUD everywhere. `drawPartyGrid` is kept
    (used by the window_renderer path).
  - `presentation/battle_layout.lua`: the temporary `mpReadout*` / `mpBar*` /
    `mpText*` keys were removed — the MP readout geometry now lives entirely in
    `drawMpReadout` / `drawPartyGridStyle`.
  - The MP readout is the shared party pool (`session.mp`/`session.maxMp`),
    not a summoner panel — consistent with F1.
  - Dialogue is a separate scene (`renderer.drawDialogue`); it now also renders
    the shared HUD via `drawSharedPartyHud`, so there is no scene without it
    (owner direction: "there should be no place where the declarative one
    isn't used").
- Gate impact: `tools/golden/battle.log` (engine logic) is UNCHANGED — all
  F2 changes are presentation-only. UI-golden logs for the scenes that show the
  HUD (battle, map, dialogue, town) must be regenerated and re-verified per
  ORCHESTRATION discipline (owner sign-off on the new captures).

**Gates:** G1, G2 (`battle.log` must be BYTE-IDENTICAL to F1's regenerated
log — this brief is plumbing/audit, not new mechanics; if your change makes
the log differ, that's a signal you changed behavior, not just confirmed
it), UI-golden for whichever scene gains the MP readout.
