-- Numbered screen-space image objects authored by events. This is the bitmap
-- counterpart to string pictures: cutscenes can crossfade and gently move
-- generated plates without giving a common event a bespoke presentation path.
local putil = require("presentation.util")

local renderer = {}
local pictures = {}
local cache = {}

local function load(path)
    local image = cache[path]
    if image then return image end
    if not love.filesystem.getInfo(path) then
        error("SHOW_IMAGE_PICTURE image not found: " .. tostring(path), 0)
    end
    image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")
    cache[path] = image
    return image
end

function renderer.show(spec)
    local id = assert(tonumber(spec.id), "SHOW_IMAGE_PICTURE requires a numeric id")
    local path = assert(spec.path, "SHOW_IMAGE_PICTURE requires path")
    load(path)
    pictures[id] = {
        id = id,
        path = path,
        x = tonumber(spec.x) or 0,
        y = tonumber(spec.y) or 0,
        opacity = tonumber(spec.opacity) or 1,
        scale = tonumber(spec.scale) or 1,
        rotation = tonumber(spec.rotation) or 0,
        anchor = spec.anchor or "left",
        layer = spec.layer or "screen",
        blend = spec.blend or "alpha",
        eraseOnMapChange = spec.eraseOnMapChange ~= false,
    }
end

function renderer.move(spec)
    local pic = pictures[tonumber(spec.id)]
    if not pic then
        error("MOVE_IMAGE_PICTURE references missing id " .. tostring(spec.id), 0)
    end
    local target = putil.copy(pic)
    for _, key in ipairs({ "x", "y", "opacity", "scale", "rotation" }) do
        if spec[key] ~= nil then target[key] = tonumber(spec[key]) or pic[key] end
    end
    local duration = tonumber(spec.duration) or 0
    if duration <= 0 then
        for k, v in pairs(target) do pic[k] = v end
        pic.motion = nil
    else
        pic.motion = {
            from = putil.copy(pic), target = target, elapsed = 0, duration = duration,
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
        local m = pic.motion
        if m then
            m.elapsed = math.min(m.duration, m.elapsed + dt)
            local raw = m.elapsed / m.duration
            local p = m.easing == "linear" and raw or putil.easeOut(raw)
            for _, key in ipairs({ "x", "y", "opacity", "scale", "rotation" }) do
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
    local image = load(pic.path)
    local ox, oy = 0, 0
    if pic.anchor == "center" then
        ox, oy = image:getWidth() / 2, image:getHeight() / 2
    elseif pic.anchor == "right" then
        ox = image:getWidth()
    end
    love.graphics.push("all")
    love.graphics.setBlendMode(pic.blend, "alphamultiply")
    love.graphics.setColor(1, 1, 1, pic.opacity)
    love.graphics.draw(image, pic.x, pic.y, pic.rotation, pic.scale, pic.scale, ox, oy)
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
