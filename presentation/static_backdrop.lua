-- Cover-fit static scene image used by title/cinematic window scenes.
local cache = {}
local backdrop = {}

function backdrop.draw(path)
    if not path or path == "" then return false end
    local image = cache[path]
    if not image then
        if not love.filesystem.getInfo(path) then error("scene backdrop not found: " .. path, 0) end
        image = love.graphics.newImage(path)
        image:setFilter("nearest", "nearest")
        cache[path] = image
    end
    -- getDimensions() reports the desktop window even while frame_renderer is
    -- drawing into the native game canvas. Fit against the active target or a
    -- high-resolution image is scaled for the window and massively cropped.
    local canvas = love.graphics.getCanvas()
    local sw, sh
    if canvas then sw, sh = canvas:getDimensions()
    else sw, sh = love.graphics.getDimensions() end
    local scale = math.max(sw / image:getWidth(), sh / image:getHeight())
    local w, h = image:getWidth() * scale, image:getHeight() * scale
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, (sw - w) / 2, (sh - h) / 2, 0, scale, scale)
    return true
end

return backdrop
