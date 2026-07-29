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
check(fixed.id == 61 and fixed.level == 3,
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
    allCanAttack = allCanAttack and damagingSkill(loader.getActor(entry.actor))
end
check(allCanAttack, "every Floor 1 enemy has an offensive action")

local saban = sessionModule.Battler.new(loader.getActor(61), fixed.level)
local mandrake = sessionModule.Battler.new(loader.getActor(30), 3)
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

check(damage > healing,
    string.format("Saban's ordinary Darting Peck (%d) exceeds a level-3 Mandrake heal (%d)",
        damage, healing))

print(string.format("=== Early-game Balance Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then error(failed .. " early-game balance test(s) failed") end
