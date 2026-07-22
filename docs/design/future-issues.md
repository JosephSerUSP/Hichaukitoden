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

## 8. Two remaining SCRIPT usages violate items/shop's S6 zero-SCRIPT rule

`items` and `shop` are on the validator's `builtinSceneIds` allowlist (S6:
zero SCRIPT commands) in `main.lua`'s `validateCommands` — but two usages
still exist:

- `shop`'s `buyItem` script (`data/scenes.json` scene `shop` → `scripts.buyItem`)
  performs real side effects (`api.gainGold`, `api.giveItem`) gated by an
  affordability check. Converting it needs either a new native command
  combining conditional gold/item mutation, or extending `GIVE_ITEM_ID`'s
  allowed `contexts` (currently `battle_phase`/`map`/`common`, missing
  `scene`) to match `GAIN_GOLD`'s (which already includes `scene`) plus
  verifying `scene_host.lua` actually executes that command in scene-hook
  context. Not attempted this session — untested engine-vocabulary
  extension, no live playtest coverage for shop purchases.
- `items`'s `useItemAndPop` script (`data/scenes.json` scene `items` →
  `scripts.useItemAndPop`) reads `api.items()[ctx.v.idx].name` to remember
  the just-used item's display name for the "Used X!" popup. Unlike shop's
  `v.items` (an explicit scene var with `.name`/`.cost`/`.stock` fields,
  already formula-accessible — see item 8's sibling fix below), items'
  inventory list is rendered via `SET_LIST windowId=items_left_panel
  listId=inventory` and never materialized into a `v.*` array, so there's no
  formula-accessible equivalent today. Fix idea: add an ordered
  `session.inventoryNames` (or similar) to `formula.sessionView`
  (`engine/formula.lua:133`) built with the *same* sort order the
  `inventory` list source uses, mirroring the precedent already set by
  `session.itemCount`/`equipCount`/`skillCount` ("lets scene hooks bound X
  without SCRIPT" — see the comments at `formula.lua:148-191`). Getting the
  ordering wrong would silently mislabel the popup, so this needs the
  ordering verified against the real list-source code, not just eyeballed.

(Fixed this session: `shopIncreaseQty`, the third SCRIPT usage in `shop`,
converted to a pure `min()`/`floor()` formula — see the
`scheduled-review-2026-07-22` branch.)

---

## 9. G2 golden battle log has been silently broken since commit `962194d` (~10 commits, unnoticed)

`lovec . validate golden` / `tools/golden/check.ps1` currently **fail on
`main`** — bisected precisely to `962194d` ("feat: add baseParams and
growthMultiplier to actors in campaigns and data"): its parent `5869f0a`
matches `tools/golden/battle.log` byte-for-byte, `962194d` itself diverges
from the very first damage roll (`Pixie` takes 10 in the reference log, 9 in
a fresh run) and the battle runs 3 events longer (33 vs 30 lines). The actor
stat rebalancing in that commit shifted a threshold (crit/hit/flee — not yet
pinned down further) enough to change the RNG-consumption pattern of the
fixed `runGolden()` action script, even though `math.randomseed(12345)` is
reseeded identically at the top of every run. Every commit since (10+,
through current HEAD `866c244`) inherited the broken gate without anyone
noticing or investigating — `git log --oneline -- tools/golden/battle.log`
shows the log was last deliberately regenerated at `9edbd38`, before
`962194d`.

**Not fixed this session** — per `docs/SPEC.md`'s golden-log discipline
("never regenerate a golden log to green a diff") this needs an owner
decision (was the `962194d` stat rebalance intentional? if so, a deliberate,
reviewed regeneration is the fix; if not, the actual bug is in whatever
stat/threshold shifted) rather than an autonomous regeneration. Reproduce
with: `git checkout 962194d -- .` (or any commit since) then
`tools/golden/check.ps1` — mismatch; `git checkout 5869f0a -- .` then same
script — match.

Same-family gap in G3: `tools/golden/check-ui.ps1` also mismatches on `main`
today for scenes `title` (pre-existing, already flagged in the
`scheduled-review-2026-07-21` review as caused by `e9e5995`'s mini-map work)
and `items` (not previously flagged — plausibly the same `962194d` stat
rebalance, or the popupTimer/dynamic-stock-formatting commits, changed
observable on-screen content without a log regen). Confirmed pre-existing on
clean `main`, unrelated to this session's diff — this branch's own G3 run
shows the identical two mismatches and nothing new.
