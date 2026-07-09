local interpreter = require("engine.interpreter")

local scene_host = {}

-- State container for the active scenes
-- Each element is { id = sceneId, v = {}, windows = {}, focusedWindow = nil }
local sceneStack = {}

local function getSceneData(ctx, id)
    if not ctx or not ctx.loader or not ctx.loader.scenes then return nil end
    for _, scene in ipairs(ctx.loader.scenes) do
        -- Check numeric or string matching
        if tostring(scene.id) == tostring(id) or scene.name == id or scene.kind == id then
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
    local events = interpreter.runImmediate(cmds, ctx)

    -- Consume SCENE_EVENT (scene_change) and update the stack
    if events then
        for _, ev in ipairs(events) do
            if ev.type == "scene_change" then
                if ev.kind == "pop" then
                    scene_host.pop(ctx)
                elseif ev.kind == "push" and ev.scene then
                    scene_host.push(ev.scene, ctx)
                elseif ev.kind == "goto" and ev.scene then
                    scene_host.goto_scene(ev.scene, ctx)
                end
            elseif ev.type == "wait" then
                state.waitTimeout = ev.duration
            end
        end
    end

    return true
end

function scene_host.push(id, ctx)
    table.insert(sceneStack, {
        id = resolveSceneId(id),
        v = {},
        windows = {},
        focusedWindow = nil
    })

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
    local state = sceneStack[#sceneStack]
    if state and (state.waitTimeout or 0) > 0 then
        state.waitTimeout = state.waitTimeout - dt
        return true
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
    if key == "escape" then
        return scene_host.runHook("on_cancel", ctx)
    elseif key == "return" or key == "space" then
        return scene_host.runHook("on_select", ctx)
    end
    -- Fallback not handled
    return false
end

return scene_host
