# Future Issues / Technical Debt

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

## 3. `partyGridOrigin` in renderer.lua duplicates `ui.panelContentOrigin`

[`presentation/renderer.lua`](../presentation/renderer.lua)'s `partyGridOrigin(session)`
re-derives a panel's content origin (`contentX`/`contentY` with the title-inset
fallback, converted via `ui.toPx`) by hand, duplicating what
[`ui.panelContentOrigin`](../presentation/ui.lua:209) already does and what
`window_renderer.lua`'s `contentOrigin` already wraps. This is the one origin
calculation that drifted from the shared helper — everything else (grid cell
math in `actor_status.gridSlot`/`cellSize`) is properly centralized. Violates
`docs/SPEC.md` §2.1 (no copy-pasted coordinate mappings).

**Fix idea:** Replace the hand-rolled logic in `partyGridOrigin` with a call to
`ui.panelContentOrigin`.

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

## 5. Editor: `shops` tab is a hand-written DOM panel, not schema-driven

Unlike `items`/`skills`/`passives`/`states`/`elements`/`roles` (all migrated
into `ENTITY_FORM_SCHEMAS` in `tools/editor/js/entity-forms.js`), the `shops`
branch of `loadFormForItem` (`tools/editor/js/widgets.js:1786-1857`) still
builds its name field and stock checklist by hand. It isn't one of
`docs/SPEC.md` §4's named complex-editor exemptions (animation timeline,
event commands, map painter) — its shape (name + per-item
checkbox/price/condition list) fits the schema layer's `custom` field kind
already used elsewhere (e.g. elements' strong/weak-against checklists in
`entity-forms.js:245-251`).

**Fix idea:** Move `shops` into `ENTITY_FORM_SCHEMAS` using the `custom`
field kind, matching the elements-tab pattern.

---

## 6. Editor: gauge/page list editors don't use the shared row-list widget

`tools/editor/js/window-editor.js`'s `buildGaugeListEditor` (~line 593) and
`buildPageListEditor` (~line 659) both hand-roll their own add/delete-only
row UI instead of `buildRowListEditor` (`widgets.js:471`), which every other
list in the editor (effects, traits, quest objectives/rewards, item refs)
uses. Beyond the code duplication, this is a real UX inconsistency: gauge/page
rows silently lack the multi-select, arrow-key nav, and Ctrl+C/X/V that users
get everywhere else in the same modal.

**Fix idea:** Rebuild both on top of `buildRowListEditor`, matching the
row-editor pattern used for effects/traits.

---

## 7. Editor: `alert()` vs the app's own `showToast()`

Eight call sites (`database.js`, `map-editor.js`, `widgets.js`, `studio.js`
×5) still use the blocking, unstyled native `alert()` for messages that have
equivalent non-blocking `showToast()` (`net.js:70`) calls elsewhere in the
same app (e.g. quest/sequence rename errors). `alert()` breaks the Win98
chrome and blocks the whole page; likely legacy code predating the toast
helper.

**Fix idea:** Sweep the 8 call sites to `showToast()`, checking each one
individually for whether it's a blocking-confirmation use (should stay
`confirm()`/stay blocking) vs. an informational message (should become a
toast).
