# Unified Animation Plan

**Date**: 2026-07-21  
**Status**: Analysis Complete → Implementation Ready  
**Scope**: All scene/window animations + portrait slot fix

---

## 1. Current State Analysis

### 1.1 What Exists — The Good

| Component | File | Capability |
|---|---|---|
| **Animation Player** | [`presentation/animation_player.lua`](presentation/animation_player.lua) | Full battler animation engine: `tint`, `blend`, `transform`, `shake`, `screen_flash`, `gradient_map`, `particles` tracks. Per-target keyed. Easing (`easeLinear`, `easeOut`). Data-driven from `data/animations.json`. |
| **UI Anim Registry** | [`presentation/ui_anim.lua`](presentation/ui_anim.lua) | Anchor registry: `window`, `event`, `point` anchors. Bridges `data/animations.json` entries to UI surfaces. |
| **Window Open Anim** | [`presentation/window_renderer.lua:876-959`](presentation/window_renderer.lua:876) | `layout.anim.open = { duration, anchor }` — quadratic ease-out grow from anchor point. Only animation windows have. |
| **Text Reveal** | [`presentation/renderer.lua:60-95`](presentation/renderer.lua:60) | Typewriter character-by-character reveal for dialogue and battle log. Configurable via `ui.textRevealDelay`. |
| **Battle Animations** | [`presentation/renderer.lua:150-173`](presentation/renderer.lua:150) | Enemy slide-in with stagger, death effect, action/damage flash. All driven through `animation_player`. |
| **Damage Popups** | [`presentation/renderer.lua:323-364`](presentation/renderer.lua:323) | Physics-based bounce, stagger for same-location hits, fade-out. |
| **HP/MP Interpolation** | [`presentation/renderer.lua:212-234`](presentation/renderer.lua:212) | Smooth lerp toward real values (8× speed). |
| **Minimap Turn** | [`presentation/renderer.lua:438-449`](presentation/renderer.lua:438) | Interpolated angle rotation. |
| **Victory Drain** | [`presentation/renderer.lua:244-292`](presentation/renderer.lua:244) | Animated EXP gauge fill + gold drain counter. |
| **Swap Ghost** | [`presentation/window_renderer.lua:711-781`](presentation/window_renderer.lua:711) | Sine-float ghost for reserve swap. Scene-specific but well-done. |
| **Roulette Pulse** | [`presentation/window_renderer.lua:867-873`](presentation/window_renderer.lua:867) | Pulsing selection highlight on craft roulette. |
| **Target Reticle** | [`presentation/ui.lua:295-337`](presentation/ui.lua:295) | Oscillating 9-slice reticle. |
| **Wait Input Marker** | [`presentation/window_renderer.lua:1042-1052`](presentation/window_renderer.lua:1042) | Animated `UI_WaitingForInput[fps=30]` at window bottom-right. |

### 1.2 What's Missing — The Gaps

#### A. Dialog Window (Highest Priority)
The dialogue scene (`id: "dialogue"` in [`data/scenes.json:4887-4970`](data/scenes.json:4887)) uses `"draw": "windows"` with 4 windows:

| Window ID | Purpose | Issue |
|---|---|---|
| `dialogue_name` | Speaker name box (0,16 → 9.5×2) | Appears instantly, no transition |
| `dialogue_portrait` | Portrait frame (0,18 → 9.5×12) | Hidden when no portrait — **BUT** `dialogue_message` stays fixed at x=9.5, leaving a hole |
| `dialogue_message` | Message text (9.5,18 → 22.5×12) | Fixed x=9.5 regardless of portrait visibility |
| `dialogue_choices` | Choice list (same rect as message) | Overlays message; no transition between text↔choice modes |

**Problems**:
1. No enter animation (windows just appear)
2. No exit animation (dialogue ends → instant map)
3. No transition between TEXT→CHOICE modes (choice strip snaps in)
4. **Portrait slot hole**: When `dialogue_portrait` is hidden (no speaker/portrait), `dialogue_message` stays at x=9.5 leaving 76px of empty space. The message window should shift to x=0 or the portrait area should collapse gracefully.
5. No typewriter-sync'd speaker name reveal (name appears instantly while text reveals character-by-character)

#### B. Window Open/Close (Broad)
- Only `anim.open` exists in [`window_renderer.lua:876-959`](presentation/window_renderer.lua:876)
- **No `anim.close`** — comment on line 880 says: *"There is no close animation: a scene that wants one can stage it with hooks (CLOSE_WINDOW + WAIT before the pop)"*
- **No `anim.idle`** — no looping/pulsing ambient animations on panels
- **No `anim.focus`** — no transition when focus shifts between windows
- Most windows in [`data/engine.json:1800+`](data/engine.json:1800) have **no `anim` block at all**

#### C. Scene Transitions (None Exist)
- **No scene enter/exit effects**: Title→Map, Map→Menu, Menu→Status, etc. all happen as hard cuts
- Only the battle defeat finale has a screen fade (`drawDefeatFadeOverlay`), and that's baked into the battle update loop, not a generic mechanism
- Map exploration slide-transition timer exists in main.lua but only for map→map

#### D. Cross-cutting Visual Feedback
- No highlight pulse on selected list items (only static cursor sprite)
- No confirmation flash when selecting a menu option
- No number-roll animation for gold/item counts changing
- No "snap" feel when cursor wraps around a list

#### E. Legacy Battle Renderer
Three battle windows are special-cased in [`window_renderer.lua:1011-1016`](presentation/window_renderer.lua:1011) (`enemyRow`, `battleLog`, `victoryPanel` styles dispatch to `renderer.lua`). These bypass the generic window animation system entirely.

---

## 2. Design Principles

1. **Data-authored, not code-authored**: Animations should be declared in `engine.json` window layouts and `scenes.json` scene configs — never hardcoded per scene.
2. **One animation system**: Everything flows through `animation_player` or a thin window-level anim scheduler. No ad-hoc `love.timer.getTime()` math in draw functions.
3. **Backward compatible**: Existing scenes without `anim` blocks render identically. Adding animation to one scene doesn't affect others.
4. **Composable**: Window-level animations stack: a window can have `open`, `idle`, and `close` animations all playing simultaneously.
5. **The `animation_player` is the single source of truth** for timing, easing, and compositing. Window animations are a thin layer on top.

---

## 3. Implementation Plan

### Phase 1: Dialog Fixes (Foundational + Most Jarring)

#### 3.1.1 Dynamic Message Window Repositioning
**File**: [`presentation/window_renderer.lua`](presentation/window_renderer.lua)

Add a `shiftWith` layout property. When a window declares `"shiftWith": "dialogue_portrait"`, it recalculates its x position based on whether the named window is currently visible:

```
"dialogue_message": {
  "shiftWith": "dialogue_portrait",
  "shiftWhenHidden": { "x": 0, "w": 32 }
}
```

When `dialogue_portrait` is visible → `dialogue_message` stays at x=9.5, w=22.5.  
When `dialogue_portrait` is hidden → `dialogue_message` shifts to x=0, w=32.

**Implementation**: In `drawWindow()` / `drawWindowFromData()`, after resolving `visible` for all windows, compute shifts for any window with `shiftWith`. Only affects x, y, w, h — content layout follows naturally since it's already relative to the window rect.

#### 3.1.2 Dialog Enter Animation
Add `anim.open` to the dialogue windows in [`data/engine.json`](data/engine.json). The name box and message box slide up from off-screen bottom; portrait fades in.

```json
"dialogue_name": {
  "anim": { "open": { "duration": 0.18, "direction": "up", "fromOffset": 16 } }
},
"dialogue_message": {
  "anim": { "open": { "duration": 0.22, "direction": "up", "fromOffset": 24 } }
},
"dialogue_portrait": {
  "anim": { "open": { "duration": 0.25, "effect": "fade" } }
}
```

**Implementation**: Extend `openAnimRect()` in [`window_renderer.lua:931-959`](presentation/window_renderer.lua:931) to support `direction` (up/down/left/right slide) and `effect` (fade, scale, the existing "grow from anchor").

#### 3.1.3 Dialog Text↔Choice Transition
When `dialogueMode` changes from `"text"` to `"choice"`, animate the choice strip growing upward from the bottom of the message box (it already uses `fitRows: "bottom"`). This is a content-level animation — the window rect doesn't change, only which content block is visible.

**Implementation**: Track `contentTransition` state per window: when a content block's `visible` formula changes, cross-fade or slide between the old and new content for one frame cycle. Store previous content, lerp alpha.

#### 3.1.4 Dialog Exit Animation
Add `anim.close` support. When `CLOSE_WINDOW` fires, instead of immediately setting `win.open = false`, enter a closing state:

```json
"dialogue_name": {
  "anim": { "close": { "duration": 0.15, "direction": "down", "toOffset": 16 } }
}
```

**Implementation**: In `applyWindowEvent()` ([`scene_host.lua:96-101`](engine/scene_host.lua:96)), when closing, set `win.closing = true` and `win.closeStarted = love.timer.getTime()` instead of `win.open = false`. The renderer plays the close animation in reverse, then sets `win.open = false` when done. A scene that pop-pushes needs to wait for close animations — add a `scene_host.closeAllWindows()` helper that returns a Promise-like or sets `state.waitTimer`.

#### 3.1.5 Portrait Slot Layout Fix (The Empty Space)
This is the core dialog visual issue. Two approaches:

**Approach A (Recommended)**: Dynamic repositioning via `shiftWith` (3.1.1). Clean, data-authored, no special-case code. The message window shifts left to fill the portrait area when no portrait is shown.

**Approach B**: Make `dialogue_portrait` always visible but draw a placeholder when no portrait is set — a subtle vignette, a "?" silhouette, or the speaker's element icon. This requires `drawPortrait()` to handle the "no image" case.

**Recommendation**: Implement both. Approach A handles layout. Approach B adds a `portraitPlaceholder` layout key that specifies what to draw when no portrait image resolves — `"vignette"`, `"none"` (current behavior), or `"frame"` (draw just the panel border).

### Phase 2: Generalized Window Animation System

#### 3.2.1 Extend `anim` Block Schema
The current `anim.open` becomes one of several animation phases:

```json
"anim": {
  "open":   { "duration": 0.22, "effect": "slideUp", "anchor": "cellOf:party" },
  "close":  { "duration": 0.15, "effect": "slideDown" },
  "idle":   { "effect": "none" },
  "focus":  { "duration": 0.10, "effect": "pulseBorder" },
  "content": { "duration": 0.12, "effect": "crossfade" }
}
```

**Effect types**:
| Effect | Description |
|---|---|
| `slideUp` / `slideDown` / `slideLeft` / `slideRight` | Translate from/to offset |
| `grow` (existing) | Scale from anchor point |
| `fade` | Alpha 0→1 |
| `scale` | Scale 0→1 or 0.8→1 |
| `none` | Instant (default) |

#### 3.2.2 Implement `anim.close`
**Files**: [`presentation/window_renderer.lua`](presentation/window_renderer.lua), [`engine/scene_host.lua`](engine/scene_host.lua)

Steps:
1. Extend `openClocks` weak table to also track `closeClocks` and `closeStartRect` (snapshot the window's last drawn rect).
2. In `openAnimRect()`, check if `win.closing` — if so, reverse the open animation.
3. In `scene_host.applyWindowEvent()`, instead of immediately setting `win.open = false`, check if the window's layout has `anim.close`. If yes, set `win.closing = true`, record `win.closeStarted`. If no, set `win.open = false` (current behavior).
4. In `scene_host.update()`, after animations complete, finalize the close by setting `win.open = false` and removing `win.closing`.
5. For `scene_host.goto_scene()` (scene pop), wait for close animations: set `state._closingAll = true` and `state._closeTarget = id`, then in update, when all closing windows are done, execute the actual scene transition.

#### 3.2.3 Implement `anim.idle` and `anim.focus`
**`anim.idle`**: A looping animation that plays while the window is open and not closing. Useful for pulsing borders on important panels.

```json
"anim": {
  "idle": { "effect": "pulseBorder", "period": 2.0, "color": [1, 0.85, 0.5] }
}
```

**Implementation**: In `drawWindow()`, if the window has `anim.idle` and is not opening/closing, compute a time-based modulation and pass it to `ui.drawPanel()` as a tint parameter.

**`anim.focus`**: Plays when a window gains focus (via `focus_window` event). Currently focus just changes `state.focusedWindow`. Animate a brief highlight or scale bump.

### Phase 3: Scene-Level Transitions

#### 3.3.1 Scene Enter/Exit Effects
Add to [`data/scenes.json`](data/scenes.json) schema:

```json
{
  "id": "status",
  "anim": {
    "enter": { "effect": "fadeIn", "duration": 0.25 },
    "exit":  { "effect": "fadeOut", "duration": 0.15 }
  }
}
```

**Implementation**: [`engine/scene_host.lua`](engine/scene_host.lua):
- `push()` → after `on_enter`, if scene has `anim.enter`, set `state._enterAnim = { effect, started, duration }`. Renderer draws a full-screen overlay that transitions from opaque to transparent (or slides, etc.).
- `pop()` → before removing scene, if scene has `anim.exit`, play exit animation, then actual pop.
- `goto_scene()` → exit current + enter new, composited.

**Effect types for scenes**:
| Effect | Description |
|---|---|
| `fadeIn` / `fadeOut` | Black full-screen overlay, alpha transition |
| `slideInLeft` / `slideOutRight` | Canvas translate |
| `none` | Hard cut (default for all existing scenes) |

#### 3.3.2 Screen Transition Canvas
Add a [`presentation/scene_transition.lua`](presentation/scene_transition.lua) module that:
- Renders a full-screen quad with animated alpha
- Supports `fade` (color→transparent), `slide` (translate), `wipe` (scissor reveal)
- Called from `scene_host.draw()` before/after the window render pass

### Phase 4: List/Menu Interaction Polish

#### 4.1.1 Cursor Move Interpolation
When the cursor moves in a list window, interpolate the cursor sprite position instead of snapping it. The cursor already draws at `contentX - 6, rowY` — animate `rowY` toward the target position.

**Implementation**: In `drawList()`, store `cursorAnimY` per window. On cursor change, set `cursorAnimTarget = newRowY`. Each frame, lerp toward target.

#### 4.1.2 Selection Flash
When a list item is confirmed (on_select), briefly flash the row's panel highlight color (e.g. white flash for 100ms).

**Implementation**: Track `win._flashRow` and `win._flashStart`. In `drawList()`, if within flash duration, override the panel highlight color.

#### 4.1.3 Number Roll
When gold/item count changes in a visible window, animate the displayed number rolling up/down to the new value (like a slot machine reel).

### Phase 5: Legacy Battle Window Integration

#### 5.1.1 Unify battle windows with the generic system
Currently `enemyRow`, `battleLog`, `victoryPanel` are hardcoded styles in [`window_renderer.lua:1011-1016`](presentation/window_renderer.lua:1011). These should:
1. Keep their `renderer.drawXxxWindow()` draw functions (complex sprite/animation code stays in renderer.lua)
2. But participate in the window animation system: `anim.open`, `anim.close`, scene transitions

**Implementation**: The special style handlers in `drawWindowContent()` should still dispatch to `renderer.lua` for content, but the outer `drawWindow()` should apply `anim.open`/`anim.close` to the window rect BEFORE calling the content handler. For `enemyRow` style (which has no outer panel), the animation applies to a scissor rect only.

---

## 4. Portrait Slot Fix — Detailed Design

### Problem
When `v.dialoguePortrait` is `nil` or `""` (no speaker portrait), `dialogue_portrait` window's `visible` formula evaluates to `false`, so it doesn't draw. But `dialogue_message` stays at `x: 9.5` (76px from left), leaving a ~76px void on the left side of the dialog box. This is the #1 visual complaint.

### Solution: Two-Part Fix

**Part 1 — Layout Shift** (`shiftWith` in `window_renderer.lua`):

Add a new layout property `shiftWith` and `shiftWhenHidden`:

```json
"dialogue_message": {
  "rect": { "x": 9.5, "y": 18, "w": 22.5, "h": 12 },
  "shiftWith": "dialogue_portrait",
  "shiftWhenHidden": { "x": 0, "w": 32 }
}
```

Logic in `drawWindowFromData()`:
```lua
-- After visibility resolution, compute shifts
for _, winDef in ipairs(sceneData.windows) do
    local layout = resolveLayout(winDef)
    if layout.shiftWith then
        local otherVisible = isWindowVisible(layout.shiftWith, state, sceneData, ctx, env)
        if not otherVisible and layout.shiftWhenHidden then
            -- Apply shifted rect
            for k, v in pairs(layout.shiftWhenHidden) do
                layout[k] = v
            end
        end
    end
end
```

This is fully data-authored — any window pair can use it, not just dialogue.

**Part 2 — Portrait Placeholder** (`portraitPlaceholder` in `window_renderer.lua`):

When a window has a portrait/image block but no image resolves, optionally draw a placeholder:

```json
"dialogue_portrait": {
  "portraitPlaceholder": "vignette",
  "placeholderTint": [0.1, 0.1, 0.15]
}
```

Placeholder types:
- `"none"` (default) — draw nothing (current behavior)
- `"vignette"` — draw a subtle dark gradient or decorative corner ornaments
- `"frame"` — draw the window panel border but no content (shows the portrait slot exists but is empty)
- `"silhouette"` — draw a generic "?" or shadow figure

**Recommendation**: Start with `shiftWith` (Part 1) as the primary fix — it's simpler and directly solves the empty space. Add `portraitPlaceholder` later as an aesthetic option.

---

## 5. Data Changes Required

### 5.1 `data/engine.json` — Window Layout Additions

Add `anim` blocks to key windows:

```json
"dialogue_name": {
  "x": 0, "y": 16, "width": 9.5, "height": 2,
  "anim": {
    "open": { "duration": 0.18, "effect": "slideUp", "fromOffset": 16 },
    "close": { "duration": 0.12, "effect": "slideDown", "toOffset": 16 }
  }
},
"dialogue_portrait": {
  "anim": {
    "open": { "duration": 0.25, "effect": "fade" },
    "close": { "duration": 0.15, "effect": "fade" }
  }
},
"dialogue_message": {
  "shiftWith": "dialogue_portrait",
  "shiftWhenHidden": { "x": 0, "w": 32 },
  "anim": {
    "open": { "duration": 0.22, "effect": "slideUp", "fromOffset": 24 },
    "close": { "duration": 0.15, "effect": "slideDown", "toOffset": 24 }
  }
}
```

### 5.2 `data/scenes.json` — Scene-Level Animations

Add `anim` block to dialogue scene:

```json
{
  "id": "dialogue",
  "anim": {
    "enter": { "effect": "fadeIn", "duration": 0.2 },
    "exit": { "effect": "fadeOut", "duration": 0.15 }
  }
}
```

Other scenes can adopt incrementally — the default is `"none"` (hard cut, current behavior).

---

## 6. Files to Modify (Summary)

| File | Phase | Changes |
|---|---|---|
| [`presentation/window_renderer.lua`](presentation/window_renderer.lua) | 1, 2, 4 | `shiftWith` support, extended `anim` block (close/idle/focus/content), cursor interpolation, selection flash, portrait placeholder |
| [`engine/scene_host.lua`](engine/scene_host.lua) | 2, 3 | Delayed close with animation, scene enter/exit transition orchestration |
| [`presentation/scene_transition.lua`](presentation/scene_transition.lua) | 3 | **NEW** — Full-screen transition effects (fade, slide, wipe) |
| [`data/engine.json`](data/engine.json) | 1, 2 | `anim` blocks on dialogue windows and other key windows |
| [`data/scenes.json`](data/scenes.json) | 1, 3 | `anim.enter`/`anim.exit` on dialogue scene, `shiftWith` on dialogue_message |
| [`presentation/renderer.lua`](presentation/renderer.lua) | 5 | Light refactor: battle windows accept outer animation rect from generic system |
| [`main.lua`](main.lua) | 1, 3 | dialogue sync updated for new portrait/message layout, scene transition calls |

---

## 7. Implementation Order (Recommended)

| Step | Description | Risk | Est. |
|---|---|---|---|
| **1** | `shiftWith` + `shiftWhenHidden` in window_renderer | Low — additive feature | 1h |
| **2** | Dialog window `anim.open` / `anim.close` (extend openAnimRect) | Medium — touches drawWindow flow | 2h |
| **3** | Portrait slot fix: apply `shiftWith` to `dialogue_message` + add `anim.open` to dialogue windows in engine.json | Low — data-only | 0.5h |
| **4** | `anim.close` in scene_host (delayed close + scene transition wait) | Medium — orchestrates across modules | 2h |
| **5** | Scene-level enter/exit transitions (new module) | Medium — new file, integration points | 2.5h |
| **6** | List cursor interpolation | Low — isolated in drawList | 1h |
| **7** | Selection flash on confirm | Low — isolated in drawList | 0.5h |
| **8** | Battle window integration | Low — adapter pattern | 1h |
| **9** | `anim.idle` / `anim.focus` / `portraitPlaceholder` | Low — additive, no breakage | 2h |

**Total**: ~12.5h across 9 steps. Steps 1-4 deliver the dialog fix (the most jarring issue). Steps 1-5 deliver unified scene transitions. Steps 6-9 are polish.

---

## 8. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Close animation timing breaks scene transitions (pop happens before close anim finishes) | `scene_host` waits for `state._closingAll` before executing transition. Graceful timeout (max 2× duration) prevents soft-locks. |
| `shiftWith` interacts badly with `fitRows` or `anim.open` anchor repositioning | Compute shifts BEFORE animation rect resolution. Shift rect is the "resting" rect; animation grows toward it. |
| Adding animation to one window changes layout of others unexpectedly | `shiftWith` is explicit and opt-in. No window's position changes unless another window references it. |
| Scene transitions conflict with `backdrop: "map"` scenes | Transition overlay draws on top of everything, including backdrop. No conflict. |
| Golden tests break due to animation timing variance | Golden harness already disables `textRevealDelay`; extend pattern to disable `anim` blocks in golden mode via a `ui.animationEnabled` toggle. |
