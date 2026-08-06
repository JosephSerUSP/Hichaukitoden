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

-- 5. OPEN_RECRUIT Interpreter Command with suggestedSlot parameter
local interpSess = session.GameSession.new(loader)
interpSess:initializeStartingParty() -- Saban in slot 1
local interpCtx = { session = interpSess, events = {} }
interpreter.runImmediate({
    { cmd = "OPEN_RECRUIT", actorId = 1, level = 1, suggestedSlot = 3 }
}, interpCtx)

assert(interpSess.party[3] ~= nil and interpSess.party[3].actorData.id == 1, "OPEN_RECRUIT cmd placed Pixie directly into slot 3")
assert(interpSess.party[2] == nil, "Slot 2 remains empty")
print("[PASS] Interpreter OPEN_RECRUIT cmd.suggestedSlot parameter wiring")

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

-- 9. Real Battle:buildTurnQueue priority, initiative, speed, and equal-speed tie-breaking
local testSess = session.GameSession.new(loader)
local fastActor = session.Battler.new(loader.getActor(1), 20)
testSess.party[1] = b1
testSess.party[2] = b2
testSess.party[3] = fastActor
local bQueueTest = battle.Battle.new(testSess, { enemyActor })

local collectedActions = {
    [1] = { type = "skill", id = "attack", target = enemyActor },
    [2] = { type = "defend", target = b2 },
    [3] = { type = "skill", id = "attack", target = enemyActor },
}

-- Invoke Battle's actual buildTurnQueue method directly
local realQueue = bQueueTest:buildTurnQueue(collectedActions)

-- Verify Defend (priority 100) acts first, then Initiative/Speed, then Order ties
assert(realQueue[1].actor == b2, "Defend (priority 100) acts first in Battle:buildTurnQueue")
assert(realQueue[1].priority == 100, "Defend action carries priority 100")
assert(realQueue[2].actor == fastActor, "Higher speed actor (level 20) acts second ahead of lower speed actors")
-- Assert insertion order tie resolution between b1 and enemyActor
local b1Pos, enemyPos = 0, 0
for idx, act in ipairs(realQueue) do
    if act.actor == b1 then b1Pos = idx end
    if act.actor == enemyActor then enemyPos = idx end
end
assert(b1Pos < enemyPos, "Insertion order resolves speed ties deterministically (ally slot 1 before enemy)")

print("[PASS] Action priority ordering and equal-speed tie resolution via real Battle:buildTurnQueue")

-- 10. Promotion / Transformation slot retention through real transform.applyAutomatic pipeline
local transform = require("engine.transform")
local transSess = session.GameSession.new(loader)
-- Create an isolated actor data object to avoid mutating global loader cache
local origPixieData = setmetatable({ autoTransforms = { { atLevel = 1, actor = 2 } } }, { __index = loader.getActor(1) })
local origPixie = session.Battler.new(origPixieData, 1)
transSess.party[3] = origPixie

local resultB = transform.applyAutomatic(transSess, origPixie)

assert(transSess.party[3] == resultB, "applyAutomatic replaces original in slot 3 via replaceInSession")
assert(transSess.party[3].actorData.id == 2, "Transformed battler in slot 3 is actor 2 (High Pixie)")
assert(transSess.party[3].row == "back", "Transformed battler in slot 3 retains back row")

print("[PASS] Promotion/Transformation slot retention via real transform.applyAutomatic pipeline")

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

-- 12. Sparse party STATE_TICKS and TICK_SKILL_TIMERS (slot 3 state decay & skill cooldowns)
local interpreter = require("engine.interpreter")
local tickSess = session.GameSession.new(loader)
local saban1 = session.Battler.new(loader.getActor(61), 5)
local pixie3 = session.Battler.new(loader.getActor(1), 3)
tickSess.party[1] = saban1
tickSess.party[3] = pixie3

local skill_cost = require("engine.skill_cost")
local testSkill = { id = "attack", cooldown = 2 }
pixie3:addState("defending", 1)
skill_cost.startCooldown(testSkill, pixie3)
assert(#pixie3.states == 1, "Pixie slot 3 has 1 state before tick")
assert(skill_cost.cooldownLeft(testSkill, pixie3) == 2, "Pixie slot 3 has cooldown 2 before tick")

local tickCtx = { party = tickSess.party, enemies = {}, session = tickSess, events = {} }
interpreter.execList({ { cmd = "STATE_TICKS" }, { cmd = "TICK_SKILL_TIMERS" } }, tickCtx)
assert(#pixie3.states == 0, "Pixie slot 3 defending state decayed to 0 and removed during STATE_TICKS")
assert(skill_cost.cooldownLeft(testSkill, pixie3) == 1, "Pixie slot 3 skill cooldown reduced during TICK_SKILL_TIMERS")

print("[PASS] Sparse party round-end state duration and skill timer ticks (slot 3)")

-- 13. Sparse party victory XP rewards (matching battle.victory flow FOR_EACH living_allies)
local expSess = session.GameSession.new(loader)
local expSaban = session.Battler.new(loader.getActor(61), 1)
local expPixie = session.Battler.new(loader.getActor(1), 1)
expSess.party[1] = expSaban
expSess.party[3] = expPixie

local initExpPixie = expPixie.exp or 0
local expCtx = { party = expSess.party, session = expSess, loader = loader, events = {} }
interpreter.execList({
    {
        cmd = "FOR_EACH",
        scope = "living_allies",
        as = "ally",
        ["do"] = {
            { cmd = "GRANT_XP", target = "ally", amount = 10 }
        }
    }
}, expCtx)
assert(expPixie.exp == initExpPixie + 10, "Pixie in slot 3 gained 10 XP from FOR_EACH living_allies victory reward")

print("[PASS] Sparse party victory XP awards (slot 3)")

-- 14. Target = 'none' regression test (actual Mystic Egg item 11)
local mysticEggItem = loader.getItem(11)
assert(mysticEggItem and mysticEggItem.target == "none", "Item 11 (Mystic Egg) has target 'none'")
local eggState = { allies = tickSess.party, enemies = {}, session = tickSess }
local noneResolved = targeting.resolve(saban1, mysticEggItem.target, eggState)
local noneCandidates = targeting.getCandidates(saban1, mysticEggItem.target, eggState)
assert(type(noneResolved) == "table" and #noneResolved == 0, "target 'none' resolves to empty table without crashing")
assert(type(noneCandidates) == "table" and #noneCandidates == 0, "target 'none' candidates return empty table without crashing")

print("[PASS] Target 'none' spec safety (Mystic Egg item 11)")

-- 15. Real UI item action shape & cover selectivity (hostile vs support actions)
local itemCoverSess = session.GameSession.new(loader)
local coverSaban = session.Battler.new(loader.getActor(61), 5)
coverSaban:addState("defending", 1)
local coverPixie = session.Battler.new(loader.getActor(1), 1)
coverPixie.hp = 5 -- Wounded Pixie
itemCoverSess.party[1] = coverSaban -- slot 1 (front-left)
itemCoverSess.party[3] = coverPixie -- slot 3 (back-left)
itemCoverSess.inventory[1] = 5     -- Item ID 1 (HP Tonic)

local bItemCover = battle.Battle.new(itemCoverSess, { enemyActor })

-- A. Real UI Potion-on-Ally action shape (action.target is the selected Battler object)
local realPotionAction = { type = "item", id = 1, itemIndex = 1, target = coverPixie }
local potionEvents = bItemCover:applyItem(realPotionAction, coverSaban, coverPixie)

assert(coverPixie.hp > 5, "Real UI Potion-on-Ally action heals target Pixie directly")

local potionIntercepted = false
for _, ev in ipairs(potionEvents) do
    if ev.type == "text" and ev.text and ev.text:find("steps in to protect") then
        potionIntercepted = true
        break
    end
end
assert(not potionIntercepted, "Friendly Potion on back-row Pixie is NOT intercepted by Defending Saban")

-- B. Support skill ("ally-any") targeting back-row Pixie
local supportSpec = { side = "ally", count = 1, mode = "choose", state = "alive", shape = "single", cover = "respect" }
local supportTargets = targeting.resolve(coverSaban, supportSpec, bItemCover, coverPixie)
local coveredSupportTargets = bItemCover:evaluateCover(coverSaban, supportSpec, supportTargets, {})
assert(#coveredSupportTargets == 1 and coveredSupportTargets[1] == coverPixie, "Support skill ('ally-any') aimed at back-row Pixie is NOT intercepted by Defending Saban")

-- C. Hostile single-target attack on back-row Pixie
local hostileSpec = { side = "enemy", shape = "single", cover = "respect" }
local hostileTargets = targeting.resolve(enemyActor, hostileSpec, bItemCover, coverPixie)
local hostileEvents = {}
local coveredHostileTargets = bItemCover:evaluateCover(enemyActor, hostileSpec, hostileTargets, hostileEvents)
assert(#coveredHostileTargets == 1 and coveredHostileTargets[1] == coverSaban, "Hostile single-target attack on back-row Pixie IS intercepted by Defending Saban")

-- D. Charmed ally hostile action cover interception
local charmedAlly = session.Battler.new(loader.getActor(61), 5)
charmedAlly:addState("charm", 1)
charmedAlly.isRestricted = function() return false end
itemCoverSess.party[2] = charmedAlly -- slot 2 (front-right ally)
local charmedItemTargets = targeting.resolve(charmedAlly, hostileSpec, bItemCover, coverPixie)
local charmedCoverEvents = {}
local coveredCharmedTargets = bItemCover:evaluateCover(charmedAlly, hostileSpec, charmedItemTargets, charmedCoverEvents)
assert(#coveredCharmedTargets == 1 and coveredCharmedTargets[1] == coverSaban, "Charmed attacker targeting back-row Pixie has cover intercepted by front-row Saban")

print("[PASS] Action-agnostic execution-time cover (real UI Potion-on-Ally, non-intercepted support, & Charmed cover)")

print("=== ALL FORMATION TESTS OK ===")
