-- Promotion preserves history (creature-parameters.md).
--
-- "Promotion never recalculates statistics. It preserves all accumulated
-- lower-form growth, grants a fixed authored one-time bonus, replaces only
-- future unused growth budgets, and changes form-defined MPD, capacities,
-- affinities, skills and passives."
--
-- The first clause is the one with teeth, and it is the reason growth had to
-- become accumulated first: under a smooth species curve there was no past to
-- preserve, because changing species re-derived every level retroactively.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local traits = require("engine.traits")
local growth = require("engine.growth")

print("[TEST] Starting promotion tests...")

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

-- Pixie (actor 1) promotes into High Pixie (actor 2) at level 6.
local PIXIE, HIGH_PIXIE = 1, 2

local function rigPixie(level)
    local sess = sessionModule.GameSession.new(loader)
    sess.party = {}
    local b = sessionModule.Battler.new(loader.getActor(PIXIE), level, 24680)
    b.hp = b:getMaxHp(sess)
    sess.party[1] = b
    sess.mp = 9999
    return sess, b
end

-- Promotion lives on the SCRIPT api, which is how the ritual scene reaches it,
-- so the tests drive exactly that path rather than reaching into internals.
-- The body goes in `code`, and `v` comes off ctx -- the idiom every scene
-- script uses.
local function runScript(sess, body)
    local ctx = { session = sess, loader = loader, events = {}, v = {} }
    interpreter.runImmediate({ { cmd = "SCRIPT",
        code = "local v = ctx.v; " .. body } }, ctx)
    return ctx.v
end

------------------------------------------------------------------- eligibility --

do
    local sess = rigPixie(1)
    local v = runScript(sess, "v.can = api.canPromote(false, 1)")
    check(v.can == false, "a level-1 Pixie cannot promote (its path needs level 6)")

    local sess2 = rigPixie(6)
    local v2 = runScript(sess2, "v.can = api.canPromote(false, 1)")
    check(v2.can == true, "a level-6 Pixie can")
end

------------------------------------------------------- history is preserved --

do
    local sess, b = rigPixie(6)

    -- What the creature earned as a Pixie, before anything changes.
    local beforeGrowth = {}
    for _, p in ipairs(growth.PARAMS) do beforeGrowth[p] = b.growth[p] end
    local beforeSeed = b.growthSeed
    local beforeName = b.name

    runScript(sess, "api.promote(false, 1)")
    local after = sess.party[1]

    check(after ~= nil and after.actorData.id == HIGH_PIXIE, "the creature promoted")
    check(after.growthSeed == beforeSeed,
        "the growth seed survives -- it is the same individual")

    -- The Pixie levels are still Pixie levels. Under the destination form's
    -- budgets they would have come out differently; this is the assertion that
    -- promotion does not rewrite the past.
    local bonus = { maxHp = 8, mat = 5, mdf = 3 }
    local preserved = true
    for _, p in ipairs(growth.PARAMS) do
        if after.growth[p] ~= beforeGrowth[p] + (bonus[p] or 0) then preserved = false end
    end
    check(preserved, "accumulated lower-form growth is preserved exactly")

    -- ...and demonstrably not the same as re-deriving under the new species.
    local rederived = growth.accumulate(loader.getActor(HIGH_PIXIE), beforeSeed, 6)
    local differs = false
    for _, p in ipairs(growth.PARAMS) do
        if rederived[p] ~= beforeGrowth[p] then differs = true end
    end
    check(differs, "re-deriving under the new form would have given different numbers")

    check(after.name == beforeName, "the creature keeps its name")
    check(after.level == 6, "and its level")
    check((after.history.promotions or 0) == 1, "the promotion is recorded")
    check(after.history.species == "Pixie",
        "history still remembers what it hatched as")
end

do
    -- The fixed bonus applies once and is exactly what was authored.
    local sess, b = rigPixie(6)
    local beforeHp = b.growth.maxHp
    runScript(sess, "api.promote(false, 1)")
    check(sess.party[1].growth.maxHp == beforeHp + 8,
        "the authored one-time bonus is applied exactly once")
end

do
    -- Fixed means fixed: promoting later does not scale the bonus up. A player
    -- who delays has banked more of the cheaper form's growth instead, which is
    -- the tradeoff the design wants -- not a larger reward for waiting.
    local function bonusAt(level)
        local sess, b = rigPixie(level)
        local before = b.growth.maxHp
        runScript(sess, "api.promote(false, 1)")
        return sess.party[1].growth.maxHp - before
    end
    check(bonusAt(6) == bonusAt(20) and bonusAt(6) == 8,
        "the bonus does not grow for promoting late")
end

do
    -- Delaying still pays, through the lower form's own accumulated levels.
    local early = (function()
        local sess, b = rigPixie(6)
        runScript(sess, "api.promote(false, 1)")
        return sess.party[1].growth.maxHp
    end)()
    local late = (function()
        local sess, b = rigPixie(12)
        runScript(sess, "api.promote(false, 1)")
        return sess.party[1].growth.maxHp
    end)()
    check(late > early, "a creature promoted later carries more accumulated growth")
end

------------------------------------------------------ future budgets change --

do
    -- Only FUTURE growth uses the new form's budgets. Levelling after the
    -- promotion must draw on High Pixie's bands, not Pixie's.
    local sess = rigPixie(6)
    runScript(sess, "api.promote(false, 1)")
    local after = sess.party[1]

    local beforeLevel, beforeGrowth = after.level, after.growth.mat
    after:gainExp(100000, sess)
    check(after.level > beforeLevel, "the promoted creature levels")
    check(after.growth.mat > beforeGrowth, "and accrues further growth")

    local expected = growth.packetFor(loader.getActor(HIGH_PIXIE),
        after.growthSeed, beforeLevel + 1).mat or 0
    local pixiePacket = growth.packetFor(loader.getActor(PIXIE),
        after.growthSeed, beforeLevel + 1).mat or 0
    check(expected ~= pixiePacket,
        "the two forms really do budget that level differently (a meaningful test)")
end

--------------------------------------------------------------- other carries --

do
    local sess, b = rigPixie(6)
    b.paramPlus.atk = 7
    b.hp = 3
    runScript(sess, "api.promote(false, 1)")
    local after = sess.party[1]
    check(after.paramPlus.atk == 7,
        "permanent stat-up items are not wiped by promotion")
    check(after.hp == 3, "current HP carries rather than being topped up")
    check(after.hp <= traits.getParam(after, "maxHp", sess), "and stays within the new max")
end

do
    -- The HP clamp must be computed AFTER the growth record is restored, or a
    -- promoted creature is capped at its unpromoted maximum.
    local sess, b = rigPixie(6)
    b.hp = b:getMaxHp(sess)
    local beforeMax = b:getMaxHp(sess)
    runScript(sess, "api.promote(false, 1)")
    local after = sess.party[1]
    check(traits.getParam(after, "maxHp", sess) > beforeMax,
        "promotion raises Max HP")
    check(after.hp > beforeMax - 1, "a full-health creature is not clipped by the old max")
end

do
    -- Learned skills (skillbooks) belong to the creature, not the species.
    local sess, b = rigPixie(6)
    table.insert(b.skills, "windBlade")
    runScript(sess, "api.promote(false, 1)")
    local kept = false
    for _, sk in ipairs(sess.party[1].skills or {}) do
        if sk == "windBlade" then kept = true end
    end
    check(kept, "a learned skill survives promotion")
end

------------------------------------------------------------- the item gate --

do
    -- An evolution with no `level` is open immediately: acquiring and spending
    -- the key IS the gate. Such an entry used to be silently ineligible
    -- forever, so an item-only promotion could not be authored at all.
    local sess = rigPixie(1)
    local b = sess.party[1]
    local privateData = {}
    for k, val in pairs(b.actorData) do privateData[k] = val end
    privateData.evolutions = { { evolvesTo = HIGH_PIXIE } }
    b.actorData = privateData

    local v = runScript(sess, "v.can = api.canPromote(false, 1)")
    check(v.can == true, "an evolution with no level requirement is open at level 1")

    runScript(sess, "api.promote(false, 1)")
    check(sess.party[1].actorData.id == HIGH_PIXIE,
        "and a level-1 creature can take it")
end

print(("=== Promotion Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then error("promotion tests failed") end
