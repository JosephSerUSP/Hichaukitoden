# D8: Battle as Scene — Implementation Plan

**Status:** 🔴 Not started — plan scaffold only
**Role:** LOCAL ONLY (NOT Jules-shippable)
**Gates:** G1, G2, G3
**SPEC Ref:** S6 (conversion order: last)

---

## Overview

Convert the Battle scene loops into data hooks in `scenes.json`. This is the most entangled scene in the codebase and requires regenerating `tools/golden/battle.log` with line-by-line justification for every change.

Unlike D4–D7 (which could skip UI-golden regeneration because they were new features), D8 **must** produce a byte-identical or explicitly-justified golden log because it touches the battle engine directly.

---

## Phase 1: Small Sprite System (prerequisite)

**Reference:** FEEDBACK.md item B.5

- Add `smallSprite` property to Actor data schema
- Format: animated sprite, cell count = `width / height` (rounded down)
- Default layout: 24×24 per cell
- Load and display in `Window_BattleStatus` and applicable menus
- Wire up damage popup / shake effect hooks on small sprites

**Files:** `data/actors.json`, `engine/battle.lua`, `presentation/renderer.lua`, `data/engine.json`

---

## Phase 2: Battle UI Overhaul (feedback items)

### 2a. Enemy Sprites (B.2)
- Fix enemy sprite rendering to use `spriteKey` instead of default red square
- Ensure all actor IDs with sprite keys resolve correctly

### 2b. Creature Element Icons (B.4)
- Displace element icons by 3px in X and Y directions
- Check `renderer.lua` element icon drawing code

### 2c. Summoner HP in Battle UI (B.1)
- Add Summoner's HP display to the battle status window
- Position: top, left of front row creature slots (B.6)

### 2d. Battler Commands Window (B.7)
- Extract battler commands menu into standalone window
- Window sits flush with battle status
- Opens/closes independently

### 2e. Two-Line Battle Log (B.8)
- Update Battle Log to support two lines of text
- Adjust layout for additional line

### 2f. Victory Window (B.9)
- Implement dedicated Victory window phase
- Separate from the main battle loop

---

## Phase 3: Text Character Delay (B.0)

- Apply small per-character delay to text rendering
- Affects both "Show Text" command and Battle Log
- Configurable in `engine.json`

**Files:** `engine/interpreter.lua`, `presentation/renderer.lua`

---

## Phase 4: Convert Battle to Hooks

- Refactor battle phase loops into `scenes.json` hooks
- Hooks: `on_enter`, `on_select`, `on_cancel`, `on_frame`, `on_exit`
- Battle phases become named hook lists (same pattern as crafting)

**Strategy:**
1. Start with battle phase hooks for non-interactive phases (victory, round_end, defeat)
2. Move to interactive phases (command selection, targeting)
3. End with the main battle loop

**Files:** `engine/battle.lua`, `data/scenes.json`, `data/flows.json`

---

## Phase 5: Golden Log Verification

1. Run current golden: `love . validate golden`
2. Capture output between `GOLDEN BEGIN` / `GOLDEN END`
3. Diff against `tools/golden/battle.log`
4. For each difference, write line-by-line justification
5. If the diff is intentional: regenerate `battle.log` via `tools/golden/capture.*`
6. Commit the new `battle.log` with the justification in the commit message

---

## Risks

| Risk | Mitigation |
|------|-----------|
| Battle.log is the most sensitive file in the repo | Local-only rule; line-by-line justification required per ORCHESTRATION.md §5 |
| 9 UI feedback items add scope beyond pure conversion | Phase 1-3 are independent and can be done before Phase 4 |
| Actor smallSprite schema change could break existing saves | Add as optional field with fallback |
| Text delay affects game feel globally | Make delay configurable and default to 0 (opt-in) |
| Victory window requires new hook/drawing logic | Build as standalone scene, not a battle phase |

---

## Implementation Order

1. **Phase 1:** Small Sprite system (prerequisite for battle status UI)
2. **Phase 2a–2c:** Enemy sprites, element icons, summoner HP (visual fixes)
3. **Phase 2d–2f:** Commands window, battle log, victory window (structural)
4. **Phase 3:** Text character delay (independent change)
5. **Phase 4:** Battle hooks conversion (most invasive — save for last)
6. **Phase 5:** Golden log comparison + line-by-line justification
