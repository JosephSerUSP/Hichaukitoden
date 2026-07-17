-- PLAY_ANIM's anchor registry (overhaul-7 follow-up, owner-directed
-- 17.07.2026): scene hooks and event scripts play data/animations.json
-- entries on UI anchors and map events, not just battlers.
--
-- This module only tracks WHAT is playing WHERE; the actual timing lives in
-- presentation/animation_player.lua (one instance per target table, pruned
-- automatically when the entry's duration elapses), and drawing lives with
-- whoever owns the surface:
--   * window/point anchors  -> window_renderer.lua draws them after its
--     windows (it owns resolveAnchor and the per-frame layout env)
--   * map event anchors     -> viewport_3d.lua applies sprite tracks to the
--     event's billboard and draws its particles at the projected position
--
-- Anchor specs (plain data, resolved at DRAW time so camera movement and
-- window animation stay honest):
--   { kind = "window", windowId = "ritual_confirm" }   window rect center
--   { kind = "window", windowId = "cellOf:party" }     selected partyGrid cell
--   { kind = "event",  event = <event table> }         map event (billboard)
--   { kind = "point",  x = 128, y = 120 }              raw pixels (256x240)

local animation_player = require("presentation.animation_player")

local ui_anim = {}

-- List of { target, animId, anchor }. For event anchors the target IS the
-- event table (so sprite tracks apply to its billboard); for window/point
-- anchors it's a fresh table (identity only — nothing sprite-bound to tint).
local active = {}

function ui_anim.play(animId, anchor)
    local target
    if anchor and anchor.kind == "event" and anchor.event then
        target = anchor.event
    else
        target = { uiAnim = animId }
    end
    animation_player.play(animId, target)
    table.insert(active, { target = target, animId = animId, anchor = anchor or { kind = "point" } })
    return target
end

-- Prune entries whose animation finished (the player removes instances
-- itself; we just drop our anchor bookkeeping). Called from both draw
-- surfaces — cheap and idempotent.
function ui_anim.prune()
    for i = #active, 1, -1 do
        local inst = active[i]
        if not animation_player.isPlaying(inst.target, inst.animId) then
            table.remove(active, i)
        end
    end
end

-- Snapshot of live instances for a draw surface. kind filters ("event" for
-- the viewport, anything else for the window overlay); nil returns all.
function ui_anim.instances(kind)
    local out = {}
    for _, inst in ipairs(active) do
        local isEvent = inst.anchor.kind == "event"
        if kind == nil or (kind == "event") == isEvent then
            table.insert(out, inst)
        end
    end
    return out
end

-- The golden/preview harnesses re-enter scenes repeatedly; leftover anchors
-- from a previous scene must not draw over the next one.
function ui_anim.reset()
    active = {}
end

return ui_anim
