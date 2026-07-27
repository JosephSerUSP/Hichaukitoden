-- Troops: what a battle is made of, and what happens during it.
--
-- RPG Maker's troop is a fixed roster. That is right for a boss and wrong for a
-- wandering encounter, and having only the rigid version is why random battles
-- had to be built somewhere else entirely -- in this engine, out of a map's
-- `encounters` table by SPAWN_ENEMIES. Two systems for one idea.
--
-- A troop's `members` is a list of SLOTS instead, and a slot is either a named
-- actor or a weighted pool with a count. A boss is named slots; a wandering
-- group is one pool slot; a boss with a variable escort is both, which RPG
-- Maker cannot express at all. There is no rigid/random mode flag, because
-- there are not two kinds of troop.
--
-- Events are ordinary event commands under a condition, and every troop
-- inherits the base troop's unless it suppresses them by id -- so a rule that
-- should hold in every battle is authored once, in data, rather than being
-- added to a battle phase flow where it applies to everything unconditionally
-- and can never be turned off for one fight.

local troop = {}

local BASE_ID = "base"

local function loaderOf(ctx)
    return ctx.loader or (ctx.session and ctx.session.loader)
end

-- Resolve a troop id to its data, raising rather than returning an empty
-- battle: a typo here is a fight against nothing.
function troop.get(id, loader)
    local t = loader.troops and loader.troops[tostring(id)]
    if not t then
        error("troop: no troop with id '" .. tostring(id) .. "'")
    end
    return t
end

-- The events this troop runs, base troop first.
--
-- Base events come first so a troop's own events see whatever they set up, and
-- so the reading order matches the firing order. `suppress` drops inherited
-- events by id; it is deliberately not a way to drop a troop's OWN events,
-- which would just be deleting them.
function troop.eventsFor(troopData, loader)
    local out = {}
    local inheritsBase = troopData.inherits ~= false
    if inheritsBase then
        local suppressed = {}
        for _, id in ipairs(troopData.suppress or {}) do suppressed[id] = true end
        local base = loader.troops and loader.troops[BASE_ID]
        for _, ev in ipairs((base and base.events) or {}) do
            if not suppressed[ev.id] then table.insert(out, ev) end
        end
    end
    for _, ev in ipairs(troopData.events or {}) do table.insert(out, ev) end
    return out
end

-- Build the battlers for one slot. A named slot yields exactly one battler; a
-- pool slot rolls `count` weighted picks. Level comes from the slot when
-- authored, then the actor's own, so a troop only says what it needs to.
-- `evalFormula` is supplied by the caller rather than reached for here: the
-- interpreter owns what a formula can see (battle, party, v...), and building
-- a second context would be a second answer to the same question.
local function buildSlot(slot, ctx, out, evalFormula)
    local loader = loaderOf(ctx)
    local sessionMod = require("engine.session")

    local function makeOne(actorId, levelMin, levelMax)
        local actorData = loader.getActor(actorId)
        if not actorData then
            error("troop: slot names missing actor '" .. tostring(actorId) .. "'")
        end
        local lo = levelMin or actorData.level or 1
        local hi = levelMax or lo
        local level = lo
        if hi > lo then level = math.random(lo, hi) end
        local b = sessionMod.Battler.new(actorData, level)
        b.hp = b:getMaxHp(ctx.session)
        table.insert(out, b)
    end

    if slot.actor ~= nil then
        makeOne(slot.actor, slot.level or slot.levelMin, slot.level or slot.levelMax)
        return
    end

    local pool = slot.pool or {}
    if #pool == 0 then return end
    local count = 1
    if slot.count ~= nil then
        count = math.floor(tonumber(evalFormula(slot.count, ctx)) or 0)
    end
    for _ = 1, count do
        local total = 0
        for _, entry in ipairs(pool) do total = total + (entry.weight or 1) end
        if total <= 0 then break end
        local roll = math.random(total)
        local sum, chosen = 0, pool[1]
        for _, entry in ipairs(pool) do
            sum = sum + (entry.weight or 1)
            if roll <= sum then chosen = entry break end
        end
        -- The slot's range is the default for everything it rolls; an entry
        -- overrides it for the one actor that needs to be tougher.
        makeOne(chosen.actor,
            chosen.levelMin or slot.levelMin,
            chosen.levelMax or slot.levelMax)
    end
end

-- The enemy list for a troop. Slots are built in authoring order, so a boss
-- declared first is enemy one however its escort rolls.
function troop.build(troopData, ctx, evalFormula)
    local enemies = {}
    for _, slot in ipairs(troopData.members or {}) do
        buildSlot(slot, ctx, enemies, evalFormula)
    end
    return enemies
end

-- Pick a troop from a map's weighted encounter table. The table holds troop
-- ids now rather than actor ids: a wandering encounter is a troop like any
-- other, so it can carry events too.
function troop.rollForMap(mapData, loader)
    local table_ = (mapData and mapData.encounters) or {}
    if #table_ == 0 then return nil end
    local total = 0
    for _, entry in ipairs(table_) do total = total + (entry.weight or 1) end
    if total <= 0 then return nil end
    local roll = math.random(total)
    local sum = 0
    for _, entry in ipairs(table_) do
        sum = sum + (entry.weight or 1)
        if roll <= sum then return troop.get(entry.troop, loader) end
    end
    return troop.get(table_[1].troop, loader)
end

troop.BASE_ID = BASE_ID

return troop
