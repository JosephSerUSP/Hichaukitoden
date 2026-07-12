-- Shared small battler sheets (assets/smallBattlers), used by the
-- battle/HUD renderer's sprite cells AND the generic window renderer's
-- sprite list rows. One cache, one animation clock — extracted from
-- renderer.lua so the window vocabulary could grow sprite rows without
-- duplicating the loader (owner direction 11.07.2026).
--
-- Sheet format: animated strip, cell count = width/height (default 24x24).
-- Filenames may carry [key=value] tokens overriding animation parameters:
--   [speed=N]  multiplier on the base frame rate (default 4)
--   [fps=N]    explicit frames per second (overrides speed)

local small_battlers = {}

local cache = {}
local animTimer = 0

-- Advance the shared animation clock (renderer.update owns the dt feed).
function small_battlers.update(dt)
    animTimer = animTimer + dt
end

function small_battlers.get(spriteKey)
    if not spriteKey or spriteKey == "" then return nil end
    local key = tostring(spriteKey)
    if cache[key] ~= nil then return cache[key] or nil end

    -- Parse [key=value] tokens from the key (e.g. "Summoner2[speed=2]")
    local overrides = {}
    local fileKey = key:gsub("%[([^=]+)=([^%]]+)%]", function(k, v)
        overrides[k] = tonumber(v) or v
        return ""
    end)
    fileKey = fileKey:gsub("^%s*(.-)%s*$", "%1")

    local paths = {
        "assets/smallBattlers/" .. fileKey:sub(1, 1):upper() .. fileKey:sub(2):lower() .. ".png",
        "assets/smallBattlers/" .. fileKey .. ".png",
        "assets/smallBattlers/" .. fileKey:lower() .. ".png",
        "assets/sprites/" .. fileKey .. ".png",
    }
    for _, p in ipairs(paths) do
        if love.filesystem.getInfo(p) then
            local img = love.graphics.newImage(p)
            img:setFilter("nearest", "nearest")
            local w = img:getWidth()
            local h = img:getHeight()
            local cellH = h
            local cellW = math.min(w, cellH) -- default cell is square (24x24)
            local numFrames = math.floor(w / cellW)
            if numFrames < 1 then numFrames = 1 end
            local result = {
                img = img,
                cellW = cellW,
                cellH = cellH,
                numFrames = numFrames,
                speed = overrides.speed,
                fps = overrides.fps,
            }
            cache[key] = result
            return result
        end
    end
    cache[key] = false
    return nil
end

-- Current animation frame for a sheet, respecting per-sprite overrides.
function small_battlers.frame(ss)
    if not ss then return 0 end
    local rate = ss.fps or (ss.speed and 4 * ss.speed or 4)
    return math.floor(animTimer * rate) % ss.numFrames
end

-- Plain animated draw at (x, y) scaled to `size` px. Returns true when a
-- sprite was drawn. Battle-specific presentation (flash/shake/dead tint)
-- stays in renderer.drawSmallSpriteCell, which builds on these primitives.
function small_battlers.draw(spriteKey, x, y, size, frameOverride)
    local ss = small_battlers.get(spriteKey)
    if not (ss and ss.img) then return false end
    local frame = frameOverride or small_battlers.frame(ss)
    local quad = love.graphics.newQuad(frame * ss.cellW, 0, ss.cellW, ss.cellH, ss.img:getWidth(), ss.img:getHeight())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(ss.img, quad, x, y, 0, size / ss.cellW, size / ss.cellW)
    return true
end

return small_battlers
