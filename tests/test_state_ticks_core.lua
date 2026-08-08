-- Round-end HP drift (STATE_TICKS), driven by the HRG trait.
--
-- This replaced a branch on `state.id == "regen"` / `"poison"` with rates read
-- from system.json. That hardcoded two content ids in the engine, left HRG
-- dead on every item and passive carrying it, and made a second regenerating
-- state impossible to author -- which the planned roster needs.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")

print("[TEST] Starting state tick tests...")

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

-- A battler with a known Max HP and no innate traits, so a tick is arithmetic
-- rather than whatever the roster currently carries.
local function rig(maxHp, traitList)
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor("skeleton", 1)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.traits = traitList or {}
    private.baseParams = { maxHp = maxHp, atk = 10, def = 10, mat = 10, mdf = 10 }
    private.growthMultiplier = 0
    b.actorData = private
    b.passives = {}
    b.level = 1
    sess.party = { b }
    return sess, b
end

local function tick(sess)
    local ctx = { session = sess, party = sess.party, enemies = {}, events = {} }
    interpreter.runImmediate({ { cmd = "STATE_TICKS" } }, ctx)
    return ctx.events
end

local function firstEvent(events, evType)
    for _, ev in ipairs(events) do if ev.type == evType then return ev end end
    return nil
end

------------------------------------------------------------------ direction --

do
    local sess, b = rig(100, { { code = "HRG", value = 0.1 } })
    b.hp = 50
    local ev = firstEvent(tick(sess), "heal")
    check(b.hp == 60 and ev and ev.value == 10,
        "a positive HRG restores that share of Max HP")
end

do
    -- Negative HRG is degeneration: one trait, both directions, so poison is
    -- not a second mechanism the engine has to know about by name.
    local sess, b = rig(100, { { code = "HRG", value = -0.1 } })
    b.hp = 50
    local ev = firstEvent(tick(sess), "damage")
    check(b.hp == 40 and ev and ev.value == 10,
        "a negative HRG drains that share of Max HP")
end

do
    local sess, b = rig(100, { { code = "HRG", value = 0.1 } })
    b.hp = 95
    tick(sess)
    check(b.hp == 100, "regeneration never overheals")
end

do
    local sess, b = rig(100, { { code = "HRG", value = -0.5 } })
    b.hp = 10
    local events = tick(sess)
    check(b.hp == 0 and b:isDead(), "degeneration can kill")
    check(firstEvent(events, "death") ~= nil, "a death from degeneration is reported")
end

do
    -- A rate too small to move a small creature emits nothing at all, rather
    -- than a "+0 HP" line that reads as a tick and is not one.
    local sess, b = rig(10, { { code = "HRG", value = 0.05 } })
    b.hp = 5
    local events = tick(sess)
    check(b.hp == 5, "a rate that rounds to nothing changes nothing")
    check(firstEvent(events, "heal") == nil and firstEvent(events, "damage") == nil,
        "a rate that rounds to nothing emits no event")
end

--------------------------------------------------------------- composition --

do
    -- Summed across sources, so an authored regeneration and a poison net out
    -- instead of both firing and racing each other in the log.
    local sess, b = rig(100, {
        { code = "HRG", value = 0.15 },
        { code = "HRG", value = -0.05 },
    })
    b.hp = 50
    tick(sess)
    check(b.hp == 60, "HRG sums across sources, so regen and poison net out")
end

do
    local sess, b = rig(100, {
        { code = "HRG", value = 0.1 },
        { code = "HRG", value = -0.1 },
    })
    b.hp = 50
    local events = tick(sess)
    check(b.hp == 50 and firstEvent(events, "heal") == nil,
        "exactly cancelling rates produce no tick")
end

do
    local sess, b = rig(100, {})
    b.hp = 50
    b:addState("regen")
    tick(sess)
    check(b.hp > 50, "the live regen state still regenerates through its trait")
end

do
    local sess, b = rig(100, {})
    b.hp = 50
    b:addState("poison")
    tick(sess)
    check(b.hp < 50, "the live poison state still damages through its trait")
end

do
    local sess, b = rig(100, {})
    b.hp = 50
    tick(sess)
    check(b.hp == 50, "a creature with no HRG anywhere is untouched")
end

-- The dead are not ticked: a corpse that keeps regenerating would climb back
-- above zero without ever leaving the dead state.
do
    local sess, b = rig(100, { { code = "HRG", value = 0.1 } })
    b.hp = 0
    b:addState("dead")
    tick(sess)
    check(b.hp == 0, "a dead creature does not tick")
end

------------------------------------------------------- no hardcoded content --

-- The point of the change: a SECOND regenerating state must work, because the
-- roster plans one (Kirin's party-wide regeneration) and the old id-matching
-- engine could only ever tick the one id it named.
do
    local sess, b = rig(100, {})
    b.hp = 50
    -- Any state carrying HRG regenerates, whatever it is called. Simulated
    -- through a passive-shaped source rather than by authoring a state, so the
    -- test does not depend on content that does not exist yet.
    b.actorData.traits = { { code = "HRG", value = 0.08 } }
    tick(sess)
    check(b.hp == 58,
        "any source carrying HRG regenerates, not just the state named 'regen'")
end

-- Duration decay is the other half of STATE_TICKS and must survive the rewrite.
do
    local sess, b = rig(100, {})
    b:addState("regen")
    local before
    for _, st in ipairs(b.states) do if st.id == "regen" then before = st.duration end end
    tick(sess)
    local after
    for _, st in ipairs(b.states) do if st.id == "regen" then after = st.duration end end
    check(before and after and after == before - 1,
        "state durations still decay one per round")
end

print(("=== State Tick Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("state tick tests failed", failed) end
