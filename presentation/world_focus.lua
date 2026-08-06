local world_focus = {}

local PRESETS = {
    low_prop = {
        duration = 0.22,
        pitch = math.rad(25),
        fovScale = 0.75,
        dolly = 0.2,
    }
}

local state = {
    phase = "idle", -- "focus_in", "holding", "focus_out", "idle"
    presetKey = nil,
    preset = nil,
    progress = 0,
    targetCoords = nil,
    session = nil,
    mapIndex = nil,
    callback = nil,
    opId = 0,
}

local currentOpId = 0

local function smoothstep(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

function world_focus.getPreset(presetKey)
    if not presetKey or not PRESETS[presetKey] then
        error("unknown focus preset: " .. tostring(presetKey), 0)
    end
    return PRESETS[presetKey]
end

function world_focus.begin(spec, targetCoords, session, onFocusedCallback)
    local presetKey = type(spec) == "table" and spec.kind or spec
    local preset = world_focus.getPreset(presetKey)

    currentOpId = currentOpId + 1
    state.opId = currentOpId
    state.phase = "focus_in"
    state.presetKey = presetKey
    state.preset = preset
    state.progress = 0
    state.targetCoords = targetCoords
    state.session = session
    state.mapIndex = session and session.currentMapIndex
    state.callback = onFocusedCallback

    return state.opId
end

function world_focus.reset()
    state.phase = "idle"
    state.presetKey = nil
    state.preset = nil
    state.progress = 0
    state.targetCoords = nil
    state.session = nil
    state.mapIndex = nil
    state.callback = nil
    state.opId = 0
end

function world_focus.isActive()
    return state.phase ~= "idle"
end

function world_focus.isBlockingInput()
    return state.phase ~= "idle"
end

function world_focus.getCameraOverride()
    if state.phase == "idle" or not state.preset then
        return { pitch = 0.0, fovScale = 1.0, dollyX = 0.0, dollyY = 0.0 }
    end

    local easeT = smoothstep(state.progress)
    local pitch = state.preset.pitch * easeT
    local fovScale = 1.0 + (state.preset.fovScale - 1.0) * easeT

    local dollyX, dollyY = 0.0, 0.0
    if state.targetCoords and state.session then
        local pdir = state.session.playerDir
        local DIRS = {
            N = { dx = 0, dy = -1 },
            E = { dx = 1, dy = 0 },
            S = { dx = 0, dy = 1 },
            W = { dx = -1, dy = 0 },
        }
        local d = DIRS[pdir] or { dx = 0, dy = 0 }
        local dist = state.preset.dolly * easeT
        dollyX = d.dx * dist
        dollyY = d.dy * dist
    end

    return {
        pitch = pitch,
        fovScale = fovScale,
        dollyX = dollyX,
        dollyY = dollyY,
    }
end

function world_focus.update(dt)
    if state.phase == "idle" or not state.preset then return end

    -- Monotonic cancellation check: session or map changed
    if state.session and state.mapIndex and state.session.currentMapIndex ~= state.mapIndex then
        world_focus.reset()
        return
    end

    if state.phase == "focus_in" then
        state.progress = math.min(1.0, state.progress + (dt / state.preset.duration))
        if state.progress >= 1.0 then
            state.phase = "focus_out" -- Transition immediately to release phase
            local cb = state.callback
            local thisOpId = state.opId
            state.callback = nil

            if cb then
                local ok, err = xpcall(cb, debug.traceback)
                if not ok then
                    world_focus.reset()
                    error(err, 0)
                end
            end
        end
    elseif state.phase == "focus_out" then
        state.progress = math.max(0.0, state.progress - (dt / state.preset.duration))
        if state.progress <= 0.0 then
            world_focus.reset()
        end
    end
end

return world_focus
