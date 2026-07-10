# E2: Context menu + keyboard model for the command list

**Context:** SPEC S5 item 3. Replaces the inline ✏️/❌ buttons currently
duplicated across at least 4 call sites in `tools/editor/js/events.js` (grep
`✏️` to find them all: the plain-line path plus `renderCommentRow`,
`renderChoiceBlock`/similar block renderers reuse the same button pattern).
This is the biggest of the readability briefs — budget real time for the
keyboard/selection plumbing, not just the button removal.

**Role:** local preferred (real interaction-model work; browser-testable
only, no headless equivalent for the keyboard/mouse flows).

## Acceptance Criteria
- [ ] Remove the ✏️ (edit) and ❌/× (delete) inline buttons from every
      command row, at every call site.
- [ ] Right-click a row → context menu with: Edit, Delete, Copy, Cut, Paste
      (Duplicate is a nice-to-have if cheap). Reuse or build one shared
      context-menu primitive — do not hand-roll a new popup per call site.
- [ ] Space, when a row has keyboard focus, opens the same edit flow as the
      old ✏️ button / row click.
- [ ] Delete key, when a row (or a multi-row selection) has focus, deletes
      it/them — same effect as the old ❌ button, extended to a selection.
- [ ] Rows need a focus concept to hang keyboard behavior off of — check
      whether one already exists (a `tabindex`, a visual focus ring) before
      adding one; if not, add a minimal one (focus ring style, click-to-focus,
      arrow-key-to-move-focus without needing a mouse).
- [ ] Shift+Up / Shift+Down extends a contiguous selection range from the
      currently focused row. Plain Up/Down moves focus (and collapses any
      existing selection, standard list-box behavior).
- [ ] Ctrl+C copies the selected command(s) (as JSON) to an in-memory
      clipboard (or the real OS clipboard via the Clipboard API if the
      editor's execution context allows it — fall back to an in-memory
      buffer if not). Ctrl+V pastes them into the list at the focused
      position.
- [ ] Keyboard handlers are scoped to the command-list container (e.g.
      listen on the container element with a focus check, not `document`
      globally) so they don't steal keystrokes from open modals, text
      inputs, or the JSON `{ }` toggle textareas elsewhere on the page.
- [ ] Works correctly for nested lists (inside CHOICE/CONDITIONAL_BRANCH
      bodies) — selection, copy, and paste should be scoped to the list the
      focused row actually belongs to, not bleed across nesting levels.
- [ ] Zero console errors; all prior click-to-edit functionality still works
      (row click still opens edit, per existing `line.onclick` behavior) —
      this is additive, not a replacement for mouse interaction.

**Gates:** G1, G3 (this is almost entirely G3 — drive it by hand: right-click
a row, use every context menu item, use Space/Delete/Shift+arrows/Ctrl+C/
Ctrl+V, confirm no console errors and a save round-trips the resulting data).
