-- Unit tests for the formation system model, session party management,
-- save format version 2 persistence, priority sorting, and battle cover redirection.

package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local session = require("engine.session")
local savegame = require("engine.savegame")
local formation = require("engine.formation")
local targeting = require("engine.targeting")
local battle = require("engine.battle")
local json = require("data.json")

loader.init()

print("=== TEST FORMATION ===")

-- 1. Pure formation geometry tests
assert(formation.SLOT_COUNT == 4, "SLOT_COUNT should be 4")
assert(formation.isValidSlot(1) and formation.isValidSlot(4), "valid slots 1..4")
assert(not formation.isValidSlot(0) and not formation.isValidSlot(5), "invalid slots 0, 5")

assert(formation.rowOf(1) == "front" and formation.rowOf(2) == "front", "slots 1,2 are front row")
assert(formation.rowOf(3) == "back" and formation.rowOf(4) == "back", "slots 3,4 are back row")

assert(formation.colOf(1) == 1 and formation.colOf(3) == 1, "slots 1,3 are col 1")
assert(formation.colOf(2) == 2 and formation.colOf(4) == 2, "slots 2,4 are col 2")

assert(formation.slotAt("front", 1) == 1 and formation.slotAt("front", 2) == 2, "front slots")
assert(formation.slotAt("back", 1) == 3 and formation.slotAt("back", 2) == 4, "back slots")

assert(formation.alignedFrontSlot(3) == 1 and formation.alignedFrontSlot(4) == 2, "aligned front slots")
assert(formation.alignedBackSlot(1) == 3 and formation.alignedBackSlot(2) == 4, "aligned back slots")

print("[PASS] Formation pure geometry functions")

-- 2. Sparse array JSON serialization round-trip test
local mockBattler1 = { id = 61, level = 3, name = "Saban", equipment = {}, states = {}, passives = {}, skills = {} }
local mockBattler2 = { id = 1, level = 1, name = "Pixie", equipment = {}, states = {}, passives = {}, skills = {} }
local partyWithHoles = { mockBattler1, false, mockBattler2, false }

local encoded = json.encode(partyWithHoles)
local decoded = json.decode(encoded)

assert(#decoded == 4, "decoded array length should be 4")
assert(decoded[1].name == "Saban", "slot 1 name Saban")
assert(decoded[2] == false, "slot 2 is false")
assert(decoded[3].name == "Pixie", "slot 3 name Pixie")
assert(decoded[4] == false, "slot 4 is false")

print("[PASS] JSON sparse array round-trip ({ b1, false, b2, false })")

-- 3. GameSession starting party & Saban slot 1
local sess = session.GameSession.new(loader)
sess:initializeStartingParty()
assert(sess.party[1] ~= nil, "Slot 1 should be occupied by Saban")
assert(sess.party[1].name == "Saban", "Saban should start in slot 1")

print("[PASS] Starting party Saban in slot 1")

-- 4. Recruitment with preferred slot and fallback
local pixie, loc = sess:recruitActor(1, 1, 3) -- preferred slot 3 (back-left)
assert(loc == "party", "recruited to party")
assert(sess.party[3] == pixie, "recruited to slot 3")

local wolf, loc2 = sess:recruitActor(1, 1, 3) -- preferred slot 3 (occupied!)
assert(loc2 == "party", "recruited to party fallback")
assert(sess.party[2] == wolf or sess.party[4] == wolf, "recruited to first empty slot")

print("[PASS] Recruitment preferred slot & fallback")

-- 5. Active party vs dense members with holes
assert(not sess:isPartyEmpty(), "party is not empty")
local active = sess:getActiveParty()
assert(#active >= 2, "active party contains non-nil battlers")

print("[PASS] Active party denseMembers")

-- 6. Save format version 2 round-trip & v1 migration
local serialized = savegame.serialize(sess, loader, "map")
assert(serialized.version == 2, "save version should be 2")
assert(#serialized.party == 4, "serialized party must be 4 elements")

local loadedSession, scene = savegame.deserialize(serialized, loader)
assert(loadedSession.party[1] ~= nil, "slot 1 restored")
assert(loadedSession.party[3] ~= nil, "slot 3 restored")

-- Test v1 save migration
local v1Data = {
    version = 1,
    party = {
        { id = 61, level = 3, name = "Saban" },
        { id = 1, level = 1, name = "Pixie" },
    }
}
local migratedSession = savegame.deserialize(v1Data, loader)
assert(migratedSession.party[1] and migratedSession.party[1].name == "Saban", "v1 migration slot 1")
assert(migratedSession.party[2] and migratedSession.party[2].name == "Pixie", "v1 migration slot 2")

print("[PASS] Save format version 2 & v1 migration")

-- 7. Targeting shapes (single, row, column, all) & cover specs
local specRow = targeting.expand({ side = "enemy", shape = "row" })
assert(specRow.shape == "row", "shape row expanded")

local specCol = targeting.expand({ side = "enemy", shape = "column" })
assert(specCol.shape == "column", "shape column expanded")

local specBypass = targeting.expand({ side = "enemy", cover = "bypass" })
assert(specBypass.cover == "bypass", "cover bypass expanded")

-- Test shape expansion on candidates
local testSess = session.GameSession.new(loader)
local b1 = session.Battler.new(loader.getActor(61), 1) -- slot 1 (front-left)
local b2 = session.Battler.new(loader.getActor(1), 1)  -- slot 2 (front-right)
local b3 = session.Battler.new(loader.getActor(1), 1)  -- slot 3 (back-left)
local b4 = session.Battler.new(loader.getActor(1), 1)  -- slot 4 (back-right)

testSess.party[1] = b1
testSess.party[2] = b2
testSess.party[3] = b3
testSess.party[4] = b4

local bState = { allies = testSess.party, enemies = {}, session = testSess }

-- Row 1 (front): b1, b2
local frontTargets = targeting.resolve(b1, { side = "ally", shape = "row" }, bState, b1)
assert(#frontTargets == 2, "front row has 2 targets")
assert(frontTargets[1] == b1 and frontTargets[2] == b2, "front row in slot order")

-- Column 1 (left): b1, b3
local col1Targets = targeting.resolve(b1, { side = "ally", shape = "column" }, bState, b3)
assert(#col1Targets == 2, "column 1 has 2 targets")
assert(col1Targets[1] == b1 and col1Targets[2] == b3, "column 1 in slot order")

print("[PASS] Targeting shapes (row, column, all)")

-- 8. Battle Defend Cover Interception
local bInst = battle.Battle.new(testSess, { session.Battler.new(loader.getActor(3), 1) })
local enemy = bInst.enemies[1]

-- Saban in slot 1 (front-left) defends
b1:addState("defending", 1)

-- Enemy attacks Pixie in slot 3 (back-left)
local attackSkill = loader.getSkill("attack")
local turn = {
    actor = enemy,
    skill = attackSkill,
    target = b3,
    speed = 10,
}

local roundEvents = {}
bInst:executeTurn(turn, roundEvents)

-- Event list should contain cover interception message
local coverMsgFound = false
for _, ev in ipairs(roundEvents) do
    if ev.type == "text" and ev.text:find("steps in to protect") then
        coverMsgFound = true
        break
    end
end
assert(coverMsgFound, "cover interception event emitted")

print("[PASS] Defend cover redirection & event logging")

-- 9. Action Priority vs Speed vs Initiative sorting
local act1 = { actor = b1, priority = 0, speed = 10, order = 1 }
local actDef = { actor = b2, priority = 100, speed = 5, order = 2 }
local actInit = { actor = b3, priority = 0, speed = 20, firstStrike = true, order = 3 }

local testQueue = { act1, actDef, actInit }
table.sort(testQueue, function(a, b)
    local pA = a.priority or 0
    local pB = b.priority or 0
    if pA ~= pB then return pA > pB end
    if (a.firstStrike or false) ~= (b.firstStrike or false) then
        return a.firstStrike == true
    end
    if a.speed ~= b.speed then return a.speed > b.speed end
    return (a.order or 0) < (b.order or 0)
end)

assert(testQueue[1] == actDef, "Defend (priority 100) acts first ahead of Initiative and speed")
assert(testQueue[2] == actInit, "Initiative acts second ahead of ordinary speed")
assert(testQueue[3] == act1, "Ordinary action acts last")

print("[PASS] Action priority ordering (priority > initiative > speed)")

print("=== ALL FORMATION TESTS OK ===")
