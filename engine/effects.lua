local traits = require("engine.traits")

local effects = {}

local function evaluateFormula(formula, a, b, session)
    if not formula then return 0 end
    
    local str = formula
    -- Replace a.level, a.atk
    str = str:gsub("a%.level", tostring(a.level or 1))
    str = str:gsub("a%.atk", tostring(traits.getParam(a, "atk", session) or 10))
    str = str:gsub("a%.mat", tostring(traits.getParam(a, "mat", session) or 10))
    
    -- Replace b.level, b.def, etc.
    if b then
        str = str:gsub("b%.level", tostring(b.level or 1))
        str = str:gsub("b%.def", tostring(traits.getParam(b, "def", session) or 10))
        str = str:gsub("b%.mdf", tostring(traits.getParam(b, "mdf", session) or 10))
    end
    
    -- Compile and evaluate
    local func = load("return " .. str)
    if func then
        local success, val = pcall(func)
        if success then return val end
    end
    return 1
end

function effects.apply(effectData, a, b, session)
    local events = {}
    
    if effectData.type == "hp_damage" then
        local val = evaluateFormula(effectData.formula, a, b, session)
        -- Defense reduction
        local def = traits.getParam(b, "def", session)
        local finalDmg = math.max(1, math.floor(val * (10 / def)))
        
        b.hp = math.max(0, b.hp - finalDmg)
        table.insert(events, {
            type = "damage",
            target = b,
            value = finalDmg
        })
        if b.hp <= 0 then
            b:addState("dead")
            table.insert(events, {
                type = "death",
                target = b
            })
        end
        
    elseif effectData.type == "hp_heal" then
        local val = evaluateFormula(effectData.formula, a, b, session)
        local maxHp = traits.getParam(b, "maxHp", session)
        local healVal = math.min(maxHp - b.hp, math.floor(val))
        b.hp = b.hp + healVal
        table.insert(events, {
            type = "heal",
            target = b,
            value = healVal
        })
        
    elseif effectData.type == "hp_drain" then
        local val = evaluateFormula(effectData.formula, a, b, session)
        local def = traits.getParam(b, "def", session)
        local finalDmg = math.max(1, math.floor(val * (10 / def)))
        
        b.hp = math.max(0, b.hp - finalDmg)
        a.hp = math.min(traits.getParam(a, "maxHp", session), a.hp + finalDmg)
        
        table.insert(events, {
            type = "damage",
            target = b,
            value = finalDmg
        })
        table.insert(events, {
            type = "heal",
            target = a,
            value = finalDmg
        })
        
        if b.hp <= 0 then
            b:addState("dead")
            table.insert(events, {
                type = "death",
                target = b
            })
        end
        
    elseif effectData.type == "add_status" then
        local roll = math.random()
        if roll <= (effectData.chance or 1.0) then
            b:addState(effectData.status, effectData.duration)
            table.insert(events, {
                type = "state_add",
                target = b,
                state = effectData.status
            })
        end

    -- Item-style effects (items.json): flat HP restore, permanent max HP
    -- boost, and XP grants. Handled here so items behave identically in
    -- battle and from the field menu.
    elseif effectData.type == "hp" then
        local maxHp = traits.getParam(b, "maxHp", session)
        local healVal = math.max(0, math.min(maxHp - b.hp, effectData.value or 0))
        b.hp = b.hp + healVal
        table.insert(events, {
            type = "heal",
            target = b,
            value = healVal
        })

    elseif effectData.type == "maxHp" then
        local gain = effectData.value or 0
        b.paramPlus.maxHp = (b.paramPlus.maxHp or 0) + gain
        local maxHp = traits.getParam(b, "maxHp", session)
        b.hp = math.min(maxHp, b.hp + gain)
        table.insert(events, {
            type = "heal",
            target = b,
            value = gain
        })

    elseif effectData.type == "xp" then
        b:gainExp(effectData.value or 0, session)
        table.insert(events, {
            type = "text",
            text = session.loader.formatTerm("battle.gains_xp", "- {0} gains {1} XP.", b.name, effectData.value or 0)
        })
    end

    return events
end

return effects
