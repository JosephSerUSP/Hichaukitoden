-- Troops: a battle's composition, rigid or rolled, in one concept.
--
-- Before this, a wandering encounter was built by SPAWN_ENEMIES reading a map's
-- `encounters` table of actor ids, while a scripted fight was an inline list of
-- actors on the BATTLE command. Two ways to describe a battle, and only one of
-- them could ever carry battle events.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local troop = require("engine.troop")

print("[TEST] Starting troop tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()
local sess = sessionModule.GameSession.new(loader)
sess:initializeStartingParty()
local ctx = { session = sess, loader = loader }
-- Slot counts are formulas, and the interpreter owns what a formula can see;
-- the tests only need arithmetic, so a minimal evaluator stands in.
local function evalNum(expr)
    if type(expr) == "number" then return expr end
    return require("engine.formula").eval(expr, {
        combat = loader.system and loader.system.combat,
    })
end

-- A named slot is exactly one enemy, at the level the slot says.
local fixed = { members = { { actor = 3, level = 7 } } }
local built = troop.build(fixed, ctx, evalNum)
check(#built == 1, "a named slot builds exactly one enemy")
check(built[1] and built[1].level == 7, "at the level the slot authored")
check(built[1] and built[1].hp == built[1]:getMaxHp(sess), "and it enters at full HP")

-- A slot that authors no level leaves the actor at its own, rather than
-- inventing one. (Carried over from test_encounter_levels.lua, which tested
-- this through the map-encounter path that troops replaced.)
local defaulted = troop.build({ members = { { actor = 3 } } }, ctx, evalNum)
check(defaulted[1] and defaulted[1].level == loader.getActor(3).level,
    "a slot with no level uses the actor's authored default")

-- A pool slot rolls its count. Repeated because the count is a random range.
local pooled = {
    members = { { pool = { { actor = 3, weight = 1 }, { actor = 9, weight = 1 } },
        count = "random(1, 3)", levelMin = 2, levelMax = 4 } },
}
local sizes, levelsInRange = {}, true
for _ = 1, 60 do
    local group = troop.build(pooled, ctx, evalNum)
    sizes[#group] = true
    for _, e in ipairs(group) do
        if e.level < 2 or e.level > 4 then levelsInRange = false end
    end
end
check(sizes[1] and sizes[3], "a pool slot's count varies across its range")
check(not sizes[0] and not sizes[4], "and never leaves it")
check(levelsInRange, "pooled enemies respect the slot's level range")

-- The thing RPG Maker's rigid troop cannot express: a fixed boss with a
-- variable escort. This is the reason members is a list of slots.
local mixed = {
    members = {
        { actor = 33, level = 20 },
        { pool = { { actor = 9, weight = 1 } }, count = "random(0, 2)" },
    },
}
local sawEscortSizes = {}
for _ = 1, 60 do
    local group = troop.build(mixed, ctx, evalNum)
    sawEscortSizes[#group - 1] = true
    if group[1].actorData.id ~= 33 then
        failed = failed + 1
        print("  [FAIL] the boss is not first")
        break
    end
end
check(sawEscortSizes[0] and sawEscortSizes[2],
    "a fixed boss can carry a variable escort, and the boss is always enemy one")

-- Inheritance. Every troop gets the base troop's events unless it says not to.
-- The loader is shared with every other test in this process, so the real base
-- events are put back afterwards rather than left swapped out.
local realBaseEvents = loader.troops.base.events
loader.troops.base.events = {
    { id = "strain", at = "round_end", commands = {} },
    { id = "ambush", at = "battle_start", commands = {} },
}
local plain = { members = { { actor = 3 } } }
local ids = {}
for _, ev in ipairs(troop.eventsFor(plain, loader)) do table.insert(ids, ev.id) end
check(table.concat(ids, ",") == "strain,ambush", "a troop inherits the base troop's events")

local suppressing = { members = { { actor = 3 } }, suppress = { "strain" } }
ids = {}
for _, ev in ipairs(troop.eventsFor(suppressing, loader)) do table.insert(ids, ev.id) end
check(table.concat(ids, ",") == "ambush", "and can suppress one by id, keeping the rest")

local opted = { members = { { actor = 3 } }, inherits = false }
check(#troop.eventsFor(opted, loader) == 0, "or opt out of the base troop entirely")

local own = { members = { { actor = 3 } }, events = { { id = "roar", at = "round_start" } } }
ids = {}
for _, ev in ipairs(troop.eventsFor(own, loader)) do table.insert(ids, ev.id) end
check(table.concat(ids, ",") == "strain,ambush,roar",
    "a troop's own events run after the inherited ones")

-- Fail loud: a typo names a fight against nothing.
check(not pcall(troop.get, "no_such_troop", loader),
    "an unknown troop id raises instead of producing an empty battle")

-- Every map that can start a fight rolls a real, fightable troop.
for _, map in ipairs(loader.maps) do
    for _, enc in ipairs(map.encounters or {}) do
        local t = loader.troops[tostring(enc.troop)]
        if not t or t.abstract == true then
            failed = failed + 1
            print("  [FAIL] map " .. tostring(map.id) .. " rolls unusable troop "
                .. tostring(enc.troop))
        end
    end
end
check(true, "every map encounter names a fightable troop")

loader.troops.base.events = realBaseEvents

-- Battle Strain moved out of the battle.round_end flow onto the base troop.
-- The numbers themselves are covered by test_mpd_economy, which exercises this
-- exact path and fails loudly if base-troop events stop firing -- the golden
-- fixtures do NOT cover it, since they never reach round six. What is new here
-- is that a single fight can now opt out, which is the reason it moved: in a
-- phase it applied to every battle, always, with no way to say otherwise.
local flowMod = require("engine.flow")

local function strainCost(troopData)
    local s = sessionModule.GameSession.new(loader)
    s:initializeStartingParty()
    s.currentMapData = { safe = false }
    s.mp = s.maxMp
    local before = s.mp
    flowMod.run("battle.round_end", {
        session = s, party = s.party, enemies = {},
        battle = { round = 15, allies = s.party, enemies = {}, troop = troopData },
        loader = loader,
    })
    return before - s.mp
end

local charged = strainCost({ id = "noisy", members = { { actor = 3 } } })
check(charged > 0, "an ordinary troop is charged Strain in a long fight")
check(strainCost({ id = "quiet", members = { { actor = 3 } }, suppress = { "strain" } }) == 0,
    "and a troop that suppresses it is not")

print(string.format("=== Troop Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then error(failed .. " troop test(s) failed") end
