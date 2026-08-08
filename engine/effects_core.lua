local traits = require("engine.traits")
local formulaEngine = require("engine.formula")
local barriers = require("engine.barriers")

local effects = {}

-- Stack barriers (#165) absorb one matching resolved instance. This lives inside
-- damage resolution rather than above it: the reduction has to be known before
-- the HP write, because death, kill rewards and drain recovery are all decided
-- from the post-hit HP. A caller wrapping effects.apply could only unwind a
-- death that a surviving target never suffered.
--
-- Nothing here names an element, skill or creature: `match` comes from the
-- authored barrier, and the hit's kind from the stat it scales off.
local function damageKind(effectData)
    if effectData.damageKind then return effectData.damageKind end
    if effectData.power == "atk" then return "physical_damage" end
    if effectData.power == "mat" then return "magical_damage" end
    return nil
end

local function absorbWithBarrier(effectData, b, finalDmg, events)
    local kind = damageKind(effectData)
    if not b or not kind or finalDmg <= 0 or not barriers.has(b, kind) then return finalDmg end
    local barrier, consumeEvents, consume = barriers.consume(b, kind)
    for _, ev in ipairs(consumeEvents or {}) do table.insert(events, ev) end
    if not barrier then return finalDmg end
    local reduction = barrier.reduction or 0
    local adjusted = reduction >= 1 and 0
        or math.max(0, math.floor(finalDmg * (1 - reduction)))
    if consume then
        consume.prevented = math.max(0, finalDmg - adjusted)
        consume.blocked = adjusted == 0
    end
    return adjusted
end

-- Elemental affinity. Elements do double duty and the two jobs remain separate
-- channels (docs/SPEC.md, "Elements"):
--
--   user layer   the acting creature's own elements vs the target's. Who you
--                ARE. Every attacker/target pairing contributes to one signed
--                relation score, so repeated alignment expresses depth while
--                contrary colors cancel before multiplier math.
--   skill layer  the element of the skill or item being used vs the target's.
--                What you WIELD -- a Red creature can learn a Green tome. Its
--                own strong/weak target relations likewise resolve to one score.
--
-- Within either channel, strong = +1, neutral = 0 and weak = -1. Positive and
-- negative relations cancel first. Only the remaining magnitude is mapped onto
-- the existing authored curve: positive depth gets diminishing additive bonus;
-- negative depth gets multiplicative resistance with a floor. This removes the
-- old 1.15 * 0.90 = 1.035 arithmetic residue without special-casing RGB or any
-- named combination, and preserves the established one-sided/repeated values.
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

local function layerMultiplier(score, bonus, decay, weakMult, floor)
    if score > 0 then
        return 1.0 + stackBonus(bonus, decay, score)
    end
    if score < 0 then
        return math.max(floor, weakMult ^ (-score))
    end
    return 1.0
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
        mult = mult * layerMultiplier(strongN - weakN,
            rules.skillStrongBonus or 0.5, rules.skillStrongDecay or 0.7,
            rules.skillWeakMultiplier or 0.65, floor)
    end

    if user then
        local strongN, weakN = 0, 0
        for _, userElem in ipairs(traits.getElements(user, session)) do
            local s, w = countMatches(elements, userElem, targetElems)
            strongN, weakN = strongN + s, weakN + w
        end
        mult = mult * layerMultiplier(strongN - weakN,
            rules.userStrongBonus or 0.15, rules.userStrongDecay or 0.8,
            rules.userWeakMultiplier or 0.9, floor)
    end

    if element and target then
        for _, found in ipairs(traits.findAllSources(target, "ELEMENT_RATE", session)) do
            if found.trait.dataId == element then
                mult = mult * (found.trait.value or 1.0)
            end
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

-- ITEM_EFFECT_RATE (RPG Maker's Pharmacology): scales what an item is worth to
-- the creature receiving it. Read from `b` — the recipient — because field item
-- use has no separate wielder, so a rate read from the user would silently do
-- nothing for every meal eaten outside battle. Skills are deliberately not
-- scaled: this is a constitution, not a spell amplifier.
local function itemRate(b, session, context)
    if not (context and context.isItem) or not session then return 1.0 end
    local user = context.user or b
    if not user then return 1.0 end
    return 1.0 + traits.getRate(user, "ITEM_EFFECT_RATE", session)
end

function effects.bestItemUser(session)
    local best, bestRate = nil, -math.huge
    for _, battler in ipairs((session and session.party) or {}) do
        if battler and not battler:isDead() then
            local rate = traits.getRate(battler, "ITEM_EFFECT_RATE", session)
            if rate > bestRate then best, bestRate = battler, rate end
        end
    end
    return best
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

        -- Armor penetration: ignore a share of the defense before the curve
        -- rather than adding damage after it. That is what makes it a distinct
        -- answer to a wall instead of a second potency -- against a soft target
        -- it is worth almost nothing, against Golem it is worth a great deal,
        -- which is exactly the Pile Bunker's job. The effect's own `penetration`
        -- and the attacker's PENETRATION trait add, then clamp: a share of a
        -- stat cannot exceed the stat.
        local pierce = (effectData.penetration or 0)
        if a then pierce = pierce + traits.getRate(a, "PENETRATION", session) end
        if pierce > 0 then
            if pierce > 1 then pierce = 1 end
            D = D * (1 - pierce)
        end

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
        -- Effective critical rate is the attacker's CRI minus the target's CEV.
        -- Critical defense matters twice over, because a critical is also the
        -- universal status backdoor (see add_status): being hard to crit means
        -- less burst AND fewer forced afflictions. Trait-driven only -- gear and
        -- passives buy it, no stat derives it, or DEF would quietly become a
        -- super-stat on top of its mitigation and physical-resistance jobs.
        --
        -- The roll happens unconditionally even when CEV has driven the rate to
        -- zero: skipping the draw would consume one fewer math.random and shift
        -- every later roll in the round, so a defensive trait would silently
        -- rewrite the whole battle's RNG stream (and G2 with it).
        local critRate = traits.getRate(a, "CRI", session)
            - (b and traits.getRate(b, "CEV", session) or 0)
        if math.random() < critRate then
            critical = true
            raw = raw * (combat.criticalMultiplier or 1.5)
        end
    end

    if relative then
        raw = raw * damageRate(b, session)
    end

    return math.max(1, math.floor(raw)), critical
end

-- How susceptible `target` is to `stateId`: the product of every STATE_RATE
-- naming that state and every STATE_CATEGORY_RATE naming one of its categories.
-- Multiplicative so a narrow resistance and a broad one compound instead of one
-- silently winning.
--
-- Also folded in: the target's own BASE def/mdf, through the authored
-- `stateResistFromStat` curves in engine.json. That is what gives the defensive
-- stats a job beyond mitigation -- DEF as the body's resilience (physical
-- afflictions), MDF as the spirit's (magical, mental) -- and it needed no new
-- mechanism, because this product already multiplies.
--
-- BASE, not final: gear that raises a defensive stat buys damage mitigation,
-- while anti-poison gear stays authorable as an explicit STATE_RATE, which is
-- more honest because it says what it does.
--
-- A rate of 0 is NOT immunity any more (see add_status) -- immunity is a trait.
-- So these curves are free to reach or pass zero without a stat quietly
-- drifting into absolute immunity.
local function stateRate(target, stateId, session)
    if not target or not session then return 1.0 end
    local rate = 1.0
    for _, found in ipairs(traits.findAllSources(target, "STATE_RATE", session)) do
        if found.trait.dataId == stateId then
            rate = rate * (found.trait.value or 1.0)
        end
    end
    local state = session.loader.getState and session.loader.getState(stateId)
    local categories = (state and state.categories) or {}
    if #categories > 0 then
        for _, found in ipairs(traits.findAllSources(target, "STATE_CATEGORY_RATE", session)) do
            for _, category in ipairs(categories) do
                if found.trait.dataId == category then
                    rate = rate * (found.trait.value or 1.0)
                end
            end
        end

        -- Stat-derived category resistance. One authored curve per category,
        -- evaluated against the target's base stats, so the shape stays a data
        -- knob rather than a constant in here.
        -- ...but only against AFFLICTIONS. `physical` and `magical` are shape
        -- tags, not intent tags: `defending` and `provoke` are positive AND
        -- physical, `regen` and `magicGuard` positive AND magical. Without this
        -- guard a creature's own VIT would resist its own Defend, and the
        -- sturdier it got the more often bracing would silently fail.
        --
        -- Explicit STATE_RATE traits above are deliberately NOT gated this way:
        -- an author who writes a rate against a positive state means it.
        local isAffliction = false
        for _, category in ipairs(categories) do
            if category == "negative" then isAffliction = true break end
        end
        if isAffliction then
            local combat = (session.loader.system and session.loader.system.combat) or {}
            local curves = combat.stateResistFromStat or {}
            local view = nil
            for _, category in ipairs(categories) do
                local curve = curves[category]
                if curve then
                    view = view or formulaEngine.battlerView(target, session)
                    rate = rate * (tonumber(formulaEngine.eval(curve, { b = view, a = view })) or 1.0)
                end
            end
        end
    end
    return rate
end

-- Execution: an attacker carrying EXECUTION_THRESHOLD finishes a target left
-- at or below that fraction of its Max HP. Checked after the damage lands, so
-- it is a finisher rather than a coin flip on a healthy creature -- Executioner
-- must execute, and Diablos must close.
--
-- Resistance SUBTRACTS from the threshold instead of rolling against it. That
-- keeps execution deterministic (no draw, so it cannot perturb the golden RNG
-- stream), makes partial resistance meaningful rather than a second dice roll,
-- and lets Safety Bit be an ordinary 1.0 that pushes any threshold below zero.
-- It is separate vocabulary from state resistance on purpose: execution is not
-- a state, and the ledger asks for it not to be smuggled in as one.
local function tryExecute(a, b, session, events)
    if not a or not b or b.hp <= 0 then return end
    local threshold = traits.getRate(a, "EXECUTION_THRESHOLD", session)
    if threshold <= 0 then return end
    threshold = threshold - traits.getRate(b, "EXECUTION_RESIST", session)
    if threshold <= 0 then return end

    local maxHp = traits.getParam(b, "maxHp", session)
    if maxHp <= 0 then return end
    if (b.hp / maxHp) > threshold then return end

    b.hp = 0
    b:addState("dead")
    table.insert(events, { type = "execution", target = b, actor = a })
    table.insert(events, {
        type = "text",
        text = session.loader.formatTerm("battle.execution", "- {0} is finished off!", b.name)
    })
    table.insert(events, { type = "death", target = b })
    return true
end

local function awardKill(a, b, session, events)
    if not a or not b or not session then return end
    local amount = math.max(0, math.floor(traits.getRate(a, "KILL_MP_RESTORE", session)))
    if amount <= 0 then return end
    local restored = math.min(amount, math.max(0, (session.maxMp or 0) - (session.mp or 0)))
    session.mp = (session.mp or 0) + restored
    table.insert(events, { type = "kill_mp_restore", actor = a, target = b, value = restored })
    if restored > 0 then
        table.insert(events, {
            type = "text",
            text = session.loader.formatTerm("battle.kill_mp_restore",
                "- {0} restores {1} MP to the Summoner!", a.name, restored)
        })
    end
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
        finalDmg = absorbWithBarrier(effectData, b, finalDmg, events)

        b.hp = math.max(0, b.hp - finalDmg)
        if b.hp > 0 and b.hasState and b:hasState("sleep") then
            b:removeState("sleep")
            local ldr = session and session.loader
            local msg = (ldr and ldr.formatTerm) and ldr.formatTerm("status.woke_up", "{0} woke up!", b.name) or (b.name .. " woke up!")
            table.insert(events, { type = "text", text = msg })
        end
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
            awardKill(a, b, session, events)
        elseif effectData.power ~= nil then
            -- Only a survivor can be executed, and only on the relative path:
            -- direct authored damage is a fixed consequence with no attacker
            -- whose weapon could finish anyone, the same reason it never crits.
            if tryExecute(a, b, session, events) then
                awardKill(a, b, session, events)
            end
        end

    elseif effectData.type == "hp_heal" then
        local skillRate = (context and context.isItem) and 1
            or (1 + traits.getRate(a, "HEAL_RATE", session))
        local val = evaluateFormula(effectData.formula, a, b, session, events)
            * skillRate * itemRate(b, session, context)
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
        -- Absorbed damage is never dealt, so it is never drained either.
        finalDmg = absorbWithBarrier(effectData, b, finalDmg, events)

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
            awardKill(a, b, session, events)
        end
        
    elseif effectData.type == "add_status" then
        -- The MZ-style infliction chain:
        --
        --   skill chance * attacker status-success * target state rate
        --
        -- clamped to 0..1. Splitting it three ways is what lets a control
        -- specialist be better at landing conditions (its own rate) without
        -- rewriting every skill, and a resistant creature shrug them off (its
        -- rate) without the skill knowing who it hit.
        local targetRate = stateRate(b, effectData.status, session)

        -- Immunity first, and above everything -- but immunity is now a TRAIT
        -- (STATE_IMMUNITY / STATE_CATEGORY_IMMUNITY), not a rate of zero.
        --
        -- Overloading 0 cost a special case here and a paragraph in two spec
        -- sections. Now a rate of 0 (or below) means vanishingly unlikely, not
        -- immune: a high-VIT creature is functionally unpoisonable, and a
        -- critical still gets through. Only a trait says never -- which also
        -- frees the derived DEF/MDF resistance curve to reach zero without a
        -- stat drifting into accidental absolute immunity.
        --
        -- Announced rather than silent: a status that simply never appears
        -- looks identical to a bug.
        if traits.hasStateImmunity(b, effectData.status, session) then
            table.insert(events, {
                type = "state_immune",
                target = b,
                state = effectData.status
            })
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.state_immune",
                    "- {0} is unaffected.", b.name)
            })
            return events
        end

        -- Brigandine's rule: a damaging action that crits guarantees the status
        -- it carries. `context.critical` is set by the damage effect earlier in
        -- the SAME action, which is why the action context is shared across an
        -- effect list rather than rebuilt per effect. A non-damaging status
        -- action has no damage effect to set it and so never gets the guarantee.
        local guaranteed = (context and context.critical) == true

        local success = 1.0
        if a and a ~= b then
            success = 1.0 + traits.getRate(a, "STATUS_SUCCESS", session)
        end
        local chance = (effectData.chance or 1.0) * success * targetRate
        if chance > 1.0 then chance = 1.0 end
        if chance < 0 then chance = 0 end

        -- Strictly less-than: math.random() can return 0, and `roll <= chance`
        -- let an authored chance of 0 land on that draw. A 0% chance must mean
        -- never on the ordinary path, even though a critical (above) can still
        -- force it -- that asymmetry is the point of §7: rates are a slope,
        -- immunity is a trait.
        local roll = math.random()
        if guaranteed or roll < chance then
            -- A hostile-status ward is consulted only once the status has
            -- actually won its own roll. Consulting it earlier would spend a
            -- stack on a status that was never going to land.
            if barriers.has(b, "hostile_status")
                    and barriers.isHostileState(session and session.loader, effectData.status) then
                local barrier, consumeEvents, consume = barriers.consume(b, "hostile_status")
                for _, ev in ipairs(consumeEvents or {}) do table.insert(events, ev) end
                if barrier then
                    -- A partial ward is a per-instance chance to refuse.
                    local blocked = barrier.reduction >= 1 or math.random() < (barrier.reduction or 0)
                    if consume then
                        consume.state = effectData.status
                        consume.prevented = blocked and 1 or 0
                        consume.blocked = blocked
                    end
                    if blocked then return events end
                end
            end
            b:addState(effectData.status, effectData.duration)
            table.insert(events, {
                type = "state_add",
                target = b,
                state = effectData.status,
                duration = effectData.duration,
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
            local prov = effectData.provenance
            if (not prov or prov == "random") and battler.actorData and battler.actorData.hatchOutcomes then
                local outcomes = {}
                for k in pairs(battler.actorData.hatchOutcomes) do
                    if k ~= "default" then
                        table.insert(outcomes, k)
                    end
                end
                if #outcomes > 0 then
                    prov = outcomes[math.random(#outcomes)]
                end
            end
            battler.provenance = prov
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
    -- error. Pharmacology belongs to the item user, selected by the item-use
    -- path even though the shared pool itself has no recipient.
    elseif effectData.type == "mp_heal" then
        local raw = ((effectData.value or 0) + (session.maxMp or 0) * (effectData.percent or 0))
            * itemRate(nil, session, context)
        local healVal = math.max(0, math.min(session.maxMp - session.mp, math.floor(raw)))
        session.mp = session.mp + healVal
        table.insert(events, {
            type = "text",
            text = session.loader.formatTerm("battle.recovers_mp", "- {0} MP restored.", healVal)
        })

    -- Spell charges (food and restoratives). The item/food channel into the
    -- charge economy, and the partial counterpart of Rest: `amount: "all"`
    -- routes through the SAME skill_cost.restore that RECOVER_PARTY's full
    -- refill uses, so a Mana Nut and a night in town cannot disagree about what
    -- "full" means. An omitted `skill` restores every skill the creature knows;
    -- naming one restores just that.
    elseif effectData.type == "restore_charges" then
        local skill_cost = require("engine.skill_cost")
        local restored = skill_cost.restore(b, session, session.loader,
            effectData.skill, effectData.amount or 1)
        if restored > 0 then
            table.insert(events, {
                type = "text",
                text = session.loader.formatTerm("battle.recovers_charges",
                    "- {0} recovers {1} charges.", b and b.name or "?", restored)
            })
        end

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

    -- Runs an authored common event (the Forbidden Lamp shape: an item that
    -- starts a scripted encounter). Emitted as a request rather than executed
    -- here: CALL_COMMON_EVENT compiles to a dialogue node and immediate mode
    -- refuses it, so effects cannot run one. The host picks this event up and
    -- starts the graph; headless runs simply see the request and carry on,
    -- which is what keeps the validator and the golden harness working.
    elseif effectData.type == "escape" then
        -- Escaping is an action like any other: it costs the turn and resolves
        -- in speed order, so a faster enemy gets its hit in first. It used to
        -- preempt the whole round from a `act.type == "flee"` scan in
        -- Battle:checkFlee, which meant one battle verb resolved somewhere no
        -- other verb did, and an escape ITEM could not exist at all.
        --
        -- The odds, FLEE_CHANCE_BONUS and gold penalty are unchanged -- they
        -- live in the battle.flee_attempt flow, which is still the only place
        -- that decides. Emitting flee_success is what ends the battle; the
        -- battle scene watches for it.
        local battle = context and context.battle
        if battle then
            local flowEvents = require("engine.flow").run("battle.flee_attempt", {
                session = session,
                battle = battle,
            })
            for _, ev in ipairs(flowEvents) do table.insert(events, ev) end
        end
    elseif effectData.type == "common_event" then
        local ceId = effectData.value
        local ce = session.loader.commonEvents and session.loader.commonEvents[tostring(ceId)]
        if not ce then
            table.insert(events, {
                type = "text",
                text = "[effect] common_event: unknown common event '" .. tostring(ceId) .. "'"
            })
        else
            table.insert(events, { type = "run_common_event", id = ceId })
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

    elseif effectData.type == "barrier" then
        -- The effect carries the whole authored spec, so granting a barrier
        -- names no element, skill or creature.
        for _, ev in ipairs(barriers.grant(b or a, effectData, session, context or {})) do
            table.insert(events, ev)
        end
    end

    return events
end

local function reactionFor(target, item)
    local lines = target and target.actorData and target.actorData.foodReactions
    if not lines or #lines == 0 then return nil end
    local key = tonumber(item.id) or #tostring(item.id or "")
    return lines[(key % #lines) + 1]
end

-- Favorite Food is resolved once per item use, not once per effect. An exact
-- favorite discovers itself and starts Savor only when no Savor is active;
-- feeding it again during the cooldown cannot refresh the counter.
function effects.finishItemUse(item, user, targets, session)
    local events = {}
    if not item or not session or (not item.meal and not item.foodTags) then return events end
    for _, target in ipairs(targets or {}) do
        if target and target.favoriteFood ~= nil then
            if tostring(target.favoriteFood) == tostring(item.id) then
                if not target.favoriteFoodFound then
                    target.favoriteFoodFound = true
                    table.insert(events, { type = "favorite_food_found", target = target, item = item.id })
                    table.insert(events, {
                        type = "text",
                        text = session.loader.formatTerm("food.favorite_found",
                            "- {0} loves {1}!", target.name, item.name)
                    })
                end
                if not target.savor or (target.savor.battlesRemaining or 0) <= 0 then
                    local authored = item.savor or {}
                    target.savor = {
                        itemId = item.id,
                        battlesRemaining = math.max(1, math.floor(authored.battles or 3)),
                        traits = authored.traits or {}
                    }
                    table.insert(events, {
                        type = "savor_start", target = target, item = item.id,
                        battles = target.savor.battlesRemaining
                    })
                end
            else
                local line = reactionFor(target, item)
                if line then
                    table.insert(events, {
                        type = "text",
                        text = session.loader.formatTerm("food.reaction",
                            "- {0}: {1}", target.name, line)
                    })
                end
            end
        end
    end
    return events
end

return effects