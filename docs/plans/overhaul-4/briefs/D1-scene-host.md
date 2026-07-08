# D1: Scene Host & Hooks

**Context:** SPEC S2. The foundation of Scenes as Data. We introduce the host that runs the frame loop and the scene lifecycle hooks.

**Role:** Jules-shippable.

## Acceptance Criteria
- [ ] Introduce the Scene Host which manages the frame loop, rendering, and cursor state.
- [ ] Update `scenes.json` format to include `hooks` (`on_enter`, `on_select`, `on_cancel`, `on_frame`, `on_exit`).
- [ ] Implement immediate-mode execution for scene hooks (reusing `interpreter.runImmediate`).
- [ ] Ensure scene-local variables (`v`) are scoped to the scene instance.
- [ ] Implement the fallback rule: if a hook is absent from `scenes.json`, run the legacy Lua block for that scene.

**Gates:** G1, G2.
