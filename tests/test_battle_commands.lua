-- The battle console used to draw a fixed five rows and dispatch on the row
-- number, so every creature could attack, flee and rummage in the bag -- an Egg
-- included, despite its only skill being Wait. The command set is data now.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local battle = require("engine.battle")

print("[TEST] Starting battle command tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local function ids(battler)
    local out = {}
    for _, c in ipairs(battle.commandsFor(battler, loader)) do table.insert(out, c.id) end
    return out
end
local function join(t) return table.concat(t, ",") end

-- An ordinary creature authors nothing and gets the default set, in the order
-- the registry declares -- which is the order the menu has always had.
local ordinary = sessionModule.Battler.new(loader.getActor(3), 1)
check(join(ids(ordinary)) == "attack,skill,defend,item,flee",
    "a creature that authors no list gets the default set, in menu order")

-- The Egg: the whole of "an Egg can do nothing else" is one authored list.
local egg = sessionModule.Battler.new(loader.getActor(15), 1)
check(join(ids(egg)) == "wait", "an Egg can only wait")

-- Registry order wins over the order an actor happens to list them in, so the
-- menu never reshuffles between creatures.
local scrambled = { actorData = { battleCommands = { "flee", "attack", "defend" } } }
check(join(ids(scrambled)) == "attack,defend,flee",
    "an actor's list is drawn in registry order, not authoring order")

-- An unknown id is ignored rather than drawn as a blank row; G1 is what
-- actually rejects it, this only pins that it cannot reach the menu.
local bogus = { actorData = { battleCommands = { "attack", "nonexistent" } } }
check(join(ids(bogus)) == "attack", "an unknown command id never reaches the menu")

-- Every command the registry offers must be dispatchable by the console: it
-- either opens target selection, opens a submenu, or commits outright.
local seen = {}
for _, cmd in ipairs(loader.engine.battleCommands or {}) do
    seen[cmd.id] = true
    check(cmd.resolve == "target" or cmd.resolve == "submenu" or cmd.resolve == "commit",
        "command '" .. tostring(cmd.id) .. "' declares how it resolves")
end
check(seen.wait and seen.flee, "Wait and Flee are registry commands like the rest")

-- Flee is a skill now, so it is authorable the way attack, defend and wait are.
check(loader.getSkill("flee") ~= nil, "Flee is backed by a real skill")
local waitSkill = loader.getSkill("wait")
check(waitSkill and #(waitSkill.effects or {}) == 0,
    "Wait is a genuine no-op -- it spends the turn and does nothing")

print(string.format("=== Battle Command Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then error(failed .. " battle command test(s) failed") end
