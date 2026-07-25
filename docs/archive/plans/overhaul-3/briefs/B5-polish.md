# B5 — Polish batch

- Branch: `o3/b5-polish`
- Runtime needs: G3 (browser)
- Depends on: B0 and B2 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules

## Do

- Tooltips on effect/trait/command dropdowns sourced from the registries'
  `description` fields (`engine.json`).
- Apply `min`/`step` from `CONFIG_SCHEMA` to every generated number input.
- Render a `field-help` span for any `CONFIG_SCHEMA` entry that has a `help`
  string (add `help` strings for at least the growth and elementRules keys).
- Enter key applies in the "Change Maximum" dialog.

## Acceptance

- [ ] Visual spot-check of each item above
- [ ] G3 green
- [ ] PR checklist filled in
