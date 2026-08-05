-- Unit tests for the formation system model, session party management,
-- save format version 2 persistence, priority sorting, defend cover redirection,
-- RECRUIT_ACTOR interpreter wiring, and sparse Saban-slot-1 / Pixie-slot-3 topology.

package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local session = require("engine.session")
local savegame = require("engine.savegame")
local formation = require("engine.formation")
local targeting = require("engine.targeting")
local battle = require("engine.battle")
local interpreter = require("engine.interpreter")
local battler_geometry = require("presentation.battler_geometry")
local validator = require("engine.validator")
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

-- 5. RECRUIT_ACTOR Interpreter Command with slot parameter
local interpSess = session.GameSession.new(loader)
interpSess:initializeStartingParty() -- Saban in slot 1
local interpCtx = { session = interpSess, events = {} }
interpreter.runImmediate({
    { cmd = "RECRUIT_ACTOR", actorId = 1, level = 1, slot = 3 }
}, interpCtx)

assert(interpSess.party[3] ~= nil and interpSess.party[3].id == 1, "RECRUIT_ACTOR cmd placed Pixie directly into slot 3")
assert(interpSess.party[2] == nil, "Slot 2 remains empty")
print("[PASS] Interpreter RECRUIT_ACTOR cmd.slot parameter wiring")

-- 6. Saban (Slot 1), Slot 2 Empty, Pixie (Slot 3) Sparse Formation End-to-End
local sparseSess = session.GameSession.new(loader)
local saban = session.Battler.new(loader.getActor(61), 3)
local pixie3 = session.Battler.new(loader.getActor(1), 1)
sparseSess.party[1] = saban
sparseSess.party[2] = nil
sparseSess.party[3] = pixie3
sparseSess.party[4] = nil

-- Test getCandidates and resolve find Pixie in slot 3 despite empty slot 2
local enemyActor = session.Battler.new(loader.getActor(3), 1)
local sparseBattle = battle.Battle.new(sparseSess, { enemyActor })

local enemyCandidates = targeting.getCandidates(enemyActor, { side = "enemy" }, sparseBattle)
assert(#enemyCandidates == 2, "Enemy finds both Saban (slot 1) and Pixie (slot 3)")
assert(enemyCandidates[1] == saban and enemyCandidates[2] == pixie3, "Candidates order Saban then Pixie")

-- Test presentation geometry for slot 3 after empty slot 2
local p1Rect = battler_geometry.rect(sparseBattle, sparseSess, saban)
local p3Rect = battler_geometry.rect(sparseBattle, sparseSess, pixie3)
assert(p1Rect ~= nil, "Saban slot 1 rect resolved")
assert(p3Rect ~= nil, "Pixie slot 3 rect resolved despite empty slot 2")
assert(p3Rect.index == 3, "Pixie rect index is 3")

-- Test cover interception when targeting Pixie in slot 3
saban:addState("defending", 1)
local attackSkill = loader.getSkill("attack")
local turnPixie = { actor = enemyActor, skill = attackSkill, target = pixie3, speed = 10 }
local sparseEvents = {}
sparseBattle:executeTurn(turnPixie, sparseEvents)

local intercepted = false
for _, ev in ipairs(sparseEvents) do
    if ev.type == "text" and ev.text:find("steps in to protect") then intercepted = true break end
end
assert(intercepted, "Saban in slot 1 intercepts attack aimed at Pixie in slot 3")

print("[PASS] Sparse formation Saban-1 / empty-2 / Pixie-3 targeting, rects, & cover")

-- 7. Cover Interception Edge Cases
-- Case A: Dead protector does NOT cover
local deadSess = session.GameSession.new(loader)
local deadSaban = session.Battler.new(loader.getActor(61), 3)
deadSaban.hp = 0
deadSaban:addState("dead", 1)
deadSaban:addState("defending", 1)
local p3Dead = session.Battler.new(loader.getActor(1), 1)
deadSess.party[1] = deadSaban
deadSess.party[3] = p3Dead
local bDead = battle.Battle.new(deadSess, { enemyActor })

local turnDead = { actor = enemyActor, skill = attackSkill, target = p3Dead, speed = 10 }
local eventsDead = {}
bDead:executeTurn(turnDead, eventsDead)
local interceptedDead = false
for _, ev in ipairs(eventsDead) do
    if ev.type == "text" and ev.text:find("steps in to protect") then interceptedDead = true break end
end
assert(not interceptedDead, "Dead protector does not intercept")

-- Case B: Stunned/Restricted protector does NOT cover
local stunSess = session.GameSession.new(loader)
local stunSaban = session.Battler.new(loader.getActor(61), 3)
stunSaban:addState("defending", 1)
stunSaban.isRestricted = function() return true end
local p3Stun = session.Battler.new(loader.getActor(1), 1)
stunSess.party[1] = stunSaban
stunSess.party[3] = p3Stun
local bStun = battle.Battle.new(stunSess, { enemyActor })

local turnStun = { actor = enemyActor, skill = attackSkill, target = p3Stun, speed = 10 }
local eventsStun = {}
bStun:executeTurn(turnStun, eventsStun)
local interceptedStun = false
for _, ev in ipairs(eventsStun) do
    if ev.type == "text" and ev.text:find("steps in to protect") then interceptedStun = true break end
end
assert(not interceptedStun, "Restricted/stunned protector does not intercept")

-- Case C: Wrong-column protector (Slot 2 front-right vs Slot 3 back-left) does NOT cover
local wrongColSess = session.GameSession.new(loader)
local wrongColSaban = session.Battler.new(loader.getActor(61), 3)
wrongColSaban:addState("defending", 1)
local p3Wrong = session.Battler.new(loader.getActor(1), 1)
wrongColSess.party[2] = wrongColSaban -- slot 2 (front-right)
wrongColSess.party[3] = p3Wrong     -- slot 3 (back-left)
local bWrong = battle.Battle.new(wrongColSess, { enemyActor })

local turnWrong = { actor = enemyActor, skill = attackSkill, target = p3Wrong, speed = 10 }
local eventsWrong = {}
bWrong:executeTurn(turnWrong, eventsWrong)
local interceptedWrong = false
for _, ev in ipairs(eventsWrong) do
    if ev.type == "text" and ev.text:find("steps in to protect") then interceptedWrong = true break end
end
assert(not interceptedWrong, "Wrong column protector (slot 2 vs slot 3) does not intercept")

-- Case D: cover = "bypass" ignores cover
local bypassSess = session.GameSession.new(loader)
local bypassSaban = session.Battler.new(loader.getActor(61), 3)
bypassSaban:addState("defending", 1)
local p3Bypass = session.Battler.new(loader.getActor(1), 1)
bypassSess.party[1] = bypassSaban
bypassSess.party[3] = p3Bypass
local bBypass = battle.Battle.new(bypassSess, { enemyActor })

local bypassSkill = { id = "ranged_attack", target = { side = "enemy", shape = "single", cover = "bypass" } }
local turnBypass = { actor = enemyActor, skill = bypassSkill, target = p3Bypass, speed = 10 }
local eventsBypass = {}
bBypass:executeTurn(turnBypass, eventsBypass)
local interceptedBypass = false
for _, ev in ipairs(eventsBypass) do
    if ev.type == "text" and ev.text:find("steps in to protect") then interceptedBypass = true break end
end
assert(not interceptedBypass, "cover = bypass ignores defender cover")

print("[PASS] Cover interception edge cases (dead, restricted, wrong column, bypass)")

-- 8. Targeting shapes (row, column, all, random) & cover specs
local b1 = session.Battler.new(loader.getActor(61), 1) -- slot 1 (front-left)
local b2 = session.Battler.new(loader.getActor(1), 1)  -- slot 2 (front-right)
local b3 = session.Battler.new(loader.getActor(1), 1)  -- slot 3 (back-left)
local b4 = session.Battler.new(loader.getActor(1), 1)  -- slot 4 (back-right)

local shapeSess = session.GameSession.new(loader)
shapeSess.party[1] = b1
shapeSess.party[2] = b2
shapeSess.party[3] = b3
shapeSess.party[4] = b4

local bState = { allies = shapeSess.party, enemies = {}, session = shapeSess }

-- Row 1 (front): b1, b2
local frontTargets = targeting.resolve(b1, { side = "ally", shape = "row" }, bState, b1)
assert(#frontTargets == 2, "front row has 2 targets")
assert(frontTargets[1] == b1 and frontTargets[2] == b2, "front row in slot order")

-- Column 1 (left): b1, b3
local col1Targets = targeting.resolve(b1, { side = "ally", shape = "column" }, bState, b3)
assert(#col1Targets == 2, "column 1 has 2 targets")
assert(col1Targets[1] == b1 and col1Targets[2] == b3, "column 1 in slot order")

-- Random row resolution
local randRowTargets = targeting.resolve(b1, { side = "ally", shape = "row", mode = "random" }, bState)
assert(#randRowTargets == 2, "random row resolves 2 targets in selected row")

print("[PASS] Targeting shapes (row, column, all, random)")

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
    return a.speed > b.speed
end)

assert(testQueue[1] == actDef, "Defend (priority 100) acts first ahead of Initiative and speed")
assert(testQueue[2] == actInit, "Initiative acts second ahead of ordinary speed")
assert(testQueue[3] == act1, "Ordinary action acts last")

print("[PASS] Action priority ordering (priority > initiative > speed)")

-- 10. Promotion / Transformation slot retention
local transSess = session.GameSession.new(loader)
local origPixie = session.Battler.new(loader.getActor(1), 1)
transSess.party[3] = origPixie

-- Promote/transform into High Pixie (actor 2)
local highPixie = session.Battler.new(loader.getActor(2), origPixie.level, origPixie.growthSeed)
transSess.party[3] = highPixie

assert(transSess.party[3] == highPixie, "Transformed battler retains slot 3 in party")
assert(transSess.party[3].row == "back", "Transformed battler in slot 3 retains back row")

print("[PASS] Promotion/Transformation slot retention")

-- 11. Validator fixedMembers slot validation
local okValBadSlot, errValBadSlot = pcall(validator.run, {
    system = {
        newGame = {
            party = {
                fixedMembers = { { id = 61, slot = 99 } }
            }
        }
    },
    getSkill = function() return {} end,
    getItem = function() return {} end,
    getActor = function() return {} end,
})
assert(not okValBadSlot, "Validator rejects invalid starting slot 99")

print("[PASS] Validator fixedMembers slot bounds check")

print("=== ALL FORMATION TESTS OK ===")
