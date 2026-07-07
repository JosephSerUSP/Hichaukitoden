# C10 — Typed meta system (registry-backed, NOT RPG Maker notetags)

- Branch: `o3/c10-meta-system`
- Runtime needs: G1 + G2; G3 for the editor side
- Depends on: current integration branch. **Prerequisite for C9.**
- Read first: SPEC.md Ground rules, S5; FEEDBACK.md round 2 + the owner's
  Item Creation design doc summary at the bottom of this brief

## Goal

Give every database entry an optional extensible `meta` object of typed
key/values, editable in the editor, checked by the validator, and readable
from formulas. This is the open-JSON analog of RPG Maker notetags — with a
key REGISTRY instead of regex-parsed strings, keeping the project rule that
the validator catches dead/unimplemented content.

## Do

1. **Data:** any entry in any DB file may carry `"meta": { <key>: value }`
   (values: number, string, or boolean; nothing nested). Loader passes it
   through untouched.
2. **Registry:** `engine.json → metaKeys`: array of
   `{ key, appliesTo: ["items", ...], type: "number"|"string"|"flag",
   description }`. Seed it with the crafting keys the C9 design needs on
   items: `tier` (number), `density` (number), `potency` (number),
   `craftElement` (string), `craftKind` (string — blacksmith/tinker/
   alchemy/cooking pool tagging).
3. **Validator:** for every `meta` in every data file — declared key with
   wrong type = error; undeclared key = warning line + total count (info,
   not failure). COMMENT-style tolerance: absent meta is always fine.
4. **Editor:** every DB form gets a "Meta" field group rendered from the
   registry: one row per PRESENT key (typed widget by registry type, ×
   delete), plus an "+ Add Key" dropdown offering the registered keys for
   that data type (description as tooltip — reuse the B5 tooltip pattern).
   Registry itself editable in the Engine window (same pattern as
   Effect Types / Trait Codes tabs).
5. **Formulas:** battler/item views in the formula sandbox expose `meta`
   (read-only table, e.g. `ingredient1.meta.tier`). Document every new
   token in `engine.json → formulaHelp`.

## Don't

- No regex/string parsing of any "note" text — values are plain JSON.
- No gameplay changes; nothing reads meta yet (C9 will). G2 byte-identical.

## Acceptance

- [ ] Corrupting a meta value's type turns G1 red; an undeclared key warns
      but stays green (both demonstrated, then reverted)
- [ ] Meta editable on an item in the editor and round-trips through Save
- [ ] formulaHelp documents meta access; G1 + G2 + G3 green
- [ ] PR checklist filled in
