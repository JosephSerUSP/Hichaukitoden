-- The Summoner MP economy: traversal cost, Battle Strain, and the MPD floor.
--
-- The design's whole expedition tension lives here -- a step costs exactly what
-- the living party costs to keep manifested, ordinary combat rounds cost
-- nothing, and only a prolonged battle bills you. Both halves used to be flat
-- numbers that ignored the party entirely.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local formula = require("engine.formula")
local flow = require("engine.flow")
local traits = require("engine.traits")

print("[TEST] Starting MPD economy tests...")

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

-- A party of creatures with exact MPD values, so a cost is arithmetic rather
-- than whatever the roster currently carries.
local function rig(mpdValues)
    local sess = sessionModule.GameSession.new(loader)
    sess.party = {}
    for i, mpd in ipairs(mpdValues) do
        local b = sessionModule.Battler.new(loader.getActor(3), 1)
        local private = {}
        for k, val in pairs(b.actorData) do private[k] = val end
        private.traits = {}
        private.baseParams = { maxHp = 50, atk = 10, def = 10, mat = 10, mdf = 10, mpd = mpd }
        private.growthMultiplier = 0
        b.actorData = private
        b.level = 1
        b.hp = 50
        sess.party[i] = b
    end
    sess.maxMp = 3000
    sess.mp = 3000
    sess.currentMapData = { safe = false }
    return sess
end

------------------------------------------------------------- the party query --

do
    local sess = rig({ 1, 2, 4 })
    check(formula.groupView(sess.party, sess).mpd == 7,
        "party.mpd is the combined MPD of the party")

    -- A dead creature stops costing anything. That is the grim arithmetic the
    -- design is built on, so it is asserted rather than assumed.
    sess.party[3].hp = 0
    sess.party[3]:addState("dead")
    check(formula.groupView(sess.party, sess).mpd == 3,
        "a dead creature contributes no MPD")
end

------------------------------------------------------------- traversal cost --

local function step(sess)
    local before = sess.mp
    flow.run("exploration.step", { session = sess, party = sess.party, loader = loader })
    return before - sess.mp
end

do
    local sess = rig({ 1 })
    check(step(sess) == 1, "a lone MPD-1 creature costs 1 MP per step")
end

do
    local sess = rig({ 4, 6, 9 })
    check(step(sess) == 19, "a heavy party costs the sum of its MPD per step")
end

do
    -- The design's headline: the Summoner has no traversal cost of their own,
    -- so an empty party walks free rather than paying a base rate.
    local sess = rig({})
    check(step(sess) == 0, "the Summoner alone pays nothing to walk")
end

do
    local sess = rig({ 4, 6 })
    sess.currentMapData = { safe = true }
    check(step(sess) == 0, "a safe map costs nothing")
end

do
    -- Range, in the terms the design's table uses: 3000 MP against a party of
    -- MPD 5 is 600 steps.
    local sess = rig({ 1, 4 })
    local steps = 0
    while sess.mp > 0 and steps < 5000 do
        step(sess)
        steps = steps + 1
    end
    check(steps == 600, "3000 MP buys 600 steps at party MPD 5 (" .. steps .. ")")
end

------------------------------------------------------------------- Strain --

local function roundEnd(sess, round)
    local before = sess.mp
    flow.run("battle.round_end", {
        session = sess, party = sess.party, enemies = {},
        battle = { round = round, allies = sess.party, enemies = {} },
        loader = loader,
    })
    return before - sess.mp
end

do
    local sess = rig({ 2, 3 })  -- combined MPD 5

    -- Ordinary rounds are free. Taking a tactical turn is not priced, which is
    -- the explicit reversal: every round used to bill the whole party's MPD.
    for round = 1, 5 do
        check(roundEnd(sess, round) == 0, "round " .. round .. " costs nothing")
    end

    check(roundEnd(sess, 6) == 20, "round 6 strains at 4x combined MPD")
    check(roundEnd(sess, 9) == 20, "round 9 is still the first band")
    check(roundEnd(sess, 10) == 40, "round 10 escalates to 8x")
    check(roundEnd(sess, 14) == 40, "round 14 is still the second band")
    check(roundEnd(sess, 15) == 80, "round 15 escalates to 16x")
    check(roundEnd(sess, 40) == 80, "the top band does not escalate further")
end

do
    -- Strain scales with the party, so a cheap party can afford a long fight
    -- and a heavy one cannot. That is the tradeoff the whole roster is priced
    -- against.
    local cheap = rig({ 1 })
    local heavy = rig({ 9, 9 })
    check(roundEnd(cheap, 6) == 4 and roundEnd(heavy, 6) == 72,
        "Strain scales with the party's combined MPD")
end

do
    local sess = rig({ 2, 3 })
    sess.currentMapData = { safe = true }
    check(roundEnd(sess, 20) == 0, "no Strain on a safe map")
end

do
    -- A wiped party costs nothing to sustain, however long the fight runs.
    local sess = rig({ 4, 4 })
    for _, b in ipairs(sess.party) do b.hp = 0 b:addState("dead") end
    check(roundEnd(sess, 20) == 0, "a party with no living creatures strains nothing")
end

--------------------------------------------------------------- the MPD floor --

do
    -- "An accessory may reduce its wearer's MPD by 1, never below 1." The floor
    -- is traits.getParam's, not a special case -- asserted here because the
    -- design states it as a hard rule and nothing else pins it.
    local sess = rig({ 2 })
    local b = sess.party[1]
    check(traits.getParam(b, "mpd", sess) == 2, "a creature reports its form MPD")

    b.actorData.traits = { { code = "PARAM_PLUS", dataId = "mpd", value = -1 } }
    check(traits.getParam(b, "mpd", sess) == 1, "an MPD reduction applies")

    b.actorData.traits = { { code = "PARAM_PLUS", dataId = "mpd", value = -99 } }
    check(traits.getParam(b, "mpd", sess) == 1, "MPD never falls below 1")
    check(formula.groupView(sess.party, sess).mpd == 1,
        "the floored value is what the party query and the step cost see")
end

print(("=== MPD Economy Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then error("MPD economy tests failed") end
