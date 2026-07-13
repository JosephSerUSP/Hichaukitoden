local interpreter = require("engine.interpreter")

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

-- Fallback mapping for legacy string IDs to scene objects where possible
local function resolveSceneId(id)
    return id
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
            scene_host.push(ev.scene, ctx)
            if ev.vars then
                local pushed = sceneStack[#sceneStack]
                if pushed then
                    for k, val in pairs(ev.vars) do pushed.v[k] = val end
                end
            end
        elseif ev.kind == "goto" and ev.scene then
            scene_host.goto_scene(ev.scene, ctx)
            if ev.vars then
                local pushed = sceneStack[#sceneStack]
                if pushed then
                    for k, val in pairs(ev.vars) do pushed.v[k] = val end
                end
            end
        end
    end

    local fallback = ctx.hookFallback
    ctx.hookHandled = oldHookHandled
    ctx.hookFallback = oldHookFallback
    return not fallback
end

function scene_host.push(id, ctx)
    ctx = ctx or lastCtx
    table.insert(sceneStack, {
        id = resolveSceneId(id),
        v = {},
        waitTimer = 0,
        windows = {},
        focusedWindow = nil
    })

    local state = sceneStack[#sceneStack]
    local sceneData = getSceneData(ctx, id)

    -- Merge registered window definitions for this scene's kind
    if sceneData and sceneData.kind then
        -- Let the scene module register its window defs first
        if sceneData.kind == "battle" then
            local sceneModule = require("engine.scenes.battle")
            if sceneModule.registerKindWindows then
                sceneModule.registerKindWindows(scene_host)
            end
        end
        -- Merge any stored window definitions into the scene state
        local kindDefs = windowDefsByKind[sceneData.kind]
        if kindDefs then
            for k, v in pairs(kindDefs) do
                state.windows[k] = v
            end
        end
    end

    if ctx then
        scene_host.runHook("on_enter", ctx)
    end
end

function scene_host.pop(ctx)
    ctx = ctx or lastCtx
    if #sceneStack > 0 then
        if ctx then
            scene_host.runHook("on_exit", ctx)
        end
        table.remove(sceneStack)
    end
end

function scene_host.goto_scene(id, ctx)
    scene_host.pop(ctx)
    scene_host.push(id, ctx)
end

function scene_host.update(dt, ctx)
    scene_host.rememberCtx(ctx)
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

function scene_host.draw(ctx)
    -- Declarative drawing is opt-in per scene ("draw": "windows" in
    -- scenes.json). Scenes without the flag fall back to legacy Lua drawing
    -- (SPEC S2 fallback rule), so conversions stay independently shippable.
    if #sceneStack == 0 then return false end
    local state = sceneStack[#sceneStack]
    local sceneData = getSceneData(ctx, state.id)
    if not sceneData or sceneData.draw ~= "windows" then return false end
    local window_renderer = require("presentation.window_renderer")
    window_renderer.draw(state, sceneData, ctx)
    return true
end

function scene_host.keypressed(key, ctx)
    -- Normalize WASD to arrow key names
    if key == "w" then key = "up"
    elseif key == "s" then key = "down"
    elseif key == "a" then key = "left"
    elseif key == "d" then key = "right"
    end

    if key == "escape" then
        return scene_host.runHook("on_cancel", ctx)
    elseif key == "return" or key == "space" then
        return scene_host.runHook("on_select", ctx)
    elseif key == "up" then
        return scene_host.runHook("on_up", ctx)
    elseif key == "down" then
        return scene_host.runHook("on_down", ctx)
    elseif key == "left" then
        return scene_host.runHook("on_left", ctx)
    elseif key == "right" then
        return scene_host.runHook("on_right", ctx)
    end
    -- Fallback not handled
    return false
end

return scene_host
