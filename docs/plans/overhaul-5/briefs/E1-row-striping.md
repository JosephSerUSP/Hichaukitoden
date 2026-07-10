# E1: Even/odd row striping in the command list

**Context:** SPEC S5 item 2. Pure readability fix for `renderCommandList`
and its nested block renderers in `tools/editor/js/events.js`.

**Role:** Jules-shippable (editor-only, CSS/DOM only).

## Acceptance Criteria
- [ ] Alternate background color for even/odd command rows.
- [ ] Applies consistently across indent levels and inside nested blocks
      (CHOICE/CONDITIONAL_BRANCH bodies) — striping should be based on each
      row's position within its own visible list, not a single global
      counter that gets thrown off by collapsed/hidden comment rows (check
      `showCommentsPref()` — hidden comments should not break the even/odd
      alternation of the rows around them).
- [ ] Does not fight with E0's category colors or the existing hover
      highlight (`line.onmouseover` sets `background: #000080`) — hover and
      selection states must still be clearly visible on top of a striped row.
- [ ] Zero console errors; no functional regression.

**Gates:** G3 (purely visual — open the editor, load a command list long
enough to show several rows, confirm alternating rows are visually distinct
and hover/selection still reads clearly on both stripe colors).
