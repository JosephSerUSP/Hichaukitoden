local traits = require("engine.traits")
local formulaEngine = require("engine.formula")

local vitality = {}

-- A safety ceiling for projects which have not authored combat.overhealCap yet.
-- The cap is a multiplier of the creature's CURRENT effective Max HP. It is a
-- ceiling for recovery, not a second HP pool: current HP remains battler.hp and
-- damage consumes it normally.
local DEFAULT_OVERHEAL_CAP = 1.5

function vitality.maxHpComponents(battler, session)
    if not battler then
        return { base = 0, permanentPlus = 0, underlying = 0, active = 0, activeModifier = 0 }
    end
    local base = traits.getBaseParam(battler, "maxHp")
    local permanentPlus = (battler.paramPlus and battler.paramPlus.maxHp) or 0
    local underlying = math.max(1, math.floor(base + permanentPlus))
    local active = traits.getParam(battler, "maxHp", session)
    return {
        base = base,
        permanentPlus = permanentPlus,
        underlying = underlying,
        active = active,
        -- Includes every currently-active trait contribution (states, gear,
        -- passives, Savor and PARAM_RATE), deliberately separate from the
        -- persistent paramPlus bucket above.
        activeModifier = active - underlying,
    }
end

-- HP thresholds use current HP / CURRENT effective Max HP. The ratio is not
-- clamped, so an Overhealed creature can deterministically report > 1.0 (and
-- therefore > 100%). This is the same interpretation traits.evaluateCondition
-- already uses for authored "HP < N%" conditions.
function vitality.hpRatio(battler, session)
    local maxHp = traits.getParam(battler, "maxHp", session)
    if maxHp <= 0 then return 0 end
    return (battler.hp or 0) / maxHp
end

function vitality.overhealCapRatio(effectData, session)
    if not (effectData and effectData.overheal == true) then return 1 end
    local combat = session and session.loader and session.loader.system
        and session.loader.system.combat or {}
    local ratio = effectData.overhealCap or combat.overhealCap or DEFAULT_OVERHEAL_CAP
    ratio = tonumber(ratio) or DEFAULT_OVERHEAL_CAP
    return math.max(1, ratio)
end

function vitality.recoveryCap(effectData, battler, session)
    local maxHp = traits.getParam(battler, "maxHp", session)
    return math.max(maxHp, math.floor(maxHp * vitality.overhealCapRatio(effectData, session)))
end

-- Applies positive recovery without ever reducing existing HP. That last rule
-- matters once Overheal exists: an ordinary potion/regen tick used at 120/100
-- restores zero; it must not silently snap the creature back to 100/100.
function vitality.applyHeal(effectData, battler, amount, session)
    if not battler then return 0, 0 end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local before = battler.hp or 0
    local cap = vitality.recoveryCap(effectData, battler, session)
    local after = math.max(before, math.min(cap, before + amount))
    battler.hp = after
    return after - before, cap
end

local function evaluateFormula(expr, a, b, session, events)
    if not expr then return 0 end
    local ctx = formulaEngine.makeContext({ a = a, b = b, target = b }, session)
    local val, err = formulaEngine.eval(expr, ctx)
    if err and events then
        table.insert(events, { type = "text", text = "[effect] formula error: " .. tostring(err) })
    end
    return tonumber(val) or 0
end

local function itemRate(b, session, context)
    if not (context and context.isItem) or not session then return 1.0 end
    local user = context.user or b
    if not user then return 1.0 end
    return 1.0 + traits.getRate(user, "ITEM_EFFECT_RATE", session)
end

-- One recovery implementation for both formula heals and flat/percentage item
-- HP effects. `overheal = true` changes only the cap; HEAL_RATE,
-- ITEM_EFFECT_RATE and percentage bases keep their ordinary meanings.
function vitality.applyHealingEffect(effectData, a, b, session, context, events)
    local raw = 0
    if effectData.type == "hp_heal" then
        local skillRate = (context and context.isItem) and 1
            or (1 + traits.getRate(a, "HEAL_RATE", session))
        raw = evaluateFormula(effectData.formula, a, b, session, events)
            * skillRate * itemRate(b, session, context)
    elseif effectData.type == "hp" then
        local maxHp = traits.getParam(b, "maxHp", session)
        raw = ((effectData.value or 0) + maxHp * (effectData.percent or 0))
            * itemRate(b, session, context)
    else
        error("vitality.applyHealingEffect: unsupported effect type '"
            .. tostring(effectData.type) .. "'", 2)
    end
    local healed, cap = vitality.applyHeal(effectData, b, raw, session)
    return healed, cap, math.max(0, math.floor(raw))
end

-- Capacity growth grants the amount of NEW capacity as current HP, but never
-- double-counts HP which was already present as Overheal. Thus 80/100 +25 ->
-- 105/125, while 130/100 +25 -> 130/125.
function vitality.applyMaxHpIncrease(battler, beforeMax, afterMax)
    if not battler or afterMax <= beforeMax then return 0 end
    local beforeHp = battler.hp or 0
    local gain = afterMax - beforeMax
    battler.hp = math.max(beforeHp, math.min(afterMax, beforeHp + gain))
    return battler.hp - beforeHp
end

-- Capacity loss is a clamp, never damage. Callers report it as max_hp_change /
-- hp_clamp events rather than damage/death so damage reactions cannot fire.
function vitality.applyMaxHpDecrease(battler, afterMax)
    if not battler then return 0 end
    local beforeHp = battler.hp or 0
    battler.hp = math.min(beforeHp, afterMax)
    return beforeHp - battler.hp
end

function vitality.maxHpTransition(battler, beforeMax, afterMax)
    local hpGranted, hpClamped = 0, 0
    if afterMax > beforeMax then
        hpGranted = vitality.applyMaxHpIncrease(battler, beforeMax, afterMax)
    elseif afterMax < beforeMax then
        hpClamped = vitality.applyMaxHpDecrease(battler, afterMax)
    end
    return {
        before = beforeMax,
        after = afterMax,
        delta = afterMax - beforeMax,
        hpGranted = hpGranted,
        hpClamped = hpClamped,
    }
end

return vitality
