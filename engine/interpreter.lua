-- Public interpreter surface. Command semantics remain in interpreter_core.lua;
-- this facade reconciles round-end state expiry with the vitality contract.
-- Keeping the rule here means timed PARAM_PLUS maxHp states work no matter what
-- content id carries them, without hardcoding Red/Green skills or state names.
local core = require("engine.interpreter_core")
local formation = require("engine.formation")
local traits = require("engine.traits")
local vitality = require("engine.vitality")

local interpreter = {}
for k, v in pairs(core) do interpreter[k] = v end

local function hasCommand(commands, id)
    for _, cmd in ipairs(commands or {}) do
        if cmd.cmd == id then return true end
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

function interpreter.runImmediate(commands, ctx)
    ctx = ctx or {}
    local watchesStateTicks = hasCommand(commands, "STATE_TICKS")
    if not watchesStateTicks then
        return core.runImmediate(commands, ctx)
    end

    local watched = battlersIn(ctx)
    local before = {}
    for _, b in ipairs(watched) do
        before[b] = {
            hp = b.hp or 0,
            maxHp = traits.getParam(b, "maxHp", ctx.session),
        }
    end
    local initialEventCount = #(ctx.events or {})
    local events = core.runImmediate(commands, ctx)

    -- Core HRG predates Overheal and uses math.min(maxHp, hp + amount). Repair
    -- its EVENT value to the real recovered amount and restore pre-existing
    -- Overheal instead of letting a positive regen tick delete it.
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
            if actual == 0 then table.remove(events, i) end
        end
    end

    -- STATE_TICKS removes expired states directly from the list in the mature
    -- core. Compare effective Max HP across the phase and perform a capacity
    -- clamp here. This is deliberately not damage and can never create death.
    for _, b in ipairs(watched) do
        local snap = before[b]
        local afterMax = traits.getParam(b, "maxHp", ctx.session)
        if afterMax ~= snap.maxHp then
            local transition = vitality.maxHpTransition(b, snap.maxHp, afterMax)
            table.insert(events, {
                type = "max_hp_change", target = b,
                before = transition.before, after = transition.after,
                value = transition.delta,
                hpGranted = transition.hpGranted,
                hpClamped = transition.hpClamped,
                temporary = true, reason = "state_tick",
            })
            if transition.hpGranted > 0 then
                table.insert(events, {
                    type = "heal", target = b, value = transition.hpGranted,
                    cap = afterMax, reason = "max_hp_gain",
                })
            elseif transition.hpClamped > 0 then
                table.insert(events, {
                    type = "hp_clamp", target = b, value = b.hp,
                    removed = transition.hpClamped, reason = "max_hp_loss",
                })
            end
        end
    end

    return events
end

return interpreter
