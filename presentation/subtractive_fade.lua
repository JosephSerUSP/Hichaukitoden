-- PSX-style fade primitive. LÖVE's subtract blend performs the same useful
-- fixed-function operation as a bright semitransparent fullscreen primitive:
-- destination.rgb = max(destination.rgb - source.rgb, 0).
--
-- Dark channels therefore reach zero first instead of every pixel being
-- hidden beneath a uniform alpha-black sheet. Callers own choreography and
-- scope by invoking this while their world/backdrop layer is still active.
local ui = require("presentation.ui")

local subtractive_fade = {}

function subtractive_fade.draw(amount)
    amount = math.max(0, math.min(1, tonumber(amount) or 0))
    if amount <= 0 then return end

    love.graphics.push("all")
    love.graphics.setBlendMode("subtract", "alphamultiply")
    love.graphics.setColor(1, 1, 1, amount)
    love.graphics.rectangle("fill", 0, 0,
        ui.toPx(ui.screenWidthTiles or 32),
        ui.toPx(ui.screenHeightTiles or 30))
    love.graphics.pop()
end

return subtractive_fade
