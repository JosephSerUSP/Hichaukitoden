# E9: dedicated Game Over scene

**Context:** Owner feedback 10.07.2026 item 9 (FEEDBACK.md): "the game
currently doesn't really work well when game overing." Today defeat is
handled inline in `battle.handleTransition` (`engine/scenes/battle.lua`):
the session is reset in place and play resumes with no dedicated screen —
abrupt and fragile.

**Role:** local preferred.

**Design constraint:** this is a scenes-as-data task. The Game Over scene
should be authored as a `scenes.json` entry (kind `menu`, hooks + the
generic window renderer with `"draw": "windows"`), NOT a new bespoke Lua
scene — overhaul 4 exists precisely so screens like this are data. Engine
involvement should be limited to: the defeat path transitioning to the
scene (`SCENE_EVENT` / `scene_host.goto_scene`), and whatever generic
command the scene needs to restart the session (check what exists before
adding one; a session-reset action may need a small new command — keep it
generic, e.g. `RESET_SESSION`, registered together with a working handler).

## Acceptance Criteria
- [ ] A `game_over` scene in `data/scenes.json`: shows a game-over message
      (terms.json-sourced), offers at minimum "Return to Title" (and, once
      E10/saves exist, "Load Game" can join — do not block on it).
- [ ] Defeat path (`battle.handleTransition` isDefeat branch, and the
      `battle.defeat` flow's `scene_change` event) routes to the game_over
      scene instead of silently resetting the session mid-frame.
- [ ] Session reset happens via the scene's data hooks when the player
      chooses to continue, not as a side effect of losing.
- [ ] The scene has a `goldenScript` so UI-golden covers it (new reference
      log, justified as a new scene — existing references byte-identical).
- [ ] `battle.log` (G2) byte-identical — the golden battle harness does not
      drive the defeat UI path; if it turns out it does, stop and report.
- [ ] Editable in the editor like any other extra scene.

**Gates:** G1, G2, G3, UI-golden.
