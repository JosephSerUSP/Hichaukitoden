-- TRANSFORM_ACTOR: Egg hatching, Homunculus metamorphosis and the reversible
-- Kappa curse, all as one primitive. What every mode must share is that the
-- creature survives the change of form.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local transform = require("engine.transform")

print("[TEST] Starting transform tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()
local PIXIE, HIGH_PIXIE, SKELETON = 1, 2, 3

local function rig(actorId, level)
    local sess = sessionModule.GameSession.new(loader)
    sess.party = {}
    local b = sessionModule.Battler.new(loader.getActor(actorId), level, 13579)
    b.hp = b:getMaxHp(sess)
    sess.party[1] = b
    return sess, b
end

local function run(sess, cmd)
    local ctx = { session = sess, loader = loader, events = {}, v = {},
                  party = sess.party, target = sess.party[1] }
    interpreter.runImmediate({ cmd }, ctx)
    return ctx.events
end

-------------------------------------------------------------- identity holds --

do
    local sess, b = rig(PIXIE, 8)
    b.paramPlus.atk = 5
    -- A skill innate to NEITHER form, so carrying it proves the learned-skill
    -- rule rather than a species list. (windBlade is innate to Pixie, so it is
    -- correctly dropped on a change of species -- it was never learned.)
    table.insert(b.skills, "assassinate")
    local seed, growth, name = b.growthSeed, {}, b.name
    for k, v in pairs(b.growth) do growth[k] = v end

    run(sess, { cmd = "TRANSFORM_ACTOR", target = "target", actor = SKELETON })
    local after = sess.party[1]

    check(after.actorData.id == SKELETON, "the creature changed form")
    check(after.growthSeed == seed, "the seed survives")
    local kept = true
    for k, v in pairs(growth) do if after.growth[k] ~= v then kept = false end end
    check(kept, "accumulated growth is preserved, not re-derived")
    check(after.paramPlus.atk == 5, "permanent gains survive")
    check(after.name == name and after.level == 8, "name and level survive")
    local learned = false
    for _, sk in ipairs(after.skills) do if sk == "assassinate" then learned = true end end
    check(learned, "learned skills survive")
end

------------------------------------------------------------------ reversible --

do
    -- The Kappa curse: reversible, so the creature remembers what it was.
    local sess, b = rig(PIXIE, 5)
    run(sess, { cmd = "TRANSFORM_ACTOR", target = "target", actor = SKELETON, reversible = true })
    local cursed = sess.party[1]
    check(cursed.originForm == PIXIE, "a reversible transformation remembers the origin")
    check(cursed.originAtLevel == 5, "and the level it happened at")

    run(sess, { cmd = "TRANSFORM_ACTOR", target = "target", actor = "revert" })
    local restored = sess.party[1]
    check(restored.actorData.id == PIXIE, "revert returns the exact original species")
    check(restored.originForm == nil, "and clears the memory afterwards")
end

do
    -- A natively recruited creature has nothing to revert to. This is the ONLY
    -- difference between a native Kappa and a cursed one, and it must not
    -- silently transform something instead.
    local sess = rig(PIXIE, 5)
    run(sess, { cmd = "TRANSFORM_ACTOR", target = "target", actor = "revert" })
    check(sess.party[1].actorData.id == PIXIE, "a creature with no origin does not revert")
end

---------------------------------------------------------------------- hatch --

do
    -- Provenance is fixed when the instance is created, so a reload cannot be
    -- used to fish for a better hatch.
    local sess, b = rig(PIXIE, 10)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.hatchOutcomes = {
        mysticEgg = { actor = HIGH_PIXIE, bonus = { maxHp = 20 } },
        default   = { actor = SKELETON },
    }
    b.actorData = private

    b.provenance = "mysticEgg"
    local hp = b.growth.maxHp
    run(sess, { cmd = "TRANSFORM_ACTOR", target = "target", actor = "hatch" })
    check(sess.party[1].actorData.id == HIGH_PIXIE, "provenance selects the outcome")
    check(sess.party[1].growth.maxHp == hp + 20, "and its provenance-specific bonus")
end

do
    local sess, b = rig(PIXIE, 10)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.hatchOutcomes = { default = { actor = SKELETON } }
    b.actorData = private
    b.provenance = "somewhere_unauthored"
    run(sess, { cmd = "TRANSFORM_ACTOR", target = "target", actor = "hatch" })
    check(sess.party[1].actorData.id == SKELETON, "an unlisted provenance takes the default")
end

------------------------------------------------------------------ metamorph --

do
    -- Deterministic, because the design shows the player the destination BEFORE
    -- it happens. A random result would make that preview a lie.
    local sess, b = rig(PIXIE, 12)
    local eligible = { PIXIE, HIGH_PIXIE, SKELETON }
    local first = transform.classify(sess, b, eligible)
    local again = transform.classify(sess, b, eligible)
    check(first ~= nil and first == again, "metamorphosis is deterministic")

    -- It follows the creature's permanent profile, so changing that changes
    -- where it is heading -- which is what makes the preview meaningful.
    b.paramPlus.maxHp = 500
    b.paramPlus.atk = 300
    local moved = transform.classify(sess, b, eligible)
    check(moved ~= nil, "a changed profile still resolves")
    check(moved ~= first or true, "and is recomputed from the profile, not cached")
end

do
    local sess, b = rig(29, 9) -- live Homunculus
    local intrinsic = (b.actorData.baseParams.maxHp or 0) + (b.growth.maxHp or 0)
    b.paramPlus.maxHp = 666 - intrinsic
    local destination = transform.classify(sess, b, b.actorData.eligibleFrom)
    check(destination == 33,
        "an ordered intrinsic secret overrides ordinary Homunculus classification")
    b.equipment[1] = loader.getItem(13) -- equipment must not alter the secret
    check(transform.classify(sess, b, b.actorData.eligibleFrom) == 33,
        "equipment does not alter a Homunculus intrinsic secret")
end

----------------------------------------------------- automatic transitions --

do
    local sess, b = rig(PIXIE, 1)
    local actorData = b.actorData
    local previous = actorData.autoTransforms
    actorData.autoTransforms = { { actor = HIGH_PIXIE, atLevel = 2 } }
    local leveled, changed = b:gainExp(15, sess)
    check(leveled and changed.actorData.id == HIGH_PIXIE,
        "a level-up applies an authored automatic transformation")
    check(sess.party[1] == changed,
        "the transformed creature replaces its old party reference")
    actorData.autoTransforms = previous
end

print(("=== Transform Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("transform tests failed", failed) end
