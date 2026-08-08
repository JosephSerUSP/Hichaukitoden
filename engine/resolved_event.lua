-- Resolved semantic facts carried by engine events.
--
-- Presentation may need to reveal a transition later than the engine resolves
-- it, but it must never reconstruct the transition itself. This module records
-- small immutable after-snapshots on events at the semantic write site so a
-- view/projection can display facts the engine already decided.
--
-- These snapshots are deliberately partial: only values a live presentation
-- currently delays belong here. Adding a new domain field never requires a
-- rollback entry; it only needs a resolved event value if/when a UI chooses to
-- stage that field visually.
local config = require("engine.config")

local resolved_event = {}

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        out[copy(k, seen)] = copy(v, seen)
    end
    return out
end

local function copyRoster(roster, maxSlots)
    local out = {}
    for i = 1, maxSlots do out[i] = roster and roster[i] or nil end
    return out
end

function resolved_event.states(states)
    return copy(states or {})
end

function resolved_event.battler(target, session)
    -- Not every descriptive engine event uses `target` for a Battler. Keep the
    -- event contract generic: only battler-like tables receive battler facts.
    if type(target) ~= "table" or type(target.getMaxHp) ~= "function" then
        return nil
    end
    return {
        hp = target.hp,
        maxHp = target:getMaxHp(session),
        states = resolved_event.states(target.states),
    }
end

-- Attach the currently resolved battler/session facts to one event. Call this
-- immediately after the semantic mutation that produced the event.
function resolved_event.attach(ev, session)
    if not ev then return ev end
    local r = ev.resolved or {}
    local b = resolved_event.battler(ev.target, session)
    if b then
        r.hp = b.hp
        r.maxHp = b.maxHp
        r.states = b.states
    end
    if session then r.mp = session.mp end
    ev.resolved = r
    return ev
end

function resolved_event.roster(session)
    if not session then return nil, nil end
    return copyRoster(session.party, config.MAX_PARTY_SIZE),
        copyRoster(session.reserve, config.MAX_RESERVE_SIZE)
end

function resolved_event.attachRoster(ev, session, party, reserve)
    if not ev then return ev end
    local r = ev.resolved or {}
    if party == nil or reserve == nil then
        party, reserve = resolved_event.roster(session)
    else
        party = copyRoster(party, config.MAX_PARTY_SIZE)
        reserve = copyRoster(reserve, config.MAX_RESERVE_SIZE)
    end
    r.party = party
    r.reserve = reserve
    if session then r.mp = session.mp end
    ev.resolved = r
    return ev
end

return resolved_event
