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
-- so multiple animations can stack on one target.-- Active animation instances, keyed by target object.
-- Each target maps to a list of { entryId, entry, elapsed, particleSystems }
-- so multiple animations can stack on one target.
local instances = {}

-- ParticleSystem instances that need update/draw, keyed by target
local particleSystems = {}

-- Completion callbacks, keyed by target
local completionCallbacks = {}

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
local function evalNum(val)
    if type(val) == "number" then
        return val
    elseif type(val) == "table" then
        if #val >= 2 then
            return love.math.random() * (val[2] - val[1]) + val[1]
        elseif #val == 1 then
            return val[1]
        end
    elseif type(val) == "string" then
        local min, max = val:match("random%s*%(%s*([%-%.%d]+)%s*,%s*([%-%.%d]+)%s*%)")
        if min and max then
            return love.math.random() * (tonumber(max) - tonumber(min)) + tonumber(min)
        end
        local maxSingle = val:match("random%s*%(%s*([%-%.%d]+)%s*%)")
        if maxSingle then
            return love.math.random() * tonumber(maxSingle)
        end
        return tonumber(val) or 0
    end
    return 0
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
-- Completion callbacks, keyed by target
function animation_player.load(data)
    entries = {}
    unknownTrackWarnings = {}
    for id, entry in pairs(data or {}) do
        entries[id] = entry
    end
end

-- Get an animation entry by id. Returns nil for unknown ids.
-- Completion callbacks, keyed by target
function animation_player.getEntry(entryId)
    return entries[entryId]
end

-- Start an animation on a target. `target` can be any object used as a key
-- (enemy battler, party member, etc.). Returns true if the animation was
-- found and started, false if entryId is unknown. Optionally delays start by delayMs.
function animation_player.play(entryId, target, delayMs)
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
        elapsed = -(delayMs or 0) / 1000,
        done = false,
        particleSystems = {},
    })
    return true
end

local function releaseInstanceParticles(inst)
    if inst.particleSystems then
        for _, psOrList in pairs(inst.particleSystems) do
            if type(psOrList) == "userdata" and psOrList.release then
                psOrList:release()
            elseif type(psOrList) == "table" then
                for _, ps in ipairs(psOrList) do
                    if type(ps) == "userdata" and ps.release then
                        ps:release()
                    end
                end
            end
        end
        inst.particleSystems = {}
    end
end

-- Registers a callback to be run when all active animations on a target finish.
-- Executes immediately if no animations are active.
function animation_player.onComplete(target, callback)
    if not animation_player.isAnyActive(target) then
        callback()
    else
        if not completionCallbacks[target] then
            completionCallbacks[target] = {}
        end
        table.insert(completionCallbacks[target], callback)
    end
end

-- Stop ALL animations on a target (e.g. when an enemy dies permanently
-- or a battler leaves the field). Also clears particle systems.
function animation_player.stop(target)
    local list = instances[target]
    if list then
        for _, inst in ipairs(list) do
            releaseInstanceParticles(inst)
        end
    end
    instances[target] = nil
    completionCallbacks[target] = nil
end

-- Stop a specific animation on a target.
function animation_player.stopAnimation(target, entryId)
    local list = instances[target]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].entryId == entryId then
            releaseInstanceParticles(list[i])
            table.remove(list, i)
        end
    end
    if #list == 0 then
        instances[target] = nil
        local callbacks = completionCallbacks[target]
        if callbacks then
            completionCallbacks[target] = nil
            for _, cb in ipairs(callbacks) do
                pcall(cb)
            end
        end
    end
end

-- Clear ALL animation state (new battle, scene transition).
function animation_player.reset()
    for _, list in pairs(instances) do
        for _, inst in ipairs(list) do
            releaseInstanceParticles(inst)
        end
    end
    instances = {}
    completionCallbacks = {}
end

-- Advance all active animations by dt seconds. Called from
-- renderer.update or equivalent update loop.
function animation_player.update(dt)
    for target, list in pairs(instances) do
        local anyFinished = false
        for i = #list, 1, -1 do
            local inst = list[i]
            inst.elapsed = inst.elapsed + dt
            local durSec = (inst.entry.duration or 0) / 1000
            
            local infinite = inst.entry.duration == -1 or inst.entry.loopForever
            local loop = inst.entry.loop
            
            if infinite then
                -- Never finishes automatically
            elseif loop then
                if inst.elapsed >= durSec then
                    inst.elapsed = durSec > 0 and (inst.elapsed % durSec) or 0
                end
            else
                if inst.elapsed >= durSec then
                    -- Animation complete — remove it
                    releaseInstanceParticles(inst)
                    table.remove(list, i)
                    anyFinished = true
                end
            end
        end
        if #list == 0 then
            instances[target] = nil
            local callbacks = completionCallbacks[target]
            if callbacks then
                completionCallbacks[target] = nil
                for _, cb in ipairs(callbacks) do
                    pcall(cb)
                end
            end
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

local function getNodeTransform(entry, inst, trackIndex, elapsedSec)
    local track = entry.tracks[trackIndex]
    local parentIdx = nil
    if track.parent then
        for idx, tr in ipairs(entry.tracks) do
            if tr.id == track.parent then
                parentIdx = idx
                break
            end
        end
    end

    local base = { offsetX = 0, offsetY = 0, scaleX = 1, scaleY = 1 }
    if parentIdx then
        local parentTf = getNodeTransform(entry, inst, parentIdx, elapsedSec)
        if track.inheritPosition ~= "never" then
            base.offsetX = parentTf.offsetX
            base.offsetY = parentTf.offsetY
        end
        if track.inheritScale ~= "never" then
            base.scaleX = parentTf.scaleX
            base.scaleY = parentTf.scaleY
        end
    end

    if track.type == "transform" then
        local t0Sec = (track.t0 or 0) / 1000
        local durSec = (track.duration or 0) / 1000
        local trackEnd = t0Sec + durSec
        if elapsedSec >= t0Sec and elapsedSec < trackEnd then
            local t = durSec > 0 and (elapsedSec - t0Sec) / durSec or 1
            local ease = easingFn(track.easing)
            local tf = evalTransform(track, ease(t))
            base.offsetX = base.offsetX + tf.offsetX
            base.offsetY = base.offsetY + tf.offsetY
            base.scaleX = base.scaleX * tf.scaleX
            base.scaleY = base.scaleY * tf.scaleY
        end
    end

    return base
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
-- Screen flash & gradient map
---------------------------------------------------------------------------

-- Generic "most-recently-started active track of a type" scanner used by the
-- screen-flash and gradient-map queries. Returns the track and its eased t.
local function activeTrackOfType(target, typeName)
    local list = instances[target]
    if not list then return nil end
    for i = #list, 1, -1 do
        local inst = list[i]
        local entry = inst.entry
        if entry and entry.tracks then
            local elapsedSec = inst.elapsed
            for _, track in ipairs(entry.tracks) do
                if track.type == typeName then
                    local t0Sec = (track.t0 or 0) / 1000
                    local durSec = (track.duration or 0) / 1000
                    if elapsedSec >= t0Sec and elapsedSec < t0Sec + durSec then
                        local t = durSec > 0 and (elapsedSec - t0Sec) / durSec or 1
                        return track, easingFn(track.easing)(t)
                    end
                end
            end
        end
    end
    return nil
end

-- Full-screen colored overlay. Returns { color = {r,g,b}, alpha = n } for the
-- active screen_flash track (alpha interpolates from→to), or nil.
function animation_player.getScreenFlash(target)
    local track, t = activeTrackOfType(target, "screen_flash")
    if not track then return nil end
    local fromA = track.fromAlpha or 1
    local toA = track.toAlpha or 0
    return {
        color = track.color or { 1, 1, 1 },
        alpha = fromA + (toA - fromA) * t,
    }
end

-- Animated luminance→gradient remap of the sprite. Returns
-- { low = {r,g,b}, high = {r,g,b}, intensity = n } or nil.
function animation_player.getGradientMap(target)
    local track, t = activeTrackOfType(target, "gradient_map")
    if not track then return nil end
    local fromI = track.fromIntensity ~= nil and track.fromIntensity or 1
    local toI = track.toIntensity ~= nil and track.toIntensity or 1
    return {
        low = track.lowColor or { 0, 0, 0 },
        high = track.highColor or { 1, 1, 1 },
        intensity = fromI + (toI - fromI) * t,
    }
end

---------------------------------------------------------------------------
-- Particle system management
---------------------------------------------------------------------------

-- Creates and returns LOVE ParticleSystems for active particle tracks on
-- the given target. The caller should draw them with appropriate
-- positioning and stencil masking. Returns a list of { ps, mask, blendMode }.
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
                        local ps = animation_player._createParticleSystem(track, entry)
                        if ps then
                            inst.particleSystems[ti] = ps
                        end
                    end
                    local psOrList = inst.particleSystems[ti]
                    if psOrList then
                        local parentTf = nil
                        if track.parent then
                            parentTf = getNodeTransform(entry, inst, ti, inst.elapsed)
                        end
                        local systems = {}
                        if type(psOrList) == "userdata" and psOrList.release then
                            table.insert(systems, psOrList)
                        elseif type(psOrList) == "table" then
                            systems = psOrList
                        end
                        for _, ps in ipairs(systems) do
                            table.insert(result, {
                                ps = ps,
                                mask = track.mask,
                                blendMode = track.blendMode or "alpha",
                                x = 0,
                                y = 0,
                                layer = track.layer or "front",
                                parentTransform = parentTf,
                            })
                        end
                    end
                end
            end
        end
    end
    if #result == 0 then return nil end
    return result
end

-- Internal: sum the accelerations contributed by all `force_field` tracks in
-- an entry, mapped onto LÖVE's acceleration channels. Force fields are
-- entry-global: they affect every particle track unless that track opts out
-- with `ignoreForces = true`. Returns linX, linY, radial, tangential, damping.
local function aggregateForces(entry, particleTrack)
    local linX, linY, radial, tangential, damping = 0, 0, 0, 0, 0
    if not entry or not entry.tracks or particleTrack.ignoreForces then
        return linX, linY, radial, tangential, damping
    end
    for _, tr in ipairs(entry.tracks) do
        if tr.type == "force_field" then
            local s = tr.strength or 0
            local field = tr.field or "gravity"
            if field == "gravity" then
                local a = math.rad(tr.angle or 90)
                linX = linX + math.cos(a) * s
                linY = linY + math.sin(a) * s
            elseif field == "attract" then
                radial = radial - s
            elseif field == "vortex" then
                tangential = tangential + s
            elseif field == "drag" then
                damping = damping + s
            end
        end
    end
    return linX, linY, radial, tangential, damping
end

local function createSinglePS(texture, track, entry, singleCellIdx)
    local ps = love.graphics.newParticleSystem(texture, 512)

    -- Cells / flipbook
    local cellW = track.cellW or track.quadWidth
    local cellH = track.cellH or track.quadHeight
    local cellCount = track.cellCount or track.quadCount
    if cellW and cellH and cellCount and cellCount > 0 then
        local w, h = texture:getDimensions()
        local cols = math.max(1, math.floor(w / cellW))
        local start = track.cellStart or 0
        local quads = {}
        if singleCellIdx then
            local idx = start + singleCellIdx
            local cx = (idx % cols) * cellW
            local cy = math.floor(idx / cols) * cellH
            table.insert(quads, love.graphics.newQuad(cx, cy, cellW, cellH, w, h))
        else
            local loops = (track.cellMode == "loop") and math.max(1, track.cellLoops or 1) or 1
            for _ = 1, loops do
                for i = 0, cellCount - 1 do
                    local idx = start + i
                    local cx = (idx % cols) * cellW
                    local cy = math.floor(idx / cols) * cellH
                    table.insert(quads, love.graphics.newQuad(cx, cy, cellW, cellH, w, h))
                end
            end
        end
        ps:setQuads(quads)
    end

    if track.direction then ps:setDirection(math.rad(evalNum(track.direction))) end
    ps:setEmissionRate(track.rate or 10)
    local life = track.lifetime or 0.5
    ps:setParticleLifetime(life, life * (track.lifetimeVariation or 1.5))
    ps:setSpread(math.rad(evalNum(track.spread or 45)))
    local speed = evalNum(track.speed or track.velocity or 50)
    ps:setSpeed(speed, evalNum(track.speedMax or speed * 1.5))

    -- Emission Area / Spawn shape
    if track.spawnShape and track.spawnShape ~= "point" then
        local dist = "none"
        if track.spawnShape == "line" then
            dist = "uniform"
        elseif track.spawnShape == "rectangle" then
            dist = "uniform"
        elseif track.spawnShape == "circle" then
            dist = "ellipse"
        elseif track.spawnShape == "ring" then
            dist = "borderellipse"
        elseif track.spawnShape == "borderrectangle" then
            dist = "borderrectangle"
        elseif track.spawnShape == "normal" then
            dist = "normal"
        end

        if dist ~= "none" then
            local rx = evalNum(track.spawnRadiusX or 0)
            local ry = evalNum(track.spawnRadiusY or 0)
            if track.spawnShape == "line" then
                ry = 0
            end
            local angle = math.rad(evalNum(track.spawnAngle or 0))
            local outward = (track.spawnDirectionOutward == true)
            pcall(function()
                ps:setEmissionArea(dist, rx, ry, angle, outward)
            end)
        end
    end

    -- Forces: the track's own gravity plus the entry's force_field tracks.
    local linX, linY, radial, tangential, damping = aggregateForces(entry, track)
    linY = linY + (track.gravity or 0)
    ps:setLinearAcceleration(linX, linY, linX, linY)
    if radial ~= 0 then ps:setRadialAcceleration(radial, radial) end
    if tangential ~= 0 then ps:setTangentialAcceleration(tangential, tangential) end
    if damping ~= 0 then ps:setLinearDamping(damping, damping) end

    if track.spin then ps:setSpin(math.rad(track.spin), math.rad(track.spin)) end
    if track.rotation then ps:setRotation(0, math.rad(track.rotation)) end

    ps:setColors(unpack(track.colorOverLife or { { 1, 1, 1, 1 }, { 1, 1, 1, 0 } }))
    local sizeStart = track.sizeStart or 1
    local sizeEnd = track.sizeEnd ~= nil and track.sizeEnd or 0.5
    ps:setSizes(sizeStart, sizeEnd)
    if track.sizeVariation then ps:setSizeVariation(track.sizeVariation) end
    ps:start()
    return ps
end

-- Internal: create a LÖVE ParticleSystem from a particles track definition.
function animation_player._createParticleSystem(track, entry)
    local texture
    if track.particleTexture then
        if love.filesystem.getInfo(track.particleTexture) then
            texture = love.graphics.newImage(track.particleTexture)
        end
    end
    if not texture then
        local dot = love.image.newImageData(2, 2)
        dot:mapPixel(function() return 1, 1, 1, 1 end)
        texture = love.graphics.newImage(dot)
    end

    local cellW = track.cellW or track.quadWidth
    local cellH = track.cellH or track.quadHeight
    local cellCount = track.cellCount or track.quadCount

    if track.cellMode == "random" and cellW and cellH and cellCount and cellCount > 0 then
        local list = {}
        for i = 0, cellCount - 1 do
            local ps = createSinglePS(texture, track, entry, i)
            table.insert(list, ps)
        end
        return list
    else
        return createSinglePS(texture, track, entry)
    end
end

-- Update all particle systems. Called from renderer.update.
function animation_player.updateParticles(dt)
    for target, list in pairs(instances) do
        for _, inst in ipairs(list) do
            local entry = inst.entry
            for ti, psOrList in pairs(inst.particleSystems or {}) do
                local track = entry and entry.tracks and entry.tracks[ti]
                if track then
                    local t0 = (track.t0 or 0) / 1000
                    local tEnd = t0 + (track.duration or 0) / 1000
                    
                    local systems = {}
                    if type(psOrList) == "userdata" and psOrList.release then
                        table.insert(systems, psOrList)
                    elseif type(psOrList) == "table" then
                        systems = psOrList
                    end
                    
                    local active = inst.elapsed >= t0 and inst.elapsed < tEnd
                    local rate = track.rate or 10
                    if type(psOrList) == "table" and #systems > 0 then
                        rate = rate / #systems
                    end
                    
                    for _, ps in ipairs(systems) do
                        if active then
                            ps:setEmissionRate(rate)
                            
                            -- Evaluate dynamic fields!
                            local ox = evalNum(track.x or 0)
                            local oy = evalNum(track.y or 0)
                            ps:setPosition(ox, oy)
                            
                            if track.direction then
                                ps:setDirection(math.rad(evalNum(track.direction)))
                            end
                            local speed = evalNum(track.speed or track.velocity or 50)
                            ps:setSpeed(speed, evalNum(track.speedMax or speed * 1.5))
                            if track.spread then
                                ps:setSpread(math.rad(evalNum(track.spread)))
                            end
                        else
                            ps:setEmissionRate(0)
                        end
                        ps:update(dt)
                    end
                end
            end
        end
    end
end

-- Draw particles for a target at the given screen position.
-- If mask is "target", the particles are clipped to the battler's sprite
-- using stencil testing against its alpha channel.
-- `layerFilter` (optional): "back" or "front" draws only that layer, so the
-- caller can render back-layer particles before the sprite and front-layer
-- ones after. nil draws all.
function animation_player.drawParticles(target, drawX, drawY, battlerDrawFn, layerFilter)
    local systems = animation_player.getParticleSystems(target)
    if not systems then return end
    for _, sys in ipairs(systems) do
        if not (layerFilter and (sys.layer or "front") ~= layerFilter) then
        local ps = sys.ps
        local blendMode = sys.blendMode
        local px = drawX + (sys.x or 0)
        local py = drawY + (sys.y or 0)
        if sys.parentTransform then
            px = px + sys.parentTransform.offsetX
            py = py + sys.parentTransform.offsetY
        end
        if sys.mask == "target" and battlerDrawFn then
            -- Stencil mask: render the battler sprite to the stencil buffer,
            -- then draw particles only where the stencil is set.
            love.graphics.stencil(function()
                battlerDrawFn()
            end, "increment", 1, false)
            love.graphics.setStencilTest("greater", 0)
            love.graphics.setBlendMode(blendMode)
            love.graphics.draw(ps, px, py)
            love.graphics.setStencilTest()
        else
            love.graphics.setBlendMode(blendMode)
            love.graphics.draw(ps, px, py)
        end
        love.graphics.setBlendMode("alpha")
        end
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
