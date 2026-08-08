-- Detached battle presentation projection (#179).
--
-- Battle resolution commits the real Battle/Battler/GameSession graph once.
-- This module keeps only the small slice the battle UI deliberately reveals on
-- a later visual beat. It never calls gameplay mutators and never writes hp,
-- states, MP, party or reserve on authoritative objects.
--
-- Real battler identity is intentionally preserved. Animation_player and the
-- small-battler renderer key transient visual state by the Battler object, so a
-- cloned Battler graph would introduce identity/reconciliation machinery for no
-- gameplay benefit. The projection is keyed *by* the real battler while storing
-- detached values beside it.
local config = require("engine.config")

local battle_view = {}

local sourceSession = nil
local active = false
local battlers = {}
local party = {}
local reserve = {}
local mp = nil
local displayedMp = nil
local proxy = nil

local function copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[copy(k, seen)] = copy(v, seen) end
    return out
end

local function copyRoster(src, maxSlots)
    local out = {}
    for i = 1, maxSlots do out[i] = src and src[i] or nil end
    return out
end

local function stateHas(states, id)
    for _, st in ipairs(states or {}) do
        if st.id == id then return true end
    end
    return false
end

local function ensureBattler(b)
    if not b then return nil end
    local found = battlers[b]
    if found then return found end
    local maxHp = sourceSession and b.getMaxHp and b:getMaxHp(sourceSession) or 1
    found = {
        hp = b.hp or 0,
        displayedHp = b.displayedHp or b.hp or 0,
        maxHp = maxHp,
        states = copy(b.states or {}),
    }
    battlers[b] = found
    return found
end

local function captureBattler(b)
    if not b then return end
    local entry = ensureBattler(b)
    entry.hp = b.hp or 0
    entry.displayedHp = b.displayedHp or b.hp or 0
    entry.maxHp = sourceSession and b.getMaxHp and b:getMaxHp(sourceSession) or entry.maxHp
    entry.states = copy(b.states or {})
end

-- Move an existing view entry's semantic targets to current authoritative
-- values while preserving its in-flight displayedHp interpolation. This is
-- used only at boundaries that were already immediate in the old scene (for
-- example victory rewards/ward saves), never to fake an event-timed beat.
local function syncBattler(b, session)
    if not b then return end
    local entry = ensureBattler(b)
    entry.hp = b.hp or 0
    entry.maxHp = b.getMaxHp and b:getMaxHp(session or sourceSession) or entry.maxHp
    entry.states = copy(b.states or {})
end

function battle_view.clear()
    sourceSession = nil
    active = false
    battlers = {}
    party = {}
    reserve = {}
    mp = nil
    displayedMp = nil
    proxy = nil
end

function battle_view.isActive()
    return active
end

-- Capture the frame that is currently on screen, then let the engine resolve
-- past it. Calling this at each round boundary also converges any tiny HP gauge
-- interpolation remainder from the previous round without touching domain hp.
function battle_view.beginRound(battle, session)
    sourceSession = session
    active = true
    battlers = {}
    party = copyRoster(session and session.party, config.MAX_PARTY_SIZE)
    reserve = copyRoster(session and session.reserve, config.MAX_RESERVE_SIZE)
    mp = session and session.mp or 0
    displayedMp = session and (session.displayedMp or session.mp) or mp
    proxy = nil

    if battle and battle.getAllActiveBattlers then
        for _, b in ipairs(battle:getAllActiveBattlers()) do captureBattler(b) end
    end
    for i = 1, config.MAX_PARTY_SIZE do captureBattler(party[i]) end
    for i = 1, config.MAX_RESERVE_SIZE do captureBattler(reserve[i]) end
end

-- Apply only the resolved channels whose *visual beat* has landed. `ev.resolved`
-- contains engine-authored after-values; no arithmetic or Battler mutation is
-- repeated here.
function battle_view.apply(ev, channels)
    if not active or not ev then return end
    local r = ev.resolved
    if not r then return end
    channels = channels or {}

    if ev.target then
        local entry = ensureBattler(ev.target)
        if channels.hp and r.hp ~= nil then entry.hp = r.hp end
        if channels.maxHp and r.maxHp ~= nil then entry.maxHp = r.maxHp end
        if channels.states and r.states ~= nil then entry.states = copy(r.states) end
    end
    if channels.mp and r.mp ~= nil then mp = r.mp end
end

-- Some post-round engine phases have always become visible immediately once
-- the battle log is finished (victory rewards, ward saves, state cleanup).
-- While reap animations still need the old roster on screen, converge every
-- non-roster field to authoritative truth without exposing the already-removed
-- party slots early.
function battle_view.syncNonRoster(battle, session)
    if not active then return end
    session = session or sourceSession
    if battle and battle.getAllActiveBattlers then
        for _, b in ipairs(battle:getAllActiveBattlers()) do syncBattler(b, session) end
    end
    for i = 1, config.MAX_PARTY_SIZE do
        syncBattler(party[i], session)
        syncBattler(session and session.party and session.party[i], session)
    end
    for i = 1, config.MAX_RESERVE_SIZE do
        syncBattler(reserve[i], session)
        syncBattler(session and session.reserve and session.reserve[i], session)
    end
    if session then mp = session.mp end
end

-- Wave events carry resolved before/after identities per slot. Applying one
-- pending entry at a time preserves the existing staggered card-flip animation
-- while authoritative party/reserve membership has already been committed.
function battle_view.applyWaveSlot(p)
    if not active or not p then return end
    if p.slot then
        party[p.slot] = p.partyAfter ~= nil and p.partyAfter or p.battler
        ensureBattler(party[p.slot])
    end
    if p.reserveKey then
        reserve[p.reserveKey] = p.reserveAfter
    end
    proxy = nil
end

-- Reap events carry the engine-resolved roster snapshot that should become
-- visible when that particular reap animation completes.
function battle_view.applyRoster(ev)
    if not active or not ev or not ev.resolved then return end
    local r = ev.resolved
    if r.party then party = copyRoster(r.party, config.MAX_PARTY_SIZE) end
    if r.reserve then reserve = copyRoster(r.reserve, config.MAX_RESERVE_SIZE) end
    for i = 1, config.MAX_PARTY_SIZE do ensureBattler(party[i]) end
    for i = 1, config.MAX_RESERVE_SIZE do ensureBattler(reserve[i]) end
    proxy = nil
end

-- Runs after renderer.update. renderer's legacy HP/MP easing still targets the
-- authoritative values, so while a projection is active we overwrite only the
-- presentation-only displayedHp/displayedMp fields from our own interpolation.
-- Authoritative hp/mp are never touched.
function battle_view.update(dt, session)
    if not active then return end
    session = session or sourceSession
    local k = 8 * (dt or 0)
    for b, entry in pairs(battlers) do
        entry.displayedHp = entry.displayedHp + (entry.hp - entry.displayedHp) * k
        if math.abs(entry.hp - entry.displayedHp) < 0.1 then entry.displayedHp = entry.hp end
        b.displayedHp = entry.displayedHp
    end
    if session then
        displayedMp = displayedMp + (mp - displayedMp) * k
        if math.abs(mp - displayedMp) < 0.1 then displayedMp = mp end
        session.displayedMp = displayedMp
    end
end

function battle_view.statesFor(battler)
    local e = active and battlers[battler]
    return e and e.states or (battler and battler.states) or {}
end

function battle_view.maxHpFor(battler, session)
    local e = active and battlers[battler]
    if e and e.maxHp ~= nil then return e.maxHp end
    if battler and battler.getMaxHp then return battler:getMaxHp(session or sourceSession) end
    return 1
end

function battle_view.isDead(battler)
    local e = active and battlers[battler]
    if not e then return battler and battler:isDead() or false end
    return (e.hp or 0) <= 0 or stateHas(e.states, "dead")
end

function battle_view.partyFor(session)
    if active and session == sourceSession then return party end
    return session and session.party or {}
end

function battle_view.reserveFor(session)
    if active and session == sourceSession then return reserve end
    return session and session.reserve or {}
end

-- Presentation-only GameSession facade: methods/other fields fall through to
-- the real session, but roster reads use the delayed view. This keeps generic
-- window rendering data-driven; it does not need a battle-specific list source.
function battle_view.sessionFor(session)
    if not active or session ~= sourceSession then return session end
    if proxy then
        proxy.party = party
        proxy.reserve = reserve
        proxy.displayedMp = session.displayedMp
        return proxy
    end
    proxy = setmetatable({
        party = party,
        reserve = reserve,
        displayedMp = session.displayedMp,
    }, { __index = session })
    return proxy
end

-- Introspection for tests: detached values only, never authoritative objects.
function battle_view.inspect(battler)
    local e = battlers[battler]
    if not e then return nil end
    return {
        hp = e.hp,
        displayedHp = e.displayedHp,
        maxHp = e.maxHp,
        states = copy(e.states),
        mp = mp,
        party = copyRoster(party, config.MAX_PARTY_SIZE),
        reserve = copyRoster(reserve, config.MAX_RESERVE_SIZE),
    }
end

return battle_view
