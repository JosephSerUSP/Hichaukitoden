# Future: the "map" Scene Kind (seed note, not a brief)

Owner direction (09.07.2026): the third scene kind — after `menu` and
`battle` — is **map**-type scenes, likely more complex than battle. Not
scoped for overhaul 4; this note seeds the eventual round.

## Starting position

Exploration already routes through scene_host ids (`map`, `town`) but is
fully legacy behind them: `renderer.drawMap()`, movement/encounters in
main.lua, `town` faked as a menu. The rules layer is already data —
maps.json (layout, events, encounters, encounterSteps, generation), map
event commands validated under the `"map"` context, ROLL_ENCOUNTER flows.
As with crafting (SPEC S0), the hardcoded surface is presentation + input.

## Why it's harder than battle

1. **Spatial nouns.** Windows/lists/cursors don't cover tiles, entities,
   collision, facing, camera. Needs a second vocabulary family
   (movement/camera/tile queries in formulas) alongside S4's window set.
2. **Interaction grammar.** `on_select` = "interact with the faced target"
   — requires target resolution. Natural map hooks are positional
   (`on_step`, `on_touch`, autorun/parallel per map event — RPG Maker's
   trigger taxonomy as data on events, not the scene).
3. **Root of the scene stack.** Everything pushes on top of the map and
   pops back. Exposes a v1 hook-set gap: there is no `on_resume` fired
   when a pushed scene pops back. Maps need it (camera re-sync, trigger
   re-check, BGM resume); adding it benefits all scenes.
4. **Golden coverage.** Scripted keys still drive it, but assertions
   become positional (`player|move|x,y`, `event|trigger|id`) with seeded
   encounter RNG (harness already seeds).

## Dependency order

D13 (generic window renderer, crafting dissolved) → D8 (battle as second
renderer consumer, hooks under battle.log discipline) → map kind as the
next round's capstone. It reuses windows (dialogue, town menus become
map-scene UI instead of a fake `town` scene) and adds the spatial host.
