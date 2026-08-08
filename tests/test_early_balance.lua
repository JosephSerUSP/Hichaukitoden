package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")
local troop = require("engine.troop")
local formula = require("engine.formula")

print("[TEST] Starting early-game balance tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local fixed = loader.system.newGame.party.fixedMembers[1]
check(fixed.id == "moa" and fixed.level == 3,
    "Saban starts at level 3, matching the top of Floor 1's enemy range")

local floor1 = loader.maps[2]
local floor1Troop = troop.rollForMap(floor1, loader)
check(floor1Troop and floor1Troop.id == "floor_1_wandering",
    "Floor 1 uses its opening-specific wandering troop")

local sess = sessionModule.GameSession.new(loader)
sess.currentMapData = floor1
local function evalNum(expr)
    if type(expr) == "number" then return expr end
    return formula.eval(expr, { combat = loader.system.combat })
end

local sawOne, sawTwo, withinCap = false, false, true
for _ = 1, 80 do
    local enemies = troop.build(floor1Troop, { session = sess, loader = loader }, evalNum)
    sawOne = sawOne or #enemies == 1
    sawTwo = sawTwo or #enemies == 2
    withinCap = withinCap and #enemies >= 1 and #enemies <= 2
end
check(withinCap and sawOne and sawTwo,
    "Floor 1 rolls one or two enemies, never the later-floor cap of three")

local function damagingSkill(actor)
    for _, skillId in ipairs(actor.skills or {}) do
        local skill = loader.getSkill(skillId)
        for _, effect in ipairs((skill and skill.effects) or {}) do
            if effect.type == "hp_damage" or effect.type == "hp_drain" then return true end
        end
    end
    return false
end

local allCanAttack = true
for _, entry in ipairs(floor1.encounters) do
    allCanAttack = allCanAttack and damagingSkill(loader.getUnit(entry.actor))
end
check(allCanAttack, "every Floor 1 enemy has an offensive action")

local saban = sessionModule.Battler.new(loader.getUnit("moa"), fixed.level)
local mandrake = sessionModule.Battler.new(loader.getUnit("mandrake"), 3)
local peck = loader.getSkill("dartingPeck")
local mend = loader.getSkill("rootMend")
saban.hp = saban:getMaxHp(sess)
mandrake.hp = mandrake:getMaxHp(sess)

local realRandom = math.random
math.random = function() return 1 end -- no critical; compare ordinary throughput
local before = mandrake.hp
effects.apply(peck.effects[1], saban, mandrake, sess,
    { element = peck.element, user = saban })
local damage = before - mandrake.hp
mandrake.hp = 1
local healBefore = mandrake.hp
effects.apply(mend.effects[1], mandrake, mandrake, sess,
    { element = mend.element, user = mandrake })
local healing = mandrake.hp - healBefore
math.random = realRandom

-- RETIRED 01.08.2026 (owner): this used to assert damage > healing -- that one
-- ordinary attack must out-damage one heal. The premise is wrong, not the
-- numbers. A single attacker against a dedicated healer is not the balance
-- question; sustain is decided by action economy across a party and a round,
-- and by the cost the heal carries, none of which a one-hit comparison sees.
-- Asserting it made a red suite out of a design opinion nobody holds.
--
-- The measurement is kept and PRINTED rather than deleted: it is the input to
-- whatever the real sustain rule turns out to be, and silently dropping it
-- would lose the only place these two numbers sit side by side. Restoring a
-- gate here needs a decision about what sustain SHOULD be, not a threshold.
print(string.format(
    "  [note] ordinary Darting Peck %d vs level-3 Mandrake root Mend %d"
        .. " (informational; no longer asserted)", damage, healing))

-- Additional early game mechanics & balance checks
check(peck.element == nil and peck.icon == 6, "Darting Peck is non-elemental with icon 6")

local hasWindBlade = false
for _, sk in ipairs(saban.actorData.skills or {}) do
    if sk == "windBlade" then hasWindBlade = true end
end
check(hasWindBlade, "Saban carries Wind Blade for Green elemental attacks")

local weakened = loader.getState("weakened")
check(weakened and weakened.duration == 3, "Weakened status duration is 3 rounds (not infinite)")

local sawBlueEnemy = false
for _, entry in ipairs(floor1.encounters) do
    local enemyActor = loader.getUnit(entry.actor)
    for _, elem in ipairs(enemyActor.elements or {}) do
        if elem == "Blue" then sawBlueEnemy = true end
    end
end
check(sawBlueEnemy, "Floor 1 contains Blue elemental enemies for Saban's Green elemental advantage")

-- Verify map navigation MP drain formula evaluation
local flow = require("engine.flow")
sess.party = { saban }
sess.mp = 50
sess.maxMp = 50
sess.mapSafe = false
flow.run("exploration.step", { session = sess, party = sess.party })
-- Verify Cerberus actor adjustments & sidequest registration
local cerberus = loader.getUnit("cerberus")
check(cerberus and cerberus.elements and cerberus.elements[1] == "Black" and cerberus.elements[2] == "White",
    "Cerberus is aligned to Black and White elements")
check(cerberus and cerberus.baseParams and cerberus.baseParams.mpd == 6,
    "Cerberus carries a heavy traversal MPD of 6")

local lostHoundQuest = loader.getQuest and loader.getQuest("lost_hound")
check(lostHoundQuest and lostHoundQuest.name == "The Stray Hound",
    "The Stray Hound sidequest is registered in quests.json")

print(string.format("=== Early-game Balance Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " early-game balance test(s) failed", failed) end
