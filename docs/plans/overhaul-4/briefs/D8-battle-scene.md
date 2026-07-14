# D8: Battle as Scene & UI Overhaul

**Context:** SPEC S6. The final, most entangled conversion. Battle is highly sensitive to the golden log. This task incorporates heavy UI changes from human feedback.

**Role:** LOCAL ONLY (Human or local agent; NOT Jules-shippable). Must manually capture and justify any `battle.log` changes.

## Acceptance Criteria
- [ ] Convert the `Battle` scene loops into data hooks in `scenes.json`.
- [x] **Feedback Integration:** Introduce a "Small Sprite" property for Actors (animated, `width / height` cell count, default 24x24) and load/display these in the battle status window. Damage-popup hooks are already available through the battle helper.
- [x] **Feedback Integration:** Fix enemy sprites so they render using their sprite keys instead of the default red square.
- [x] **Feedback Integration:** Displace Creature Element icons by 3 pixels in both the X and Y directions.
- [x] **Feedback Integration:** Add the Summoner's HP to the Battle UI.
- [ ] **Feedback Integration:** Reposition the Summoner's battle status to the top, left of the front row of creature slots.
- [ ] **Feedback Integration:** Extract the battler commands menu into a standalone window that sits flush with the battle status.
- [ ] **Feedback Integration:** Update the Battle Log to support two lines of text.
- [ ] **Feedback Integration:** Add a small character delay to text rendering (applies to "Show Text" and the Battle Log).
- [ ] **Feedback Integration:** Implement a dedicated Victory window phase.
- [ ] Regenerate `tools/golden/battle.log` and provide a line-by-line justification for the intentional layout and sequence changes in the PR.

**Gates:** G1, G2, G3.
