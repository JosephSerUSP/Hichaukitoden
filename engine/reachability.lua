-- Reachability report: content that RESOLVES but nothing can ever produce.
--
-- This is deliberately NOT a gate. G1 fails a reference that points at nothing,
-- because that is always an authoring mistake. "Nothing produces this yet" is a
-- different claim: it is usually a design observation -- an item staged before
-- the floor that drops it, a creature held back, a debuff waiting on the skill
-- that inflicts it -- and failing a build over it would punish authoring in the
-- order authors actually work. So this prints a report and always exits 0. Read
-- it, decide, and if an entry turns out to be a real dead end, delete the
-- content or wire up its source.
--
-- The caution that governs every "is it referenced?" sweep in this repo applies
-- here too: ids are also resolved at RUNTIME, from pools and hooks, not only
-- from static fields. So each section below names the exact producers it knows
-- about rather than pattern-matching for the id, and anything reached by a
-- source not listed here will be reported as unreachable when it is not. When
-- that happens, teach the section the new producer -- do not weaken the sweep.

local craft = require("engine.craft")

local reachability = {}

local function sortedIds(t)
    local out = {}
    for k in pairs(t) do table.insert(out, k) end
    table.sort(out, function(a, b)
        local na, nb = tonumber(a), tonumber(b)
        if na and nb then return na < nb end
        return tostring(a) < tostring(b)
    end)
    return out
end

-- Every table in the data set, walked once. `visit(node)` sees each table.
local function walkAll(loader, visit)
    local seen = {}
    local function rec(node)
        if type(node) ~= "table" or seen[node] then return end
        seen[node] = true
        visit(node)
        for _, v in pairs(node) do rec(v) end
    end
    for _, root in ipairs({ loader.scenes, loader.flows, loader.commonEvents,
        loader.maps, loader.quests, loader.items, loader.units, loader.shops,
        loader.skills, loader.states, loader.system, loader.actionSequences }) do
        rec(root)
    end
end

function reachability.collectUnitSources(loader)
    local unitSources = {}
    local function addUnit(id, src)
        if id == nil then return end
        id = tostring(id)
        unitSources[id] = unitSources[id] or {}
        unitSources[id][src] = true
    end

    walkAll(loader, function(node)
        if node.cmd == "COMMENT" then return end
        if node.actorId ~= nil then addUnit(node.actorId, "event") end
    end)

    for _, map in ipairs(loader.maps or {}) do
        for _, id in ipairs(map.recruits or {}) do addUnit(id, "recruit pool") end
        for _, enc in ipairs(map.encounters or {}) do
            if type(enc) == "table" then addUnit(enc.id, "encounter") end
        end
    end

    local sys = loader.system or {}
    local ng = sys.newGame or {}
    local partyRules = ng.party or {}
    if partyRules.fixedMembers ~= nil then
        for _, member in ipairs(partyRules.fixedMembers or {}) do
            if member.id and (not loader.getUnit or loader.getUnit(member.id)) then
                addUnit(member.id, "initial party (fixed)")
            end
        end
    end

    for _, actor in ipairs(loader.units or {}) do
        if actor.unlocked then addUnit(actor.id, "summon pool") end
        if actor.initialParty then addUnit(actor.id, "initial party") end
        if actor.role == "Summoner" then addUnit(actor.id, "role Summoner") end
        for _, evo in ipairs(actor.evolutions or {}) do addUnit(evo.evolvesTo, "promotion") end
    end

    for _, item in ipairs(loader.items or {}) do
        for _, eff in ipairs(item.effects or {}) do
            if eff.type == "recruit_egg" then
                addUnit(eff.value or eff.actorId, "item " .. tostring(item.id))
            end
        end
    end

    return unitSources
end

function reachability.build(loader)
    local lines = {}
    local function line(s) table.insert(lines, s or "") end
    local function section(title) line(); line("## " .. title); line() end

    -- ------------------------------------------------------------- producers
    -- Which shops the player can actually walk into. shopId only ever arrives
    -- from a literal OPEN_SHOP command (interpreter.lua compiles it straight
    -- into the node; main.openShop takes it from there), so a shop no
    -- OPEN_SHOP names is a shop with no door -- and its exclusive stock is
    -- unbuyable even though G1 is happy with every id in it.
    local openedShops, itemSources, calledEvents = {}, {}, {}
    local function addItem(id, src)
        if id == nil then return end
        id = tostring(id)
        itemSources[id] = itemSources[id] or {}
        itemSources[id][src] = true
    end

    local unitSources = reachability.collectUnitSources(loader)

    walkAll(loader, function(node)
        local cmd = node.cmd
        if cmd == "COMMENT" then return end
        if cmd == "OPEN_SHOP" and node.shopId ~= nil then
            openedShops[tostring(node.shopId)] = true
        end
        if node.commonEventId ~= nil then calledEvents[tostring(node.commonEventId)] = true end
        if node.scriptId ~= nil then calledEvents[tostring(node.scriptId)] = true end
        -- CHANGE_ITEM with a negative count takes items away; only a positive
        -- one is a source. item="random" draws from map.treasures, handled below.
        if (cmd == "CHANGE_ITEM" or cmd == "GIVE_ITEM_ID") and node.item ~= nil
            and node.item ~= "random" and (type(node.count) ~= "number" or node.count > 0) then
            addItem(node.item, "event")
        end
    end)

    for shopId, shop in pairs(loader.shops or {}) do
        if openedShops[tostring(shopId)] then
            for _, stock in ipairs(shop.items or {}) do
                if type(stock) == "table" then addItem(stock.id, "shop " .. tostring(shopId)) end
            end
        end
    end
    for qid, quest in pairs(loader.quests or {}) do
        for _, rew in ipairs(((quest.rewards or {}).items) or {}) do
            addItem(rew.id, "quest " .. tostring(qid))
        end
    end
    -- Map pools: chests roll `treasures` (CHANGE_ITEM item="random").
    for _, map in ipairs(loader.maps or {}) do
        for _, id in ipairs(map.treasures or {}) do addItem(id, "chest") end
    end
    -- Sacrifice materials (interpreter.sacrificeRewardTable), the summon pool
    -- (`unlocked`), the starting party (`actor.initialParty` or `system.newGame.party.fixedMembers`),
    -- promotion targets, and the recruit_egg effect are all producers no static id reference shows.
    local sys = loader.system or {}
    for _, rew in ipairs(((sys.summoner or {}).defaultSacrificeRewards) or {}) do
        addItem(rew.itemId, "sacrifice (default)")
    end
    for _, actor in ipairs(loader.units or {}) do
        for _, rew in ipairs(actor.sacrificeRewards or {}) do
            addItem(rew.itemId, "sacrifice")
        end
    end

    -- ------------------------------------------------------------- craft sweep
    -- The real Item Creation model, swept over its own possibility space:
    -- every ordered ingredient pair, for every creature on the roster, ideated
    -- at the centre (rng omitted -- no scatter) and resolved through
    -- craft.resolve. Anything that never comes out first is something no
    -- deliberate craft produces; only a scatter roll could ever land on it.
    local sessionMod = require("engine.session")
    local vSession = sessionMod.GameSession.new(loader)
    local craftWinners, craftPairs = {}, 0
    local items = loader.items or {}
    for _, actorData in ipairs(loader.units or {}) do
        if actorData.discipline then
            local crafter = sessionMod.Battler.new(actorData, actorData.level or 1)
            for _, a in ipairs(items) do
                for _, b in ipairs(items) do
                    local point = craft.ideate(a, b, crafter, vSession, nil)
                    local ranked = craft.resolve(point, crafter, vSession)
                    local top = ranked[1]
                    if top then
                        craftWinners[tostring(top.item.id)] = true
                        craftPairs = craftPairs + 1
                    end
                end
            end
        end
    end

    -- ------------------------------------------------------------- the report
    line("# Reachability report")
    line()
    line("Content that resolves (G1-clean) but that nothing in the data can")
    line("produce or trigger. Advisory only -- this never fails a build.")

    section("Items with no source")
    line("Sources counted: stock in a shop some OPEN_SHOP opens, quest reward,")
    line("CHANGE_ITEM/GIVE_ITEM_ID in any event, map `treasures` chest pool,")
    line("`sacrificeRewards`. Item Creation is reported separately, since a")
    line("craft-only item is a deliberate design, not a dead end.")
    line()
    local orphanCount = 0
    for _, item in ipairs(items) do
        local id = tostring(item.id)
        if not itemSources[id] then
            orphanCount = orphanCount + 1
            local craftable = craftWinners[id] and "craftable" or "NOT craftable either"
            line(("- item %s '%s' (%s) -- %s"):format(id, tostring(item.name),
                tostring(item.type), craftable))
        end
    end
    if orphanCount == 0 then line("- (none)") end

    section("Items no craft produces")
    line(("Swept %d ideations at the centre of the possibility space."):format(craftPairs))
    line("An item listed here is in some discipline's pool but never wins the")
    line("resolution, so no deliberate combination yields it.")
    line()
    local n = 0
    for _, item in ipairs(items) do
        local id = tostring(item.id)
        if not craftWinners[id] and (item.meta or {}).craftable ~= false then
            local sig = craft.signature(item, loader)
            if #(sig.disciplines or {}) > 0 then
                n = n + 1
                line(("- item %s '%s' (pool: %s)"):format(id, tostring(item.name),
                    table.concat(sig.disciplines, ", ")))
            end
        end
    end
    if n == 0 then line("- (none)") end

    section("Shops with no door")
    n = 0
    for _, shopId in ipairs(sortedIds(loader.shops or {})) do
        if not openedShops[shopId] then
            n = n + 1
            local shop = loader.shops[shopId]
            line(("- shop %s '%s' (%d items) -- no OPEN_SHOP names it"):format(
                shopId, tostring(shop.name), #(shop.items or {})))
        end
    end
    if n == 0 then line("- (none)") end

    section("Creatures nothing can obtain")
    line("Sources counted: starting party (`actor.initialParty` or `system.newGame.party.fixedMembers`),")
    line("`unlocked` (summon pool), map `encounters` and `recruits` pools, promotion targets,")
    line("`recruit_egg` items, a Unit `role` the engine looks up, explicit actorId.")
    line()
    n = 0
    for _, actor in ipairs(loader.units or {}) do
        if not unitSources[tostring(actor.id)] then
            n = n + 1
            line(("- Unit %s '%s'"):format(tostring(actor.id), tostring(actor.name)))
        end
    end
    if n == 0 then line("- (none)") end

    section("States nothing applies")
    line("Counted: add_status effects, ADD_STATE/SYNC_TRAIT_STATE commands, and")
    line("addState calls in Lua (which this sweep cannot see -- 'dead' is")
    line("applied by battle.lua, so it is excluded by name).")
    line()
    local applied = { dead = true }
    walkAll(loader, function(node)
        if node.cmd == "COMMENT" then return end
        if node.type == "add_status" and node.status then applied[tostring(node.status)] = true end
        local s = node.state or node.stateId
        if s and (node.cmd == "ADD_STATE" or node.cmd == "SYNC_TRAIT_STATE") then
            applied[tostring(s)] = true
        end
    end)
    n = 0
    for _, id in ipairs(sortedIds(loader.states or {})) do
        if not applied[id] then
            n = n + 1
            line(("- state '%s' ('%s')"):format(id, tostring(loader.states[id].name)))
        end
    end
    if n == 0 then line("- (none)") end

    section("Common events nothing calls")
    line("Counted: `scriptId` on a map event or event page, `commonEventId` on")
    line("CALL_COMMON_EVENT, and an actor's `recruitEvent` scriptId.")
    line()
    for _, actor in ipairs(loader.units or {}) do
        local rec = actor.recruitEvent
        if type(rec) == "number" or type(rec) == "string" then
            calledEvents[tostring(rec)] = true
        elseif type(rec) == "table" and rec.scriptId then
            calledEvents[tostring(rec.scriptId)] = true
        end
    end
    n = 0
    for _, id in ipairs(sortedIds(loader.commonEvents or {})) do
        if not calledEvents[id] then
            n = n + 1
            line(("- commonEvent %s '%s'"):format(id, tostring(loader.commonEvents[id].name)))
        end
    end
    if n == 0 then line("- (none)") end

    line()
    return table.concat(lines, "\n")
end

return reachability
