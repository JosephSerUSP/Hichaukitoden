# Input & Movement UX Fix Plan

## Problem Summary

1. **No key repeat** — holding a directional key does nothing; every action requires a fresh tap. Affects both map movement and menu scrolling.

2. **Transition-ignored movement** — during the 150ms turn/move animation, the player can still move, which instantly snaps the grid position/direction while the visual camera is mid-animation, creating a disorienting mismatch.

3. **Silent wall bump** — attempting to move into an impassable tile returns `false` with zero feedback; no visual or audio cue.

---

## Fix 1: Update-Driven Auto-Repeat (Not OS Key Repeat)

### Why not OS key repeat?

OS key repeat has two problems for games:
- **Initial delay** is too long (~500ms on Windows) — feels sluggish in menus
- **Repeat rate** is too fast (~30ms between repeats) — cursor zips through lists
- **Inconsistent** across operating systems and user settings
- **Bypasses the input mapper** — raw key names, not logical SNES buttons

### Approach: Held-key tracking in `love.update`

Instead of whitelisting repeats in `love.keypressed`, we keep the blanket `if repeat_event then return end` and build our own auto-repeat in the update loop:

### Files to modify:

#### Fix 1a: Track held keys via `love.keyreleased` 
**[`main.lua:3152`](main.lua:3152)** — Add key release handler

```lua
-- Per-key held state for auto-repeat
local heldKeys = {}  -- key → { holdTime = seconds, lastFire = fireCount }

function love.keyreleased(key)
    heldKeys[key] = nil
end
```

#### Fix 1b: Auto-repeat in `love.update`
**[`main.lua:2433`](main.lua:2433)** — After transitionTimer/bumpTimer decay

```lua
-- ── Auto-repeat for held directional keys ──────────────────────────────
local REPEAT_DIR_KEYS = { "up", "down", "left", "right",
                          "w", "a", "s", "d", "q", "e" }
local REPEAT_INITIAL  = 0.4   -- seconds before auto-repeat starts
local REPEAT_INTERVAL = 0.12  -- seconds between auto-repeat fires (~8/sec)

for _, key in ipairs(REPEAT_DIR_KEYS) do
    if love.keyboard.isDown(key) then
        local state = heldKeys[key]
        if not state then
            heldKeys[key] = { holdTime = 0, lastFire = 0 }
            state = heldKeys[key]
        end
        state.holdTime = state.holdTime + dt
        if state.holdTime >= REPEAT_INITIAL then
            local elapsed = state.holdTime - REPEAT_INITIAL
            local fireCount = math.floor(elapsed / REPEAT_INTERVAL)
            if fireCount > state.lastFire then
                state.lastFire = fireCount
                -- Route through input mapper (scene_host.keypressed) first,
                -- then fall back to legacy handleKeyPressed
                local ctx = { session = activeSession, loader = loader, party = activeSession.party or {} }
                if not scene_host.keypressed(key, ctx) then
                    handleKeyPressed(key)
                end
            end
        end
    else
        heldKeys[key] = nil
    end
end
```

**Why this works:**

| Scenario | First press | Hold 400ms | Hold 1s |
|----------|------------|------------|---------|
| Menu scroll (`up`/`down`) | Immediate via `love.keypressed` | Repeat starts at 400ms | Repeats every 120ms |
| Map move (`up`/`w`) | Immediate via `love.keypressed` | Repeat fires, but transitionTimer gates | ~150ms per step (transitionTimer) |

- Routes through `scene_host.keypressed` which uses `input_map.resolveHook()` → respects rebindable controls
- No OS dependency — works identically on all platforms
- Initial delay (400ms) is shorter than OS default (500ms) → feels more responsive
- Repeat interval (120ms) is slower than OS default (30ms) → controlled scrolling

---

## Fix 2: Block Movement During Transition Animation

### Target: [`main.lua:2946`](main.lua:2946) (map movement block)

**Current behavior:**
The map movement code processes movement/turn regardless of `session.transitionTimer`. The timer only affects the **visual** camera interpolation in `viewport_3d.draw()`. So the player can press forward while the turn animation plays — the position updates instantly while the camera is mid-animation.

**Change — add a guard at the top of the map movement block:**

```lua
elseif scene_host.getCurrent() == "map" then
    -- Block movement while transition animation is playing
    if activeSession.transitionTimer and activeSession.transitionTimer > 0 then
        return
    end
    -- ... rest of movement code (strafe guard, movement, etc.) ...
```

**Effect:**
- During a turn (150ms): `transitionTimer > 0` → all movement/turn inputs are ignored
- During a step (150ms): same gate → cannot queue the next step until the camera settles
- Player holds a key → auto-repeat fires every 120ms → transitionTimer blocks most → only fires when timer = 0 → natural ~6.6 tiles/second pace
- Completely eliminates the disorienting "move while camera is mid-turn" bug

---

## Fix 3: Bump Animation on Wall Collision

### 3a. Trigger bump on failed move
**[`main.lua:2957-2987`](main.lua:2957-2987)** — Wrap each movement call

```lua
-- Forward
moved = exploration.moveForward(activeSession)
if not moved then activeSession.bumpTimer = 0.12 end

-- Backward
moved = exploration.moveBackward(activeSession)
if not moved then activeSession.bumpTimer = 0.12 end

-- Strafe left
moved = exploration.strafeLeft(activeSession)
if not moved then activeSession.bumpTimer = 0.12 end

-- Strafe right
moved = exploration.strafeRight(activeSession)
if not moved then activeSession.bumpTimer = 0.12 end
```

**Not** for turns — turns always succeed.

### 3b. Decay bump timer
**[`main.lua:2429-2431`](main.lua:2429-2431)** — Add to existing timer decay block

```lua
if activeSession then
    if activeSession.transitionTimer and activeSession.transitionTimer > 0 then
        activeSession.transitionTimer = activeSession.transitionTimer - dt
    end
    if activeSession.bumpTimer and activeSession.bumpTimer > 0 then
        activeSession.bumpTimer = activeSession.bumpTimer - dt
    end
end
```

### 3c. Apply camera shake in viewport
**[`presentation/viewport_3d.lua:500-508`](presentation/viewport_3d.lua:500-508)** — After camera position, before wall loop

```lua
-- ── Bump shake ─────────────────────────────────────────────────────────
if session.bumpTimer and session.bumpTimer > 0 then
    local intensity = session.bumpTimer / 0.12   -- 1.0 → 0.0 over duration
    local phase     = session.bumpTimer * 60      -- ~60 rad/s
    local offset    = math.sin(phase) * intensity * 0.15  -- max 0.15 tiles
    -- Shake perpendicular to facing direction
    local perpX = math.cos(cAngle + math.pi / 2)
    local perpY = math.sin(cAngle + math.pi / 2)
    cx = cx + perpX * offset
    cy = cy + perpY * offset
end
```

**Visual result:**
- Walking into a wall → view shakes horizontally (left/right relative to camera) for 120ms
- Oscillation at ~10Hz with linear decay → quick jolt, no seasickness
- 0.15 tile max ≈ 1.2px on 256px viewport → subtle but noticeable

---

## Summary of All Files Changed

| # | File | What Changes |
|---|------|-------------|
| 1a | [`main.lua:3152`](main.lua:3152) | Add `love.keyreleased()` handler (3 lines) |
| 1b | [`main.lua:2433+`](main.lua:2433+) | Add auto-repeat loop in `love.update()` (~30 lines) |
| 2 | [`main.lua:2946-2948`](main.lua:2946-2948) | Add `transitionTimer > 0` guard (3 lines) |
| 3a | [`main.lua:2957-2987`](main.lua:2957-2987) | Set `bumpTimer` on failed move (4× 2-line additions) |
| 3b | [`main.lua:2429-2431`](main.lua:2429-2431) | Decay `bumpTimer` in update (3 lines) |
| 3c | [`presentation/viewport_3d.lua:500-508`](presentation/viewport_3d.lua:500-508) | Apply camera shake from bumpTimer (~12 lines) |

**Total: ~55 lines of new code, zero rewrites, zero new assets.**

---

## Discussion Points

1. **Repeat rate tuning**: `REPEAT_INITIAL = 0.4` and `REPEAT_INTERVAL = 0.12` are starting values. If menu scrolling feels too fast, bump interval to 0.15 (6.6/s). If initial delay feels sluggish, drop to 0.3.

2. **Bump intensity**: The 0.15 tile offset at peak is ~1.2px. If too subtle, increase to 0.25 (~2px). If too strong, drop to 0.08.

3. **Input mapper integration**: The auto-repeat fires through `scene_host.keypressed()` which calls `input_map.resolveHook()` internally. This means rebindable controls work automatically with the repeat system — no separate mapping needed.

4. **Bump sound hook**: The `bumpTimer` trigger point is the natural place to add `love.audio.play()` later. No visual changes needed.
