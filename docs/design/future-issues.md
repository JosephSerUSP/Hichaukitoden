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

## 4. ~~`reserve`/`ritual`/`quest_log` scenes haven't fully adopted the §1.4
context-help-bar convention~~ FIXED (30.07.2026), merged to main (05.08.2026)

`reserve`'s separate `reserve_title` + `reserve_help` windows are gone,
replaced by one top `help` window (`windowLayout.help`, no scene-owned
title text — matching `items`/`status`, which show no persistent scene
name either). The imperative `api.emit({type="set_text", windowId=
"reserve_help", ...})` calls in `executeReservePopup`/`executeSwap`
(the exact "old pattern" §1.4 replaces) are gone too, replaced by a
`v.statusText` variable the bar's formula reads declaratively.
`reserve_roster`'s `windowLayout` entry grew into the space the old
bottom bar occupied (`y2 h11.5` -> `y4 h14`).

`ritual_title` keeps its per-mode text for `v.state == 1` but now branches
on `v.state == 2`/`3` to show confirm/result hotkeys instead of a stale
mode header during those overlays — geometry (`y0 h2`) is unchanged, so
the replacement string had to fit one line at that width; the first
attempt wrapped and got clipped by the 2-tile height, caught via the
freshly-fixed screenshot harness (`lovec . screenshots`) and shortened.

`quest_log`'s `quest_help` text is now a formula keyed on `v.questCount`,
matching the `datalog_help` precedent, instead of always claiming
"select quest" even against an empty list.

All three visually verified via `lovec . screenshots` (deterministic
capture, no wall-clock waits, no overlap/clipping). G1/G2/G3/unit all
green post-merge — the `reserve` UI trace was already owner-signed and
re-recorded in `8a0e011`/`36754ab` ahead of this code landing.

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

## 7. ~~Editor: `alert()` vs the app's own `showToast()`~~ FIXED (22.07.2026, corrected 01.08.2026)

All 8 call sites swapped to `showToast()`; each was a pure informational
message followed immediately by `return`, so no blocking-confirmation
behavior was lost.

**Correction:** the 22.07 pass missed `tools/editor/js/tileset-editor.js`
(7 more `alert()` sites, same shape). Fixed 01.08.2026 -- no `alert()`
remains anywhere in `tools/editor/js/`.

---

## 8. SCRIPT usages in `builtinSceneIds` builtin scenes (`shop` & `items`)

Audited `shop` and `items` in `data/scenes.json`:
- `shop`'s purchase path uses native commands `GAIN_GOLD` and `CHANGE_ITEM` (no `SCRIPT` commands in `shop`).
- `items` uses `USE_ITEM` and dynamic variable bindings via `v.lastItemResult` (no `SCRIPT` commands in `items`).
(The only remaining `SCRIPT` usages in `data/scenes.json` belong to complex/optional extra scenes like `Item Creation`).

---

## 9. ~~G2 golden battle log & G3 UI logs updated~~ FIXED (24.07.2026)

Sanctioned update of `tools/golden/battle.log` and `scene_*.log` golden references following the actor stat rebalance. G2 (`check.ps1`) and G3 (`check-ui.ps1`) now pass 100% clean.

---

## 10. Editing game interfaces in the editor is a wall of fields (31.07.2026)

Raised by the owner while turning off the battle enemy info block. That change
was a single data flag, which is the system working as intended — but finding
and setting it meant scrolling a flat list of `battleLayout` keys
(`enemyInfoVisible`, `enemyInfoWidth`, `enemyInfoOffsetY`,
`enemyInfoBarOffsetY`, `enemyInfoShowName`, `enemyInfoShowHpBar`,
`enemyInfoShowElements`, ...) with no picture of what any of them do.

The same shape recurs across every interface-shaping registry: `windowLayout`
(rects in tiles, per-window `anim`, `chrome`, `slotHeight`/`slotGap`),
`battleLayout`, the `dock` variants and their shells. All of it is
schema-driven form generation via `buildRecursiveForm`, which is why adding a
field costs nothing — and also why editing one feels like editing a config file
rather than a layout.

**The complaint is not that the data model is wrong.** Data-driven layout is
load-bearing and should stay. The gap is that the editor renders a *spatial*
domain as a *textual* one: numbers whose only meaning is where something lands
on a 256x240 canvas are typed blind, then verified by launching the game.

Directions worth weighing before building anything:

- The engine can already render any scene or window headlessly through the
  real presentation stack (`lovec . preview-scene`, `preview-window`,
  `preview-anim`, and the G5 screenshot harness). An interface editor that
  showed the live frame beside the fields — or let a rect be dragged and wrote
  the numbers back — would reuse that, not reimplement it. **The editor must
  keep rendering nothing itself** (SPEC 1.2); it asks the engine for a frame.
- Grouping matters as much as visualisation: the `enemyInfo*` keys are one
  feature spread across seven sibling fields. Whether that becomes a nested
  object in data or is only grouped in the form is a real decision -- the
  first changes the schema and every reader, the second does not.
- Scope is the risk. This touches the editor's most generic machinery, so it
  wants a narrow first target (one registry, e.g. `battleLayout`) rather than
  a general "visual layout editor" rewrite.

Not scheduled. Recorded so the next person to add a layout field has the
argument in front of them instead of rediscovering it.
