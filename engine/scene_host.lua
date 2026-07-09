local interpreter = require("engine.interpreter")
local formula = require("engine.formula")

local scene_host = {}

-- State container for the active scenes
-- Each element is { id = sceneId, v = {}, windows = {}, focusedWindow = nil }
local sceneStack = {}

-- Window definitions registered by kind (via scene_host.register).
-- Populated by calling registerKindWindows from scene modules.
-- Keyed by kind string (e.g. "crafting"), value is a table of window defs.
local windowDefsByKind = {}

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
-- Called by scene modules (e.g. crafting.registerKindWindows) during push.
-- Stored defs are merged into the scene state's windows table on push.
function scene_host.register(kind, windowDefs)
    windowDefsByKind[kind] = windowDefs
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

    -- Reset cascade guard: sequential IF blocks check v._guard == 0
    -- and set v._guard = 1 when they match, preventing state cascades
    -- (e.g. IF v.state==1 sets state=2, then IF v.state==2 fires immediately)
    state.v._guard = 0

    -- Set up crafting-specific formula context if applicable
    if sceneData and sceneData.kind == "crafting" and ctx.loader then
        local loader = ctx.loader
        if state.v.i1Id and state.v.i1Id > 0 then
            local item = loader.getItem(state.v.i1Id)
            if item then ctx.ingredient1 = formula.itemView(item) end
        end
        if state.v.i2Id and state.v.i2Id > 0 then
            local item = loader.getItem(state.v.i2Id)
            if item then ctx.ingredient2 = formula.itemView(item) end
        end
        if state.v.crafterIdx and ctx.party then
            local crafter = ctx.party[state.v.crafterIdx]
            if crafter then
                ctx.crafter = formula.battlerView(crafter, ctx.session)
            end
        end
        local config = sceneData.config or {}
        ctx.alpha = config.alpha or 0.5
        if state.v.S ~= nil then ctx.S = state.v.S end
    end

    -- Save old events list to avoid accumulating transition events across nested hook/push calls
    local oldEvents = ctx.events
    ctx.events = {}

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
        elseif ev.kind == "goto" and ev.scene then
            scene_host.goto_scene(ev.scene, ctx)
        end
    end

    return true
end

function scene_host.push(id, ctx)
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
        if sceneData.kind == "crafting" then
            local sceneModule = require("engine.scenes.crafting")
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
    -- The drawing will be managed by scene hooks or windowLayout in D2.
    -- For D1, return false so we always fall back to legacy drawing.
    return false
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
