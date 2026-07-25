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
-- A broken effect formula now surfaces a "text" event into the caller's
-- event stream (parallel to interpreter.lua's evalFormula), instead of
-- failing silently — previously only formula.lua's warnOnce console print
-- fired, so a malformed skill/item formula was invisible in-game.
local function evaluateFormula(expr, a, b, session, events)
    if not expr then return 0 end
    local ctx = formulaEngine.makeContext({ a = a, b = b, target = b }, session)
    local val, err = formulaEngine.eval(expr, ctx)
    if err and events then
        table.insert(events, { type = "text", text = "[effect] formula error: " .. tostring(err) })
    end
    return val
end

-- context (optional): { element = "White" } — the element of the skill/item
-- driving this effect, used for affinity multipliers on damage.
function effects.apply(effectData, a, b, session, context)
    local events = {}
    local ctxElement = context and context.element or nil

    if effectData.type == "hp_damage" then
        local val = evaluateFormula(effectData.formula, a, b, session, events)
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
        local val = evaluateFormula(effectData.formula, a, b, session, events)
        local maxHp = traits.getParam(b, "maxHp", session)
        local healVal = math.min(maxHp - b.hp, math.floor(val))
        b.hp = b.hp + healVal
        table.insert(events, {
            type = "heal",
            target = b,
            value = healVal
        })
        
    elseif effectData.type == "hp_drain" then
        local val = evaluateFormula(effectData.formula, a, b, session, events)
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

    -- Skillbook: permanently teaches `skill` to the target (creature
    -- customization — Item Creation's tier pools can yield these). A creature
    -- that already knows the skill is a no-op that says so, so the item isn't
    -- silently consumed for nothing (the caller checks usability first).
    elseif effectData.type == "learn_skill" then
        local skillId = effectData.skill
        local known = false
        for _, s in ipairs(b.skills or {}) do
            if s == skillId then known = true break end
        end
        if not skillId or not (session.loader.skills and session.loader.skills[skillId]) then
            table.insert(events, {
                type = "text",
                text = "[effect] learn_skill: unknown skill '" .. tostring(skillId) .. "'"
            })
        elseif known then
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.already_knows", "- {0} already knows that skill.", b.name)
            })
        else
            b.skills = b.skills or {}
            table.insert(b.skills, skillId)
            local skillData = session.loader.skills[skillId]
            table.insert(events, {
                type = "learn_skill",
                target = b,
                skill = skillId
            })
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.learns_skill", "- {0} learns {1}!",
                    b.name, (skillData and skillData.name) or skillId)
            })
        end

    -- Permanent stat-up (the general form of `maxHp` above): adds `value` to
    -- the target's paramPlus for `param`, which savegame persists and
    -- traits.getParam folds into every stat read. maxHp also heals by the
    -- gain so the boost is immediately usable, matching the `maxHp` effect.
    elseif effectData.type == "param_plus" then
        local param = effectData.param
        local gain = math.floor(effectData.value or 0)
        b.paramPlus = b.paramPlus or {}
        if param == nil or b.paramPlus[param] == nil then
            table.insert(events, {
                type = "text",
                text = "[effect] param_plus: unknown param '" .. tostring(param) .. "'"
            })
        else
            b.paramPlus[param] = b.paramPlus[param] + gain
            if param == "maxHp" and gain > 0 then
                b.hp = math.min(traits.getParam(b, "maxHp", session), b.hp + gain)
            end
            table.insert(events, {
                type = "param_plus",
                target = b,
                param = param,
                value = gain
            })
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.param_up", "- {0}'s {1} rises by {2}!",
                    b.name, param, gain)
            })
        end

    -- Hatching item (the Mystic Egg): recruits `value` as a new creature into
    -- the party, or the reserve when the four active slots are full. The name
    -- is historical -- it is a plain "recruit this actor" effect, `level`
    -- optional (defaults to the actor's own).
    elseif effectData.type == "recruit_egg" then
        local actorId = effectData.value or effectData.actorId
        local battler, slotType = session:recruitActor(actorId, effectData.level)
        if not battler then
            table.insert(events, {
                type = "text",
                text = "[effect] recruit_egg: cannot recruit '" .. tostring(actorId)
                    .. "' (" .. tostring(slotType) .. ")"
            })
        else
            table.insert(events, {
                type = "recruit",
                target = battler,
                slot = slotType
            })
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.hatched", "- {0} joins you!", battler.name)
            })
        end

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
        local stateId = effectData.value
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
