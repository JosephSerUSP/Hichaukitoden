local interpreter = require("engine.interpreter")
local scene = {}

local sceneStack = {}
local activeScene = nil

-- Scene Host loop & context
function scene.init()
    sceneStack = {}
    activeScene = nil
end

function scene.getActive()
    return activeScene
end

function scene.push(ctx, id)
    local loader = ctx.loader or (ctx.session and ctx.session.loader)
    local sceneData = loader and loader.getScene and loader.getScene(id) or (loader.scenesById and loader.scenesById[id])
    if not sceneData then
        error("scene.push: unknown scene id " .. tostring(id))
    end

    local newScene = {
        id = id,
        data = sceneData,
        v = {}, -- Scene-local variables (S2) scoped to the instance
        ctx = {
            session = ctx.session,
            loader = loader,
            events = {}
        }
    }

    -- Link scene-local v to its ctx
    newScene.ctx.v = newScene.v

    table.insert(sceneStack, newScene)
    activeScene = newScene

    -- Fire on_enter
    return scene.runHook("on_enter")
end

function scene.pop()
    if #sceneStack > 0 then
        scene.runHook("on_exit")
        table.remove(sceneStack)
        activeScene = sceneStack[#sceneStack]
        if activeScene then
            scene.runHook("on_enter") -- or maybe on_resume? S2 just says on_enter
        end
    end
end

function scene.runHook(hookName)
    if not activeScene then return false end

    local hooks = activeScene.data.hooks
    local cmds = hooks and hooks[hookName]

    if cmds and #cmds > 0 then
        -- Run data hook via immediate mode
        interpreter.runImmediate(cmds, activeScene.ctx)
        return true
    end
    -- Fallback to legacy Lua block
    return false
end

function scene.update(dt)
    if not activeScene then return false end
    activeScene.ctx.dt = dt
    return scene.runHook("on_frame")
end

function scene.keypressed(key)
    if not activeScene then return false end

    if key == "escape" then
        if scene.runHook("on_cancel") then
            return true
        end
    elseif key == "space" or key == "return" then
        if scene.runHook("on_select") then
            return true
        end
    end
    return false
end

return scene
