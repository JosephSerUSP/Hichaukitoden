local interpreter = require("engine.interpreter")

local SceneHost = {}
SceneHost.__index = SceneHost

function SceneHost.new(session, loader, sceneData)
    local self = setmetatable({}, SceneHost)
    self.session = session
    self.loader = loader
    self.sceneData = sceneData

    -- v: Scene-local variables, scoped to this scene instance.
    self.v = {}

    -- Context passed to runImmediate
    self.ctx = {
        session = session,
        loader = loader,
        v = self.v,
        hostCtx = "scene"
    }

    return self
end

function SceneHost:runHook(hookName, ...)
    local hooks = self.sceneData and self.sceneData.hooks
    if hooks and hooks[hookName] then
        interpreter.runImmediate(hooks[hookName], self.ctx)
        return true
    end

    -- Fallback rule: if the hook is absent, run the legacy Lua block
    local kind = self.sceneData and self.sceneData.kind
    if kind then
        -- Capitalize kind for camelCase functions (e.g. "crafting" -> "Crafting")
        local CamelKind = kind:sub(1, 1):upper() .. kind:sub(2)
        if hookName == "on_frame" then
            local funcName = "update" .. CamelKind .. "Scene"
            if _G[funcName] then
                _G[funcName](...)
                return true
            end
        elseif hookName == "on_draw" then
            local funcName = "draw" .. CamelKind .. "Scene"
            if _G[funcName] then
                _G[funcName](...)
                return true
            end
        elseif hookName == "on_keypressed" then
            local funcName = "keypressed" .. CamelKind .. "Scene"
            if _G[funcName] then
                _G[funcName](...)
                return true
            end
        end
    end

    return false
end

function SceneHost:enter()
    self:runHook("on_enter")
end

function SceneHost:exit()
    self:runHook("on_exit")
end

function SceneHost:select(...)
    self:runHook("on_select", ...)
end

function SceneHost:cancel(...)
    self:runHook("on_cancel", ...)
end

function SceneHost:update(dt)
    self.ctx.dt = dt
    self:runHook("on_frame", dt)
end

function SceneHost:draw()
    self:runHook("on_draw")
end

function SceneHost:keypressed(key)
    self.ctx.key = key
    self:runHook("on_keypressed", key)
end

return {
    SceneHost = SceneHost
}
