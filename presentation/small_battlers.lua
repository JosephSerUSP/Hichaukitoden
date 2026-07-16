-- Shared small battler sheets (assets/smallBattlers) AND the shared
-- damage-feedback animation state (flash/shake/dead), used by BOTH the
-- battle/map HUD (renderer.lua's party grid, summoner status) and the
-- generic window renderer's party-shaped list rows. One cache, one clock,
-- one flash/shake state table — so a party member's status cell looks and
-- behaves identically no matter where it's drawn (owner direction
-- 11.07.2026: "it should all be calling the same thing").
--
-- overhaul-7 A1: damage-feedback animation (flash, shake, tint) is owned
-- by presentation/animation_player.lua using data/animations.json entries.
-- This module still owns the sprite cache, idle animation clock, and the
-- dead-tint constant for game-state dead display (separate from the death
-- animation, which plays on enemy portraits).
--
-- Sheet format: animated strip, cell count = width/height (default 24x24).
-- Filenames may carry [key=value] tokens overriding animation parameters:
--   [speed=N]  multiplier on the base frame rate (default 4)
--   [fps=N]    explicit frames per second (overrides speed)

local small_battlers = {}

local cache = {}
local animTimer = 0

-- Dead-tint applied when a battler's game-state is dead (not an animation —
-- this is the static visual that replaces the sprite for dead party members
-- in the grid). The death animation (system.death) handles enemy portraits.
local DEAD_TINT = { 0.28, 0.26, 0.32, 1 }

-- overhaul-7 A1: animVal and the per-battler animState flash/shake tracking
-- are deleted. Damage feedback plays via animation_player.play("system.small_damage", ref)
-- and the draw function queries the player for current tint/blend/shake.

local animation_player = require("presentation.animation_player")
local gradient_shader  = require("presentation.gradient_shader")

-- Kept for backward compat: renderer.lua still references small_battlers.animVal
-- in its enemy-flash draw path. The stub delegates to the animation player's
-- system entries for the value the renderer needs. After the renderer migration
-- is complete this stub can be removed too.
local function animVal(key)
    -- Map old animVal keys to their animation entry sources
    -- Dead tint stays as a module constant (game-state display, not animation)
    if key == "deadTint" then return DEAD_TINT end
    if key == "flashDuration" then
        local entry = animation_player.getEntry("system.damage_flash")
        return entry and entry.duration / 1000 or 0.35
    end
    if key == "flashColorAction" then
        local entry = animation_player.getEntry("system.action_flash")
        if entry and entry.tracks then
            for _, t in ipairs(entry.tracks) do
                if t.type == "tint" then return t.color or { 0.8, 1.0, 1.0 } end
            end
        end
        return { 0.8, 1.0, 1.0 }
    end
    if key == "flashColorDamage" then
        local entry = animation_player.getEntry("system.damage_flash")
        if entry and entry.tracks then
            for _, t in ipairs(entry.tracks) do
                if t.type == "tint" then return t.color or { 1.0, 0.2, 0.2 } end
            end
        end
        return { 1.0, 0.2, 0.2 }
    end
    if key == "shakeDuration" then
        local entry = animation_player.getEntry("system.small_damage")
        if entry and entry.tracks then
            for _, t in ipairs(entry.tracks) do
                if t.type == "shake" then return t.duration / 1000 or 0.3 end
            end
        end
        return 0.3
    end
    if key == "shakeAmplitude" then
        local entry = animation_player.getEntry("system.small_damage")
        if entry and entry.tracks then
            for _, t in ipairs(entry.tracks) do
                if t.type == "shake" then return t.amplitude or 2 end
            end
        end
        return 2
    end
    if key == "shakeFrequency" then
        local entry = animation_player.getEntry("system.small_damage")
        if entry and entry.tracks then
            for _, t in ipairs(entry.tracks) do
                if t.type == "shake" then return t.frequency or 30 end
            end
        end
        return 30
    end
    return nil
end
small_battlers.animVal = animVal

-- Per-battler-object damage feedback is now owned by animation_player.
-- These stubs forward to the player for backward compat during migration.
function small_battlers.resetAnims()
    animation_player.reset()
end

function small_battlers.triggerDamage(battlerRef)
    if not battlerRef then return end
    animation_player.play("system.small_damage", battlerRef)
end

function small_battlers.updateAnims(dt)
    -- Animation player handles its own update; this is called from
    -- renderer.update for backward compat. The player.update is called
    -- separately by the renderer (which also calls small_battlers.update).
    -- No-op here — the player's update drives everything.
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
        "assets/system/" .. fileKey .. ".png",
        "assets/system/" .. fileKey:sub(1, 1):upper() .. fileKey:sub(2):lower() .. ".png",
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
-- overhaul-7 A1: damage-feedback flash/shake queries the animation player
-- instead of the deleted inline animState table.
function small_battlers.draw(spriteKey, x, y, size, dead, battlerRef)
    local ss = small_battlers.get(spriteKey)
    if not (ss and ss.img) then return false end

    local frame = dead and 0 or small_battlers.frame(ss)

    -- Damage-feedback shake and transform from animation player
    local drawX = x
    local drawY = y
    local scaleX = 1
    local scaleY = 1
    if not dead and battlerRef then
        local shakeOff = animation_player.getShakeOffset(battlerRef)
        local xf = animation_player.getTransform(battlerRef)
        drawX = x + shakeOff + xf.offsetX
        drawY = y + xf.offsetY
        scaleX = xf.scaleX
        scaleY = xf.scaleY
    end

    local quad = love.graphics.newQuad(frame * ss.cellW, 0, ss.cellW, ss.cellH, ss.img:getWidth(), ss.img:getHeight())
    local drawScale = size / ss.cellW

    local function drawSprite()
        love.graphics.draw(ss.img, quad, drawX, drawY, 0, drawScale * scaleX, drawScale * scaleY)
    end

    if not dead and battlerRef then
        love.graphics.setColor(1, 1, 1, 1)
        animation_player.drawParticles(battlerRef, drawX + size / 2, y + size, drawSprite, "back")
    end

    if dead then
        love.graphics.setColor(DEAD_TINT[1], DEAD_TINT[2], DEAD_TINT[3], DEAD_TINT[4] or 1)
        drawSprite()
    else
        love.graphics.setColor(1, 1, 1, 1)
        gradient_shader.drawWithGradient(battlerRef, drawSprite, animation_player)
    end

    -- Damage-feedback flash overlay from animation player
    if not dead and battlerRef then
        local tint = animation_player.getTint(battlerRef)
        local blend = animation_player.getBlendMode(battlerRef)
        if tint and blend then
            love.graphics.setBlendMode(blend)
            love.graphics.setColor(tint.color[1], tint.color[2], tint.color[3], tint.alpha)
            drawSprite()
            love.graphics.setBlendMode("alpha")
        end
    end

    if not dead and battlerRef then
        love.graphics.setColor(1, 1, 1, 1)
        animation_player.drawParticles(battlerRef, drawX + size / 2, y + size, drawSprite, "front")
    end

    love.graphics.setColor(1, 1, 1, 1)
    return true
end

return small_battlers
