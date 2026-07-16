local formula = require("engine.formula")

local targeting = {}

-- Expand target shorthand specifications to standard schema table
function targeting.expand(spec)
    if type(spec) == "string" then
        -- Parse shorthand like side-random-count
        local sidePart, countPart = spec:match("^([a-z]+)%-random%-(.+)$")
        if sidePart and countPart then
            local countVal = tonumber(countPart) or countPart
            return { side = sidePart, count = countVal, mode = "random", state = "alive" }
        end

        if spec == "enemy" or spec == "enemy-any" then
            return { side = "enemy", count = 1, mode = "choose", state = "alive" }
        elseif spec == "ally-any" or spec == "ally" then
            return { side = "ally", count = 1, mode = "choose", state = "alive" }
        elseif spec == "self" then
            return { side = "self", count = 1, mode = "choose", state = "alive" }
        elseif spec == "party" or spec == "ally-all" then
            return { side = "ally", count = "all", mode = "choose", state = "alive" }
        elseif spec == "enemy-all" then
            return { side = "enemy", count = "all", mode = "choose", state = "alive" }
        else
            return { side = "enemy", count = 1, mode = "choose", state = "alive" }
        end
    elseif type(spec) == "table" then
        return {
            side = spec.side or "enemy",
            count = spec.count or 1,
            mode = spec.mode or "choose",
            state = spec.state or "alive"
        }
    else
        return { side = "enemy", count = 1, mode = "choose", state = "alive" }
    end
end

-- Resolve targeting to concrete target list
function targeting.resolve(actor, spec, battleState, chosenTarget, actionContext)
    local exp = targeting.expand(spec)
    
    -- Determine target side groups
    local allies = battleState.allies or {}
    local enemies = battleState.enemies or {}
    
    -- Check if actor is an enemy
    local actorIsEnemy = false
    for _, e in ipairs(enemies) do
        if e == actor then
            actorIsEnemy = true
            break
        end
    end
    
    local friendlyGroup = actorIsEnemy and enemies or allies
    local opposingGroup = actorIsEnemy and allies or enemies
    
    local candidates = {}
    if exp.side == "enemy" then
        candidates = opposingGroup
    elseif exp.side == "ally" then
        candidates = friendlyGroup
    elseif exp.side == "self" then
        candidates = { actor }
    elseif exp.side == "any" then
        for _, b in ipairs(allies) do table.insert(candidates, b) end
        for _, b in ipairs(enemies) do table.insert(candidates, b) end
    end
    
    -- Filter by state (alive, dead, or any)
    local legal = {}
    for _, b in ipairs(candidates) do
        local match = false
        if exp.state == "alive" then
            match = not b:isDead()
        elseif exp.state == "dead" then
            match = b:isDead()
        elseif exp.state == "any" then
            match = true
        end
        if match then
            table.insert(legal, b)
        end
    end
    
    -- Resolve count
    local count = exp.count
    if count == "all" then
        return legal
    end
    
    if type(count) == "string" then
        local val, err = formula.eval(count, { a = actor, actor = actor, session = battleState.session })
        count = tonumber(val) or 1
    end
    count = math.max(1, math.floor(tonumber(count) or 1))
    
    -- Check mode: if actor is AI (enemy) and no chosen target is provided, force mode to random
    local isAI = actorIsEnemy
    local mode = exp.mode
    if isAI and not chosenTarget then
        mode = "random"
    end
    
    -- Heuristic 1: AI prioritizes wounded allies for healing actions
    if isAI and exp.side == "ally" and actionContext and actionContext.effects then
        local isHealAction = false
        for _, eff in ipairs(actionContext.effects) do
            if eff.type == "hp_heal" or eff.type == "hp" then
                isHealAction = true
                break
            end
        end
        if isHealAction then
            local wounded = {}
            for _, b in ipairs(legal) do
                local curHp = b.hp
                local maxHp = b:getMaxHp(battleState.session)
                if curHp < maxHp then
                    table.insert(wounded, { battler = b, pct = curHp / maxHp })
                end
            end
            if #wounded > 0 then
                table.sort(wounded, function(x, y) return x.pct < y.pct end)
                local picked = {}
                for i = 1, math.min(count, #wounded) do
                    table.insert(picked, wounded[i].battler)
                end
                -- If we still need more targets to satisfy count, pad with random survivors
                if #picked < count then
                    local temp = {}
                    for _, b in ipairs(legal) do
                        local alreadyPicked = false
                        for _, p in ipairs(picked) do
                            if p == b then alreadyPicked = true break end
                        end
                        if not alreadyPicked then table.insert(temp, b) end
                    end
                    while #picked < count and #temp > 0 do
                        local idx = math.random(#temp)
                        table.insert(picked, temp[idx])
                        -- Allow duplicates if user wants, but choose distinct ones first
                    end
                    -- If we still need more, duplicate selection of the wounded
                    while #picked < count do
                        table.insert(picked, picked[math.random(#picked)])
                    end
                end
                return picked
            end
        end
    end
    
    if mode == "choose" then
        if chosenTarget then
            for _, b in ipairs(legal) do
                if b == chosenTarget then
                    -- If count > 1, duplicate selection of chosenTarget
                    local picked = {}
                    for i = 1, count do
                        table.insert(picked, chosenTarget)
                    end
                    return picked
                end
            end
        end
        -- Fallback
        if #legal > 0 then
            local picked = {}
            for i = 1, count do
                table.insert(picked, legal[1])
            end
            return picked
        else
            return {}
        end
    elseif mode == "random" then
        if #legal == 0 then
            return {}
        end
        local picked = {}
        for i = 1, count do
            local idx = math.random(#legal)
            table.insert(picked, legal[idx])
        end
        return picked
    end
end

-- Return the raw list of legal selection candidates for manual target picking (no fallback, no count limits, no random selections)
function targeting.getCandidates(actor, spec, battleState, actionContext)
    local exp = targeting.expand(spec)
    
    local allies = battleState.allies or {}
    local enemies = battleState.enemies or {}
    
    local actorIsEnemy = false
    for _, e in ipairs(enemies) do
        if e == actor then
            actorIsEnemy = true
            break
        end
    end
    
    local friendlyGroup = actorIsEnemy and enemies or allies
    local opposingGroup = actorIsEnemy and allies or enemies
    
    local candidates = {}
    if exp.side == "enemy" then
        candidates = opposingGroup
    elseif exp.side == "ally" then
        candidates = friendlyGroup
    elseif exp.side == "self" then
        candidates = { actor }
    elseif exp.side == "any" then
        for _, b in ipairs(allies) do table.insert(candidates, b) end
        for _, b in ipairs(enemies) do table.insert(candidates, b) end
    end
    
    local legal = {}
    for _, b in ipairs(candidates) do
        local match = false
        if exp.state == "alive" then
            match = not b:isDead()
        elseif exp.state == "dead" then
            match = b:isDead()
        elseif exp.state == "any" then
            match = true
        end
        
        if match then
            table.insert(legal, b)
        end
    end
    
    return legal
end

return targeting
