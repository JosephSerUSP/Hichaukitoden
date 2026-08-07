-- Optional developer diagnostics drawn in the game's fixed 256x240 canvas.
-- These values are intentionally presentation-only and disabled by default so
-- CLI previews and byte-compared golden screenshots remain deterministic.
local dev_overlay = {
    fpsEnabled = false,
    perfEnabled = false,
}

function dev_overlay.setFpsEnabled(value)
    dev_overlay.fpsEnabled = value == true
end

function dev_overlay.isFpsEnabled()
    return dev_overlay.fpsEnabled == true
end

function dev_overlay.setPerfEnabled(value)
    dev_overlay.perfEnabled = value == true
end

function dev_overlay.isPerfEnabled()
    return dev_overlay.perfEnabled == true
end

function dev_overlay.draw()
    if not dev_overlay.fpsEnabled and not dev_overlay.perfEnabled then return end

    local ui = require("presentation.ui")
    local lines = {}
    if dev_overlay.fpsEnabled then
        lines[#lines + 1] = string.format("FPS: %d", love.timer.getFPS())
    end
    if dev_overlay.perfEnabled then
        local stats = love.graphics.getStats and love.graphics.getStats() or {}
        local drawcalls = stats.drawcalls or 0
        local frameMs = (love.timer.getAverageDelta() or 0) * 1000
        local memoryKb = collectgarbage("count")
        lines[#lines + 1] = string.format("DRAW: %d", drawcalls)
        lines[#lines + 1] = string.format("FRAME: %.2fms", frameMs)
        lines[#lines + 1] = string.format("LUA: %.0fKB", memoryKb)
    end

    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, ui.measureText(line))
    end
    local x, y = 4, 4
    local lineHeight = ui.lineHeight
    local panelW = width + 8
    local panelH = #lines * lineHeight + 6

    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", x - 2, y - 2, panelW, panelH)
    for i, line in ipairs(lines) do
        ui.drawString(line, x, y + (i - 1) * lineHeight, { 1, 1, 0.7, 1 })
    end
    love.graphics.pop()
end

return dev_overlay
