-- PSX-style fade primitive. LÖVE's subtract blend performs the same useful
-- fixed-function operation as a bright semitransparent fullscreen primitive:
-- destination.rgb = max(destination.rgb - source.rgb, 0).
--
-- Dark channels therefore reach zero first instead of every pixel being
-- hidden beneath a uniform alpha-black sheet. Callers own choreography and
-- scope by invoking this while their world/backdrop layer is still active.
local ui = require("presentation.ui")
local util = require("presentation.util")

local subtractive_fade = {}

-- A panel drawn immediately after a modal fade is, structurally, a modal
-- rather than a transparent menu shell. Keep that rule beside the fade
-- primitive so every current and future dimming modal gets the same solid
-- button windowskin without each scene remembering the convention.
--
-- `window_renderer` draws in the exact order fade -> modal outer panel, so a
-- one-shot role is sufficient. World transitions pass `marksModal = false`
-- because they darken the frame without owning a panel afterwards.
local modalPanelPending = false
local originalDrawPanel = ui.drawPanel

if not ui._subtractiveModalPanelWrapped then
    ui._subtractiveModalPanelWrapped = true
    ui.drawPanel = function(x, y, w, h, title, role)
        if modalPanelPending then
            modalPanelPending = false
            role = role or "button"
        end
        return originalDrawPanel(x, y, w, h, title, role)
    end
end

function subtractive_fade.draw(amount, marksModal)
    amount = util.clamp01(tonumber(amount) or 0)
    if amount <= 0 then return end

    if marksModal ~= false then
        modalPanelPending = true
    end

    love.graphics.push("all")
    love.graphics.setBlendMode("subtract", "alphamultiply")
    love.graphics.setColor(1, 1, 1, amount)
    love.graphics.rectangle("fill", 0, 0,
        ui.toPx(ui.screenWidthTiles or 32),
        ui.toPx(ui.screenHeightTiles or 30))
    love.graphics.pop()
end

return subtractive_fade
