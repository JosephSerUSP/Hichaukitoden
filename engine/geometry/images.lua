-- Pixel-level reading of an image-authored geometry asset.
--
-- Uses love.image only, never love.graphics, so validation can read masks and
-- dimensions in a headless run. ImageData is cached per path: several assets
-- routinely share one atlas, and a validate pass would otherwise decode the
-- same PNG many times.
local images = {}
local buildProfiler = require("engine.map_build_profiler")

local cache = {}

function images.data(path)
    if cache[path] then
        buildProfiler.cache("source.imageData", true)
        return cache[path]
    end
    buildProfiler.cache("source.imageData", false)
    if not love.filesystem.getInfo(path) then
        error("geometry image missing: " .. path, 0)
    end
    local decodeSpan = buildProfiler.span("source.imageDecode", "cpu")
    local ok, data = pcall(love.image.newImageData, path)
    decodeSpan()
    if not ok then error("geometry image unreadable: " .. path, 0) end
    cache[path] = data
    return data
end

function images.forget(path)
    if path then cache[path] = nil else cache = {} end
end

-- Nearest sample in normalized coordinates. u runs left to right, v runs top to
-- bottom in image space, matching how the art is painted.
function images.sample(data, u, v)
    local width, height = data:getWidth(), data:getHeight()
    local x = math.max(0, math.min(width - 1, math.floor(u * (width - 1) + 0.5)))
    local y = math.max(0, math.min(height - 1, math.floor(v * (height - 1) + 0.5)))
    return data:getPixel(x, y)
end

-- The height PNG's grayscale channel. Authored art is grayscale, so the red
-- channel is the value; a non-grayscale height pixel is an authoring mistake
-- that images.checkGrayscale reports rather than silently averaging away.
function images.heightValue(data, u, v)
    local r, _, _, a = images.sample(data, u, v)
    return r, a
end

-- Signed plane displacement in -1..1: 128 is the neutral plane, darker recedes
-- and lighter projects (design doc, height conventions by topology).
function images.signedDisplacement(data, u, v)
    local value, alpha = images.heightValue(data, u, v)
    return (value - 128 / 255) * 2, alpha
end

function images.dimensionsMatch(a, b)
    return a:getWidth() == b:getWidth() and a:getHeight() == b:getHeight()
end

-- Mirror image-authored geometry in the same direction as a mirrored albedo
-- UV. Wall faces on opposite sides of a cell reverse U so architectural marks
-- read consistently from the corridor; their displacement field must undergo
-- the identical transform or relief and paint register on only two directions.
function images.flipX(data)
    local width, height = data:getWidth(), data:getHeight()
    local flipped = love.image.newImageData(width, height)
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            flipped:setPixel(x, y, data:getPixel(width - 1 - x, y))
        end
    end
    return flipped
end

-- Warning-level check: a height map whose RGB channels disagree was probably
-- painted in colour by mistake, and only its red channel would be read.
function images.checkGrayscale(data, limit)
    local width, height = data:getWidth(), data:getHeight()
    local step = math.max(1, math.floor(math.min(width, height) / 16))
    local offenders = 0
    for y = 0, height - 1, step do
        for x = 0, width - 1, step do
            local r, g, b = data:getPixel(x, y)
            if math.abs(r - g) > 1 / 255 or math.abs(r - b) > 1 / 255 then
                offenders = offenders + 1
                if offenders > (limit or 0) then return false end
            end
        end
    end
    return true
end

return images
