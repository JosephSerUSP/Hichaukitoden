local schema = require("engine.barrier_schema")
local registry = {}

local function addOnce(list, def, key)
    for _, existing in ipairs(list or {}) do
        if existing[key] == def[key] then return end
    end
    table.insert(list, def)
end

local function addParam(effectTypes, effectId, param)
    for _, def in ipairs(effectTypes or {}) do
        if def.id == effectId then
            def.params = def.params or {}
            for _, existing in ipairs(def.params) do if existing == param then return end end
            table.insert(def.params, param)
            return
        end
    end
end

function registry.installEngine(engine, ext)
    if type(engine) ~= "table" or type(ext) ~= "table" then return end
    engine.effectTypes, engine.traitCodes, engine.commands = engine.effectTypes or {}, engine.traitCodes or {}, engine.commands or {}
    if ext.effectType then addOnce(engine.effectTypes, ext.effectType, "id") end
    if ext.traitCode then addOnce(engine.traitCodes, ext.traitCode, "code") end
    for _, def in ipairs(ext.commands or {}) do addOnce(engine.commands, def, "id") end
    for _, effectId in ipairs(ext.damageKindEffects or {}) do addParam(engine.effectTypes, effectId, "damageKind") end
end

local function insertAt(list, hook, phase)
    if hook.before or hook.after then
        local anchor = hook.before or hook.after
        for i, cmd in ipairs(list) do
            if cmd.cmd == anchor then return hook.before and i or i + 1 end
        end
        schema.fail("barriers.json flowHooks", "phase '" .. phase .. "' cannot find anchor command '" .. tostring(anchor) .. "'")
    end
    return #list + 1
end

function registry.installFlows(flows, ext)
    if type(flows) ~= "table" or type(ext) ~= "table" then return end
    for phase, hook in pairs(ext.flowHooks or {}) do
        local host, name = tostring(phase):match("^([^%.]+)%.(.+)$")
        if not host or type(flows[host]) ~= "table" or type(flows[host][name]) ~= "table" then
            schema.fail("barriers.json flowHooks", "references missing phase '" .. tostring(phase) .. "'")
        end
        local commands = hook.commands or hook
        local at = insertAt(flows[host][name], hook, phase)
        for offset, cmd in ipairs(commands or {}) do
            table.insert(flows[host][name], at + offset - 1, cmd)
        end
    end
end

return registry
