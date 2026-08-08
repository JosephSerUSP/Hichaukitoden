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

local effects = require("engine.effects")

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

local function approx(a, b, why)
    assert(math.abs(a - b) < 1e-6,
        string.format("%s: expected %.6f, got %.6f", why or "mismatch", b, a))
end

print("=== Testing effects.elementMultiplier (signed two-layer element model) ===")

-- The five true elements: Red > Green > Blue > Red is a cycle, White <-> Black
-- is a mutual opposition. Mirrors data/elements.json.
local ELEMENTS = {
    Red   = { strongAgainst = { "Green" }, weakAgainst = { "Blue" } },
    Green = { strongAgainst = { "Blue" },  weakAgainst = { "Red" } },
    Blue  = { strongAgainst = { "Red" },   weakAgainst = { "Green" } },
    White = { strongAgainst = { "Black" }, weakAgainst = {} },
    Black = { strongAgainst = { "White" }, weakAgainst = {} },
}

local RULES = {
    skillStrongBonus = 0.5, skillStrongDecay = 0.7, skillWeakMultiplier = 0.65,
    userStrongBonus = 0.15, userStrongDecay = 0.8,  userWeakMultiplier = 0.9,
    weakFloor = 0.3,
}

local session = {
    loader = {
        elements = ELEMENTS,
        engine = { elementRules = RULES },
        getPassive = function() return nil end,
        getState = function() return nil end,
    }
}

local function battler(elems, equipment)
    return {
        actorData = { elements = elems },
        passives = {}, equipment = equipment or {}, states = {}, paramPlus = {}
    }
end

-- Reference implementation of the diminishing-returns curve, kept independent
-- of the engine's so a change to one does not silently validate the other.
local function bonus(rate, decay, n)
    local sum = 0
    for i = 0, n - 1 do sum = sum + rate * decay ^ i end
    return sum
end

test("no element anywhere is a flat 1.0 -- the non-elemental hedge", function()
    local m = effects.elementMultiplier(nil, battler({}), battler({}), session)
    approx(m, 1.0, "neutral vs neutral")
end)

test("a neutral target is immune to advantage from either layer", function()
    local m = effects.elementMultiplier("Red", battler({ "Red", "Red" }), battler({}), session)
    approx(m, 1.0, "everything vs non-elemental")
end)

test("a neutral attacker with a neutral skill gets no user bonus", function()
    local m = effects.elementMultiplier(nil, battler({}), battler({ "Green" }), session)
    approx(m, 1.0, "Golem swinging plainly")
end)

test("single skill match keeps parity with the old flat 1.5x", function()
    local m = effects.elementMultiplier("Red", nil, battler({ "Green" }), session)
    approx(m, 1.5, "one strong match")
end)

test("skill layer counts the TARGET's repeated depth, with diminishing returns", function()
    local m = effects.elementMultiplier("Red", nil, battler({ "Green", "Green", "Green" }), session)
    approx(m, 1 + bonus(0.5, 0.7, 3), "three target Greens")
    -- The old pre-diminishing model multiplied: 1.5^3 = 3.375. The curve must be tamer.
    assert(m < 3.375, "diminishing returns should undercut 1.5^n")
end)

test("skill strong and weak relations cancel before multiplier math", function()
    -- Red is strong into Green and weak into Blue: one +1 and one -1 is
    -- exactly neutral, not the old 1.5 * 0.65 = 0.975 residue.
    local m = effects.elementMultiplier("Red", nil, battler({ "Green", "Blue" }), session)
    approx(m, 1.0, "Red skill into Green+Blue")
end)

test("user layer is a cross-product of both sides' depth", function()
    -- 3 attacker Reds x 2 target Greens = 6 favorable pairings.
    local m = effects.elementMultiplier(nil,
        battler({ "Red", "Red", "Red" }), battler({ "Green", "Green" }), session)
    approx(m, 1 + bonus(0.15, 0.8, 6), "3x2 cross-product")
end)

test("opposed innate colors cancel exactly", function()
    -- Red is weak to Blue; Green is strong to Blue. The visible + and - cancel.
    local m = effects.elementMultiplier(nil,
        battler({ "Red", "Green" }), battler({ "Blue" }), session)
    approx(m, 1.0, "RG into Blue")
end)

test("RGB is innately neutral into each RGB-cycle color", function()
    local user = battler({ "Red", "Green", "Blue" })
    for _, targetElem in ipairs({ "Red", "Green", "Blue" }) do
        local m = effects.elementMultiplier(nil, user, battler({ targetElem }), session)
        approx(m, 1.0, "RGB into " .. targetElem)
    end
end)

test("balanced broad attacker and defender cancel exactly", function()
    local m = effects.elementMultiplier(nil,
        battler({ "Red", "Green", "Blue" }),
        battler({ "Red", "Green", "Blue" }), session)
    approx(m, 1.0, "RGB into RGB")
end)

test("repeated alignment survives cancellation as remaining depth", function()
    -- RRG into Blue is weak, weak, strong => net -1, not neutral and not the
    -- old 1.15 * 0.9^2 = 0.9315 residue.
    local m = effects.elementMultiplier(nil,
        battler({ "Red", "Red", "Green" }), battler({ "Blue" }), session)
    approx(m, 0.9, "RRG into Blue")
end)

test("the two layers stack independently", function()
    local m = effects.elementMultiplier("Red",
        battler({ "Red", "Red", "Red" }), battler({ "Green", "Green" }), session)
    approx(m, (1 + bonus(0.5, 0.7, 2)) * (1 + bonus(0.15, 0.8, 6)), "both layers")
end)

test("an off-element skill still carries the wielder's own relation separately", function()
    -- Imp (Red) using a Green tome against Blue: the tome is strong, and Imp's
    -- own Red is weak to Blue. The channels multiply after each resolves itself.
    local m = effects.elementMultiplier("Green",
        battler({ "Red" }), battler({ "Blue" }), session)
    approx(m, (1 + bonus(0.5, 0.7, 1)) * 0.9, "Green tome in Red hands")
end)

test("a neutral mixed caster does not dilute a favorable skill", function()
    -- RG is innately neutral into Blue, while a Green skill is favorable.
    -- Keeping the channels separate means the result is exactly the skill 1.5x.
    local m = effects.elementMultiplier("Green",
        battler({ "Red", "Green" }), battler({ "Blue" }), session)
    approx(m, 1.5, "neutral identity plus favorable skill")
end)

test("disadvantage remains multiplicative by uncancelled depth", function()
    local m = effects.elementMultiplier("Red", nil, battler({ "Blue", "Blue" }), session)
    approx(m, 0.65 ^ 2, "two weak matches")
    assert(m > 0, "multiplicative decay must stay positive")
end)

test("the weak floor turns deep mismatch into resistance, not immunity", function()
    local m = effects.elementMultiplier("Red", nil,
        battler({ "Blue", "Blue", "Blue" }), session)
    -- 0.65^3 = 0.2746, below the 0.3 floor.
    approx(m, 0.3, "floored")
end)

test("ELEMENT_CHANGE replaces the innate list", function()
    local sword = { traits = { { code = "ELEMENT_CHANGE", dataId = "Red" } } }
    local wielder = battler({ "Blue" }, { sword })
    -- Innate Blue would be weak into Green; the sword makes it Red, which is strong.
    local m = effects.elementMultiplier(nil, wielder, battler({ "Green" }), session)
    approx(m, 1 + bonus(0.15, 0.8, 1), "sword overrode Blue with Red")
end)

test("ELEMENT_ADD appends instead of replacing, deepening alignment", function()
    local charm = { traits = { { code = "ELEMENT_ADD", dataId = "Red" } } }
    local wielder = battler({ "Red" }, { charm })
    local m = effects.elementMultiplier(nil, wielder, battler({ "Green" }), session)
    approx(m, 1 + bonus(0.15, 0.8, 2), "Red charm on a Red creature reads as Red x2")
end)

test("ELEMENT_ADD stacks on top of ELEMENT_CHANGE", function()
    local sword = { traits = { { code = "ELEMENT_CHANGE", dataId = "Red" } } }
    local charm = { traits = { { code = "ELEMENT_ADD", dataId = "Red" } } }
    local wielder = battler({ "Blue", "Blue" }, { sword, charm })
    -- innate Blue x2 discarded by CHANGE, then ADD appends: Red, Red.
    local m = effects.elementMultiplier(nil, wielder, battler({ "Green" }), session)
    approx(m, 1 + bonus(0.15, 0.8, 2), "CHANGE then ADD")
end)

test("White and Black hit each other both ways", function()
    local w = effects.elementMultiplier("White", nil, battler({ "Black" }), session)
    local b = effects.elementMultiplier("Black", nil, battler({ "White" }), session)
    approx(w, 1.5, "White into Black")
    approx(b, 1.5, "Black into White")
end)

test("ELEMENT_RATE remains an explicit separate modifier layer", function()
    local ward = { traits = { { code = "ELEMENT_RATE", dataId = "Red", value = 0.5 } } }
    local m = effects.elementMultiplier("Red", nil, battler({ "Green" }, { ward }), session)
    approx(m, 1.5 * 0.5, "Red affinity then explicit target rate")
end)

test("rates are read from elementRules, not hardcoded", function()
    local tweaked = {
        loader = {
            elements = ELEMENTS,
            engine = { elementRules = { skillStrongBonus = 2.0, skillStrongDecay = 0 } },
            getPassive = function() return nil end,
            getState = function() return nil end,
        }
    }
    local m = effects.elementMultiplier("Red", nil, battler({ "Green" }), tweaked)
    approx(m, 3.0, "tuning must come from data")
end)

print(string.format("=== Element Affinity Tests Completed: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    os.exit(1)
end
