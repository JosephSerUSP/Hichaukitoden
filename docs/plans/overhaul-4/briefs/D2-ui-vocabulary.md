# D2: UI Command Vocabulary & Layout Data

**Context:** SPEC S4. Defines the declarative vocabulary for manipulating UI windows within scene hooks, and extracts window layout data. Also incorporates global UI polish from human feedback.

**Role:** Jules-shippable.

## Acceptance Criteria
- [ ] Register new non-interactive UI commands with `contexts: ["scene"]`: `OPEN_WINDOW`, `CLOSE_WINDOW`, `SET_LIST`, `SET_TEXT`, `SET_CURSOR`, `FOCUS_WINDOW`, `PLAY_ANIM`, `WAIT`, `SCENE_EVENT`.
- [ ] Implement `WAIT` as a non-blocking host-timed suspension.
- [ ] Move window geometry and styles into `engine.json -> windowLayout`.
- [ ] **Feedback Integration:** Remove the black border around headers universally in the engine layout.
- [ ] **Feedback Integration:** Implement a global configuration for spacing between headers and window content.
- [ ] **Feedback Integration:** Adjust global right-alignment to ensure right-aligned elements sit exactly at `ui.tileSize` from the right border.

**Gates:** G1, G2, G3.
