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

-- Escaping is an effect, not a keyword. It used to be `act.type == "flee"`
-- scanned before the round was built, so it preempted the whole round and no
-- item could ever carry it. It resolves in speed order now, which is why the
-- default golden fixture's fleeing Pixie dies to a faster Skeleton first --
-- that fixture no longer covers a SUCCESSFUL escape, so this does.
local effects = require("engine.effects")

local fleeSkill = loader.getSkill("flee")
local escapeEffect
for _, eff in ipairs(fleeSkill.effects or {}) do
    if eff.type == "escape" then escapeEffect = eff end
end
check(escapeEffect ~= nil, "the Flee skill escapes by declaring an effect, not by its id")

local sess = sessionModule.GameSession.new(loader)
sess:initializeStartingParty()
local enemy = sessionModule.Battler.new(loader.getActor(3), 1)
local arena = battle.Battle.new(sess, { enemy })
local actor = sess.party[1]

-- The flow decides, so run it enough times to see both branches rather than
-- reaching past it and asserting the roll.
local sawSuccess, sawFailure = false, false
for _ = 1, 200 do
    local evs = effects.apply(escapeEffect, actor, actor, sess, { battle = arena })
    for _, ev in ipairs(evs) do
        if ev.type == "flee_success" then sawSuccess = true end
        if ev.type == "text" then sawFailure = true end
    end
end
check(sawSuccess, "an escape effect can succeed, emitting flee_success")
check(sawFailure, "and can fail, which is what makes it a gamble")

-- Outside a battle there is nothing to escape from; a menu must not blow up.
local outside = effects.apply(escapeEffect, actor, actor, sess, {})
check(type(outside) == "table" and #outside == 0,
    "an escape effect outside battle does nothing rather than erroring")

print(string.format("=== Battle Command Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " battle command test(s) failed", failed) end
