# B1 — Icon picker widget

- Branch: `o3/b1-icon-picker`
- Runtime needs: G3 (browser)
- Depends on: B0 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules

## Goal

Replace typed numeric "Icon #" fields with a visual picker.

## Facts you need

- Iconset: `assets/system/iconset.png`, 12×12-pixel cells, 10 columns, ids
  1-indexed: `col = (id-1) % 10`, `row = floor((id-1) / 10)` (see
  `presentation/ui.lua → ui.drawIcon`).
- The editor server already serves `assets/*` paths.

## Do

- `openIconPicker(currentId, cb)`: modal rendering the sheet as a scrollable
  grid of cells (CSS `background-position` on a shared image, or canvas);
  hover shows the id; click selects and calls back.
- Replace every numeric icon field (items, passives, states, elements forms)
  with: 12×12 live preview swatch (scaled ×2 for visibility) + id label +
  "Pick…" button.

## Don't

- No engine changes; no changes to how icon ids are stored (still numbers).

## Acceptance

- [ ] Picking an icon updates payload + preview in all four forms
- [ ] Current icon is highlighted when the picker opens
- [ ] G3 green
- [ ] PR checklist filled in
