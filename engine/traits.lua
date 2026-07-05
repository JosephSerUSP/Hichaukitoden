local traits = {}

-- Returns a list of all trait objects currently active on a battler
function traits.getActiveObjects(battler, session)
    local objs = {}
    
    -- 1. Innate actor data
    table.insert(objs, {
        traits = battler.actorData.traits or {},
        condition = nil
    })
    
    -- 2. Passives
    for _, passiveId in ipairs(battler.passives) do
        local passive = session.loader.getPassive(passiveId)
        if passive then
            table.insert(objs, {
                traits = passive.traits or {},
                condition = passive.condition
            })
        end
    end
    
    -- 3. Equipment
    for i = 1, 3 do
        local eq = battler.equipment[i]
        if eq then
            table.insert(objs, {
                traits = eq.traits or {},
                condition = eq.condition
            })
        end
    end
    
    -- 4. States
    for _, stateInfo in ipairs(battler.states) do
        local state = session.loader.getState(stateInfo.id)
        if state then
            table.insert(objs, {
                traits = state.traits or {},
                condition = state.condition
            })
        end
    end
    
    return objs
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
    end
    
    -- Default fallback
    return false
end

-- Get a base parameter from the actor's base design
function traits.getBaseParam(battler, paramName)
    local data = battler.actorData
    if paramName == "maxHp" then
        -- Scale Max HP with level
        local base = data.maxHp or 10
        return math.floor(base + (battler.level - 1) * (base * 0.15))
    elseif paramName == "atk" then
        return 10 + (battler.level - 1) * 0.5
    elseif paramName == "def" then
        return 10 + (battler.level - 1) * 0.5
    elseif paramName == "mat" then
        return 10 + (battler.level - 1) * 0.5
    elseif paramName == "mdf" then
        return 10 + (battler.level - 1) * 0.5
    elseif paramName == "mpd" then
        return data.mpd or 2
    elseif paramName == "mxa" then
        return data.mxa or 4
    elseif paramName == "mxp" then
        return data.mxp or 2
    end
    return 10
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
