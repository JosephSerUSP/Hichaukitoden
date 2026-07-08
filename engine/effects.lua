local traits = require("engine.traits")
local formulaEngine = require("engine.formula")

local effects = {}

-- Elemental affinity multiplier: the attack's element vs each of the target's
-- elements, using the strongAgainst/weakAgainst lists in data/elements.json
-- and the multipliers in data/engine.json (elementRules).
local function elementMultiplier(element, target, session)
    if not element then return 1.0 end
    local elemData = session.loader.elements and session.loader.elements[element]
    if not elemData then return 1.0 end

    local rules = (session.loader.engine and session.loader.engine.elementRules) or {}
    local strongMult = rules.strongMultiplier or 1.5
    local weakMult = rules.weakMultiplier or 0.65

    local mult = 1.0
    local targetElems = traits.getElements(target, session)
    for _, targetElem in ipairs(targetElems) do
        for _, strong in ipairs(elemData.strongAgainst or {}) do
            if strong == targetElem then mult = mult * strongMult end
        end
        for _, weak in ipairs(elemData.weakAgainst or {}) do
            if weak == targetElem then mult = mult * weakMult end
        end
    end
    return mult
end

-- Thin wrapper kept for the existing call sites: builds the a/b context
-- through engine/formula.lua and evaluates in its sandbox. On error the
-- sandbox falls back to 0 (SPEC S5) where the old code returned 1.
local function evaluateFormula(expr, a, b, session)
    if not expr then return 0 end
    local ctx = formulaEngine.makeContext({ a = a, b = b, target = b }, session)
    return (formulaEngine.eval(expr, ctx))
end

-- context (optional): { element = "White" } — the element of the skill/item
-- driving this effect, used for affinity multipliers on damage.
function effects.apply(effectData, a, b, session, context)
    local events = {}
    local ctxElement = context and context.element or nil

    if effectData.type == "hp_damage" then
        local val = evaluateFormula(effectData.formula, a, b, session)
        -- Defense reduction, then elemental affinity
        local def = traits.getParam(b, "def", session)
        local finalDmg = math.max(1, math.floor(val * (10 / def) * elementMultiplier(ctxElement, b, session)))
        
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
        local finalDmg = math.max(1, math.floor(val * (10 / def) * elementMultiplier(ctxElement, b, session)))
        
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

    -- Restores the summoner's shared MP pool (e.g. pub drinks)
    elseif effectData.type == "mp_heal" then
        local healVal = math.max(0, math.min(session.maxMp - session.mp, effectData.value or 0))
        session.mp = session.mp + healVal
        table.insert(events, {
            type = "text",
            text = session.loader.formatTerm("battle.recovers_mp", "- {0} MP restored.", healVal)
        })

    -- Cures the state named in value (e.g. wine curing "weakened")
    elseif effectData.type == "remove_status" then
        local stateId = effectData.value or effectData.status
        if stateId then
            b:removeState(stateId)
            table.insert(events, {
                type = "state_remove",
                target = b,
                state = stateId
            })
        end
    end

    return events
end

return effects
