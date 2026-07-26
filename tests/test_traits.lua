package.path = package.path .. ";../?.lua;?.lua"

-- Mock love for config when running under a plain Lua runner. Under LÖVE
-- the real table must survive — replacing it kills love.event and crashes
-- the boot loop after the tests finish.
if not _G.love then
    _G.love = {
        filesystem = {
            getInfo = function() return false end,
            read = function() return "{}" end
        }
    }
end

local traits = require("engine.traits")
local config = require("engine.config")

config.growth = {
    growthExponent = 1.2,
    baseParams = { maxHp = 10, atk = 10, def = 10, mat = 10, mdf = 10, mpd = 2, mxa = 4, mxp = 2 },
    growthRates = { maxHp = 0.12, atk = 0.15, def = 0.13, mat = 0.15, mdf = 0.13, mpd = 0.05 }
}

-- Simple test framework
local passed = 0
local failed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("  [PASS] " .. name)
        passed = passed + 1
    else
        print("  [FAIL] " .. name)
        print("         " .. tostring(err))
        failed = failed + 1
    end
end

print("=== Testing traits.getActiveObjects ===")

local mockSession = {
    loader = {
        getPassive = function(id)
            if id == "passive_hp" then
                return { traits = { {code = "PARAM_RATE", dataId = "maxHp", value = 1.1} }, condition = nil }
            elseif id == "passive_conditional" then
                return { traits = { {code = "PARAM_RATE", dataId = "atk", value = 1.5} }, condition = "HP < 50%" }
            end
            return nil
        end,
        getState = function(id)
            if id == "poison" then
                return { traits = { {code = "PARAM_RATE", dataId = "def", value = 0.8} }, condition = nil }
            end
            return nil
        end
    }
}

test("empty battler returns only default innate traits object", function()
    local battler = {
        actorData = {},
        passives = {},
        equipment = {},
        states = {}
    }

    local objs = traits.getActiveObjects(battler, mockSession)

    assert(#objs == 1, "Should have 1 active object (innate)")
    assert(type(objs[1].traits) == "table", "Innate traits should be a table")
    assert(#objs[1].traits == 0, "Innate traits should be empty")
    assert(objs[1].condition == nil, "Innate condition should be nil")
end)

test("battler with actorData traits includes them in innate object", function()
    local battler = {
        actorData = { traits = { {code = "PARAM_PLUS", dataId = "maxHp", value = 50} } },
        passives = {},
        equipment = {},
        states = {}
    }

    local objs = traits.getActiveObjects(battler, mockSession)

    assert(#objs == 1, "Should have 1 active object")
    assert(#objs[1].traits == 1, "Should have 1 innate trait")
    assert(objs[1].traits[1].code == "PARAM_PLUS", "Innate trait code mismatch")
    assert(objs[1].traits[1].dataId == "maxHp", "Innate trait dataId mismatch")
    assert(objs[1].traits[1].value == 50, "Innate trait value mismatch")
end)

test("battler with passives includes their traits", function()
    local battler = {
        actorData = {},
        passives = { "passive_hp", "passive_missing", "passive_conditional" },
        equipment = {},
        states = {}
    }

    local objs = traits.getActiveObjects(battler, mockSession)

    assert(#objs == 3, "Should have 3 active objects (1 innate + 2 passives)")

    -- objs[1] is innate

    -- objs[2] is passive_hp
    assert(#objs[2].traits == 1, "Passive 1 should have 1 trait")
    assert(objs[2].traits[1].code == "PARAM_RATE", "Passive 1 trait code mismatch")
    assert(objs[2].condition == nil, "Passive 1 condition mismatch")

    -- objs[3] is passive_conditional
    assert(#objs[3].traits == 1, "Passive 2 should have 1 trait")
    assert(objs[3].condition == "HP < 50%", "Passive 2 condition mismatch")
end)

test("battler with equipment includes their traits", function()
    local battler = {
        actorData = {},
        passives = {},
        equipment = {
            { traits = { {code = "ELEMENT_CHANGE", dataId = "fire"} }, condition = nil },
            nil,
            { traits = { {code = "PARAM_PLUS", dataId = "atk", value = 10} }, condition = "HP < 100%" }
        },
        states = {}
    }

    local objs = traits.getActiveObjects(battler, mockSession)

    assert(#objs == 3, "Should have 3 active objects (1 innate + 2 equipments)")

    -- objs[2] is equipment 1
    assert(objs[2].traits[1].code == "ELEMENT_CHANGE", "Equip 1 trait mismatch")
    assert(objs[2].condition == nil, "Equip 1 condition mismatch")

    -- objs[3] is equipment 3
    assert(objs[3].traits[1].code == "PARAM_PLUS", "Equip 3 trait mismatch")
    assert(objs[3].condition == "HP < 100%", "Equip 3 condition mismatch")
end)

test("battler with states includes their traits", function()
    local battler = {
        actorData = {},
        passives = {},
        equipment = {},
        states = {
            { id = "poison" },
            { id = "missing_state" }
        }
    }

    local objs = traits.getActiveObjects(battler, mockSession)

    assert(#objs == 2, "Should have 2 active objects (1 innate + 1 state)")

    -- objs[2] is poison state
    assert(objs[2].traits[1].code == "PARAM_RATE", "State trait mismatch")
    assert(objs[2].traits[1].dataId == "def", "State trait dataId mismatch")
end)

test("battler with all combinations returns correctly ordered objects", function()
    local battler = {
        actorData = { traits = { {code = "1"} } },
        passives = { "passive_hp" },
        equipment = { { traits = { {code = "3"} } } },
        states = { { id = "poison" } }
    }

    local objs = traits.getActiveObjects(battler, mockSession)

    assert(#objs == 4, "Should have 4 active objects")

    assert(objs[1].traits[1].code == "1", "Innate trait should be first")
    assert(objs[2].traits[1].code == "PARAM_RATE", "Passive should be second")
    assert(objs[3].traits[1].code == "3", "Equipment should be third")
    assert(objs[4].traits[1].dataId == "def", "State should be fourth")
end)

print("=== Testing creature parameter growth ===")

test("growth is the accumulated seeded record, not a curve", function()
    -- Growth is ADDITIVE and per-instance now: a stat is its base plus the
    -- packets this creature actually received. The old assertion here computed
    -- `8 * (1 + .15 * 9^1.2)` and expected every creature of a species to land
    -- on the same number -- which is precisely what the seeded model exists to
    -- stop.
    local actorData = {
        baseParams = { atk = 8 },
        growthBands = { { from = 2, to = 10, atk = 18 } },
    }
    local battler = {
        actorData = actorData, growthSeed = 12345, level = 10,
        passives = {}, equipment = {}, states = {}, paramPlus = {}
    }
    -- Base 8 plus the level 2-10 budget of 18. The total is not exactly 26:
    -- an instance's seed perturbs the authored budget by about +-5%, so it may
    -- be lucky or unlucky in a stat without receiving a materially larger
    -- lifetime total. The band is the assertion; the exact number is the
    -- creature's own.
    local atk = traits.getParam(battler, "atk", mockSession)
    assert(atk >= 25 and atk <= 27,
        "base 8 plus an 18 budget varied by ~5% should land in 25..27, got " .. tostring(atk))

    -- An explicit accumulated record wins over replaying the seed, because it
    -- is the creature's actual history (a promotion changes future budgets
    -- without touching what was already earned).
    battler.growth = { atk = 3 }
    assert(traits.getParam(battler, "atk", mockSession) == 11,
        "an accumulated record is used as-is")
end)

test("two instances of one species grow differently", function()
    local actorData = {
        baseParams = { atk = 10, maxHp = 30 },
        growthBands = { { from = 2, to = 10, atk = 20, maxHp = 40 } },
    }
    local function at(seed, level)
        return traits.getParam({
            actorData = actorData, growthSeed = seed, level = level,
            passives = {}, equipment = {}, states = {}, paramPlus = {}
        }, "atk", mockSession)
    end
    -- Same budget, so the same level-10 total: the variation is in the PATH.
    local diverged = false
    for level = 2, 9 do
        if at(111, level) ~= at(999, level) then diverged = true end
    end
    assert(diverged, "different seeds should produce different growth histories")
end)

test("mpd, mxa and mxp are form-defined and never grow", function()
    local battler = {
        actorData = { baseParams = { mpd = 2, mxa = 4, mxp = 2 } },
        level = 20,
        passives = {}, equipment = {}, states = {}, paramPlus = {}
    }
    assert(traits.getParam(battler, "mxa", mockSession) == 4, "mxa must not grow")
    assert(traits.getParam(battler, "mxp", mockSession) == 2, "mxp must not grow")
    -- MPD used to grow at 0.05 a level, so raising a creature quietly made it
    -- more expensive to keep manifested -- the reverse of the economy the
    -- design describes, where an early form stays cheap and promotion is what
    -- costs you. It is a form-defined expedition cost now, full stop.
    assert(traits.getParam(battler, "mpd", mockSession) == 2,
        "mpd is form-defined and must not grow with level")
end)

print(string.format("=== Tests completed: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    os.exit(1)
end
