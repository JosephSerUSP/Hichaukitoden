# E8: smallBattler damage feedback — flash, shake, dead display

**Context:** Owner feedback 10.07.2026 items 7–8 (FEEDBACK.md). Enemies
already flash when targeted; party smallBattlers (2x2 grid + summoner
sprite) give no damage feedback at all, and dead members keep animating.
Read `future-animation-system.md` first: this brief is the seed of that
system — every timing/color/amplitude value goes in DATA, not inline
constants.

**Role:** local preferred (visual judgment; needs `lovec . test-battle`).

## Acceptance Criteria
- [ ] smallBattlers **flash** when taking damage (party grid slots and the
      summoner status sprite), using the same trigger path that flashes
      enemies (see `battleAnims` flash handling in `presentation/renderer.lua`
      and where damage popups are spawned — that call site knows the target).
- [ ] smallBattlers **shake** when taking damage: a short horizontal offset
      oscillation on the sprite (amplitude/duration/frequency from data).
- [ ] **Dead display:** a dead member's small sprite is tinted dark
      purple/greyish, does NOT animate, and shows only frame 1. No death
      animation plays for smallBattlers.
- [ ] All constants in data, not Lua: add a `battle_screen.animations` block
      to `data/system.json` (e.g. flashDuration, flashColor, shakeDuration,
      shakeAmplitude, deadTint) and route the EXISTING enemy flash constants
      (hardcoded 0.35s and colors in renderer.lua) through the same block —
      the owner explicitly asked for the enemy flash to become configurable.
- [ ] Behavior identical for the summoner sprite and grid sprites (shared
      helper, not two copies — the drawSummonerStatus/drawPartyGrid split
      already duplicates sprite drawing; prefer extracting the sprite-cell
      draw into one function while there).
- [ ] G2 golden byte-identical (renderer-only; no combat logic changes).

**Gates:** G1, G2, UI-golden (all byte-identical), `lovec . test-battle`
draw smoke + owner visual sign-off.
