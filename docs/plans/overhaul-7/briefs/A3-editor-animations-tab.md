# A3: Editor Animations Tab + Live Preview

**Context:** Read SPEC.md S4 and the direction note's RPG-Maker-departure
framing (system animations are first-class editable entries). **Depends on
A1 (schema frozen); prefer landing after A2** so the skills/items
`animation` picker has real semantics.

**Role:** local agent; the preview-channel decision (engine bridge vs. JS
re-implementation) needs an owner pick before building — present both
options with effort estimates, don't choose unilaterally.

## Acceptance Criteria
- [ ] New Animations tab in `tools/editor` following the registry pattern
      (like Effect Types / Trait Codes): system entries pre-seeded,
      always present, non-deletable; assignable entries CRUD.
- [ ] Per-`kind` field rendering via existing `widgets.js` patterns;
      color fields reuse existing color widgets; unknown `kind` values in
      loaded data render read-only rather than breaking the tab.
- [ ] Live preview pane animates a dummy battler sprite per the entry.
      Path (engine bridge vs. JS reimplementation) chosen by owner and
      documented. Fidelity bar: timing and color visibly match in-game
      results for the 4 ported entries.
- [ ] Skills and items editors gain an `animation` picker: dropdown of
      assignable entries + "(default)"; writes/clears the field.
- [ ] Editor save round-trips animations.json without reordering or
      dropping unknown fields (extensibility rule).

**Gates:** G1 (edited data still validates), G2/G3 unaffected. Manual
editor smoke test: create, edit, preview, delete an assignable entry;
verify a system entry cannot be deleted.
