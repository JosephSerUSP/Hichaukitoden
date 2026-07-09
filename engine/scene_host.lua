local interpreter = require("engine.interpreter")
local session = require("engine.session")
local ui = require("presentation.ui")

local scene_host = {}

scene_host.scenes = {}
scene_host.stack = {}

function scene_host.loadScenes(scenesData)
    for _, s in ipairs(scenesData or {}) do
        scene_host.scenes[s.id] = s
    end
end

function scene_host.activeScene()
    if #scene_host.stack > 0 then
        return scene_host.stack[#scene_host.stack]
    end
    return nil
end

local function runHook(hookName, fallbackFn)
    local active = scene_host.activeScene()
    if not active then return end

    local hook = active.data.hooks and active.data.hooks[hookName]
    if hook and type(hook) == "table" and #hook > 0 then
        local events = interpreter.runImmediate(hook, active.ctx)
        scene_host.processEvents(events)
    elseif fallbackFn then
        fallbackFn()
    end
end

function scene_host.processEvents(events)
    for _, ev in ipairs(events or {}) do
        if ev.type == "scene_change" then
            if ev.kind == "pop" then
                scene_host.pop()
            elseif ev.kind == "push" and ev.scene then
                scene_host.push(ev.scene, scene_host.activeScene().ctx)
            elseif ev.kind == "goto" and ev.scene then
                scene_host.goto(ev.scene, scene_host.activeScene().ctx)
            end
        end
    end
end

function scene_host.push(sceneId, ctx)
    local sceneData = scene_host.scenes[sceneId]
    if not sceneData then return end

    local v = {}

    local sceneCtx = {
        session = ctx.session,
        loader = ctx.loader,
        events = {},
        v = v
    }

    local inst = {
        id = sceneId,
        data = sceneData,
        v = v,
        ctx = sceneCtx
    }

    table.insert(scene_host.stack, inst)

    runHook("on_enter", function()
        if sceneData.kind == "crafting" and _G.initCraftingScene then
            _G.initCraftingScene()
        end
    end)
end

function scene_host.pop()
    local active = scene_host.activeScene()
    if not active then return end

    runHook("on_exit", function()
        -- Optional fallback for on_exit
    end)

    table.remove(scene_host.stack)
end

function scene_host.goto(sceneId, ctx)
    local active = scene_host.activeScene()
    if active then
        runHook("on_exit", function()
            -- Optional fallback for on_exit
        end)
        table.remove(scene_host.stack)
    end

    scene_host.push(sceneId, ctx)
end

function scene_host.update(dt)
    runHook("on_frame", function()
        local active = scene_host.activeScene()
        if active and active.data.kind == "crafting" and _G.updateCraftingScene then
            _G.updateCraftingScene(dt)
        end
    end)
end

function scene_host.draw()
    local active = scene_host.activeScene()
    if active then
        if active.data.kind == "crafting" and _G.drawCraftingScene then
            _G.drawCraftingScene()
        end
    end
end

function scene_host.keypressed(key)
    if key == "space" or key == "return" then
        runHook("on_select", function()
            local active = scene_host.activeScene()
            if active and active.data.kind == "crafting" and _G.keypressedCraftingScene then
                _G.keypressedCraftingScene(key)
            end
        end)
    elseif key == "escape" then
        runHook("on_cancel", function()
            local active = scene_host.activeScene()
            if active and active.data.kind == "crafting" and _G.keypressedCraftingScene then
                _G.keypressedCraftingScene(key)
            end
        end)
    else
        local active = scene_host.activeScene()
        if active and active.data.kind == "crafting" and _G.keypressedCraftingScene then
            _G.keypressedCraftingScene(key)
        end
    end
end

return scene_host
