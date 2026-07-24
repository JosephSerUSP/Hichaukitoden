-- Unit test for Creature Recruitment system
-- Run via Love2D or Lua test runner

package.path = package.path .. ";./?.lua;./engine/?.lua"

local recruitment = require("engine.recruitment")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local GameSession = sessionModule.GameSession

print("[TEST] Starting creature recruitment system tests...")

-- Mock loader for testing
local mockLoader = {
    actors = {
        [1] = { id = 1, name = "Pixie", level = 1, role = "Healer", recruitEvent = { type = "heal" } },
        [3] = { id = 3, name = "Skeleton", level = 1, role = "Attacker", recruitEvent = { type = "hostile" } },
        [4] = { id = 4, name = "Angel", level = 2, role = "Support", recruitEvent = { type = "gold", goldCost = 30 } },
        [12] = { id = 12, name = "Ooze", level = 1, role = "Debuffer", recruitEvent = { type = "aid", itemRequired = 1 } },
        [13] = { id = 13, name = "Bat", level = 1, role = "Attacker", recruitEvent = { type = "free" } },
        [15] = { id = 15, name = "CustomCreature", level = 1, recruitEvent = { commands = { { type = "TEXT", text = "Custom event!" } } } },
        [16] = { id = 16, name = "ArrayCreature", level = 1, recruitEvent = { { type = "TEXT", text = "Direct array event!" } } },
        [17] = { id = 17, name = "ScriptIdCreature", level = 1, recruitEvent = 4 },
    },
    commonEvents = {
        ["4"] = { id = "4", name = "Recruit Pixie", commands = { { type = "TEXT", text = "Common event recruit!" } } }
    },
    items = {
        [1] = { id = 1, name = "Potion", type = "item" }
    },
    getActor = function(self, id) return self.actors[id] end,
    getItem = function(self, id) return self.items[id] end,
    getTerm = function(self, key, default) return default end,
    formatTerm = function(self, key, default, p1) return (default:gsub("{0}", tostring(p1))) end,
    system = { combat = { encounterChance = 0.1 } }
}

-- Test 1: recruitment.compile outputs expected script commands for each type and format
local pixieScript = recruitment.compile(mockLoader.actors[1], 1, { loader = mockLoader })
assert(#pixieScript > 0, "Pixie heal script failed to compile")
assert(pixieScript[2].type == "RECOVER_PARTY", "Pixie script missing RECOVER_PARTY")

local angelScript = recruitment.compile(mockLoader.actors[4], 1, { loader = mockLoader })
assert(#angelScript > 0, "Angel gold script failed to compile")
assert(angelScript[2].type == "CHOICE", "Angel script missing CHOICE")
assert(angelScript[2].options[1].condition == "gold:30", "Angel script missing gold condition")

local customScript = recruitment.compile(mockLoader.actors[15], 1, { loader = mockLoader })
assert(#customScript == 1 and customScript[1].text == "Custom event!", "Custom command object failed to compile")

local arrayScript = recruitment.compile(mockLoader.actors[16], 1, { loader = mockLoader })
assert(#arrayScript == 1 and arrayScript[1].text == "Direct array event!", "Direct command array failed to compile")

local scriptIdScript = recruitment.compile(mockLoader.actors[17], 1, { loader = mockLoader })
assert(#scriptIdScript == 1 and scriptIdScript[1].text == "Common event recruit!", "ScriptId reference failed to compile")

print("  [PASS] recruitment.compile scripts generated successfully for all types and event formats")

-- Test 2: GameSession:recruitActor party vs reserve filling
local sess = GameSession.new(mockLoader)
assert(#sess.party == 0, "Party should start empty")

-- Recruit up to 4 members into active party
for i = 1, 4 do
    local battler, slotType = sess:recruitActor(13, 1)
    assert(battler ~= nil, "Failed to recruit Bat #" .. i)
    assert(slotType == "party", "Bat #" .. i .. " should be placed in party")
end
assert(#sess.party == 4, "Party should have 4 members")

-- 5th member should be routed to reserve roster
local battler5, slotType5 = sess:recruitActor(13, 1)
assert(battler5 ~= nil, "Failed to recruit 5th Bat")
assert(slotType5 == "reserve", "5th Bat should be placed in reserve")
assert(sess.reserve[1] ~= nil, "Reserve slot 1 should hold 5th Bat")
print("  [PASS] GameSession:recruitActor places members correctly in party and reserve")

-- Test 3: Interpreter command handlers (RECRUIT_ACTOR, ERASE_EVENT, TAKE_ITEM)
sess.inventory[1] = 5
local ctx = { session = sess, events = {} }

interpreter.runImmediate({
    { type = "TAKE_ITEM", item = 1, count = 2 },
    { type = "RECRUIT_ACTOR", actorId = 4, level = 2 }
}, ctx)

assert(sess.inventory[1] == 3, "TAKE_ITEM did not deduct items correctly")
assert(sess.reserve[2] ~= nil and sess.reserve[2].id == 4, "RECRUIT_ACTOR did not add Angel to reserve")
print("  [PASS] Interpreter commands TAKE_ITEM and RECRUIT_ACTOR executed cleanly")

-- Test 4: ERASE_EVENT removes map event
sess.currentMapData = {
    events = {
        { id = "recruit_1", type = "recruit" },
        { id = "stairs_1", type = "stairs" }
    }
}
ctx.eventId = "recruit_1"
interpreter.runImmediate({
    { type = "ERASE_EVENT" }
}, ctx)

assert(#sess.currentMapData.events == 1, "ERASE_EVENT did not remove target event")
assert(sess.currentMapData.events[1].id == "stairs_1", "Wrong event was erased")
print("  [PASS] Interpreter command ERASE_EVENT erased target map event")

print("[TEST] All Creature Recruitment tests passed successfully!")
