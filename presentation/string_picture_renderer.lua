-- Screen-space text objects authored by events. They behave like RPG Maker
-- pictures: numbered, replaceable, independently movable, and layerable.
local ui = require("presentation.ui")
local config = require("engine.config")

local renderer = {}
local pictures = {}

local function copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function easeOut(p)
    return 1 - (1 - p) * (1 - p)
end

local function wrapPicText(pic)
    local font = ui.loadFont(pic.font, pic.fontSize)
    if font and pic.width and pic.width > 0 then
        local _, lines = font:getWrap(pic.text, pic.width)
        pic.wrappedText = table.concat(lines, "\n")
    else
        pic.wrappedText = pic.text
    end
end

function renderer.show(spec)
    local id = assert(tonumber(spec.id), "SHOW_STRING_PICTURE requires a numeric id")
    local pic = {
        id = id,
        text = tostring(spec.text or ""),
        x = tonumber(spec.x) or 0,
        y = tonumber(spec.y) or 0,
        opacity = tonumber(spec.opacity) or 1,
        scale = tonumber(spec.scale) or 1,
        anchor = spec.anchor or "left",
        align = spec.align or "left",
        width = tonumber(spec.width) or 256,
        font = spec.font,
        fontSize = tonumber(spec.fontSize) or (ui.fontSize or 8),
        color = tonumber(spec.color) or 0,
        shadow = spec.shadow ~= false,
        frame = spec.frame == true,
        layer = spec.layer or "screen",
        blend = spec.blend or "alpha",
        eraseOnMapChange = spec.eraseOnMapChange ~= false,
        reveal = spec.reveal == true,
        revealElapsed = 0,
    }
    wrapPicText(pic)
    pictures[id] = pic
end

function renderer.move(spec)
    local pic = pictures[tonumber(spec.id)]
    if not pic then error("MOVE_STRING_PICTURE references missing id " .. tostring(spec.id), 0) end
    local target = copy(pic)
    for _, key in ipairs({ "x", "y", "opacity", "scale" }) do
        if spec[key] ~= nil then target[key] = tonumber(spec[key]) or pic[key] end
    end
    if spec.text ~= nil then
        target.text = tostring(spec.text)
        wrapPicText(target)
    end
    local duration = tonumber(spec.duration) or 0
    if duration <= 0 then
        for k, v in pairs(target) do pic[k] = v end
        pic.motion = nil
    else
        pic.motion = {
            from = copy(pic), target = target, elapsed = 0, duration = duration,
            easing = spec.easing or "out",
        }
    end
end

function renderer.erase(id, duration)
    local pic = pictures[tonumber(id)]
    if not pic then return end
    duration = tonumber(duration) or 0
    if duration <= 0 then
        pictures[tonumber(id)] = nil
    else
        renderer.move({ id = id, opacity = 0, duration = duration })
        pic.eraseAfterMove = true
    end
end

function renderer.clear()
    pictures = {}
end

function renderer.update(dt)
    local remove = {}
    for id, pic in pairs(pictures) do
        pic.revealElapsed = (pic.revealElapsed or 0) + dt
        local m = pic.motion
        if m then
            m.elapsed = math.min(m.duration, m.elapsed + dt)
            local raw = m.elapsed / m.duration
            local p = m.easing == "linear" and raw or easeOut(raw)
            for _, key in ipairs({ "x", "y", "opacity", "scale" }) do
                pic[key] = m.from[key] + (m.target[key] - m.from[key]) * p
            end
            if m.elapsed >= m.duration then
                pic.motion = nil
                if pic.eraseAfterMove then remove[#remove + 1] = id end
            end
        end
    end
    for _, id in ipairs(remove) do pictures[id] = nil end
end

local function drawPicture(pic)
    local font = ui.loadFont(pic.font, pic.fontSize)
    if not font then return end
    local palette = (config.ui and config.ui.textPalette) or {}
    local color = palette[pic.color + 1] or { 1, 1, 1, 1 }
    local width = pic.width
    local x = pic.x
    if pic.anchor == "center" then x = x - width / 2
    elseif pic.anchor == "right" then x = x - width end

    local fullText = pic.wrappedText or pic.text
    love.graphics.push("all")
    love.graphics.setBlendMode(pic.blend, "alphamultiply")
    love.graphics.translate(x, pic.y)
    love.graphics.scale(pic.scale, pic.scale)
    local shouldPad = (pic.align == "center" or pic.align == "right")
    local displayText = pic.reveal and ui.revealedText(fullText, pic.revealElapsed, shouldPad)
        or fullText
    if pic.frame then
        local _, lines = font:getWrap(fullText, width)
        ui.drawPanel(-4, -4, width + 8, #lines * font:getHeight() + 8)
    end
    local c = { color[1], color[2], color[3], (color[4] or 1) * pic.opacity }
    if pic.shadow then
        love.graphics.setFont(font)
        love.graphics.setColor(0, 0, 0, 0.8 * pic.opacity)
        love.graphics.printf(displayText, 1, 1, width, pic.align)
    end
    love.graphics.setFont(font)
    love.graphics.setColor(c)
    love.graphics.printf(displayText, 0, 0, width, pic.align)
    love.graphics.pop()
end

function renderer.draw(layer)
    local ids = {}
    for id, pic in pairs(pictures) do
        if pic.layer == layer then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do drawPicture(pictures[id]) end
end

function renderer.get(id)
    return pictures[tonumber(id)]
end

return renderer
