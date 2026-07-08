# C8 — Image previews everywhere

- Branch: `o3/c8-image-previews`  |  Runtime needs: G3
- Read first: SPEC.md Ground rules; FEEDBACK.md round 2, editor item 3

## Goal
Every sprite/image reference in the editor shows a live preview and picks
via the SAME asset selector the Event editor uses (openAssetPicker + the
preview thumbnail pattern in tools/editor/js/events.js
updateEventGraphicPreview).

## Do
- Extract a reusable `createSpriteField(container, label, value, onChange)`
  widget: thumbnail preview (or "(none)"), path label, "Pick…" button via
  openAssetPicker.
- Use it for: Actor sprite field (currently a plain text/asset input),
  Common Event default sprite, dungeon.exitSprite (CONFIG_SCHEMA assetPath
  widget), and any other image path field found in the forms.
- The asset picker grid already previews files — keep it.

## Acceptance
- [ ] Actor + Common Event sprite fields show thumbnails and pick via the
      shared selector; payload round-trips through Save
- [ ] No remaining bare-text image path fields (grep proof in PR)
- [ ] G3 green; PR checklist filled in
