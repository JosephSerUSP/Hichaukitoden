# D0: Editor Polish & Enhancements

**Context:** Sourced from overhaul-4 human feedback. This task improves the editor experience and is independent of the S10 scene conversions.

**Role:** Jules-shippable (Orchestrator will clear G3 verification debt).

## Acceptance Criteria
- [ ] Replace the "Descend Stairs" event command with a generic "Teleport" command.
- [ ] Update field layouts to use vertical labels in all remaining editor tabs (matching the recent Terms tab improvements).
- [ ] Ensure that Icons are positioned as the top leftmost element in all applicable data tabs.
- [ ] Refactor image preview fields: remove the separate string input and `[...]` button. Make it so double-clicking the image preview directly opens the image selector.
- [ ] Add a full-resolution (and animated, if applicable) sprite preview to the right side of the Image Selector modal.

**Gates:** G3.
