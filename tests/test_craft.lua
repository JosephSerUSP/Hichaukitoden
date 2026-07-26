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

local craft = require("engine.craft")

local passed, failed = 0, 0
local function test(name, fn)
    craft.reset()
    local ok, err = pcall(fn)
    if ok then
        print("  [PASS] " .. name); passed = passed + 1
    else
        print("  [FAIL] " .. name); print("         " .. tostring(err)); failed = failed + 1
    end
end
local function approx(a, b, why)
    assert(math.abs(a - b) < 1e-6,
        string.format("%s: expected %.6f, got %.6f", why or "mismatch", b, a))
end

print("=== Testing engine.craft (Item Creation) ===")

-- Mirrors data/: the five true elements, four disciplines, and the registry
-- tables crafting reads its element contributions from.
local ELEMENTS = {
    Red   = { strongAgainst = { "Green" }, weakAgainst = { "Blue" } },
    Green = { strongAgainst = { "Blue" },  weakAgainst = { "Red" } },
    Blue  = { strongAgainst = { "Red" },   weakAgainst = { "Green" } },
    White = { strongAgainst = { "Black" }, weakAgainst = {} },
    Black = { strongAgainst = { "White" }, weakAgainst = {} },
}

local ENGINE = {
    disciplines = {
        { kind = "blacksmithing", stat = "atk" },
        { kind = "tinkering",     stat = "mdf" },
        { kind = "alchemy",       stat = "mat" },
        { kind = "cooking",       stat = "maxHp" },
    },
    elementRules = { skillStrongBonus = 0.5, skillWeakMultiplier = 0.65 },
    disciplineDefaults = {
        byEquipType = { Weapon = "blacksmithing", Armor = "blacksmithing", Accessory = "tinkering" },
        byEffect = { mp_heal = "cooking" },
        byType = { consumable = "alchemy" },
    },
    intensityGrades = {
        { grade = "mundane", mult = 0.5 }, { grade = "normal", mult = 1.0 },
        { grade = "precious", mult = 2.0 }, { grade = "legendary", mult = 3.0 },
    },
    craftElementSources = {
        elementChangeWeight = 3.0, paramWeight = 0.7, nameWeight = 2.0, descriptionWeight = 0.5,
        effects = { hp = { Green = 1.0 }, mp_heal = { Red = 0.5 }, xp = { White = 1.0 } },
        traits = { ON_PERMADEATH = { White = 1.4 } },
        params = { atk = { Red = 1.0 }, mdf = { White = 0.5 } },
    },
    craftLexicon = { ember = "Red", obsidian = "Black", wind = "Green", philosopher = "Red" },
    craftRules = {
        crafterPull = 0.30, alpha = 0.50, intensityWeight = 0.70,
        scatter = 0.24, scatterFalloff = 1.2,
        reachBase = 14.0, reachPerStat = 14.0, beyondReachCost = 0.12,
        foreignIngredientWorth = 0.20, statDivisor = 20.0,
        intensityScale = 40.0, crafterIntensityScale = 10.0, coherenceRange = 1.2,
    },
}

local ITEMS = {
    { id = 1, name = "Ember Root",  type = "junk",       cost = 5,   meta = { disciplines = { "alchemy" } } },
    { id = 2, name = "Iron Sliver", type = "equipment",  equipType = "Weapon", cost = 100 },
    { id = 3, name = "Plain Broth", type = "consumable", cost = 10, effects = { { type = "mp_heal", value = 1 } } },
    { id = 4, name = "Wind Charm",  type = "equipment",  equipType = "Accessory", cost = 30 },
    { id = 5, name = "Sealed Relic", type = "equipment", equipType = "Accessory", cost = 900,
      meta = { craftable = false } },
    { id = 6, name = "Obsidian Chip", type = "junk", cost = 15,
      meta = { disciplines = { "blacksmithing" }, intensityGrade = "precious" } },
}

local session = {
    loader = {
        elements = ELEMENTS, engine = ENGINE, items = ITEMS,
        getElement = function(id) return ELEMENTS[id] end,
        getPassive = function() return nil end,
        getState = function() return nil end,
    }
}
local loader = session.loader

local function crafter(discipline, elements, params)
    return {
        actorData = { discipline = discipline, elements = elements, baseParams = params },
        level = 1, passives = {}, equipment = {}, states = {}, paramPlus = {}
    }
end

-- ------------------------------------------------------------- signatures --

test("element is read off the name lexicon", function()
    local sig = craft.signature(ITEMS[1], loader)
    assert(sig.el.Red == 2.0, "ember should contribute Red at the name weight")
    approx(sig.hy, 1.0, "pure Red points straight up the hue plane")
end)

test("intensity comes from price, log-scaled", function()
    approx(craft.signature(ITEMS[2], loader).intensity, 20.043213, "100g")
    approx(craft.signature(ITEMS[3], loader).intensity, 10.413927, "10g")
end)

test("an intensity grade multiplies the price-derived value", function()
    local plain = 10 * math.log(15 + 1, 10)
    approx(craft.signature(ITEMS[6], loader).intensity, plain * 2.0, "precious doubles")
end)

test("non-elemental items sit at the origin", function()
    local sig = craft.signature(ITEMS[2], loader)
    approx(sig.hx, 0, "hx"); approx(sig.hy, 0, "hy"); approx(sig.val, 0, "val")
end)

test("mix, not depth, decides direction", function()
    local one = { Red = 1 }
    local three = { Red = 3 }
    local ax, ay = craft.elemVec(one)
    local bx, by = craft.elemVec(three)
    approx(ax, bx, "hx"); approx(ay, by, "hy")
end)

test("White and Black cancel to non-elemental", function()
    local hx, hy, val = craft.elemVec({ White = 1, Black = 1 })
    approx(hx, 0, "hx"); approx(hy, 0, "hy"); approx(val, 0, "true opposites annihilate")
end)

-- ------------------------------------------------------------- membership --

test("membership defaults from what the item plainly is", function()
    assert(craft.disciplinesOf(ITEMS[2], loader)[1] == "blacksmithing", "Weapon")
    assert(craft.disciplinesOf(ITEMS[4], loader)[1] == "tinkering", "Accessory")
    assert(craft.disciplinesOf(ITEMS[3], loader)[1] == "cooking", "consumable with mp_heal")
end)

test("authored membership overrides the default", function()
    local ds = craft.disciplinesOf(ITEMS[1], loader)
    assert(#ds == 1 and ds[1] == "alchemy", "junk has no type signal, so it is authored")
end)

test("craftable=false keeps an item out of every pool", function()
    for _, kind in ipairs({ "blacksmithing", "tinkering", "alchemy", "cooking" }) do
        for _, it in ipairs(craft.pool(kind, loader)) do
            assert(it.name ~= "Sealed Relic", "opted-out item appeared in " .. kind)
        end
    end
end)

test("a discipline pool contains only what it can produce", function()
    local names = {}
    for _, it in ipairs(craft.pool("cooking", loader)) do names[it.name] = true end
    assert(names["Plain Broth"], "cooking should produce broth")
    assert(not names["Iron Sliver"], "cooking must never produce a weapon")
end)

-- ---------------------------------------------------------------- crafter --

test("the crafter pull uses innate elements only", function()
    local c = crafter("alchemy", { "Red" }, { mat = 20 })
    -- equipment carrying ELEMENT_CHANGE must not redirect a crafter
    c.equipment = { { traits = { { code = "ELEMENT_CHANGE", dataId = "Blue" } } } }
    local hx, hy = craft.crafterVec(c)
    approx(hy, 1.0, "still Red despite the Blue trinket")
    approx(hx, 0, "hx")
end)

test("reach grows with the discipline stat", function()
    local weak = craft.reach(crafter("alchemy", {}, { mat = 4 }), session)
    local strong = craft.reach(crafter("alchemy", {}, { mat = 40 }), session)
    assert(strong > weak, "a better crafter reaches further")
end)

-- --------------------------------------------------------------- ideation --

test("a foreign ingredient steers but does not empower", function()
    local cook = crafter("cooking", {}, { maxHp = 20 })
    -- Iron Sliver (blacksmithing, 100g) is foreign to cooking
    local native = craft.ideate(ITEMS[3], ITEMS[3], cook, session, nil)
    local foreign = craft.ideate(ITEMS[3], ITEMS[2], cook, session, nil)
    assert(foreign.intensity < native.intensity + 1,
        "iron in a stockpot must not lift the mix the way a native ingredient would")
    assert(foreign.nativeB == false, "iron is not native to cooking")
end)

test("the same ingredients in different hands land in different places", function()
    local red = crafter("alchemy", { "Red" }, { mat = 20 })
    local white = crafter("alchemy", { "White" }, { mat = 20 })
    local a = craft.ideate(ITEMS[1], ITEMS[3], red, session, nil)
    local b = craft.ideate(ITEMS[1], ITEMS[3], white, session, nil)
    assert(math.abs(a.val - b.val) > 0.1 or math.abs(a.hy - b.hy) > 0.1,
        "the crafter is the third vertex, so identity must move the point")
end)

test("ideation is deterministic without an rng, and scattered with one", function()
    local c = crafter("alchemy", { "Red" }, { mat = 20 })
    local a = craft.ideate(ITEMS[1], ITEMS[3], c, session, nil)
    local b = craft.ideate(ITEMS[1], ITEMS[3], c, session, nil)
    approx(a.hx, b.hx, "hx"); approx(a.intensity, b.intensity, "intensity")

    local n, moved = 0, 0
    local rng = function() n = n + 1; return (n * 0.37) % 1 end
    local s = craft.ideate(ITEMS[1], ITEMS[3], c, session, rng)
    if math.abs(s.hx - a.hx) > 1e-9 or math.abs(s.intensity - a.intensity) > 1e-9 then
        moved = 1
    end
    assert(moved == 1, "an rng must displace the point")
end)

test("scatter shrinks as the discipline stat grows", function()
    local function spread(stat)
        local c = crafter("alchemy", { "Red" }, { mat = stat })
        local base = craft.ideate(ITEMS[1], ITEMS[3], c, session, nil)
        local n = 0
        local rng = function() n = n + 1; return (n * 0.37) % 1 end
        local s = craft.ideate(ITEMS[1], ITEMS[3], c, session, rng)
        return math.abs(s.hx - base.hx)
    end
    assert(spread(60) < spread(4), "a master's hand wanders less than a novice's")
end)

-- ------------------------------------------------------------- resolution --

test("resolution ranks the neighbourhood nearest first", function()
    local c = crafter("cooking", {}, { maxHp = 20 })
    local point = craft.ideate(ITEMS[3], ITEMS[3], c, session, nil)
    local ranked = craft.resolve(point, c, session)
    assert(#ranked > 0, "cooking must have candidates")
    for i = 2, #ranked do
        assert(ranked[i-1].distance <= ranked[i].distance, "not sorted at " .. i)
    end
    assert(ranked[1].item.name == "Plain Broth", "two broths should make broth")
end)

test("beyond-reach costs distance but is never forbidden", function()
    local near = crafter("blacksmithing", {}, { atk = 60 })
    local far = crafter("blacksmithing", {}, { atk = 2 })
    local point = { hx = 0, hy = 0, val = 0, intensity = 20, kind = "blacksmithing" }
    local d1 = craft.distance(point, ITEMS[2], craft.reach(near, session), loader)
    local d2 = craft.distance(point, ITEMS[2], craft.reach(far, session), loader)
    assert(d2 > d1, "a weak crafter is further from a valuable outcome")
    assert(d2 < math.huge, "but it is a falloff, not a wall")
end)

test("coherence is 1 dead on and 0 nowhere near", function()
    approx(craft.coherence(0, loader), 1.0, "dead on")
    approx(craft.coherence(99, loader), 0.0, "nowhere near")
    assert(craft.coherence(0.6, loader) > 0 and craft.coherence(0.6, loader) < 1, "banded between")
end)

print(string.format("=== Craft Tests Completed: %d passed, %d failed ===", passed, failed))
if failed > 0 then os.exit(1) end
