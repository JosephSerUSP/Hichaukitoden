-- Static illustrated location backdrop used while a map event is speaking.
-- The room itself never animates. Door fades are composited over it, but all
-- spatial zoom belongs to the raycaster side of the threshold.
local ui = require("presentation.ui")
local door_transition = require("presentation.door_transition")

local location_renderer = {}
local cache = {}
local activeKey = nil
local enteredAt = 0

local function getImage(key)
    if cache[key] ~= nil then return cache[key] or nil end
    local path = "assets/locationArt/" .. tostring(key)
    if not love.filesystem.getInfo(path) then
        cache[key] = false
        error("location art not found: " .. path, 0)
    end
    local image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")
    cache[key] = image
    return image
end

function location_renderer.draw(key)
    if not key or key == "" then return false end
    local image = getImage(key)
    if activeKey ~= key then
        activeKey = key
        enteredAt = love.timer.getTime()
    end

    local screenW = ui.toPx(ui.screenWidthTiles or 32)
    local screenH = ui.toPx(ui.screenHeightTiles or 30)
    local baseScale = math.max(screenW / image:getWidth(), screenH / image:getHeight())
    local scale = baseScale
    local drawW, drawH = image:getWidth() * scale, image:getHeight() * scale

    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, (screenW - drawW) / 2, (screenH - drawH) / 2, 0, scale, scale)
    love.graphics.pop()
    -- Black belongs to the illustrated backdrop, not the dialogue windows
    -- which scene_host draws after this function returns.
    door_transition.draw()
    return true
end

function location_renderer.clear()
    activeKey = nil
end

return location_renderer
