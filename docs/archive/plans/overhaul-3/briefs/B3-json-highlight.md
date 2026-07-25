# B3 — Color-coded JSON editing

- Branch: `o3/b3-json-highlight`
- Runtime needs: G3 (browser)
- Depends on: B0 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules

## Goal

Upgrade the `{ } JSON` mode (`attachJsonToggle`) from a plain textarea to a
highlighted editor.

## Do

- Transparent `<textarea>` overlaid on a scroll-synced `<pre>` that
  re-tokenizes on input: object keys, strings, numbers, booleans/null in
  distinct colors. No external dependencies.
- Keep the existing red-background invalid-JSON state and the Apply/Back
  behavior exactly as they are.

## Don't

- No editor libraries (CodeMirror/Monaco etc.). No change to how Apply
  mutates the payload.

## Acceptance

- [ ] Typing stays responsive on the largest object (`data/system.json` via
      Database → System → JSON)
- [ ] Highlighting matches content after fast edits and scrolling stays in
      sync
- [ ] G3 green
- [ ] PR checklist filled in
