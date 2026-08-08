local schema = {}

schema.MATCH = { physical_damage = true, magical_damage = true, hostile_status = true }
schema.MODE = { add = true, set = true, refresh = true }
schema.TRIGGER = { battle_start = true, round_start = true, round_end = true }
schema.TRAIT_AT = { battle_start = true, round_start = true }

local function posInt(v)
    return type(v) == "number" and v >= 1 and v == math.floor(v)
end

local function fail(where, message)
    error((where or "barrier") .. ": " .. message, 0)
end
schema.fail = fail

function schema.validateSpec(spec, where, opts)
    opts = opts or {}
    where = where or "barrier"
    if type(spec) ~= "table" then fail(where, "must be an object") end
    if type(spec.id) ~= "string" or spec.id == "" then fail(where, "id must be a non-empty string") end
    if not schema.MATCH[spec.match] then
        fail(where, "match '" .. tostring(spec.match) .. "' must be physical_damage, magical_damage, or hostile_status")
    end
    if not posInt(spec.stacks) then fail(where, "stacks must be a positive integer") end
    if type(spec.reduction) ~= "number" or spec.reduction <= 0 or spec.reduction > 1 then
        fail(where, "reduction must be a number in (0, 1]")
    end
    if spec.maxStacks ~= nil then
        if not posInt(spec.maxStacks) then fail(where, "maxStacks must be a positive integer when present") end
        if spec.stacks > spec.maxStacks then fail(where, "stacks cannot exceed maxStacks") end
    end
    if spec.duration ~= nil and not posInt(spec.duration) then
        fail(where, "duration must be a positive whole number of rounds when present")
    end
    local mode = spec.mode or opts.defaultMode or "add"
    if not schema.MODE[mode] then fail(where, "mode '" .. tostring(mode) .. "' must be add, set, or refresh") end
    if opts.trait then
        local at = spec.at or "battle_start"
        if not schema.TRAIT_AT[at] then fail(where, "at '" .. tostring(at) .. "' must be battle_start or round_start") end
    end
    return true
end

local function walk(node, where, seen)
    if type(node) ~= "table" then return end
    seen = seen or {}
    if seen[node] then return end
    seen[node] = true
    if node.type == "barrier" and (node.id ~= nil or node.match ~= nil or node.stacks ~= nil) then
        schema.validateSpec(node, where .. " barrier effect")
    elseif node.code == "BARRIER_GRANT" then
        schema.validateSpec(node, where .. " BARRIER_GRANT trait", { trait = true, defaultMode = "set" })
    elseif node.cmd == "BARRIER" then
        schema.validateSpec(node, where .. " BARRIER command")
    elseif node.cmd == "BARRIER_SYNC" and not schema.TRIGGER[node.trigger] then
        fail(where .. " BARRIER_SYNC command", "trigger '" .. tostring(node.trigger) .. "' must be battle_start, round_start, or round_end")
    end
    if (node.type == "hp_damage" or node.type == "hp_drain") and node.damageKind ~= nil
            and node.damageKind ~= "physical_damage" and node.damageKind ~= "magical_damage" then
        fail(where .. " damage effect", "damageKind '" .. tostring(node.damageKind) .. "' must be physical_damage or magical_damage")
    end
    for key, value in pairs(node) do
        if type(value) == "table" then walk(value, where .. "." .. tostring(key), seen) end
    end
end

function schema.validateData(loader)
    local roots = {
        actors = loader.actors, items = loader.items, skills = loader.skills,
        passives = loader.passives, states = loader.states, flows = loader.flows,
        troops = loader.troops, commonEvents = loader.commonEvents,
        actionSequences = loader.actionSequences, maps = loader.maps, scenes = loader.scenes,
    }
    for name, root in pairs(roots) do walk(root, name, {}) end
    return true
end

return schema
