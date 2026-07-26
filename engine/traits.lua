local config = require("engine.config")

local traits = {}

-- Level-growth tuning from data/system.json (system.growth), editable in the
-- editor's System tab; engine defaults keep old saves/data working.
local function growthConf(key, default)
    local g = config.growth
    if g and g[key] ~= nil then return g[key] end
    return default
end

-- Parameters that receive level growth. mpd, mxa and mxp are absent on purpose:
-- MPD is a form-defined expedition cost and the capacities are form-defined
-- limits, and none of the three grows with level (creature-parameters.md). MPD
-- used to grow at 0.05 per level, which quietly made every creature more
-- expensive to keep manifested the longer you raised it -- the exact opposite
-- of the economy the design describes, where an early form stays cheap and
-- promotion is what costs you.
local GROWTH_PARAMS = {
    maxHp = true, atk = true, def = true, mat = true, mdf = true
}

local function numberOr(value, fallback)
    return type(value) == "number" and value or fallback
end

local function actorBaseParam(data, paramName)
    local params = data.baseParams or {}
    return params[paramName]
end

-- Returns a list of all trait objects currently active on a battler.
-- Each entry also carries provenance (`source`, plus `slot`/`item`/`id` where
-- applicable) so callers that must act on the SOURCE rather than just sum a
-- value can find it -- e.g. a death ward that destroys the equipment which
-- saved the creature (see traits.findSource).
function traits.getActiveObjects(battler, session)
    local objs = {}

    -- 1. Innate actor data
    table.insert(objs, {
        traits = battler.actorData.traits or {},
        condition = nil,
        source = "actor"
    })

    -- 2. Passives
    for _, passiveId in ipairs(battler.passives) do
        local passive = session.loader.getPassive(passiveId)
        if passive then
            table.insert(objs, {
                traits = passive.traits or {},
                condition = passive.condition,
                source = "passive",
                id = passiveId
            })
        end
    end

    -- 3. Equipment
    for i = 1, 3 do
        local eq = battler.equipment[i]
        if eq then
            table.insert(objs, {
                traits = eq.traits or {},
                condition = eq.condition,
                source = "equipment",
                slot = i,
                item = eq
            })
        end
    end
    
    -- 4. States
    for _, stateInfo in ipairs(battler.states) do
        local state = session.loader.getState(stateInfo.id)
        if state then
            table.insert(objs, {
                traits = state.traits or {},
                condition = state.condition,
                source = "state",
                id = stateInfo.id
            })
        end
    end

    return objs
end

-- Every ACTIVE trait with `traitCode`, as a list of { trait = <trait>,
-- source = <getActiveObjects entry> } in getActiveObjects order (actor,
-- passives, equipment, states).
--
-- Unlike getRate (which sums values across every source), this exists for
-- one-shot triggers whose SOURCE matters -- notably ON_PERMADEATH death wards,
-- where the engine must know which equipment slot to break, and must choose
-- BETWEEN candidates rather than take the first one found (see
-- interpreter.lua's resolveWard: a free innate relic should save the creature
-- before a consumable amulet is destroyed).
function traits.findAllSources(battler, traitCode, session)
    local found = {}
    for _, obj in ipairs(traits.getActiveObjects(battler, session)) do
        if traits.evaluateCondition(obj.condition, battler, session) then
            for _, t in ipairs(obj.traits) do
                if t.code == traitCode then
                    table.insert(found, { trait = t, source = obj })
                end
            end
        end
    end
    return found
end

-- Evaluates if a condition is met
function traits.evaluateCondition(condition, battler, session)
    if not condition then return true end
    
    -- HP-based conditions
    if condition:match("HP%s*<%s*(%d+)%%") then
        local pct = tonumber(condition:match("HP%s*<%s*(%d+)%%"))
        if (battler.hp / traits.getParam(battler, "maxHp", session)) * 100 < pct then
            return true
        end
        return false
    end
    
    -- Default fallback
    return false
end

-- Get a base parameter from the actor's base design
function traits.getBaseParam(battler, paramName)
    local data = battler.actorData
    local defaults = config.growth and config.growth.baseParams or {}
    local base = actorBaseParam(data, paramName)
    if base == nil then
        if paramName == "maxHp" then
            base = numberOr(defaults.maxHp, growthConf("statBase", 10))
        elseif paramName == "mpd" then
            base = numberOr(defaults.mpd, 2)
        elseif paramName == "mxa" then
            base = numberOr(defaults.mxa, 4)
        elseif paramName == "mxp" then
            base = numberOr(defaults.mxp, 2)
        else
            base = numberOr(defaults[paramName], growthConf("statBase", 10))
        end
    end

    if not GROWTH_PARAMS[paramName] then return base end

    -- Growth is ACCUMULATED, not recalculated. `battler.growth` holds the sum
    -- of the seeded packets this instance has actually received (engine/
    -- growth.lua), so a creature's past is a thing it owns rather than a curve
    -- re-derived from its current species every time the value is read.
    --
    -- That distinction is the whole point: under the old smooth formula there
    -- was nothing for a promotion to preserve, because changing the species
    -- silently re-derived every level the creature had ever gained.
    local gained = battler.growth and battler.growth[paramName]
    if gained == nil then
        -- No accumulated record (an enemy built for one battle, a preview, a
        -- save from before growth was seeded): replay the history the seed
        -- describes rather than inventing one. Same answer, every time.
        local growthMod = require("engine.growth")
        gained = growthMod.accumulate(data,
            battler.growthSeed or growthMod.defaultSeed(data),
            battler.level or 1)[paramName] or 0
    end
    return base + gained
end

-- Get a final parameter value after applying all traits
function traits.getParam(battler, paramName, session)
    local base = traits.getBaseParam(battler, paramName)
    local plus = battler.paramPlus and (battler.paramPlus[paramName] or 0) or 0
    local rate = 1.0
    
    local activeObjects = traits.getActiveObjects(battler, session)
    for _, obj in ipairs(activeObjects) do
        if traits.evaluateCondition(obj.condition, battler, session) then
            for _, t in ipairs(obj.traits) do
                if t.code == "PARAM_PLUS" and t.dataId == paramName then
                    plus = plus + t.value
                elseif t.code == "PARAM_RATE" and t.dataId == paramName then
                    rate = rate * t.value
                end
            end
        end
    end
    
    return math.max(1, math.floor(base * rate + plus))
end

-- The battler's effective elements. ELEMENT_CHANGE traits (from equipment,
-- passives or states) replace the actor's innate list while active; ELEMENT_ADD
-- traits then append to whatever the base resolved to, deepening an existing
-- alignment or adding a new one.
--
-- Note this is the EFFECTIVE list, which is what battle wants. Item Creation
-- deliberately reads `actorData.elements` directly instead: a creature's
-- crafting identity is what it is, not what it is wearing, or a bag of
-- element-swapping trinkets would collapse the whole crafter roster into one.
function traits.getElements(battler, session)
    local override, added = nil, nil
    local activeObjects = traits.getActiveObjects(battler, session)
    for _, obj in ipairs(activeObjects) do
        if traits.evaluateCondition(obj.condition, battler, session) then
            for _, t in ipairs(obj.traits) do
                if t.code == "ELEMENT_CHANGE" and t.dataId then
                    override = override or {}
                    table.insert(override, t.dataId)
                elseif t.code == "ELEMENT_ADD" and t.dataId then
                    added = added or {}
                    table.insert(added, t.dataId)
                end
            end
        end
    end

    local base = override or (battler.actorData and battler.actorData.elements) or {}
    if not added then return base end

    local out = {}
    for _, e in ipairs(base) do table.insert(out, e) end
    for _, e in ipairs(added) do table.insert(out, e) end
    return out
end

-- Get rate modifiers (e.g. HIT, EVA, CRI, HRG)
function traits.getRate(battler, traitCode, session)
    local sum = 0
    local activeObjects = traits.getActiveObjects(battler, session)
    for _, obj in ipairs(activeObjects) do
        if traits.evaluateCondition(obj.condition, battler, session) then
            for _, t in ipairs(obj.traits) do
                if t.code == traitCode then
                    sum = sum + t.value
                end
            end
        end
    end
    
    -- Special defaults
    if traitCode == "HIT" then
        return 1.0 + sum -- Base hit rate is 100%
    elseif traitCode == "EVA" then
        return 0.0 + sum -- Base evasion is 0%
    elseif traitCode == "CRI" then
        return 0.05 + sum -- Base crit rate is 5%
    elseif traitCode == "HRG" then
        return 0.0 + sum -- HP regeneration
    end
    return sum
end

return traits
