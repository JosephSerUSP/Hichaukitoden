-- Public interpreter surface. Command semantics remain in interpreter_core.lua;
-- this facade reconciles round-end state expiry with the vitality contract.
-- Keeping the rule here means timed PARAM_PLUS maxHp states work no matter what
-- content id carries them, without hardcoding Red/Green skills or state names.
--
-- #179 adds one second, deliberately narrow responsibility while #178's facade
-- cleanup is still pending: events leaving the immediate interpreter are
-- stamped with already-resolved facts, and REAP_FALLEN's engine decision is
-- committed before control returns to presentation. No presentation callback
-- owns GameSession membership anymore.
local core = require("engine.interpreter_core")
local formation = require("engine.formation")
local traits = require("engine.traits")
local vitality = require("engine.vitality")
local resolved_event = require("engine.resolved_event")
local config = require("engine.config")

local interpreter = {}
for k, v in pairs(core) do interpreter[k] = v end

-- STATE_TICKS is normally a top-level round-end phase command, but immediate
-- command lists may contain nested IF/branch command tables too. Watch the
-- whole authored tree so a future data-only rearrangement cannot bypass the
-- Max-HP expiry reconciliation.
local function hasCommand(node, id, seen)
    if type(node) ~= "table" then return false end
    seen = seen or {}
    if seen[node] then return false end
    seen[node] = true
    if node.cmd == id then return true end
    for _, value in pairs(node) do
        if type(value) == "table" and hasCommand(value, id, seen) then return true end
    end
    return false
end

local function battlersIn(ctx)
    local out, seen = {}, {}
    local function add(group)
        for _, b in ipairs(formation.denseMembers(group or {})) do
            if b and not seen[b] then seen[b] = true; table.insert(out, b) end
        end
    end
    add(ctx and ctx.party)
    add(ctx and ctx.enemies)
    if ctx and ctx.session then
        add(ctx.session.party)
    end
    return out
end

local function copyRoster(src, maxSlots)
    local out = {}
    for i = 1, maxSlots do out[i] = src and src[i] or nil end
    return out
end

-- REAP_FALLEN already decides who dies, how much EXP is banked and which party
-- slot that creature occupied. Historically it deliberately stopped one write
-- short and let processEvent("reap") clear that slot later. That made a visual
-- callback part of domain correctness. Commit the already-decided removals here,
-- after the whole immediate flow has run but before it returns to the scene.
--
-- We build per-event roster snapshots beside the real writes so presentation
-- can still fade one outgoing card at a time. If the final removal empties the
-- field, autoFieldIfEmpty runs here too; only the final reap snapshot exposes
-- those replacements, matching the old last-card completion beat.
local function commitReaps(events, session, firstNew)
    if not session then return end
    local stagedParty = copyRoster(session.party, config.MAX_PARTY_SIZE)
    local stagedReserve = copyRoster(session.reserve, config.MAX_RESERVE_SIZE)
    local fieldReaps = {}

    for i = firstNew, #events do
        local ev = events[i]
        if ev and ev.type == "reap" and ev.slot then
            table.insert(fieldReaps, ev)
            stagedParty[ev.slot] = nil
            session.party[ev.slot] = nil

            ev.resolved = ev.resolved or {}
            ev.resolved.party = copyRoster(stagedParty, config.MAX_PARTY_SIZE)
            ev.resolved.reserve = copyRoster(stagedReserve, config.MAX_RESERVE_SIZE)
        end
    end

    if #fieldReaps > 0 then
        session:autoFieldIfEmpty()
        -- The final visible reap beat reveals any automatic reserve deployment
        -- produced by the authoritative post-reap roster rule.
        resolved_event.attachRoster(fieldReaps[#fieldReaps], session)
    end
end

local function publishUnstamped(events, session, firstNew)
    for i = firstNew, #events do
        local ev = events[i]
        -- effects.apply and battle.lua may already have stamped the event at a
        -- more precise semantic write site. Never replace those exact snapshots
        -- with the later end-of-phase state; this is only a safety net for the
        -- remaining direct interpreter handlers until #178 folds the facade in.
        if ev and ev.resolved == nil then
            resolved_event.attach(ev, session)
        end
    end
end

function interpreter.runImmediate(commands, ctx)
    ctx = ctx or {}
    local initialEventCount = #(ctx.events or {})
    local watchesStateTicks = hasCommand(commands, "STATE_TICKS")
    local events

    if not watchesStateTicks then
        events = core.runImmediate(commands, ctx)
    else
        local watched = battlersIn(ctx)
        local before = {}
        for _, b in ipairs(watched) do
            before[b] = {
                hp = b.hp or 0,
                maxHp = traits.getParam(b, "maxHp", ctx.session),
            }
        end
        events = core.runImmediate(commands, ctx)

        -- Core HRG predates Overheal and uses math.min(maxHp, hp + amount).
        -- Repair its EVENT value to the real recovered amount and restore
        -- pre-existing Overheal instead of letting a positive regen tick delete
        -- it. (#178 will move this reconciliation into STATE_TICKS itself.)
        for i = #events, initialEventCount + 1, -1 do
            local ev = events[i]
            local snap = ev and ev.type == "heal" and before[ev.target]
            if snap then
                local requested = math.max(0, tonumber(ev.value) or 0)
                local actual = math.max(0, math.min(snap.maxHp, snap.hp + requested) - snap.hp)
                ev.value = actual
                if snap.hp > snap.maxHp and ev.target.hp < snap.hp then
                    ev.target.hp = snap.hp
                end
                if actual == 0 then
                    table.remove(events, i)
                else
                    -- This direct STATE_TICKS event did not pass through
                    -- effects.apply; stamp it only after the existing repair has
                    -- reached its actual authoritative result.
                    resolved_event.attach(ev, ctx.session)
                end
            end
        end

        -- STATE_TICKS removes expired states directly from the list in the
        -- mature core. Compare effective Max HP across the phase and perform a
        -- capacity clamp here. This is deliberately not damage and can never
        -- create death.
        for _, b in ipairs(watched) do
            local snap = before[b]
            local afterMax = traits.getParam(b, "maxHp", ctx.session)
            if afterMax ~= snap.maxHp then
                local transition = vitality.maxHpTransition(b, snap.maxHp, afterMax)
                local maxEv = {
                    type = "max_hp_change", target = b,
                    before = transition.before, after = transition.after,
                    value = transition.delta,
                    hpGranted = transition.hpGranted,
                    hpClamped = transition.hpClamped,
                    temporary = true, reason = "state_tick",
                }
                resolved_event.attach(maxEv, ctx.session)
                table.insert(events, maxEv)
                if transition.hpGranted > 0 then
                    local healEv = {
                        type = "heal", target = b, value = transition.hpGranted,
                        cap = afterMax, reason = "max_hp_gain",
                    }
                    resolved_event.attach(healEv, ctx.session)
                    table.insert(events, healEv)
                elseif transition.hpClamped > 0 then
                    local clampEv = {
                        type = "hp_clamp", target = b, value = b.hp,
                        removed = transition.hpClamped, reason = "max_hp_loss",
                    }
                    resolved_event.attach(clampEv, ctx.session)
                    table.insert(events, clampEv)
                end
            end
        end
    end

    -- firstNew is calculated after any STATE_TICKS removals/insertions but the
    -- prefix event count itself is stable: all new events are still after it.
    local firstNew = initialEventCount + 1
    commitReaps(events, ctx.session, firstNew)
    publishUnstamped(events, ctx.session, firstNew)
    return events
end

return interpreter
