# D4: Convert Crafting to Hooks

**Context:** SPEC S7. The composability proof for scenes. Converts the Crafting scene to use the new data hooks instead of legacy Lua. Incorporates crafting-specific UI feedback.

**Role:** Jules-shippable.

## Acceptance Criteria
- [ ] Replace `engine/scenes/crafting.lua` specific UI logic with hooks in `scenes.json`.
- [ ] `on_enter`: use `OPEN_WINDOW` for the discipline list and `SET_LIST`.
- [ ] `on_select`: use `IF` to drill down (discipline -> ingredients -> yield computation -> pool).
- [ ] `on_cancel`: step back a level or emit `SCENE_EVENT pop`.
- [ ] Implement the visual roulette sequence via `PLAY_ANIM` and `WAIT`.
- [ ] **Feedback Integration:** Fix the Crafting user sprite so it is drawn at 1x scale rather than oddly upscaled (2x).
- [ ] Ensure the scene UI-golden log is byte-identical before and after conversion.

**Gates:** G1, G2, G3 + UI-golden.
