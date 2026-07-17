package.path = package.path .. ";../?.lua;?.lua"

-- Mock love for config
_G.love = {
    filesystem = {
        getInfo = function() return false end,
        read = function() return "{}" end
    }
}

local effects = require("engine.effects")
local traits = require("engine.traits")

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

print("=== Testing effects.apply ===")

local function makeMockBattler(hp, def)
    return {
        hp = hp,
        level = 1,
        actorData = {},
        passives = {},
        equipment = {},
        states = {},
        paramPlus = { def = def - 10 }, -- default def is 10, so we adjust with paramPlus
        addedStates = {},
        addState = function(self, state)
            self.addedStates[state] = true
        end
    }
end

local mockSession = {
    loader = {
        elements = {
            Fire = {
                strongAgainst = {"Ice"},
                weakAgainst = {"Water"}
            }
        },
        engine = {
            elementRules = {
                strongMultiplier = 1.5,
                weakMultiplier = 0.5
            }
        }
    }
}

test("hp_damage applies basic damage and returns event", function()
    local a = makeMockBattler(100, 10)
    local b = makeMockBattler(100, 10)

    local effectData = {
        type = "hp_damage",
        formula = "50"
    }

    local events = effects.apply(effectData, a, b, mockSession)

    assert(b.hp == 50, "HP should be reduced by 50. Actual: " .. b.hp)
    assert(#events == 1, "Should return exactly 1 event")
    assert(events[1].type == "damage", "Event should be of type 'damage'")
    assert(events[1].target == b, "Event target should be b")
    assert(events[1].value == 50, "Event value should be 50")
end)

test("hp_damage reduces to 0 and adds dead state", function()
    local a = makeMockBattler(100, 10)
    local b = makeMockBattler(40, 10)

    local effectData = {
        type = "hp_damage",
        formula = "50"
    }

    local events = effects.apply(effectData, a, b, mockSession)

    assert(b.hp == 0, "HP should not drop below 0. Actual: " .. b.hp)
    assert(b.addedStates["dead"] == true, "Battler should have 'dead' state added")
    assert(#events == 2, "Should return damage and death events")
    assert(events[2].type == "death", "Second event should be 'death'")
    assert(events[2].target == b, "Death event target should be b")
end)

test("hp_damage with elemental weakness increases damage", function()
    local a = makeMockBattler(100, 10)
    local b = makeMockBattler(100, 10)
    -- Target is Ice element
    b.actorData.elements = {"Ice"}

    local effectData = {
        type = "hp_damage",
        formula = "50"
    }

    local context = { element = "Fire" }

    local events = effects.apply(effectData, a, b, mockSession, context)

    -- Formula gives 50. Element multiplier strong Against Ice (1.5). Def is 10 (multiplier 1.0).
    -- finalDmg = math.max(1, math.floor(50 * 1 * 1.5)) = 75
    assert(b.hp == 25, "HP should be reduced by 75. Actual: " .. b.hp)
    assert(events[1].value == 75, "Event value should be 75")
end)

test("hp_damage with elemental resistance decreases damage", function()
    local a = makeMockBattler(100, 10)
    local b = makeMockBattler(100, 10)
    -- Target is Water element
    b.actorData.elements = {"Water"}

    local effectData = {
        type = "hp_damage",
        formula = "50"
    }

    local context = { element = "Fire" }

    local events = effects.apply(effectData, a, b, mockSession, context)

    -- Formula gives 50. Element multiplier weak Against Water (0.5).
    -- finalDmg = math.max(1, math.floor(50 * 1 * 0.5)) = 25
    assert(b.hp == 75, "HP should be reduced by 25. Actual: " .. b.hp)
    assert(events[1].value == 25, "Event value should be 25")
end)

print(string.format("=== Tests completed: %d passed, %d failed ===", passed, failed))
if failed > 0 then
    os.exit(1)
end
