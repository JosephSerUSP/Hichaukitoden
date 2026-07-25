# Future Issues / Technical Debt

> **Intent, not status.** This document describes what we mean to build and why.
> For what is actually implemented right now, read the generated
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how the engine
> works, `docs/SPEC.md`. Where this document and those disagree, they win.

## 1. Editor file picker doesn't handle `[key=value]` animation tokens

The runtime supports `[fps=N]` and `[speed=N]` tokens both in sprite keys (JSON
data like `"sprite": "UI_BlueDot[fps=30]"`) and embedded in `.png` filenames
(parsed by [`small_battlers.resolveFile`](../presentation/small_battlers.lua:86)).
The two are independent — the sprite key token overrides the file token —
so changing a value in JSON doesn't break file association.

However, the **editor's asset/file picker** only shows raw filenames. If a user
renames the `.png` file (changing or removing its `[fps=N]` token), JSON entries
that reference the OLD sprite key (with the old token) will still resolve at
runtime (key token != file token, key wins), but the editor has no UI feedback
to communicate this. Users can't tell whether a `[fps=N]` value comes from the
JSON key, the filename, or the default.

**Fix idea:** Have the editor's file browser strip `[key=value]` suffixes from
display names and show the effective animation parameters (fps/speed) as
metadata columns or tooltips, so it's clear which value is in effect and where
it originates.

---

## 2. `small_battlers` module has grown beyond "small battlers"

The module [`presentation/small_battlers.lua`](../presentation/small_battlers.lua)
started as a renderer for 24×24 battler sprites but is now used as the general-purpose
sprite cache and animation driver for many non-battler UI elements (e.g.
`UI_WaitingForInput`, `UI_BlueDot`, `Cursor`). The module name no longer reflects
its scope.

**Fix idea:** Rename/refactor into a more generic `sprite_cache` or `sprite_atlas`
module, separating the battler-specific logic (dead tint, damage feedback) from
the shared image loading, frame slicing, and idle animation clock.

---

## 3. ~~`partyGridOrigin` in renderer.lua duplicates `ui.panelContentOrigin`~~ FIXED (22.07.2026)

`partyGridOrigin` now calls `ui.panelContentOrigin` directly instead of
re-deriving the same title-inset math by hand. No behavior change (same
defaults, same output).

---

## 4. `reserve`/`ritual`/`quest_log` scenes haven't fully adopted the §1.4
context-help-bar convention

`docs/SPEC.md` §1.4 describes a shared skeleton for `"draw":"windows"` menu
scenes: a top context-help bar with formula-driven, state-keyed content, plus
a bottom dock. It's applied to `status`/`equip`/`items`/`victory`, but:

- `reserve` has a separate static `reserve_title` (top, `y0 h2`) and
  `reserve_help` (mid-screen, `y13.5`, right above the dock) instead of one
  top bar with formula content.
- `ritual` has only a static `ritual_title` (`y0 h2`) — no hint/context bar
  at all.
- `quest_log`'s `quest_help` window sits in the right position (`y0 h4`,
  matching `windowLayout.help`) but its content is a hardcoded string
  (`'UP/DOWN: select quest   ESC: back'`) rather than a formula keyed on
  scene state — the exact "old pattern" §1.4 says it replaces.

All three do correctly use the shared bottom `partyGrid` dock — only the top
half is unmigrated. `game_over` has neither bar nor dock, which may be
intentional for a terminal, non-navigable screen rather than an oversight.

**Fix idea:** Migrate `reserve`/`ritual` to a single top `help` window
(reusing `data/engine.json`'s shared `windowLayout.help` entry) with
formula-driven content per scene state; make `quest_log`'s `quest_help` text
a formula (e.g. keyed on whether a quest is selected). Needs visual
verification (dock pixel-fit) before landing, not a blind data edit.

---

## 5. ~~Editor: `shops` tab is a hand-written DOM panel, not schema-driven~~ FIXED (24.07.2026)

Migrated `shops` tab into `ENTITY_FORM_SCHEMAS` in `tools/editor/js/entity-forms.js` using the `custom` field kind. Removed hand-written DOM construction from `loadFormForItem` in `tools/editor/js/widgets.js`.

---

## 6. ~~Editor: gauge/page list editors don't use the shared row-list widget~~ FIXED (22.07.2026)

Both rebuilt on `buildRowListEditor`. Pages now render as list rows
(double-click to edit) instead of a tab strip, gaining multi-select/arrow-nav/
Ctrl+C/X/V for free; gauges keep the same inline field layout with
Enter-to-commit added. No data shape changes.

---

## 7. ~~Editor: `alert()` vs the app's own `showToast()`~~ FIXED (22.07.2026)

All 8 call sites swapped to `showToast()`; each was a pure informational
message followed immediately by `return`, so no blocking-confirmation
behavior was lost.

---

## 8. SCRIPT usages in `builtinSceneIds` builtin scenes (`shop` & `items`)

Audited `shop` and `items` in `data/scenes.json`:
- `shop`'s purchase path uses native commands `GAIN_GOLD` and `CHANGE_ITEM` (no `SCRIPT` commands in `shop`).
- `items` uses `USE_ITEM` and dynamic variable bindings via `v.lastItemResult` (no `SCRIPT` commands in `items`).
(The only remaining `SCRIPT` usages in `data/scenes.json` belong to complex/optional extra scenes like `Item Creation`).

---

## 9. ~~G2 golden battle log & G3 UI logs updated~~ FIXED (24.07.2026)

Sanctioned update of `tools/golden/battle.log` and `scene_*.log` golden references following the actor stat rebalance. G2 (`check.ps1`) and G3 (`check-ui.ps1`) now pass 100% clean.
