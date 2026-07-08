local interpreter = require("engine.interpreter")
local scene_host = {}

scene_host.active_scenes = {} -- Scene stack

function scene_host.clearStack()
    scene_host.active_scenes = {}
end

function scene_host.getActiveScene()
    if #scene_host.active_scenes > 0 then
        return scene_host.active_scenes[#scene_host.active_scenes]
    end
    return nil
end

function scene_host.processSceneEvents(events, session)
    if not events then return end
    for _, ev in ipairs(events) do
        if ev.type == "scene_change" then
            if ev.kind == "push" and ev.scene then
                scene_host.push(ev.scene, session)
            elseif ev.kind == "pop" then
                scene_host.pop(session)
            elseif ev.kind == "goto" and ev.scene then
                scene_host.gotoScene(ev.scene, session)
            end
        end
    end
end

function scene_host.runHook(hookName, session)
    local active = scene_host.getActiveScene()
    if not active then return false end

    if active.data.hooks and active.data.hooks[hookName] then
        -- Run the immediate-mode commands
        local ctx = {
            session = session,
            v = active.v,
            scene = active.data
        }
        local events = interpreter.runImmediate(active.data.hooks[hookName], ctx)
        scene_host.processSceneEvents(events, session)
        return true -- Hook existed and ran
    end

    return false -- Hook not found
end

function scene_host.push(sceneId, session)
    -- Don't allow pushing the exact same scene that is already active
    local current = scene_host.getActiveScene()
    if current and current.id == sceneId then return false end

    local sceneData = nil
    for _, s in ipairs(session.loader.scenes or {}) do
        if tostring(s.id) == tostring(sceneId) or s.kind == sceneId then
            sceneData = s
            break
        end
    end
    if not sceneData then return false end

    table.insert(scene_host.active_scenes, {
        id = sceneData.id,
        data = sceneData,
        v = {} -- Scene-scoped variables
    })

    scene_host.runHook("on_enter", session)
    return true
end

function scene_host.pop(session)
    if #scene_host.active_scenes > 0 then
        scene_host.runHook("on_exit", session)
        table.remove(scene_host.active_scenes)
        return true
    end
    return false
end

function scene_host.gotoScene(sceneId, session)
    if #scene_host.active_scenes > 0 then
        scene_host.runHook("on_exit", session)
        table.remove(scene_host.active_scenes)
    end
    return scene_host.push(sceneId, session)
end

function scene_host.update(dt, session)
    local ran = scene_host.runHook("on_frame", session)
    if not ran then
        local active = scene_host.getActiveScene()
        if active and active.data.kind == "crafting" then
            if updateCraftingScene then updateCraftingScene(dt) end
        end
    end
end

function scene_host.draw(session)
    -- on_frame represents the loop, there is no on_draw hook
    local active = scene_host.getActiveScene()
    if active and active.data.kind == "crafting" then
        if drawCraftingScene then drawCraftingScene() end
    end
end

function scene_host.keypressed(key, session)
    if key == "space" or key == "return" then
        local ran = scene_host.runHook("on_select", session)
        if ran then return end
    elseif key == "escape" then
        local ran = scene_host.runHook("on_cancel", session)
        if ran then return end
    end

    local active = scene_host.getActiveScene()
    if active and active.data.kind == "crafting" then
        if keypressedCraftingScene then keypressedCraftingScene(key) end
    end
end

return scene_host
