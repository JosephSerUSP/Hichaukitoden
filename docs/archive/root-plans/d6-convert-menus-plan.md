# D6: Convert Menus — Implementation Plan

## Overview

Convert Title, Main Menu, Item, and Status scenes into data hooks in `scenes.json`, while fixing UI feedback issues for Items (spacing/height), Equip (icons), and Status (Exp/Level display).

**Key constraint:** The scene UI-golden log must be byte-identical before and after the conversion (or explicitly justified for UI feedback tweaks).

## Files to Modify

| File | Changes |
|---|---|
| `data/scenes.json` | Add 4 new scene entries (title, menu, items, status) with hooks |
| `main.lua` | Route scene hooks for the new scenes; handle SCENE_EVENT output |
| `presentation/renderer.lua` | UI fixes: item spacing, equip icons, Exp/Level display |
| `engine/scene_host.lua` | Possibly enhance to support string scene IDs better |

## Phase 1: Scene Definitions in `data/scenes.json`

Add four new entries alongside the existing crafting scene:

### 1. Title Scene
```json
{
  "id": "title",
  "name": "Title Screen",
  "kind": "menu",
  "hooks": {
    "on_enter": [
      { "cmd": "OPEN_WINDOW", "windowId": "title_bg" },
      { "cmd": "SET_TEXT", "windowId": "title_bg", "text": "\\c[6]HICHAUKITODEN" },
      { "cmd": "OPEN_WINDOW", "windowId": "title_menu" },
      { "cmd": "SET_TEXT", "windowId": "title_menu", "text": "Press ENTER to start" }
    ],
    "on_select": [
      { "cmd": "SCENE_EVENT", "kind": "goto", "scene": "town" }
    ],
    "on_cancel": [
      { "cmd": "SCENE_EVENT", "kind": "quit" }
    ]
  }
}
```

### 2. Main Menu Scene
```json
{
  "id": "menu",
  "name": "Main Menu",
  "kind": "menu",
  "hooks": {
    "on_enter": [
      { "cmd": "OPEN_WINDOW", "windowId": "menu_left_panel" },
      { "cmd": "SET_LIST", "windowId": "menu_left_panel", "listId": "menu_options" },
      { "cmd": "SET_CURSOR", "windowId": "menu_left_panel", "index": 1 },
      { "cmd": "OPEN_WINDOW", "windowId": "menu_right_panel" },
      { "cmd": "SET_LIST", "windowId": "menu_right_panel", "listId": "party" },
      { "cmd": "OPEN_WINDOW", "windowId": "menu_info_panel" }
    ],
    "on_select": [
      { "cmd": "IF", "condition": "v.opt == 1", "then": [{ "cmd": "SCENE_EVENT", "kind": "goto", "scene": "items" }] },
      { "cmd": "IF", "condition": "v.opt == 2", "then": [{ "cmd": "SCENE_EVENT", "kind": "goto", "scene": "status" }] },
      { "cmd": "IF", "condition": "v.opt == 3", "then": [{ "cmd": "SCENE_EVENT", "kind": "goto", "scene": "equip" }] }
    ],
    "on_cancel": [{ "cmd": "SCENE_EVENT", "kind": "pop" }]
  }
}
```

### 3. Items Scene (merge with use_target)
### 4. Status Scene

## Phase 2: Engine Integration (`main.lua`)

### Key Changes:
1. **`love.draw()`** — Before falling back to legacy `renderer.drawTitle()`, call `scene_host.runHook("on_draw", ctx)` for the scene. If the hook emits window events, the renderer should draw the declared windows.
2. **`handleKeyPressed()`** — The existing `scene_host.keypressed()` already runs hooks (on_select, on_cancel, etc.) so navigation via hooks works. Legacy code acts as fallback when hooks return false.
3. **Scene stack** — The `menuSubScene` variable in main.lua needs to be reconciled with scene_host's scene stack for sub-navigation (items_list, party_select, status_detail, etc.).

### Sub-scene Mapping:

Legacy `menuSubScene` values become scene host pushes:

| Legacy `menuSubScene` | Scene entity |
|---|---|
| `"main"` | `menu` (root) |
| `"items_list"` / `"use_target"` | `items` |
| `"party_select"` | `menu` (before selecting sub-action) |
| `"status_detail"` | `status` |
| `"equip_passive"` | `equip` |
| `"select_passive"` | `equip_select` |

## Phase 3: UI Fixes (`presentation/renderer.lua`)

### 3a. Items Menu Spacing & Height
- **File:** `renderer.lua` lines 911-948
- **Current issue:** Items are drawn with `drawCount * 11` pixel spacing which may not use the full panel height.
- **Fix:** Calculate available height from the right panel dimensions and distribute items evenly. Ensure the list extends to the bottom of the panel.

### 3b. Equip Menu Item Icons
- **File:** `renderer.lua` `drawSelectEquipMenu()` (lines 1171-1215)
- **Current issue:** Equipment items in the selection list (`drawSelectEquipMenu`) don't show icons.
- **Fix:** Add `ui.drawIcon(item.icon, ...)` call before each item name, similar to how `drawMainMenu` does it for consumables (line 934).

### 3c. Status Exp/Level Display
- **File:** `renderer.lua` `drawStatusDetail()` (lines 963-1065)
- **Current issue:** The status screen shows Level in the header (line 985) but doesn't show Experience/XP progress.
- **Fix:** Add lines showing `EXP: current / nextLevel` and an XP progress bar below the HP bar section.

## Implementation Order

1. **UI fixes first** (Phase 3) — These are independent, low-risk, and don't affect the golden log comparison for the conversion.
2. **Scene definitions** (Phase 1) — Add the data entries with hooks.
3. **Engine integration** (Phase 2) — Wire up main.lua to route through hooks.
4. **Golden log verification** — Run `love . validate golden-ui` before and after to confirm byte-identical output.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| String scene IDs (`"title"`, `"menu"`) conflict with existing numeric IDs | Use distinct string IDs; the loader's `getSceneData` already supports string matching |
| Sub-scene navigation (items_list -> use_target) is complex | Keep legacy menuSubScene logic alongside hooks; hooks handle the transitions, legacy handles drawing |
| Golden log divergence | Run golden-ui comparison after each sub-task |
