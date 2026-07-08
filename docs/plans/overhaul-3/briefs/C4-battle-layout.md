# C4 — Battle screen layout: finish data-driving it

- Branch: `o3/c4-battle-layout`
- Runtime needs: G1 + G2; play-test debt for visual placement
- Depends on: nothing beyond the current integration branch
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules; `BIBLE.md`
  (shared layout code, no duplicated coordinates)

## Goal

The owner reports the battle command menu overlaps the Summoner status
display, plus other minor layout collisions (feedback game item 2 in
`docs/plans/overhaul-3/FEEDBACK.md`). They want to fix placement themselves
in the editor — but some coordinates are still hardcoded in
`presentation/`, so the editor's Battle Layout tab can't reach them.

## Do

1. Inventory every hardcoded position/size in the battle screen renderer
   (`presentation/renderer.lua`, `presentation/ui.lua` battle sections):
   command menu window, summoner status block, enemy row, party grid,
   console/log window, cursor/highlight offsets.
2. Move each into `data/engine.json → battleLayout` with the CURRENT value
   as the committed default (pixel-identical rendering — before/after
   screenshots).
3. Add matching `CONFIG_SCHEMA` entries (labels, min/step, help) so every
   value is editable under Engine → Rendering; the existing battleLayout
   JSON toggle covers bulk edits.
4. Do NOT redesign the layout yourself. The owner tunes values in the
   editor afterwards — your deliverable is reachability, not aesthetics.

## Don't

- No gameplay/logic changes; G2 must stay byte-identical.
- No new data files.

## Acceptance

- [ ] Zero hardcoded battle-screen coordinates left in presentation/ (grep
      proof in the PR description)
- [ ] Defaults render pixel-identical (screenshots)
- [ ] Every new key visible and editable in Engine → Rendering
- [ ] G1 + G2 green
- [ ] PR checklist filled in
