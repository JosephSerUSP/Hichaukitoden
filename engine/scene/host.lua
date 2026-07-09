local interpreter = require("engine.interpreter")

local host = {
    stack = {}, -- Stack of active scene ids/names
    contexts = {}, -- Map from scene name/id to its own ctx (which holds `v` for locals)
}

function host.push(sceneIdOrName, baseCtx)
    table.insert(host.stack, sceneIdOrName)
    if not host.contexts[sceneIdOrName] then
        host.contexts[sceneIdOrName] = { v = {} }
    end
    local ctx = host.contexts[sceneIdOrName]
    -- Merge baseCtx into ctx (like session, loader, etc)
    if baseCtx then
        for k, v in pairs(baseCtx) do
            ctx[k] = v
        end
    end

    host.runHook("on_enter")
end

function host.pop()
    if #host.stack > 0 then
        host.runHook("on_exit")
        local popped = table.remove(host.stack)
        host.contexts[popped] = nil
        return popped
    end
    return nil
end

function host.clearStack()
    while #host.stack > 0 do
        host.pop()
    end
    host.contexts = {}
end

function host.getActiveScene()
    if #host.stack > 0 then
        return host.stack[#host.stack]
    end
    return nil
end

function host.runHook(hookName, args)
    local active = host.getActiveScene()
    if not active then return false end

    local ctx = host.contexts[active]
    if not ctx then return false end

    local sceneData = nil
    if ctx.loader then
        for _, s in pairs(ctx.loader.scenes or {}) do
            if s.name == active or s.id == active or s.kind == active then
                sceneData = s
                break
            end
        end
    end

    if not sceneData or not sceneData.hooks or not sceneData.hooks[hookName] then
        return false -- hook not found or scene not found, allowing fallback
    end

    -- Inject dynamic args
    if args then
        for k, v in pairs(args) do
            ctx[k] = v
        end
    end

    interpreter.runImmediate(sceneData.hooks[hookName], ctx)
    return true
end

return host
