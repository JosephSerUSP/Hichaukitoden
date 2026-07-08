# B2 — Layout pass with inner tabs

- Branch: `o3/b2-layout-tabs`
- Runtime needs: G3 (browser)
- Depends on: B0 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules

## Goal

Denser, RPG-Maker-style forms. Reference style (RPG Maker VX Ace "Terms"
screen): grouped `fieldset`s with titles, labels **above** narrow inputs, 2–4
columns per group, horizontal inner tabs (e.g. `Battle1 | Battle2 | Others`)
instead of one long scroll.

## Do

- Reusable helpers: `buildTabbedSections(container, sections)` (horizontal
  inner tab strip + panel swap) and `buildFieldGroup(title, cols)`
  (fieldset with an n-column grid).
- Apply to: Engine window tabs (Battle Flow currently wastes half the panel),
  the Database System tab, and the Terms tab (top-level term keys become inner
  tabs).
- Convert `buildRecursiveForm`'s collapsible sections to field groups /
  inner tabs at depth 0–1; keep collapsibles only at depth ≥ 2.

## Don't

- No data-binding changes — only presentation. No changes to which fields
  exist.

## Acceptance

- [ ] Before/after screenshots of Engine → Battle Flow and Database → Terms
      attached to the PR
- [ ] No horizontal scrollbars at 1280×800
- [ ] G3 green
- [ ] PR checklist filled in
