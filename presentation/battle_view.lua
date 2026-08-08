-- Detached presentation-time battle projection (#179).
--
-- Battle resolution mutates the real Battle/Battler/GameSession graph exactly
-- once. While the combat log is revealing, presentation may still need to show
-- the earlier visual frame (old HP/state/party membership) until the matching
-- beat lands. This module owns that earlier frame without ever writing back to
-- domain objects.
--
-- Proxies are keyed by real battler identity so all authored/persistent data
-- still comes from the source object. Only mutable values the battle UI needs
-- to present on a delayed clock are shadowed here.

local config = require("engine.config")

local battle_view = {}

local active = false
local sourceSession = nil
local sourceBattle = nil
local entries = {}
local proxies = {}
local party = {}
local reserve = {}
local projectedMp = 0
local projectedMaxMp = 0
local displayedMp = 0
local round = 1

local function copyTable(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function copyStates(states)
    local out = {}
    for _, state in ipairs(states or {}) do
        out[#out + 1] = copyTable(state)
    end
    return out
end

local function hasState(states, id)
    for _, state in ipairs(states or {}) do
        if state.id == id then return true end
    end
    return false
end

local function removeState(states, id)
    for i = #states, 1, -1 do
        if states[i].id == id then table.remove(states, i) end
    end
end

local function addState(states, id, duration)
    removeState(states, id)
    states[#states + 1] = { id = id, duration = duration or 9999, maxDuration = duration or 9999 }
end

local function maxHpOf(battler)
    if not battler then return 0 end
    if battler.getMaxHp then return battler:getMaxHp(sourceSession) end
    return battler.hp or 0
end

local function ensureEntry(real)
    if not real then return nil end
    local entry = entries[real]
    if entry then return entry end
    entry = {
        source = real,
        hp = real.hp or 0,
        displayedHp = real.displayedHp or real.hp or 0,
        states = copyStates(real.states),
        paramPlus = copyTable(real.paramPlus),
        maxHp = maxHpOf(real),
    }
    entries[real] = entry
    return entry
end

local function proxyFor(real)
    if not real then return nil end
    local cached = proxies[real]
    if cached then return cached end
    local entry = ensureEntry(real)
    local proxy = {}
    setmetatable(proxy, {
        __index = function(t, key)
            if key == "__battleViewSource" then return real end
            if key == "hp" then return entry.hp end
            if key == "displayedHp" then return entry.displayedHp end
            if key == "states" then return entry.states end
            if key == "paramPlus" then return entry.paramPlus end
            if key == "getMaxHp" then
                return function() return entry.maxHp end
            end
            if key == "isDead" then
                return function()
                    return entry.hp <= 0 or hasState(entry.states, "dead")
                end
            end
            if key == "hasState" then
                return function(_, id) return hasState(entry.states, id) end
            end
            if key == "addState" then
                return function(_, id, duration) addState(entry.states, id, duration) end
            end
            if key == "removeState" then
                return function(_, id) removeState(entry.states, id) end
            end
            return real[key]
        end,
        -- Presentation helpers sometimes attach ephemeral draw fields such as
        -- spriteStatic. They belong to the proxy while a projection is active,
        -- never to the authoritative battler.
        __newindex = function(t, key, value)
            rawset(t, key, value)
        end,
    })
    proxies[real] = proxy
    return proxy
end

local function sourceOf(value)
    if type(value) ~= "table" then return value end
    return value.__battleViewSource or value
end

local function copyGroup(group, maxSlots)
    local out = {}
    if maxSlots then
        for i = 1, maxSlots do
            if group and group[i] then out[i] = proxyFor(sourceOf(group[i])) end
        end
    else
        for k, battler in pairs(group or {}) do
            if battler then out[k] = proxyFor(sourceOf(battler)) end
        end
    end
    return out
end

function battle_view.beginRound(session, battle)
    battle_view.clear()
    if not session or not battle then return end
    active = true
    sourceSession = session
    sourceBattle = battle
    projectedMp = session.mp or 0
    projectedMaxMp = session.maxMp or projectedMp
    displayedMp = session.displayedMp or projectedMp
    round = battle.round or 1

    -- Capture all currently visible/eligible identities before resolution,
    -- including reserve creatures that may enter through an emergency wave.
    for i = 1, config.MAX_PARTY_SIZE do
        ensureEntry(session.party and session.party[i])
        ensureEntry(battle.enemies and battle.enemies[i])
    end
    for _, battler in pairs(session.reserve or {}) do ensureEntry(battler) end

    party = copyGroup(session.party, config.MAX_PARTY_SIZE)
    reserve = copyGroup(session.reserve)
end

function battle_view.clear()
    active = false
    sourceSession = nil
    sourceBattle = nil
    entries = {}
    proxies = {}
    party = {}
    reserve = {}
    projectedMp = 0
    projectedMaxMp = 0
    displayedMp = 0
    round = 1
end

function battle_view.isActive()
    return active
end

function battle_view.target(real)
    if not active then return real end
    return proxyFor(sourceOf(real))
end

function battle_view.source(value)
    return sourceOf(value)
end

local function applyHp(ev, mode)
    local real = sourceOf(ev.target)
    local entry = ensureEntry(real)
    if not entry then return end
    if ev.maxHpAfter ~= nil then entry.maxHp = ev.maxHpAfter end
    if ev.hpAfter ~= nil then
        entry.hp = ev.hpAfter
        return
    end
    if mode == "clamp" and ev.value ~= nil then
        -- hp_clamp.value is itself the resolved assignment, not an amount to
        -- reinterpret. Every damage/heal producer must publish hpAfter.
        entry.hp = ev.value
        return
    end
    error("BattleView requires resolved hpAfter for " .. tostring(mode) .. " events", 0)
end

local function applyState(ev, adding)
    local entry = ensureEntry(sourceOf(ev.target))
    if not entry or not ev.state then return end
    if adding then addState(entry.states, ev.state, ev.duration)
    else removeState(entry.states, ev.state) end
end

local function applyResolvedMp(ev)
    if ev.maxMpAfter ~= nil then projectedMaxMp = ev.maxMpAfter end
    if ev.mpAfter ~= nil then
        projectedMp = ev.mpAfter
        return true
    end
    return false
end

function battle_view.applyEvent(ev)
    if not active or not ev then return end
    if ev.type == "damage" then
        applyHp(ev, "damage")
    elseif ev.type == "heal" then
        applyHp(ev, "heal")
    elseif ev.type == "hp_clamp" then
        applyHp(ev, "clamp")
    elseif ev.type == "max_hp_change" then
        local entry = ensureEntry(sourceOf(ev.target))
        if entry and ev.after ~= nil then entry.maxHp = ev.after end
    elseif ev.type == "death" then
        local entry = ensureEntry(sourceOf(ev.target))
        if entry then
            entry.hp = ev.hpAfter or 0
            if not hasState(entry.states, "dead") then addState(entry.states, "dead", 9999) end
        end
    elseif ev.type == "ward_save" then
        -- REAP_FALLEN has already revived the authoritative battler and paid
        -- any ward cost. While other reaps are still being animated, advance
        -- only this visual copy to the resolved saved state.
        local entry = ensureEntry(sourceOf(ev.target))
        if entry then
            entry.hp = ev.hp or entry.hp
            removeState(entry.states, "dead")
            entry.maxHp = maxHpOf(sourceOf(ev.target))
        end
    elseif ev.type == "state_add" then
        applyState(ev, true)
    elseif ev.type == "state_remove" then
        applyState(ev, false)
    elseif ev.type == "mp_drain" or ev.type == "overcast"
            or ev.type == "kill_mp_restore" then
        if not applyResolvedMp(ev) then
            error("BattleView requires resolved mpAfter for " .. tostring(ev.type) .. " events", 0)
        end
    elseif ev.type == "action" and ev.actorHpAfter ~= nil then
        local entry = ensureEntry(sourceOf(ev.actor))
        if entry then entry.hp = ev.actorHpAfter end
    else
        -- Effects that change shared MP but historically emitted only a text
        -- event can still publish resolved MP metadata without inventing a new
        -- presentation event type.
        applyResolvedMp(ev)
    end
end

function battle_view.applyWaveEntry(p)
    if not active or not p or not p.slot then return end
    local incoming = sourceOf(p.battler)
    party[p.slot] = incoming and proxyFor(incoming) or nil
    if p.reserveKey ~= nil then reserve[p.reserveKey] = nil end
end

function battle_view.applyReap(ev)
    if not active or not ev or not ev.slot then return end
    -- REAP_FALLEN has already performed the authoritative removal/refill.
    -- At the end of the fade, the projected slot catches up to whichever
    -- creature the engine now owns there (or becomes empty).
    local real = sourceSession and sourceSession.party and sourceSession.party[ev.slot]
    party[ev.slot] = real and proxyFor(real) or nil
end

function battle_view.update(dt)
    if not active then return end
    dt = dt or 0
    local alpha = math.min(1, dt * 8)
    for _, entry in pairs(entries) do
        entry.displayedHp = entry.displayedHp + (entry.hp - entry.displayedHp) * alpha
        if math.abs(entry.hp - entry.displayedHp) < 0.1 then entry.displayedHp = entry.hp end
    end
    displayedMp = displayedMp + (projectedMp - displayedMp) * alpha
    if math.abs(projectedMp - displayedMp) < 0.1 then displayedMp = projectedMp end
end

local function sessionProxy()
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            if key == "party" then return party end
            if key == "reserve" then return reserve end
            if key == "mp" then return projectedMp end
            if key == "displayedMp" then return displayedMp end
            if key == "maxMp" then return projectedMaxMp end
            return sourceSession and sourceSession[key] or nil
        end,
        __newindex = function(t, key, value) rawset(t, key, value) end,
    })
    return proxy
end

local function battleProxy(sessionView)
    local proxy = {}
    setmetatable(proxy, {
        __index = function(_, key)
            if key == "allies" then return party end
            if key == "enemies" then return copyGroup(sourceBattle and sourceBattle.enemies, config.MAX_PARTY_SIZE) end
            if key == "round" then return round end
            if key == "session" then return sessionView end
            return sourceBattle and sourceBattle[key] or nil
        end,
        __newindex = function(t, key, value) rawset(t, key, value) end,
    })
    return proxy
end

-- Returns detached scene/session views for drawing. Scene variables are
-- shallow-copied because presentation itself advances ordinary scene-local
-- flags (combatLog, eventQueueIndex, etc.) on the authoritative scene state;
-- only the domain-bearing battle/session references are replaced here.
function battle_view.projectState(state, session)
    if not active or not state or session ~= sourceSession then return nil, nil end
    local sv = sessionProxy()
    local stateView = copyTable(state)
    stateView.v = copyTable(state.v)
    stateView.v.battle = battleProxy(sv)
    return stateView, sv
end

return battle_view
