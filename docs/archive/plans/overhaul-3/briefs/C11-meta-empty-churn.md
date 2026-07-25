# C11 — Stop empty `meta` objects polluting saves (Zoo Code starter task)

- Branch: `o3/c11-meta-empty-churn`
- Runtime needs: G1 + G3 (both runnable locally — this is a self-verify task)
- Depends on: C10 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules
- Intended executor: **Zoo Code (local VS Code agent)** — the point of this
  first task is to run ALL gates yourself and hand back a green branch, not a
  candidate with unverified debt.

## Problem

The C10 Meta field group calls `owner.meta = owner.meta || {}` when a record
is rendered (`tools/editor/js/widgets.js`, ~lines 1836 and 1954). So merely
*opening* an actor/item/etc. in the editor mutates its payload with an empty
`meta: {}`. On the next "Save Database" every touched record gains an empty
`meta`, and the save rewrites the file — producing noisy diffs of pure
`"meta": {}` additions (observed: opening Pixie + the Workbench dirtied nine
data files with nothing but empty-meta churn).

## Do

1. Render the Meta group **without** persisting an empty object: read from
   `owner.meta || {}` for display, but only create `owner.meta` on the
   payload when the user actually adds the first key. When the last key is
   removed, delete `owner.meta` again (leave no empty object behind).
2. Add a save-time sweep: before the payload is written (find the save path
   in `tools/editor/js/*.js` / the Save Database flow), strip any `meta` that
   is an empty object from every record, so pre-existing empty-meta objects
   in memory never reach disk.
3. Do not change how non-empty meta is stored, validated, or read by
   formulas (C10 behavior stays intact).

## Don't

- No engine Lua changes. No change to `engine.json → metaKeys`.
- Don't reformat data files. Never regenerate `tools/golden/battle.log`.

## Acceptance

- [ ] Opening several records and hitting Save Database produces **no**
      `"meta": {}` additions (`git status` clean if nothing real changed)
- [ ] Adding a meta key still persists it; removing all keys removes `meta`
- [ ] G1 `& "C:\Program Files\LOVE\lovec.exe" . validate` ends VALIDATE OK
- [ ] G3: exercised in the browser, zero console errors
- [ ] PR checklist filled in (all three gates run locally — no debt expected)
