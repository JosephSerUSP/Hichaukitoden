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
- [ ] Entries edit as a track list: add/remove/reorder typed tracks, each
      with its own field set via existing `widgets.js` patterns — tint
      colors via color widgets, particle emitter params, `mask: "target"`
      toggle, per-axis scale inputs, blend-mode dropdown. Unknown track
      types in loaded data render read-only rather than breaking the tab.
- [ ] Live preview pane animates a dummy battler sprite per the entry,
      reusing the ENGINE via the E5/E12 bridge precedent (`preview-anim`
      CLI mode + server endpoint; frame-sequence PNGs acceptable v1) —
      particles/masking/blend make a JS reimplementation unrealistic.
      Approach confirmed with owner before building; documented.
      Fidelity bar: timing, color, blend, and masking visibly match
      in-game results for the ported system entries.
- [ ] Skills and items editors gain an `animation` picker: dropdown of
      assignable entries + "(default)"; writes/clears the field.
- [ ] Editor save round-trips animations.json without reordering or
      dropping unknown fields (extensibility rule).

**Gates:** G1 (edited data still validates), G2/G3 unaffected. Manual
editor smoke test: create, edit, preview, delete an assignable entry;
verify a system entry cannot be deleted.
