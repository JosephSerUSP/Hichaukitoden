-- Shared small battler sheets (assets/smallBattlers) AND the shared
-- damage-feedback animation state (flash/shake/dead), used by BOTH the
-- battle/map HUD (renderer.lua's party grid, summoner status) and the
-- generic window renderer's party-shaped list rows. One cache, one clock,
-- one flash/shake state table — so a party member's status cell looks and
-- behaves identically no matter where it's drawn (owner direction
-- 11.07.2026: "it should all be calling the same thing").
--
-- Sheet format: animated strip, cell count = width/height (default 24x24).
-- Filenames may carry [key=value] tokens overriding animation parameters:
--   [speed=N]  multiplier on the base frame rate (default 4)
--   [fps=N]    explicit frames per second (overrides speed)

local small_battlers = {}

local cache = {}
local animTimer = 0

local ANIM_DEFAULTS = {
    flashDuration = 0.35,
    flashColorAction = { 0.8, 1.0, 1.0 },
    flashColorDamage = { 1.0, 0.2, 0.2 },
    shakeDuration = 0.3,
    shakeAmplitude = 2,
    shakeFrequency = 30,
    deadTint = { 0.28, 0.26, 0.32, 1 },
}

local function animVal(key)
    local config = require("engine.config")
    local block = config.battle_screen and config.battle_screen.animations
    local v = block and block[key]
    if v == nil then v = ANIM_DEFAULTS[key] end
    return v
end
small_battlers.animVal = animVal

-- Per-battler-object damage feedback (flash/shake). Keyed by battler
-- identity (session objects) so battle events reach whichever draw site
-- happens to be showing that battler. Rows with no battlerRef (menu
-- scenes, where nothing triggers damage) simply never look up an entry.
local animState = {}

function small_battlers.resetAnims()
    animState = {}
end

function small_battlers.triggerDamage(battlerRef)
    if not battlerRef then return end
    animState[battlerRef] = {
        flashTimer = animVal("flashDuration"),
        shakeTimer = animVal("shakeDuration"),
    }
end

function small_battlers.updateAnims(dt)
    for ref, anim in pairs(animState) do
        anim.flashTimer = math.max(0, (anim.flashTimer or 0) - dt)
        anim.shakeTimer = math.max(0, (anim.shakeTimer or 0) - dt)
        if anim.flashTimer <= 0 and anim.shakeTimer <= 0 then
            animState[ref] = nil
        end
    end
end

-- Advance the shared idle-animation clock (renderer.update owns the dt feed).
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

-- The single shared "draw a battler's animated sprite" call: idle
-- animation, dead tint, and (when battlerRef is given and has a live
-- damage-feedback entry) flash/shake overlay on top. Used identically by
-- the battle/map HUD's party grid, the summoner status box, and any
-- scene's party-shaped list rows. Returns true when a sprite was drawn.
function small_battlers.draw(spriteKey, x, y, size, dead, battlerRef)
    local ss = small_battlers.get(spriteKey)
    if not (ss and ss.img) then return false end

    local frame = dead and 0 or small_battlers.frame(ss)
    local anim = battlerRef and animState[battlerRef]

    local drawX = x
    if not dead and anim and anim.shakeTimer and anim.shakeTimer > 0 then
        local dur = animVal("shakeDuration")
        local decay = dur > 0 and (anim.shakeTimer / dur) or 0
        drawX = x + animVal("shakeAmplitude") * decay
            * math.sin(anim.shakeTimer * animVal("shakeFrequency") * 2 * math.pi)
    end

    local quad = love.graphics.newQuad(frame * ss.cellW, 0, ss.cellW, ss.cellH, ss.img:getWidth(), ss.img:getHeight())
    local drawScale = size / ss.cellW
    if dead then
        local tint = animVal("deadTint")
        love.graphics.setColor(tint[1], tint[2], tint[3], tint[4] or 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.draw(ss.img, quad, drawX, y, 0, drawScale, drawScale)

    if not dead and anim and anim.flashTimer and anim.flashTimer > 0 then
        local dur = animVal("flashDuration")
        local col = animVal("flashColorDamage")
        love.graphics.setBlendMode("add")
        love.graphics.setColor(col[1], col[2], col[3], dur > 0 and (anim.flashTimer / dur) or 0)
        love.graphics.draw(ss.img, quad, drawX, y, 0, drawScale, drawScale)
        love.graphics.setBlendMode("alpha")
    end
    love.graphics.setColor(1, 1, 1, 1)
    return true
end

return small_battlers
