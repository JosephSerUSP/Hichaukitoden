-- Public effect surface. The pre-#166 implementation lives unchanged in
-- effects_core.lua; this facade owns the cross-cutting vitality rules so every
-- caller of engine.effects gets one Overheal / Max-HP transition contract.
local core = require("engine.effects_core")
local traits = require("engine.traits")
local vitality = require("engine.vitality")

local effects = {}
for k, v in pairs(core) do effects[k] = v end

local function maxHpEvent(target, transition, extra)
    local ev = {
        type = "max_hp_change",
        target = target,
        before = transition.before,
        after = transition.after,
        value = transition.delta,
        hpGranted = transition.hpGranted,
        hpClamped = transition.hpClamped,
    }
    for k, v in pairs(extra or {}) do ev[k] = v end
    return ev
end

local function findEvent(events, kind, target)
    for _, ev in ipairs(events or {}) do
        if ev.type == kind and (target == nil or ev.target == target) then return ev end
    end
end

function effects.apply(effectData, a, b, session, context)
    -- Ordinary and Overheal-capable recovery intentionally share all formula,
    -- HEAL_RATE and item-rate math. Only the recovery ceiling differs.
    if effectData.type == "hp_heal" or effectData.type == "hp" then
        local events = {}
        local healed, cap = vitality.applyHealingEffect(effectData, a, b, session, context, events)
        table.insert(events, {
            type = "heal",
            target = b,
            value = healed,
            cap = cap,
            overheal = effectData.overheal == true or nil,
        })
        return events
    end

    -- Drain damage remains the mature core path (crit, affinity, execution,
    -- death and kill rewards). Re-run only its recovery side through vitality
    -- so a drain cannot erase existing Overheal and can opt into Overheal with
    -- the same authored fields as other recovery. A self-drain is left to the
    -- mature path: restoring the source snapshot there would also undo the
    -- damage because source and target are the same object.
    if effectData.type == "hp_drain" and a and a ~= b then
        local beforeHp = a.hp or 0
        local events = core.apply(effectData, a, b, session, context)
        local damageEv = findEvent(events, "damage", b)
        local healEv = findEvent(events, "heal", a)
        if damageEv and healEv then
            a.hp = beforeHp
            local healed, cap = vitality.applyHeal(effectData, a, damageEv.value or 0, session)
            healEv.value = healed
            healEv.cap = cap
            healEv.overheal = effectData.overheal == true or nil
        end
        return events
    end

    -- A state is the existing battle-scoped carrier for temporary parameter
    -- traits. PARAM_PLUS maxHp therefore changes active Max HP without touching
    -- persistent battler.paramPlus. The facade observes the effective Max HP on
    -- either side of the ordinary state transaction and applies the shared
    -- capacity transition semantics.
    if (effectData.type == "add_status" or effectData.type == "remove_status") and b then
        local beforeMax = traits.getParam(b, "maxHp", session)
        local events = core.apply(effectData, a, b, session, context)
        local changed = effectData.type == "add_status"
            and findEvent(events, "state_add", b)
            or findEvent(events, "state_remove", b)
        if changed then
            local afterMax = traits.getParam(b, "maxHp", session)
            if afterMax ~= beforeMax then
                local transition = vitality.maxHpTransition(b, beforeMax, afterMax)
                table.insert(events, maxHpEvent(b, transition, {
                    temporary = true,
                    state = effectData.status or effectData.value,
                }))
                if transition.hpGranted > 0 then
                    -- Presentation can replay the state_add first (raising the
                    -- cap), then this ordinary heal without inferring a delta.
                    table.insert(events, {
                        type = "heal", target = b, value = transition.hpGranted,
                        cap = afterMax, reason = "max_hp_gain",
                    })
                elseif transition.hpClamped > 0 then
                    -- A distinct non-damage event. The battle presentation seam
                    -- can apply the assignment without producing damage/death
                    -- reactions or a fake green recovery popup.
                    table.insert(events, {
                        type = "hp_clamp", target = b, value = b.hp,
                        removed = transition.hpClamped, reason = "max_hp_loss",
                    })
                end
            end
        end
        return events
    end

    -- Permanent Max-HP growth keeps its existing lifetime and event text. If
    -- current HP was already above the old cap, raising that cap must not erase
    -- real HP merely because the mature implementation used math.min.
    local permanentParam = effectData.param or effectData.dataId
    if effectData.type == "maxHp"
        or (effectData.type == "param_plus" and permanentParam == "maxHp") then
        local beforeHp = b and b.hp or 0
        local beforeMax = b and traits.getParam(b, "maxHp", session) or 0
        local events = core.apply(effectData, a, b, session, context)
        if b and beforeHp > beforeMax and b.hp < beforeHp then b.hp = beforeHp end
        return events
    end

    return core.apply(effectData, a, b, session, context)
end

return effects
