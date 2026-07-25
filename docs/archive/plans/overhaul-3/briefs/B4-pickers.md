# B4 — More data pickers

- Branch: `o3/b4-pickers`
- Runtime needs: G3 (browser); server part is text-only
- Depends on: B0 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules

## Goal

Replace remaining free-text references with pickers.

## Do

1. `tools/editor/server.js`: add `GET /api/graphs` returning the basenames of
   `data/graphs/*.json` as a JSON array.
2. Widgets:
   - `graphPicker` — dropdown fed by `/api/graphs`; use it for town-option
     `graph` fields (System tab, town options editor).
   - `mapPicker` — extract the existing inline map-title select into a
     reusable widget.
   - `termPicker` — dropdown/tree of dotted paths walked from
     `dbPayload.terms`; registered so command-param type `term` (used by the
     A6 palette) can consume it. Coordinate through the param-type name only —
     do not import A6 code.

## Don't

- No engine changes beyond none; server change is the one endpoint.

## Acceptance

- [ ] `/api/graphs` lists every graph file
- [ ] Town options edit with the graph dropdown; map picker works where maps
      are referenced
- [ ] G3 green
- [ ] PR checklist filled in
