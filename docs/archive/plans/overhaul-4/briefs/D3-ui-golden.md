# D3: UI-Golden Harness

**Context:** SPEC S5. Builds the safety net for refactoring scenes by allowing us to capture and verify a scripted sequence of UI inputs.

**Role:** Jules-shippable.

## Acceptance Criteria
- [ ] Extend the validator to support `love . validate golden-ui`.
- [ ] Implement a test harness that can drive a scripted input sequence (down, down, confirm, cancel, etc.) through a given scene.
- [ ] Capture the normalized UI event log (`window|action|target|value` per line) and output it between `UI GOLDEN BEGIN/END`.
- [ ] Establish reference logs at `tools/golden/scene_<key>.log` for all scenes targeted in this overhaul.
- [ ] Ensure validator scene hooks conform strictly to the rules (valid `cmd`, no interactive commands, valid `window`/`scene` params).

**Gates:** G1, G2.
