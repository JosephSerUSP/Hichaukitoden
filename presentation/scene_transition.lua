-- Full-screen scene enter/exit transition manager.
-- Handles fadeIn, fadeOut, and custom overlays for scene switches.

local ui = require("presentation.ui")

local scene_transition = {}

local activeTransition = nil

-- Start a transition effect.
-- kind: "enter" | "exit"
-- effect: "fade" | "fadeIn" | "fadeOut" | "none"
-- duration: duration in seconds (default 0.2)
-- color: optional {r, g, b} color for fade (default {0, 0, 0})
function scene_transition.start(kind, effect, duration, color)
    if not effect or effect == "none" then
        activeTransition = nil
        return
    end

    local dur = tonumber(duration) or 0.2
    if dur <= 0 then
        activeTransition = nil
        return
    end

    activeTransition = {
        kind = kind or "enter",
        effect = effect,
        duration = dur,
        elapsed = 0,
        color = color or { 0, 0, 0 },
    }
end

function scene_transition.update(dt)
    if not activeTransition then return end
    activeTransition.elapsed = activeTransition.elapsed + dt
    if activeTransition.elapsed >= activeTransition.duration then
        activeTransition = nil
    end
end

function scene_transition.isActive()
    return activeTransition ~= nil
end

function scene_transition.draw()
    if not activeTransition then return end

    local t = activeTransition
    local p = math.min(1, t.elapsed / t.duration)
    local ease = 1 - (1 - p) * (1 - p) -- ease out

    local alpha = 0
    if t.effect == "fadeIn" or (t.kind == "enter" and t.effect == "fade") then
        -- Entering scene: alpha starts at 1 (opaque) and fades to 0 (transparent)
        alpha = 1 - ease
    elseif t.effect == "fadeOut" or (t.kind == "exit" and t.effect == "fade") then
        -- Exiting scene: alpha starts at 0 and goes to 1
        alpha = ease
    end

    if alpha > 0 then
        love.graphics.push("all")
        love.graphics.setColor(t.color[1], t.color[2], t.color[3], alpha)
        local screenW = ui.toPx(ui.screenWidthTiles or 32)
        local screenH = ui.toPx(ui.screenHeightTiles or 30)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
        love.graphics.pop()
    end
end

function scene_transition.clear()
    activeTransition = nil
end

return scene_transition
