-- Troops: what a battle is made of, and what happens during it.
--
-- RPG Maker's troop is a fixed roster. That is right for a boss and wrong for a
-- wandering encounter, and having only the rigid version is why random battles
-- had to be built somewhere else entirely -- in this engine, out of a map's
-- `encounters` table by SPAWN_ENEMIES. Two systems for one idea.
--
-- A troop's `members` is a list of SLOTS instead, and a slot is either a named
-- Unit or a weighted pool with a count. A boss is named slots; a wandering
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
    -- The base troop does not inherit itself. It reaches this function like any
    -- other troop -- a battle with no troop of its own resolves to it -- and
    -- without this guard its own events would be collected twice, charging
    -- Strain double for exactly the battles that named no troop.
    local inheritsBase = troopData.inherits ~= false and troopData.id ~= BASE_ID
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
-- authored, then the Unit's own, so a troop only says what it needs to.
-- `evalFormula` is supplied by the caller rather than reached for here: the
-- interpreter owns what a formula can see (battle, party, v...), and building
-- a second context would be a second answer to the same question.
local function buildSlot(slot, ctx, out, evalFormula)
    local loader = loaderOf(ctx)
    local sessionMod = require("engine.session")

    local function makeOne(unitId, levelMin, levelMax)
        local unitData = loader.getUnit(unitId)
        if not unitData then
            error("troop: slot names missing unit '" .. tostring(unitId) .. "'")
        end
        local lo = levelMin or unitData.level or 1
        local hi = levelMax or lo
        local level = lo
        if hi > lo then level = math.random(lo, hi) end
        -- Enemy/ally is a battle relationship, not an authored Unit type. A
        -- troop therefore constructs the same Battler abstraction used on the
        -- player side rather than an Enemy-specific data/runtime class.
        local b = sessionMod.Battler.new(unitData, level)
        b.hp = b:getMaxHp(ctx.session)
        table.insert(out, b)
    end

    if slot.actor ~= nil then
        -- `actor` is retained as the authored field spelling for compatibility;
        -- its value is a Unit resource id and will be renamed only with the
        -- dedicated symbolic-reference migration.
        makeOne(slot.actor, slot.level or slot.levelMin, slot.level or slot.levelMax)
        return
    end

    -- `poolFrom` is a pool by reference rather than by value. "map" means the
    -- current map's own encounter table, which is where a floor's roster
    -- belongs: what can appear differs per map, but the shape of a wandering
    -- fight does not, so one troop describes every random encounter in the
    -- game instead of one near-identical troop per floor.
    local pool = slot.pool
    if slot.poolFrom == "map" then
        pool = (ctx.session and ctx.session.currentMapData
            and ctx.session.currentMapData.encounters) or {}
    end
    pool = pool or {}
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
        -- overrides it for the one Unit that needs to be tougher.
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

-- The troop a wandering encounter on this map fights.
--
-- The map keeps its own weighted Unit table -- that roster is the thing that
-- differs floor to floor. What does NOT differ is the shape of a wandering
-- fight, so one `wandering` troop describes all of them and reads the table
-- through a `poolFrom: "map"` slot. Turning each map's table into its own
-- troop, as this first did, produced seven near-identical troops whose only
-- content was a pool the map already had.
--
-- A floor that wants something else -- a fixed ambush, a table with its own
-- battle events -- names it in `encounterTroop`.
function troop.rollForMap(mapData, loader)
    if not mapData then return nil end
    local named = mapData.encounterTroop
    if named and named ~= "" then return troop.get(named, loader) end
    if #((mapData.encounters) or {}) == 0 then return nil end
    local default = (loader.system and loader.system.combat
        and loader.system.combat.wanderingTroop) or "wandering"
    return troop.get(default, loader)
end

-- The points a battle event can declare itself at. Named rather than free-form
-- so a typo is a build failure instead of an event that never fires, and
-- deliberately few: every one of these is a place the round already stops, so
-- adding an event costs no new machinery.
troop.PHASES = {
    battle_start = true,   -- once, as the encounter opens
    round_start = true,    -- before actions are collected
    after_action = true,   -- after each turn resolves; for HP thresholds
    round_end = true,      -- after the round's ticks
}

-- Troops are reached by two different routes depending on the phase: at
-- battle_start the Battle object does not exist yet (the phase is what builds
-- its enemies), so the troop rides on ctx; afterwards it rides on the Battle.
-- One accessor rather than that distinction leaking into every caller.
function troop.current(ctx)
    local found = (ctx.battle and ctx.battle.troop) or ctx.troop
    if found then return found end
    -- A battle with no troop of its own is still a battle, and the base troop
    -- is by definition the rules of every one of them. Returning nil here
    -- instead would make "no troop named" silently mean "no Strain, no
    -- ambush" -- a cliff between a fight the player walked into and one a
    -- harness built, which is exactly the kind of difference that makes a
    -- test stop testing the real thing.
    local loader = loaderOf(ctx)
    return loader and loader.troops and loader.troops[BASE_ID]
end

-- Where `once` bookkeeping lives. Before the Battle exists there is nothing to
-- remember across -- battle_start runs exactly once anyway -- so an empty table
-- is the honest answer rather than a stashed global.
function troop.firedTable(ctx)
    if not ctx.battle then return {} end
    ctx.battle.firedEvents = ctx.battle.firedEvents or {}
    return ctx.battle.firedEvents
end

-- The troop's events eligible to run at this phase: declared for it, and not
-- already spent if they are `once`.
--
-- `when` is an ordinary sandboxed formula and `commands` an ordinary command
-- list, so a battle event is not a new language -- TRANSFORM_ACTOR already
-- gives a boss its second form, CALL_COMMON_EVENT already gives it dialogue.
-- Evaluating the condition and running the commands belongs to the
-- interpreter, which owns both; this only decides what is on the table.
--
-- `once` fires an event a single time per battle. Without it an event repeats
-- every time its condition holds at its phase, which is what a per-round rule
-- like Strain wants and what an HP threshold very much does not.
function troop.eventsAt(troopData, phase, loader, fired)
    if not troopData then return {} end
    fired = fired or {}
    local out = {}
    for _, ev in ipairs(troop.eventsFor(troopData, loader)) do
        if (ev.at or "round_start") == phase
            and not (ev.once and fired[tostring(ev.id)]) then
            table.insert(out, ev)
        end
    end
    return out
end

-- Records that a `once` event has now fired.
function troop.markFired(fired, ev)
    if ev.once and fired then fired[tostring(ev.id)] = true end
end

troop.BASE_ID = BASE_ID

return troop
