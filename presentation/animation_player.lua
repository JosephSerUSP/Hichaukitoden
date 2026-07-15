-- Animation player: owns all battler animation timing and state.
-- Created by overhaul-7 A1 to replace the hardcoded inline timers and
-- constants that were scattered across presentation/renderer.lua and
-- presentation/small_battlers.lua.
--
-- Loading: the caller (data/loader.lua or a scene's init) calls
-- animation_player.load(animationsData) once with the parsed
-- data/animations.json table.
--
-- Active instances: each call to play(entryId, target) creates an instance
-- that lives for the entry's duration. Multiple animations can run
-- simultaneously on the same target; compositing rules are documented on
-- each query method.
--
-- Timing: all track t0/duration values are in MILLISECONDS in the data;
-- the player converts to seconds internally for LOVE's dt.
--
-- Unknown track types: one log message, then skipped — future track types
-- never crash old engine builds.

local animation_player = {}

-- Loaded animation entries: id -> entry table
local entries = {}

-- Active animation instances, keyed by target object.
-- Each target maps to a list of { entryId, entry, elapsed, particleSystems }
-- so multiple animations can stack on one target.
local instances = {}

-- ParticleSystem instances that need update/draw, keyed by target
local particleSystems = {}

-- Log-once set for unknown track types
local unknownTrackWarnings = {}

---------------------------------------------------------------------------
-- Easing functions
---------------------------------------------------------------------------

local function easeLinear(t)
    return t
end

local function easeOut(t)
    -- Quadratic ease-out: fast start, slow end
    return 1 - (1 - t) * (1 - t)
end

local function easingFn(name)
    if name == "ease_out" then return easeOut end
    return easeLinear
end

---------------------------------------------------------------------------
-- Track evaluation helpers
---------------------------------------------------------------------------

local function evalBlend(track, t)
    -- Blend track: just returns the mode string for the track's duration.
    -- After the track ends, its effect is removed (caller checks bounds).
    return track.mode or "alpha"
end

local function evalTint(track, t)
    -- Tint: interpolate alpha from fromAlpha to toAlpha.
    -- Color stays constant (the track's color field).
    local alpha = track.fromAlpha + (track.toAlpha - track.fromAlpha) * t
    return {
        color = track.color or { 1, 1, 1 },
        alpha = alpha
    }
end

local function evalTransform(track, t)
    -- Transform: interpolate offset and scale independently.
    local fromX = track.fromX or 0
    local toX = track.toX or 0
    local fromY = track.fromY or 0
    local toY = track.toY or 0
    local fromScaleX = track.fromScaleX or 1
    local toScaleX = track.toScaleX or 1
    local fromScaleY = track.fromScaleY or 1
    local toScaleY = track.toScaleY or 1
    return {
        offsetX = fromX + (toX - fromX) * t,
        offsetY = fromY + (toY - fromY) * t,
        scaleX = fromScaleX + (toScaleX - fromScaleX) * t,
        scaleY = fromScaleY + (toScaleY - fromScaleY) * t,
    }
end

local function evalShake(track, t)
    -- Shake: amplitude decays with t (1 = full, 0 = none).
    -- Oscillation is based on elapsed time, not normalized t.
    -- Frequency controls the speed of oscillation.
    local amplitude = track.amplitude or 2
    local frequency = track.frequency or 30
    return {
        amplitude = amplitude * (1 - t),
        frequency = frequency,
        -- The actual offset is computed at draw time using the
        -- animation's real elapsed time, not the normalized t,
        -- so the sine wave continues smoothly.
    }
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Load animation entries (called once from data/loader.lua or scene init).
-- `data` is the parsed JSON table (animations.json).
function animation_player.load(data)
    entries = {}
    unknownTrackWarnings = {}
    for id, entry in pairs(data or {}) do
        entries[id] = entry
    end
end

-- Get an animation entry by id. Returns nil for unknown ids.
function animation_player.getEntry(entryId)
    return entries[entryId]
end

-- Start an animation on a target. `target` can be any object used as a key
-- (enemy battler, party member, etc.). Returns true if the animation was
-- found and started, false if entryId is unknown.
function animation_player.play(entryId, target)
    local entry = entries[entryId]
    if not entry then
        if not unknownTrackWarnings[entryId] then
            unknownTrackWarnings[entryId] = true
            print("[animation_player] unknown animation entry: " .. tostring(entryId))
        end
        return false
    end

    if not instances[target] then
        instances[target] = {}
    end
    table.insert(instances[target], {
        entryId = entryId,
        entry = entry,
        elapsed = 0,
        done = false,
        particleSystems = {},
    })
    return true
end

-- Stop ALL animations on a target (e.g. when an enemy dies permanently
-- or a battler leaves the field). Also clears particle systems.
function animation_player.stop(target)
    instances[target] = nil
    if particleSystems[target] then
        for _, ps in ipairs(particleSystems[target]) do
            ps:release()
        end
        particleSystems[target] = nil
    end
end

-- Stop a specific animation on a target.
function animation_player.stopAnimation(target, entryId)
    local list = instances[target]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].entryId == entryId then
            table.remove(list, i)
        end
    end
    if #list == 0 then
        instances[target] = nil
    end
end

-- Clear ALL animation state (new battle, scene transition).
function animation_player.reset()
    -- Release all particle systems
    for target, pss in pairs(particleSystems) do
        for _, ps in ipairs(pss) do
            ps:release()
        end
    end
    instances = {}
    particleSystems = {}
end

-- Advance all active animations by dt seconds. Called from
-- renderer.update or equivalent update loop.
function animation_player.update(dt)
    for target, list in pairs(instances) do
        for i = #list, 1, -1 do
            local inst = list[i]
            inst.elapsed = inst.elapsed + dt
            local durSec = (inst.entry.duration or 0) / 1000
            if inst.elapsed >= durSec then
                -- Animation complete — remove it
                table.remove(list, i)
            end
        end
        if #list == 0 then
            instances[target] = nil
        end
    end
end

-- Returns true if `target` has any active animation matching entryId.
function animation_player.isPlaying(target, entryId)
    local list = instances[target]
    if not list then return false end
    for _, inst in ipairs(list) do
        if inst.entryId == entryId then return true end
    end
    return false
end

-- Returns true if `target` has ANY active animation.
function animation_player.isAnyActive(target)
    local list = instances[target]
    return list and #list > 0 or false
end

---------------------------------------------------------------------------
-- Per-target state queries
--
-- Each query evaluates all active animations on the target and composites
-- the results. Compositing rules:
--  - tint: most recently started animation's tint wins
--  - blend: most recently started animation's blend wins
--  - transform: offsets accumulate (summed), scales multiply
--  - shake: most recently started shake wins
---------------------------------------------------------------------------

-- Returns { color = {r,g,b}, alpha = n } or nil if no tint animation active.
-- The color field is the track's static color; alpha is interpolated.
function animation_player.getTint(target)
    local list = instances[target]
    if not list then return nil end
    -- Most recently started animation with a tint track wins
    for i = #list, 1, -1 do
        local inst = list[i]
        local entry = inst.entry
        if entry and entry.tracks then
            local elapsedSec = inst.elapsed
            for _, track in ipairs(entry.tracks) do
                if track.type == "tint" then
                    local t0Sec = (track.t0 or 0) / 1000
                    local durSec = (track.duration or 0) / 1000
                    local trackEnd = t0Sec + durSec
                    if elapsedSec >= t0Sec and elapsedSec < trackEnd then
                        local t = durSec > 0 and (elapsedSec - t0Sec) / durSec or 1
                        local ease = easingFn(track.easing)
                        return evalTint(track, ease(t))
                    end
                end
            end
        end
    end
    return nil
end

-- Returns blend mode string (e.g. "add", "alpha") or nil if no blend
-- animation active. When nil, the caller should use "alpha".
function animation_player.getBlendMode(target)
    local list = instances[target]
    if not list then return nil end
    for i = #list, 1, -1 do
        local inst = list[i]
        local entry = inst.entry
        if entry and entry.tracks then
            local elapsedSec = inst.elapsed
            for _, track in ipairs(entry.tracks) do
                if track.type == "blend" then
                    local t0Sec = (track.t0 or 0) / 1000
                    local durSec = (track.duration or 0) / 1000
                    local trackEnd = t0Sec + durSec
                    if elapsedSec >= t0Sec and elapsedSec < trackEnd then
                        return track.mode or "alpha"
                    end
                end
            end
        end
    end
    return nil
end

-- Returns { offsetX, offsetY, scaleX, scaleY } with accumulated values
-- from all active transform tracks. Defaults: offset (0,0), scale (1,1).
function animation_player.getTransform(target)
    local list = instances[target]
    local result = { offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1 }
    if not list then return result end
    for _, inst in ipairs(list) do
        local entry = inst.entry
        if entry and entry.tracks then
            local elapsedSec = inst.elapsed
            for _, track in ipairs(entry.tracks) do
                if track.type == "transform" then
                    local t0Sec = (track.t0 or 0) / 1000
                    local durSec = (track.duration or 0) / 1000
                    local trackEnd = t0Sec + durSec
                    if elapsedSec >= t0Sec and elapsedSec < trackEnd then
                        local t = durSec > 0 and (elapsedSec - t0Sec) / durSec or 1
                        local ease = easingFn(track.easing)
                        local tf = evalTransform(track, ease(t))
                        result.offsetX = result.offsetX + tf.offsetX
                        result.offsetY = result.offsetY + tf.offsetY
                        result.scaleX = result.scaleX * tf.scaleX
                        result.scaleY = result.scaleY * tf.scaleY
                    elseif elapsedSec < t0Sec then
                        -- Track hasn't started yet
                    end
                end
            end
        end
    end
    return result
end

-- Returns shake horizontal offset in pixels, or 0 if no shake active.
-- The offset oscillates using the track's frequency and decaying amplitude.
function animation_player.getShakeOffset(target)
    local list = instances[target]
    if not list then return 0 end
    for i = #list, 1, -1 do
        local inst = list[i]
        local entry = inst.entry
        if entry and entry.tracks then
            local elapsedSec = inst.elapsed
            for _, track in ipairs(entry.tracks) do
                if track.type == "shake" then
                    local t0Sec = (track.t0 or 0) / 1000
                    local durSec = (track.duration or 0) / 1000
                    local trackEnd = t0Sec + durSec
                    if elapsedSec >= t0Sec and elapsedSec < trackEnd then
                        local t = durSec > 0 and (elapsedSec - t0Sec) / durSec or 1
                        local shake = evalShake(track, t)
                        return shake.amplitude * math.sin(elapsedSec * shake.frequency * 2 * math.pi)
                    end
                end
            end
        end
    end
    return 0
end

---------------------------------------------------------------------------
-- Text flow drawing
---------------------------------------------------------------------------

-- Returns a list of { char, x, y, color } for text_flow tracks that have
-- visible characters at the current elapsed time. The caller positions
-- these relative to the target's screen position.
-- Returns nil if no text_flow is active.
function animation_player.getTextFlowGlyphs(target, targetScreenX, targetScreenY)
    local list = instances[target]
    if not list then return nil end
    local glyphs = {}
    for _, inst in ipairs(list) do
        local entry = inst.entry
        if entry and entry.tracks then
            local elapsedMs = inst.elapsed * 1000
            for _, track in ipairs(entry.tracks) do
                if track.type == "text_flow" then
                    local t0Ms = track.t0 or 0
                    local durMs = track.duration or 1000
                    local trackEndMs = t0Ms + durMs
                    if elapsedMs >= t0Ms and elapsedMs < trackEndMs then
                        local seq = track.sequence or ""
                        local interval = track.interval or 50
                        local relativeElapsed = elapsedMs - t0Ms
                        local numChars = math.min(#seq, math.floor(relativeElapsed / interval) + 1)
                        local color = track.color or { 1, 1, 1 }
                        for i = 1, numChars do
                            table.insert(glyphs, {
                                char = seq:sub(i, i),
                                x = targetScreenX + (i - 1) * 6,
                                y = targetScreenY - 8,
                                color = color,
                            })
                        end
                    end
                end
            end
        end
    end
    if #glyphs == 0 then return nil end
    return glyphs
end

---------------------------------------------------------------------------
-- Particle system management
---------------------------------------------------------------------------

-- Creates and returns LOVE ParticleSystems for active particle tracks on
-- the given target. The caller should draw them with appropriate
-- positioning and stencil masking. Returns a list of { ps, mask, blendMode }.
function animation_player.getParticleSystems(target)
    local list = instances[target]
    if not list then return nil end
    local result = {}
    for _, inst in ipairs(list) do
        local entry = inst.entry
        if entry and entry.tracks then
            for ti, track in ipairs(entry.tracks) do
                if track.type == "particles" then
                    -- Create particle system if not yet created for this track
                    if not inst.particleSystems[ti] then
                        local ps = animation_player._createParticleSystem(track)
                        if ps then
                            inst.particleSystems[ti] = ps
                        end
                    end
                    local ps = inst.particleSystems[ti]
                    if ps then
                        table.insert(result, {
                            ps = ps,
                            mask = track.mask,
                            blendMode = track.blendMode or "alpha",
                        })
                    end
                end
            end
        end
    end
    if #result == 0 then return nil end
    return result
end

-- Internal: create a LÖVE ParticleSystem from a particles track definition.
-- `track` fields: rate, lifetime, spread, velocity, gravity, colorOverLife,
-- blendMode, particleTexture (optional — falls back to 2px white quad).
function animation_player._createParticleSystem(track)
    -- Try loading a particle texture if specified
    local texture
    if track.particleTexture then
        if love.filesystem.getInfo(track.particleTexture) then
            texture = love.graphics.newImage(track.particleTexture)
        end
    end
    -- Fallback: create a small white image for colored particles
    if not texture then
        texture = love.graphics.newImage(love.image.newImageData(2, 2))
        -- Default white; the particle color/colorOverLife tints it
    end

    local ps = love.graphics.newParticleSystem(texture, 256)
    ps:setEmissionRate(track.rate or 10)
    ps:setParticleLifetime(track.lifetime or 0.5, (track.lifetime or 0.5) * 1.5)
    ps:setSpread(math.rad(track.spread or 45))
    ps:setSpeed(track.velocity or 50, (track.velocity or 50) * 1.5)
    ps:setGravity(track.gravity or 0)
    ps:setColors(unpack(track.colorOverLife or { { 1, 1, 1, 1 }, { 1, 1, 1, 0 } }))
    ps:setSizes(1, 0.5)
    ps:start()
    return ps
end

-- Update all particle systems. Called from renderer.update.
function animation_player.updateParticles(dt)
    for target, list in pairs(instances) do
        for _, inst in ipairs(list) do
            for _, ps in pairs(inst.particleSystems or {}) do
                ps:update(dt)
            end
        end
    end
end

-- Draw particles for a target at the given screen position.
-- If mask is "target", the particles are clipped to the battler's sprite
-- using stencil testing against its alpha channel.
function animation_player.drawParticles(target, drawX, drawY, battlerDrawFn)
    local systems = animation_player.getParticleSystems(target)
    if not systems then return end
    for _, sys in ipairs(systems) do
        local ps = sys.ps
        local blendMode = sys.blendMode
        if sys.mask == "target" and battlerDrawFn then
            -- Stencil mask: render the battler sprite to the stencil buffer,
            -- then draw particles only where the stencil is set.
            love.graphics.stencil(function()
                battlerDrawFn()
            end, "increment", 1, false)
            love.graphics.setStencilTest("greater", 0)
            love.graphics.setBlendMode(blendMode)
            love.graphics.draw(ps, drawX, drawY)
            love.graphics.setStencilTest()
        else
            love.graphics.setBlendMode(blendMode)
            love.graphics.draw(ps, drawX, drawY)
        end
        love.graphics.setBlendMode("alpha")
    end
end

---------------------------------------------------------------------------
-- Debug / introspection
---------------------------------------------------------------------------

function animation_player.getActiveCount()
    local count = 0
    for _, list in pairs(instances) do
        count = count + #list
    end
    return count
end

function animation_player.getEntryIds()
    local ids = {}
    for id, _ in pairs(entries) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

return animation_player
