local interpreter = require("engine.interpreter")
local input_map = require("engine.input_map")
local scene_transition = require("presentation.scene_transition")

local scene_host = {}

-- State container for the active scenes
-- Each element is { id = sceneId, v = {}, windows = {}, focusedWindow = nil }
local sceneStack = {}

-- Window definitions registered by kind (via scene_host.register).
-- Populated by calling registerKindWindows from scene modules.
-- Keyed by kind string (e.g. "battle"), value is a table of window defs.
local windowDefsByKind = {}

-- Fallback ctx for push/goto_scene call sites that omit it (there are many
-- across main.lua's legacy code, all pre-dating scenes with real hooks — a
-- scene without hooks tolerated a missing ctx silently since on_enter was a
-- no-op either way). Now that "map" has a real on_enter, a missing ctx means
-- v.mode/etc never get initialized, and every subsequent hook call falls
-- through NO branch (nil doesn't match any state check) with
-- hookHandled/hookFallback both left false — runHook returns "handled" for
-- every keypress despite doing nothing, freezing all input. love.update
-- refreshes this every frame with a real { session, loader } ctx, so it's
-- never more than one frame stale.
local lastCtx = nil

function scene_host.rememberCtx(ctx)
    if ctx then lastCtx = ctx end
end

local function getSceneData(ctx, id)
    if not ctx or not ctx.loader or not ctx.loader.scenes then return nil end
    -- Two-pass matching: first pass prefers exact id/name match,
    -- second pass falls back to kind match.
    -- This prevents ambiguity when multiple scenes share a kind (e.g. "menu").
    for _, scene in ipairs(ctx.loader.scenes) do
        if tostring(scene.id) == tostring(id) or scene.name == id then
            return scene
        end
    end
    -- Second pass: match by kind (lowest priority)
    for _, scene in ipairs(ctx.loader.scenes) do
        if scene.kind == id then
            return scene
        end
    end
    return nil
end

-- Initialize the host with an active session and loader
function scene_host.init(startScene)
    sceneStack = {}
    if startScene then
        scene_host.push(startScene)
    end
end

function scene_host.getCurrent()
    if #sceneStack == 0 then return nil end
    return sceneStack[#sceneStack].id
end

function scene_host.getPrevious()
    if #sceneStack < 2 then return nil end
    return sceneStack[#sceneStack - 1].id
end

function scene_host.getCurrentState()
    if #sceneStack == 0 then return nil end
    return sceneStack[#sceneStack]
end

-- Register window definitions for a scene kind.
-- Called by scene modules (e.g. battle.registerKindWindows) during push.
-- Stored defs are merged into the scene state's windows table on push.
function scene_host.register(kind, windowDefs)
    windowDefsByKind[kind] = windowDefs
end

-- Consume a D2 window command event into the scene's runtime window state,
-- which the generic window renderer (presentation/window_renderer.lua) draws
-- for scenes that opt in with "draw": "windows".
local function applyWindowEvent(state, ev)
    if not state.winState then
        state.winState = {}
        state.windowOrder = {}
    end
    local function ensure(id)
        if not id then return nil end
        if not state.winState[id] then
            state.winState[id] = {}
            table.insert(state.windowOrder, id)
        end
        return state.winState[id]
    end
    if ev.type == "open_window" then
        local w = ensure(ev.windowId)
        if w then w.open = true end
    elseif ev.type == "close_window" then
        local w = state.winState[ev.windowId]
        if w then w.open = false end
    elseif ev.type == "set_list" then
        local w = ensure(ev.windowId)
        if w then
            w.listId = ev.listId
            w.format = ev.format
            w.priority = ev.priority
            w.highlight = ev.highlight
            w.sprite = ev.sprite
            w.gaugeValue = ev.gaugeValue
            w.gaugeMax = ev.gaugeMax
            w.gaugeColor = ev.gaugeColor
            w.gaugeFill = ev.gaugeFill
            w.slot = ev.slot
            w.member = ev.member
        end
    elseif ev.type == "set_text" then
        local w = ensure(ev.windowId)
        if w then w.text = ev.text end
    elseif ev.type == "set_cursor" then
        local w = ensure(ev.windowId)
        if w then
            w.cursor = ev.index
            -- Keep the raw formula so the renderer can re-evaluate the
            -- cursor against live scene variables every frame.
            w.cursorFormula = ev.indexFormula
        end
    elseif ev.type == "focus_window" then
        state.focusedWindow = ev.windowId
    end
end

function scene_host.runHook(hookName, ctx)
    if #sceneStack == 0 then return false end
    local state = sceneStack[#sceneStack]

    local sceneData = getSceneData(ctx, state.id)
    if not sceneData or not sceneData.hooks then
        return false -- No data or no hooks for this scene, fallback
    end

    local cmds = sceneData.hooks[hookName]
    if not cmds then
        return false -- Hook is absent, fallback to legacy Lua block
    end

    -- We have a hook, execute it in immediate mode
    -- Ensure ctx.v is scoped to the scene instance
    ctx.v = state.v

    -- Expose the scene definition generically so SCRIPT commands can read
    -- scene config and scene-local named scripts (D13) — no per-kind context.
    ctx.scene = sceneData

    -- Reset cascade guard: sequential IF blocks check v._guard == 0
    -- and set v._guard = 1 when they match, preventing state cascades
    -- (e.g. IF v.state==1 sets state=2, then IF v.state==2 fires immediately)
    state.v._guard = 0

    -- Save old events list to avoid accumulating transition events across nested hook/push calls
    local oldEvents = ctx.events
    local oldHookHandled = ctx.hookHandled
    local oldHookFallback = ctx.hookFallback
    ctx.events = {}
    ctx.hookHandled = false
    ctx.hookFallback = false

    local events = interpreter.runImmediate(cmds, ctx)

    -- Consume SCENE_EVENT (scene_change) and update the stack
    -- Wait to process these until after the loop so we don't recurse deeply
    -- or mutate sceneStack while iterating.
    local transitions = {}
    if events then
        for _, ev in ipairs(events) do
            if ev.type == "wait" then
                state.waitTimer = ev.duration
            elseif ev.type == "scene_change" then
                table.insert(transitions, ev)
            elseif ev.type == "open_window" or ev.type == "close_window"
                or ev.type == "set_list" or ev.type == "set_text"
                or ev.type == "set_cursor" or ev.type == "focus_window" then
                applyWindowEvent(state, ev)
            end
        end
    end

    -- If there was an old events list, append the new events to it
    -- so that the caller (like the golden harness) can still see them.
    if oldEvents then
        for _, ev in ipairs(events) do
            table.insert(oldEvents, ev)
        end
        ctx.events = oldEvents
    end

    for _, ev in ipairs(transitions) do
        if ev.kind == "pop" then
            scene_host.pop(ctx)
        elseif ev.kind == "push" and ev.scene then
            scene_host.push(ev.scene, ctx, ev.vars)
        elseif ev.kind == "goto" and ev.scene then
            scene_host.goto_scene(ev.scene, ctx, ev.vars)
        end
    end

    local fallback = ctx.hookFallback
    ctx.hookHandled = oldHookHandled
    ctx.hookFallback = oldHookFallback
    return not fallback
end

-- vars (optional): pre-resolved values from a SCENE_EVENT push/goto, seeded
-- into the new scene's v BEFORE on_enter so its setup hooks can read them
-- (e.g. the ritual scene's ritualMode/targetIndex).
function scene_host.push(id, ctx, vars)
    ctx = ctx or lastCtx
    if id == "dialogue" then
        _G.dialogueEnterTime = love.timer.getTime()
    end
    table.insert(sceneStack, {
        id = id,
        v = {},
        waitTimer = 0,
        windows = {},
        focusedWindow = nil
    })
    if vars then
        local pushed = sceneStack[#sceneStack]
        for k, val in pairs(vars) do pushed.v[k] = val end
    end

    local state = sceneStack[#sceneStack]
    local sceneData = getSceneData(ctx, id)

    -- Merge registered window definitions for this scene's kind
    if sceneData and sceneData.kind then
        -- Let the scene module (engine/scenes/<kind>.lua, if one exists)
        -- register its window defs first. Resolved generically by kind —
        -- no per-kind hardcoding (D13); kinds without a module are fine.
        local ok, sceneModule = pcall(require, "engine.scenes." .. sceneData.kind)
        if ok and type(sceneModule) == "table" and sceneModule.registerKindWindows then
            sceneModule.registerKindWindows(scene_host)
        end
        -- Merge any stored window definitions into the scene state
        local kindDefs = windowDefsByKind[sceneData.kind]
        if kindDefs then
            for k, v in pairs(kindDefs) do
                state.windows[k] = v
            end
        end
    end

    if sceneData and sceneData.anim and sceneData.anim.enter then
        local enterAnim = sceneData.anim.enter
        scene_transition.start("enter", enterAnim.effect or "fade", enterAnim.duration or 0.2, enterAnim.color)
    end

    if ctx then
        scene_host.runHook("on_enter", ctx)
    end
end

function scene_host.pop(ctx)
    ctx = ctx or lastCtx
    if #sceneStack > 0 then
        local state = sceneStack[#sceneStack]
        local sceneData = getSceneData(ctx, state.id)
        if sceneData and sceneData.anim and sceneData.anim.exit then
            local exitAnim = sceneData.anim.exit
            scene_transition.start("exit", exitAnim.effect or "fade", exitAnim.duration or 0.15, exitAnim.color)
        end
        if ctx then
            scene_host.runHook("on_exit", ctx)
        end
        table.remove(sceneStack)
    end
end

function scene_host.goto_scene(id, ctx, vars)
    scene_host.pop(ctx)
    scene_host.push(id, ctx, vars)
end

function scene_host.update(dt, ctx)
    scene_host.rememberCtx(ctx)
    scene_transition.update(dt)

    if #sceneStack > 0 then
        local state = sceneStack[#sceneStack]
        if state.waitTimer and state.waitTimer > 0 then
            state.waitTimer = math.max(0, state.waitTimer - dt)
            if state.waitTimer > 0 then return true end
        end
    end
    -- The hook runs runImmediate which takes ctx.
    return scene_host.runHook("on_frame", ctx)
end

-- Menu-style windows scenes reached from exploring (dialogue, shop, status,
-- ...) can opt into showing the 3D map behind their windows instead of a
-- blank canvas ("backdrop": "map" in scenes.json) — a VN-style overlay
-- rather than a scene swap. Guarded on real map state existing: the
-- deterministic golden-ui harness session never calls exploration.loadMap,
-- so this silently no-ops there rather than erroring the smoke test.
local function drawBackdrop(sceneData, ctx)
    if sceneData.backdrop ~= "map" then return end
    local session = ctx.session
    if not (session and session.currentMapData and session.mapGrid) then return end
    require("presentation.viewport_3d").draw(session)
end

function scene_host.draw(ctx)
    -- Declarative drawing is opt-in per scene ("draw": "windows" in
    -- scenes.json). Scenes without the flag fall back to legacy Lua drawing
    -- (SPEC S2 fallback rule), so conversions stay independently shippable.
    if #sceneStack == 0 then return false end
    local state = sceneStack[#sceneStack]
    local sceneData = getSceneData(ctx, state.id)
    if not sceneData or sceneData.draw ~= "windows" then
        scene_transition.draw()
        return false
    end
    drawBackdrop(sceneData, ctx)
    local window_renderer = require("presentation.window_renderer")
    window_renderer.draw(state, sceneData, ctx)
    scene_transition.draw()
    return true
end

function scene_host.keypressed(key, ctx)
    -- Raw key capture (e.g. the `controls` scene rebinding a button):
    -- while the current scene's v._capturingKey is set, the very next
    -- physical key -- WASD/arrows/escape included -- is routed to a
    -- scene-local on_raw_key hook instead of normal WASD-normalize +
    -- hook dispatch below. Scoped to this one need; not a generic hook.
    if #sceneStack > 0 then
        local state = sceneStack[#sceneStack]
        if state.v and state.v._capturingKey then
            local sceneData = getSceneData(ctx, state.id)
            if sceneData and sceneData.hooks and sceneData.hooks.on_raw_key then
                ctx.v = state.v
                ctx.v.rawKey = key
                return scene_host.runHook("on_raw_key", ctx)
            end
        end
    end

    -- Normalize WASD to arrow key names
    if key == "w" then key = "up"
    elseif key == "s" then key = "down"
    elseif key == "a" then key = "left"
    elseif key == "d" then key = "right"
    end

    -- Resolve the physical key to a logical SNES button via the rebindable
    -- input map, then to the existing hook that button drives. Defaults
    -- (data/input.json) reproduce the previous hardcoded mapping exactly.
    local button = input_map.resolveHook(key)
    if not button then
        return false
    end
    local hookName = input_map.BUTTON_TO_HOOK[button]
    if not hookName then
        -- X, Y, SELECT: bound but no game hook consumes them yet.
        return false
    end
    -- Page-flip hook for scenes with multiple info pages (e.g. the
    -- ritual scene's stats/art pages). Scenes that don't define it
    -- fall through unhandled, as with any absent hook.
    return scene_host.runHook(hookName, ctx)
end

return scene_host
