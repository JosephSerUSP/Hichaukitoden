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

local function snapshotTarget(target, session)
    if not target then return nil end
    return {
        hp = target.hp or 0,
        maxHp = traits.getParam(target, "maxHp", session),
    }
end

-- #179: events are also the presentation boundary, so publish resolved facts
-- while the semantic owner still has both sides of the transition available.
-- Presentation may delay SHOWING these facts, but must never have to rerun HP,
-- cap or shared-MP rules to discover what happened.
local function resolvedFacts(events, beforeA, beforeB, a, b, session,
        mpBefore, maxMpBefore)
    events = events or {}
    local cursors = {}
    local function seed(target, snap)
        if target and snap and not cursors[target] then
            cursors[target] = { hp = snap.hp, maxHp = snap.maxHp }
        end
    end
    seed(a, beforeA)
    seed(b, beforeB)

    local maxChangePublished = {}
    for _, ev in ipairs(events) do
        local target = ev.target
        local cur = target and cursors[target]
        if cur then
            if ev.type == "damage" then
                ev.hpBefore = cur.hp
                ev.maxHpBefore = cur.maxHp
                cur.hp = math.max(0, cur.hp - (ev.value or 0))
                ev.hpAfter = cur.hp
                ev.maxHpAfter = cur.maxHp
            elseif ev.type == "heal" then
                ev.hpBefore = cur.hp
                ev.maxHpBefore = cur.maxHp
                -- Public heal events carry the amount ACTUALLY granted. Add
                -- that resolved delta verbatim. Do not clamp against ev.cap
                -- here: preserving pre-existing Overheal is part of vitality's
                -- contract, and clamping this descriptive cursor would invent a
                -- different result from the mutation that already happened.
                cur.hp = cur.hp + (ev.value or 0)
                ev.hpAfter = cur.hp
                ev.maxHpAfter = cur.maxHp
            elseif ev.type == "hp_clamp" then
                ev.hpBefore = cur.hp
                ev.maxHpBefore = cur.maxHp
                cur.hp = ev.value or cur.hp
                ev.hpAfter = cur.hp
                ev.maxHpAfter = cur.maxHp
            elseif ev.type == "max_hp_change" then
                ev.maxHpBefore = ev.before or cur.maxHp
                cur.maxHp = ev.after or cur.maxHp
                ev.maxHpAfter = cur.maxHp
                maxChangePublished[target] = true
            elseif ev.type == "death" then
                ev.hpBefore = cur.hp
                ev.maxHpBefore = cur.maxHp
                cur.hp = 0
                ev.hpAfter = 0
                ev.maxHpAfter = cur.maxHp
            end
        end
    end

    -- Permanent max-HP growth can be represented by an ordinary heal + text
    -- rather than max_hp_change. Publish the new cap on the first target event
    -- so the view moves to the engine's resolved capacity without inspecting
    -- mutated paramPlus itself.
    for target, cur in pairs(cursors) do
        local finalMax = traits.getParam(target, "maxHp", session)
        if finalMax ~= cur.maxHp and not maxChangePublished[target] then
            for _, ev in ipairs(events) do
                if ev.target == target then
                    ev.maxHpBefore = ev.maxHpBefore or cur.maxHp
                    ev.maxHpAfter = finalMax
                    break
                end
            end
            cur.maxHp = finalMax
        end
    end

    local mpAfter = session and session.mp or mpBefore
    local maxMpAfter = session and session.maxMp or maxMpBefore
    if session and (mpAfter ~= mpBefore or maxMpAfter ~= maxMpBefore) then
        local carrier = nil
        -- Prefer the semantic event when one exists; otherwise an effect such
        -- as mp_heal/max_mp_plus historically reports itself as text only.
        for _, ev in ipairs(events) do
            if ev.type == "kill_mp_restore" or ev.type == "mp_drain" then
                carrier = ev
                break
            end
        end
        carrier = carrier or events[1]
        if carrier then
            carrier.mpBefore = mpBefore
            carrier.mpAfter = mpAfter
            carrier.maxMpBefore = maxMpBefore
            carrier.maxMpAfter = maxMpAfter
        end
    end

    return events
end

function effects.apply(effectData, a, b, session, context)
    local beforeA = snapshotTarget(a, session)
    local beforeB = (b == a) and beforeA or snapshotTarget(b, session)
    local mpBefore = session and session.mp or 0
    local maxMpBefore = session and session.maxMp or mpBefore
    local function finish(events)
        return resolvedFacts(events, beforeA, beforeB, a, b, session,
            mpBefore, maxMpBefore)
    end

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
        return finish(events)
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
        return finish(events)
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
        return finish(events)
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
        local healEv = findEvent(events, "heal", b)
        if b and healEv then healEv.value = math.max(0, b.hp - beforeHp) end
        return finish(events)
    end

    return finish(core.apply(effectData, a, b, session, context))
end

return effects
