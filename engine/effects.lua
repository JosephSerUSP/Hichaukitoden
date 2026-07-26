local traits = require("engine.traits")
local formulaEngine = require("engine.formula")

local effects = {}

-- Elemental affinity. Elements do double duty and the two jobs are separate
-- channels (docs/SPEC.md, "Elements"):
--
--   user layer   the acting creature's own elements vs the target's. Who you
--                ARE. Cross-product: an intensely Red creature swinging at an
--                intensely Green one counts every pairing.
--   skill layer  the element of the skill or item being used vs the target's.
--                What you WIELD -- a Red creature can learn a Green tome.
--
-- Advantage is additive with diminishing returns, so stacking alignment keeps
-- paying but never runs away. Disadvantage stays multiplicative -- it decays
-- toward zero instead of marching through it the way additive penalties do --
-- and is floored so deep mismatch is resistance, never immunity.
local function stackBonus(rate, decay, n)
    if n <= 0 then return 0 end
    if decay >= 1 then return rate * n end
    return rate * (1 - decay ^ n) / (1 - decay)
end

-- Count (strong, weak) matchups of one element against a list of elements.
local function countMatches(elements, element, targetElems)
    local elemData = elements and elements[element]
    if not elemData then return 0, 0 end
    local strongN, weakN = 0, 0
    for _, targetElem in ipairs(targetElems) do
        for _, strong in ipairs(elemData.strongAgainst or {}) do
            if strong == targetElem then strongN = strongN + 1 end
        end
        for _, weak in ipairs(elemData.weakAgainst or {}) do
            if weak == targetElem then weakN = weakN + 1 end
        end
    end
    return strongN, weakN
end

local function layerMultiplier(strongN, weakN, bonus, decay, weakMult, floor)
    local mult = 1.0 + stackBonus(bonus, decay, strongN)
    if weakN > 0 then
        mult = mult * math.max(floor, weakMult ^ weakN)
    end
    return mult
end

-- user (optional): the battler performing the action, for the user layer.
--
-- Exposed on the module (not just local) because the golden battle log barely
-- exercises this: the scripted encounter's participants have almost no
-- affinity relationships, so G2 cannot see a regression here. Unit tests own
-- this behaviour instead -- see tests/test_element_affinity.lua.
function effects.elementMultiplier(element, user, target, session)
    local elements = session.loader.elements
    if not elements then return 1.0 end

    local rules = (session.loader.engine and session.loader.engine.elementRules) or {}
    local floor = rules.weakFloor or 0.3
    local targetElems = traits.getElements(target, session)
    local mult = 1.0

    if element then
        local strongN, weakN = countMatches(elements, element, targetElems)
        mult = mult * layerMultiplier(strongN, weakN,
            rules.skillStrongBonus or 0.5, rules.skillStrongDecay or 0.7,
            rules.skillWeakMultiplier or 0.65, floor)
    end

    if user then
        local strongN, weakN = 0, 0
        for _, userElem in ipairs(traits.getElements(user, session)) do
            local s, w = countMatches(elements, userElem, targetElems)
            strongN, weakN = strongN + s, weakN + w
        end
        mult = mult * layerMultiplier(strongN, weakN,
            rules.userStrongBonus or 0.15, rules.userStrongDecay or 0.8,
            rules.userWeakMultiplier or 0.9, floor)
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

-- ITEM_EFFECT_RATE (RPG Maker's Pharmacology): scales what an item is worth to
-- the creature receiving it. Read from `b` — the recipient — because field item
-- use has no separate wielder, so a rate read from the user would silently do
-- nothing for every meal eaten outside battle. Skills are deliberately not
-- scaled: this is a constitution, not a spell amplifier.
local function itemRate(b, session, context)
    if not (context and context.isItem) or not b or not session then return 1.0 end
    return 1.0 + traits.getRate(b, "ITEM_EFFECT_RATE", session)
end

-- The stat a power source is measured against. Physical actions meet DEF,
-- magical actions meet MDF; an exceptional skill may author `defense` to pair
-- them otherwise. Before this, EVERY action reduced through DEF, which made a
-- promised magical weakness invisible -- a creature could advertise ruinous MDF
-- and never once be hit through it.
local DEFENSE_PAIRING = { atk = "def", mat = "mdf" }

-- Damage taken multiplier: the product of every DAMAGE_RATE on the target.
-- Multiplicative rather than summed (the shape traits.getRate gives the additive
-- rates) because two independent 0.5 protections should be a quarter, not zero.
local function damageRate(b, session)
    local rate = 1.0
    for _, found in ipairs(traits.findAllSources(b, "DAMAGE_RATE", session)) do
        rate = rate * (found.trait.value or 1.0)
    end
    return rate
end

-- One damage resolution for hp_damage and hp_drain, in the order
-- docs/design/creature-parameters.md fixes:
--
--   relative damage -> potency -> element -> critical x1.5 -> damage rate
--   -> rounding, with a floor of 1
--
-- The relative curve is potency * P^2 / (P + D). Its useful property is that
-- damage is a SHARE of power decided by the defense ratio -- 50% at D = P, 33%
-- at D = 2P -- so scratch damage is real and a Pixie punching a Golem is
-- meant to be an almost useless action, which a flat subtraction cannot
-- express and the old `10 / DEF` divisor got backwards at low DEF.
--
-- `formula` without `power` is the direct path: an authored number that lands
-- as-is. A trap that says 20 deals 20. It takes no DAMAGE_RATE, matching the
-- rule that guarding does not blunt authored indirect damage.
local function resolveDamage(effectData, a, b, session, context, events)
    local ctxElement = context and context.element or nil
    local ctxUser = context and context.user or nil
    local relative = (effectData.power ~= nil)
    local raw

    if relative then
        local powerStat = effectData.power
        local defStat = effectData.defense or DEFENSE_PAIRING[powerStat] or "def"
        local P = traits.getParam(a, powerStat, session)
        local D = traits.getParam(b, defStat, session)
        local potency = effectData.potency or 1.0
        raw = potency * (P * P) / (P + D)
    else
        raw = evaluateFormula(effectData.formula, a, b, session, events)
    end

    raw = raw * effects.elementMultiplier(ctxElement, ctxUser, b, session)

    -- Criticals roll here rather than in battle.lua so that every damaging
    -- action gets them on one code path, and so a multi-hit action rolls per
    -- hit exactly as the design requires. Only the relative path crits: a trap
    -- has no attacker to be skilful.
    local critical = false
    if relative and a then
        local combat = (session.loader.system and session.loader.system.combat) or {}
        if math.random() < traits.getRate(a, "CRI", session) then
            critical = true
            raw = raw * (combat.criticalMultiplier or 1.5)
        end
    end

    if relative then
        raw = raw * damageRate(b, session)
    end

    return math.max(1, math.floor(raw)), critical
end

-- context (optional): { element = "White", user = <battler>, isItem = true } —
-- the element of the skill/item driving this effect, the creature performing
-- the action (used for the two affinity layers on damage), and whether an item
-- rather than a skill drives it. `user` is passed separately from `a` because
-- for items `a` is the recipient, not the wielder.
function effects.apply(effectData, a, b, session, context)
    local events = {}
    local ctxElement = context and context.element or nil
    local ctxUser = context and context.user or nil

    if effectData.type == "hp_damage" then
        local finalDmg, critical = resolveDamage(effectData, a, b, session, context, events)

        b.hp = math.max(0, b.hp - finalDmg)
        -- Recorded on the shared action context so a status attached to the
        -- same action can see the hit landed critically (see add_status).
        if critical and context then context.critical = true end
        table.insert(events, {
            type = "damage",
            target = b,
            value = finalDmg,
            critical = critical or nil
        })
        if b.hp <= 0 then
            b:addState("dead")
            table.insert(events, {
                type = "death",
                target = b
            })
        end
        
    elseif effectData.type == "hp_heal" then
        local val = evaluateFormula(effectData.formula, a, b, session, events) * itemRate(b, session, context)
        local maxHp = traits.getParam(b, "maxHp", session)
        local healVal = math.min(maxHp - b.hp, math.floor(val))
        b.hp = b.hp + healVal
        table.insert(events, {
            type = "heal",
            target = b,
            value = healVal
        })
        
    elseif effectData.type == "hp_drain" then
        local finalDmg, critical = resolveDamage(effectData, a, b, session, context, events)

        b.hp = math.max(0, b.hp - finalDmg)
        a.hp = math.min(traits.getParam(a, "maxHp", session), a.hp + finalDmg)
        if critical and context then context.critical = true end

        table.insert(events, {
            type = "damage",
            target = b,
            value = finalDmg,
            critical = critical or nil
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
        -- Brigandine's rule: a damaging action that crits guarantees the status
        -- it carries. `context.critical` is set by the damage effect earlier in
        -- the SAME action, which is why the action context is shared across an
        -- effect list rather than rebuilt per effect. A non-damaging status
        -- action has no damage effect to set it and so never gets the guarantee.
        --
        -- NOTE: the design also exempts explicit immunity (target state rate 0),
        -- which cannot be honored until STATE_RATE exists -- recorded in
        -- docs/design/content-engine-gaps.md.
        local guaranteed = (context and context.critical) == true
        local roll = math.random()
        if guaranteed or roll <= (effectData.chance or 1.0) then
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
        -- Flat + percentage of the recipient's own Max HP. Both parts are
        -- optional, so one effect type covers a 30 HP herb, a "restores a
        -- quarter of HP" meal, and the hybrid foods that are both.
        local raw = (effectData.value or 0) + maxHp * (effectData.percent or 0)
        local healVal = math.max(0, math.min(maxHp - b.hp,
            math.floor(raw * itemRate(b, session, context))))
        b.hp = b.hp + healVal
        table.insert(events, {
            type = "heal",
            target = b,
            value = healVal
        })

    elseif effectData.type == "maxHp" then
        local gain = effectData.value or 0
        b.paramPlus = b.paramPlus or {}
        b.paramPlus.maxHp = (b.paramPlus.maxHp or 0) + gain
        local maxHp = traits.getParam(b, "maxHp", session)
        b.hp = math.min(maxHp, b.hp + gain)
        table.insert(events, {
            type = "heal",
            target = b,
            value = gain
        })
        table.insert(events, {
            type = "text",
            text = session.loader.formatTerm("battle.param_up", "- {0}'s {1} rises by {2}!",
                b.name, "Max HP", gain)
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
            local statLabel = param
            if param == "atk" then statLabel = "ATK"
            elseif param == "def" then statLabel = "DEF"
            elseif param == "mat" then statLabel = "MAT"
            elseif param == "mdf" then statLabel = "MDF"
            elseif param == "maxHp" then statLabel = "Max HP"
            end
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.param_up", "- {0}'s {1} rises by {2}!",
                    b.name, statLabel, gain)
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

    -- Restores the summoner's shared MP pool (e.g. pub drinks). Percentage is
    -- of Max MP, which is what lets a draught stay meaningful as the cap climbs
    -- from the opening scale toward maxMpCap instead of becoming a rounding
    -- error. ITEM_EFFECT_RATE reads from the recipient, and the pool has none.
    elseif effectData.type == "mp_heal" then
        local raw = (effectData.value or 0) + (session.maxMp or 0) * (effectData.percent or 0)
        local healVal = math.max(0, math.min(session.maxMp - session.mp, math.floor(raw)))
        session.mp = session.mp + healVal
        table.insert(events, {
            type = "text",
            text = session.loader.formatTerm("battle.recovers_mp", "- {0} MP restored.", healVal)
        })

    -- Permanent Summoner Max MP. Capped by system.summoner.maxMpCap and saved
    -- with the session, so this is the item-scale counterpart of the much
    -- larger increases major events are meant to grant. Restores the gain too,
    -- matching how the maxHp effect heals what it adds.
    elseif effectData.type == "max_mp_plus" then
        local sys = (session.loader.system and session.loader.system.summoner) or {}
        local cap = sys.maxMpCap or 9999
        local gain = math.max(0, math.floor(effectData.value or 0))
        local applied = math.min(gain, math.max(0, cap - (session.maxMp or 0)))
        session.maxMp = (session.maxMp or 0) + applied
        session.mp = math.min(session.maxMp, (session.mp or 0) + applied)
        if applied > 0 then
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.max_mp_up", "- Maximum MP rises by {0}!", applied)
            })
        else
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.max_mp_capped", "- Maximum MP is already at its limit.")
            })
        end

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
