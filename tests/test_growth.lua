-- Seeded, budget-first growth (engine/growth.lua).
--
-- The properties here are the ones creature-parameters.md states as rules, and
-- none of them is visible to the golden gates: a stable log proves the numbers
-- did not change, not that they are uneven, replayable, or within budget.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local growth = require("engine.growth")
local traits = require("engine.traits")

print("[TEST] Starting growth tests...")

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

local ACTOR = {
    id = 999,
    baseParams = { maxHp = 30, atk = 10, def = 12, mat = 18, mdf = 16, mpd = 1 },
    growthBands = {
        { from = 2,  to = 10, maxHp = 40, atk = 4,  def = 13, mat = 27, mdf = 22 },
        { from = 11, to = 20, maxHp = 55, atk = 7,  def = 17, mat = 37, mdf = 31 },
        { from = 21, to = 30, maxHp = 60, atk = 9,  def = 22, mat = 50, mdf = 35 },
    },
}

------------------------------------------------------------------ determinism --

do
    local a = growth.accumulate(ACTOR, 4242, 20)
    local b = growth.accumulate(ACTOR, 4242, 20)
    local same = true
    for _, p in ipairs(growth.PARAMS) do
        if a[p] ~= b[p] then same = false end
    end
    check(same, "the same seed always produces the same history")

    -- The design's rule in full: a creature generated directly at a high level
    -- replays the history it would have lived, so a reload cannot reroll a
    -- level-up and a level-20 recruit is not a different kind of creature.
    local walked = {}
    for _, p in ipairs(growth.PARAMS) do walked[p] = 0 end
    for level = 2, 20 do
        local packet = growth.packetFor(ACTOR, 4242, level)
        for _, p in ipairs(growth.PARAMS) do
            walked[p] = walked[p] + (packet[p] or 0)
        end
    end
    local matches = true
    for _, p in ipairs(growth.PARAMS) do
        if walked[p] ~= a[p] then matches = false end
    end
    check(matches, "a creature generated at level 20 replays the same history")
end

do
    -- Different seeds are different creatures. Two given seeds may still agree
    -- on a total -- they share the authored budget, and the variation on it is
    -- deliberately narrow -- so the claim is tested across a spread rather than
    -- on one pair, and on the PATH as well as the destination.
    local totals = {}
    for seed = 1, 12 do
        local t = growth.accumulate(ACTOR, seed * 31337, 20)
        totals[t.maxHp .. "/" .. t.mat] = true
    end
    local distinct = 0
    for _ in pairs(totals) do distinct = distinct + 1 end
    check(distinct > 1, "different seeds produce different lifetime totals")

    local pathDiffers = false
    for level = 2, 20 do
        if (growth.packetFor(ACTOR, 111, level).maxHp or 0)
            ~= (growth.packetFor(ACTOR, 222, level).maxHp or 0) then
            pathDiffers = true
        end
    end
    check(pathDiffers, "and reach them by different paths")
end

do
    -- Growth must never touch the global RNG: it would make a creature's stats
    -- depend on when they happened to be computed, and shift every battle roll
    -- after it.
    local draws = 0
    local realRandom = math.random
    math.random = function(...) draws = draws + 1 return realRandom(...) end
    growth.accumulate(ACTOR, 777, 30)
    math.random = realRandom
    check(draws == 0, "growth consumes no global RNG")
end

------------------------------------------------------------------- the budget --

do
    -- Each band's total lands within the narrow instance variation of what was
    -- authored: lucky in a stat, never materially richer overall.
    local worstDrift = 0
    for seed = 1, 40 do
        local total = growth.accumulate(ACTOR, seed * 7919, 10)
        for _, p in ipairs(growth.PARAMS) do
            local authored = ACTOR.growthBands[1][p]
            if authored and authored > 8 then
                local drift = math.abs(total[p] - authored) / authored
                if drift > worstDrift then worstDrift = drift end
            end
        end
    end
    check(worstDrift <= 0.12,
        ("every seed stays near the authored budget (worst drift %.1f%%)"):format(worstDrift * 100))
end

do
    -- Level 1 IS the base parameters: nothing is granted for existing.
    local none = growth.accumulate(ACTOR, 4242, 1)
    local zero = true
    for _, p in ipairs(growth.PARAMS) do
        if none[p] ~= 0 then zero = false end
    end
    check(zero, "level 1 grants no growth")
end

do
    -- Past the authored bands growth simply stops rather than extrapolating a
    -- curve nobody authored.
    local at30 = growth.accumulate(ACTOR, 4242, 30)
    local at45 = growth.accumulate(ACTOR, 4242, 45)
    local same = true
    for _, p in ipairs(growth.PARAMS) do
        if at30[p] ~= at45[p] then same = false end
    end
    check(same, "growth stops past the last authored band")
end

--------------------------------------------------------------- the unevenness --

do
    -- HP rises at EVERY level. A level-up that shows no change reads as a bug
    -- even when other stats moved.
    local everyLevel = true
    for seed = 1, 25 do
        for level = 2, 30 do
            local packet = growth.packetFor(ACTOR, seed * 104729, level)
            if (packet.maxHp or 0) < 1 then everyLevel = false end
        end
    end
    check(everyLevel, "every level raises HP by at least 1")
end

do
    -- ...and it is NOT smooth. The design wants memorable spurts, so a band's
    -- largest HP packet should be several times its smallest.
    local packets = {}
    for level = 21, 30 do
        table.insert(packets, growth.packetFor(ACTOR, 4242, level).maxHp or 0)
    end
    local lo, hi = math.huge, 0
    for _, v in ipairs(packets) do
        lo = math.min(lo, v)
        hi = math.max(hi, v)
    end
    check(hi >= lo * 3,
        ("HP growth is uneven, not a flat rate (%d..%d across the band)"):format(lo, hi))
end

--------------------------------------------------------------- the live wiring --

do
    local sess = sessionModule.GameSession.new(loader)
    local b = sessionModule.Battler.new(loader.getActor(1), 1, 4242)
    check(b.growthSeed == 4242, "a battler keeps the seed it was given")
    check(b.growth ~= nil, "a battler carries an accumulated growth record")

    -- Levelling adds the next packet to the permanent record; it does not
    -- recompute the earlier ones. That is what a promotion later relies on.
    local before = b.growth.maxHp
    local hpBefore = traits.getParam(b, "maxHp", sess)
    b:gainExp(10000, sess)
    check(b.level > 1, "the creature levelled")
    check(b.growth.maxHp > before, "levelling accrued permanent growth")
    check(traits.getParam(b, "maxHp", sess) > hpBefore, "and the stat followed")

    -- The accumulated record is authoritative: it is the creature's history,
    -- not a cache of something re-derivable.
    b.growth.atk = 99
    check(traits.getParam(b, "atk", sess) ==
        math.floor(traits.getBaseParam(b, "atk")),
        "the accumulated record is what the stat reads")
end

do
    -- An unseeded battler (an enemy built for one battle, an old save) still
    -- resolves, by replaying the actor's stable default rather than inventing
    -- a history. This is what keeps the golden harness reproducible.
    local sess = sessionModule.GameSession.new(loader)
    local raw = {
        actorData = loader.getActor(1), level = 10,
        passives = {}, equipment = {}, states = {}, paramPlus = {},
    }
    local a = traits.getParam(raw, "maxHp", sess)
    local b = traits.getParam(raw, "maxHp", sess)
    check(a == b and a > 0, "an unseeded battler resolves stably")
end

do
    -- Save round trip: both the seed and the record must survive, or a reload
    -- rerolls the creature.
    local savegame = require("engine.savegame")
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(1, 8)
    local seed, hp = b.growthSeed, traits.getParam(b, "maxHp", sess)
    local data = savegame.serialize(sess, loader, "map")
    local restored = savegame.deserialize(data, loader)
    local r = restored.party[1]
    check(r and r.growthSeed == seed, "the growth seed survives a save")
    check(r and traits.getParam(r, "maxHp", restored) == hp,
        "and the creature is the same creature afterwards")
end

do
    -- Two creatures recruited from one species are individuals. This is the
    -- headline promise of the whole model.
    local sess = sessionModule.GameSession.new(loader)
    local seeds = {}
    for _ = 1, 6 do
        local b = sessionModule.Battler.new(loader.getActor(1), 1,
            math.random(1, 2147483646))
        seeds[b.growthSeed] = true
    end
    local distinct = 0
    for _ in pairs(seeds) do distinct = distinct + 1 end
    check(distinct > 1, "recruited creatures get their own seeds")
end

print(("=== Growth Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then error("growth tests failed") end
