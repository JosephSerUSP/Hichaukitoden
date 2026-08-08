-- Stack barriers (#165): a generic combat-state resource, neutral to element,
-- skill name and creature. The authored vocabulary (barrier effect, BARRIER /
-- BARRIER_SYNC commands, BARRIER_GRANT trait) lives in data/engine.json, and the
-- battle lifecycle hooks are ordinary authored phases in data/flows.json. This
-- module owns only the runtime semantics.
local traits = require("engine.traits")
local schema = require("engine.barrier_schema")
local barriers = {
    validateSpec = schema.validateSpec,
    validateData = schema.validateData,
}

local function store(target)
    if not target then return nil end
    target.barriers = target.barriers or {}
    return target.barriers
end

local function ids(t)
    local out = {}
    for id in pairs(t or {}) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function event(kind, target, b, before, mode)
    return {
        type = kind, target = target, barrier = b.id, match = b.match,
        mode = mode, before = before, stacks = b.stacks, maxStacks = b.maxStacks,
        reduction = b.reduction, duration = b.remainingRounds,
    }
end

function barriers.grant(target, spec, session, context)
    if not target then return {} end
    schema.validateSpec(spec, "runtime barrier")
    local t = store(target)
    local id = tostring(spec.id)
    local current = t[id]
    local before = current and current.stacks or 0
    local mode = spec.mode or "add"
    local after = mode == "set" and spec.stacks
        or mode == "refresh" and math.max(before, spec.stacks)
        or before + spec.stacks
    if spec.maxStacks then after = math.min(after, spec.maxStacks) end
    local b = current or { id = id }
    b.match = spec.match
    b.stacks = math.floor(after)
    b.reduction = spec.reduction
    b.maxStacks = spec.maxStacks and math.floor(spec.maxStacks) or nil
    b.remainingRounds = spec.duration and math.floor(spec.duration) or nil
    b.lastTickRound = context and context.battle and context.battle.round or nil
    t[id] = b
    return { event(current and "barrier_refresh" or "barrier_grant", target, b, before, mode) }
end

function barriers.get(target, id)
    return target and target.barriers and target.barriers[tostring(id)] or nil
end

-- Does this target carry a live barrier for `match`? Callers use this to decide
-- whether to interpose on a hit at all: with no matching barrier there is
-- nothing to absorb, and the hit must take the ordinary path untouched.
function barriers.has(target, match)
    for _, b in pairs((target and target.barriers) or {}) do
        if b.match == match and (b.stacks or 0) > 0 then return true end
    end
    return false
end

function barriers.reset(target)
    if target then target.barriers = {} end
end

function barriers.consume(target, match)
    local t = target and target.barriers
    if not t then return nil, {} end
    for _, id in ipairs(ids(t)) do
        local b = t[id]
        if b and b.match == match and b.stacks > 0 then
            local before = b.stacks
            b.stacks = b.stacks - 1
            local used = event("barrier_consume", target, b, before, "consume")
            local events = { used }
            if b.stacks <= 0 then
                t[id] = nil
                events[#events + 1] = {
                    type = "barrier_break", target = target, barrier = b.id,
                    match = b.match, reduction = b.reduction,
                }
            end
            return b, events, used
        end
    end
    return nil, {}
end

function barriers.tick(target, round)
    local events, t = {}, target and target.barriers
    if not t then return events end
    for _, id in ipairs(ids(t)) do
        local b = t[id]
        if b and b.remainingRounds ~= nil and (round == nil or b.lastTickRound ~= round) then
            b.remainingRounds = b.remainingRounds - 1
            b.lastTickRound = round
            if b.remainingRounds <= 0 then
                t[id] = nil
                events[#events + 1] = {
                    type = "barrier_expire", target = target, barrier = b.id,
                    match = b.match, stacks = b.stacks, reduction = b.reduction,
                }
            end
        end
    end
    return events
end

local function traitSpec(tr, trigger)
    return {
        id = tr.id, match = tr.match, stacks = tr.stacks, reduction = tr.reduction,
        maxStacks = tr.maxStacks, duration = tr.duration,
        mode = tr.mode or (trigger == "round_start" and "refresh" or "set"),
    }
end

function barriers.sync(target, trigger, session, context)
    if not target then return {} end
    if not schema.TRIGGER[trigger] then
        schema.fail("runtime BARRIER_SYNC", "unknown trigger '" .. tostring(trigger) .. "'")
    end
    if trigger == "battle_start" then barriers.reset(target) end
    if trigger == "round_end" then
        return barriers.tick(target, context and context.battle and context.battle.round or nil)
    end
    local events = {}
    for _, found in ipairs(traits.findAllSources(target, "BARRIER_GRANT", session)) do
        local tr = found.trait
        if (tr.at or "battle_start") == trigger then
            for _, ev in ipairs(barriers.grant(target, traitSpec(tr, trigger), session, context)) do
                events[#events + 1] = ev
            end
        end
    end
    return events
end

function barriers.isHostileState(loader, stateId)
    local state = loader and loader.getState and loader.getState(stateId)
    for _, category in ipairs((state and state.categories) or {}) do
        if category == "negative" then return true end
    end
    return false
end

return barriers
