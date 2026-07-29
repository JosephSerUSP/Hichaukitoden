-- Level-up reporting (engine/progress.lua).
--
-- None of this is visible to the golden gates: they prove the battle log did
-- not change, not that a diff taken around an EXP grant names the right
-- creature, the right numbers, or survives the transform that a level-up can
-- trigger (which REPLACES the object in the party slot).
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local progress = require("engine.progress")
local traits = require("engine.traits")

print("[TEST] Starting progress tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  [PASS] " .. msg)
    else
        failed = failed + 1
        print("  [FAIL] " .. msg)
    end
end

loader.init()

local function rowFor(entry, param)
    for _, r in ipairs(entry.rows) do
        if r.param == param then return r end
    end
end

do
    -- The base case: one creature crosses a threshold and the report is a
    -- before/after of what the player can see on the status screen.
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(1, 1)
    local before = progress.snapshot(sess)
    local hpBefore = traits.getParam(b, "maxHp", sess)
    b:gainExp(1000, sess)
    local entries = progress.levelUps(sess, before)

    check(#entries == 1, "a creature that levelled produces exactly one entry")
    local e = entries[1]
    check(e and e.fromLevel == 1 and e.toLevel == sess.party[1].level,
        "the entry spans the whole grant, not one level of it")
    check(e and e.portraitKey ~= "", "the entry carries a portrait key")
    local hp = e and rowFor(e, "maxHp")
    check(hp and hp.from == hpBefore and hp.to == traits.getParam(sess.party[1], "maxHp", sess),
        "HP is reported from the same accessor the status screen reads")
    check(hp and hp.delta == hp.to - hp.from and hp.deltaText == "+" .. hp.delta,
        "the delta is derived, and pre-signed for the window's format string")
end

do
    -- No level, no entry. The window must not appear for a fight that merely
    -- moved the EXP gauge.
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(1, 1)
    local before = progress.snapshot(sess)
    b:gainExp(1, sess)
    check(#progress.levelUps(sess, before) == 0, "a sub-threshold grant reports nothing")
end

do
    -- A stat that sat this level out prints nothing rather than "+0" -- every
    -- growing parameter still gets a row, so the table doesn't reflow.
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(1, 1)
    local before = progress.snapshot(sess)
    b:gainExp(1000, sess)
    local e = progress.levelUps(sess, before)[1]
    check(e and #e.rows == 5, "every growing parameter gets a row")
    local ok = true
    for _, r in ipairs(e.rows) do
        if r.delta == 0 and r.deltaText ~= "" then ok = false end
    end
    check(ok, "an unchanged stat shows no delta text")
end

do
    -- Slot-keyed, not identity-keyed: an Egg levelling to 10 hatches, which
    -- REPLACES the object in the party slot. An identity-keyed diff would lose
    -- exactly the creature whose report matters most.
    local sess = sessionModule.GameSession.new(loader)
    local egg = sess:recruitActor(15, 9)
    local wasId = egg.actorData.id
    local before = progress.snapshot(sess)
    egg:gainExp(1000, sess)
    local entries = progress.levelUps(sess, before)
    check(sess.party[1].actorData.id ~= wasId, "the Egg hatched into another actor")
    check(#entries == 1, "a level-up that transforms the creature still reports once")
    check(entries[1] and entries[1].noteText ~= "", "and says what it became")
end

do
    -- publish() is the seam the data-authored window reads. Index 0 (nobody
    -- levelled) must leave the vars empty rather than nil-erroring a format.
    local v = {}
    progress.publish(v, {}, 0)
    check(v.levelUpName == "" and #v.levelUpRows == 0, "publishing nothing clears the vars")

    local entries = {
        { name = "A", portraitKey = "a", fromLevel = 1, toLevel = 2, exp = 3,
          expNeeded = 30, rows = {}, noteText = "" },
        { name = "B", portraitKey = "b", fromLevel = 4, toLevel = 5, exp = 6,
          expNeeded = 75, rows = {}, noteText = "" },
    }
    progress.publish(v, entries, 2)
    check(v.levelUpName == "B" and v.levelUpToLevel == 5, "publishing selects by index")
    check(v.levelUpCounter == "2/2", "and shows a position while there is more than one")
    progress.publish(v, { entries[1] }, 1)
    check(v.levelUpCounter == "", "a lone level-up needs no position indicator")
end

print(("=== Progress Tests: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then error("progress tests failed") end
