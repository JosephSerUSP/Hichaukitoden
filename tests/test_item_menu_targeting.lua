package.path = package.path .. ";../?.lua;?.lua"

if not _G.love then
    _G.love = {
        filesystem = {
            getInfo = function() return false end,
            read = function() return "{}" end
        }
    }
end

local session = require("engine.session")
local loader = require("data.loader")
local targeting = require("engine.targeting")
local usability = require("engine.usability")
local interpreter = require("engine.interpreter")

loader.init()

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

print("=== Testing Item Menu Targeting, Usability & Effect Feedback ===")

test("targeting.expand handles 'none' spec", function()
    local exp = targeting.expand("none")
    assert(exp.side == "none", "side should be none")
    assert(exp.count == 0, "count should be 0")
end)

test("canUseItem validates no-target items (Mystic Egg, MP drinks)", function()
    local sess = session.GameSession.new(loader)
    sess.mp = sess.maxMp -- MP full

    local mpItem = loader.getItem(29) -- Mug of Ale
    assert(mpItem, "Mug of Ale item should exist")
    assert(mpItem.target == "none", "Mug of Ale target should be none")

    local ok, reason = usability.canUseItem(mpItem, nil, { session = sess, isField = true })
    assert(not ok, "Should not be usable when MP is full")
    assert(reason == "MP is already full", "Reason mismatch: " .. tostring(reason))

    sess.mp = 0
    local ok2, _ = usability.canUseItem(mpItem, nil, { session = sess, isField = true })
    assert(ok2, "Should be usable when MP is not full")
end)

test("USE_ITEM command handles target: 'none' items without single-target selection (recruits exactly 1 with random name)", function()
    local sess = session.GameSession.new(loader)
    sess:addItem(11, 1) -- Mystic Egg (id 11)
    local hero = session.Battler.new(loader.getActor(1), 1)
    sess.party = { hero, session.Battler.new(loader.getActor(2), 1) }

    local ctx = {
        session = sess,
        loader = loader,
        v = { tab = 1, state = 1, idx = 1, _guard = 0 }
    }

    interpreter.runImmediate({ { cmd = "USE_ITEM", itemIndex = 1, target = 0 } }, ctx)

    assert(ctx.v.lastItemResult and ctx.v.lastItemResult.success == true, "USE_ITEM should succeed")
    assert(ctx.v.state == 3, "State should transition to 3 (popup)")
    assert(ctx.v.popupText:find("joins you"), "Popup text should mention recruitment feedback")
    assert((sess.inventory[11] or 0) == 0, "Item should be consumed")
    assert(#sess.party == 3, "Party count should increase from 2 to 3 (recruiting exactly 1 creature, not 4)")

    local eggBattler = sess.party[3]
    assert(eggBattler and eggBattler.actorData.id == 15, "Recruited creature should be Egg actor (id 15)")
    local namesSet = {}
    for _, n in ipairs(eggBattler.actorData.names or {}) do namesSet[n] = true end
    assert(namesSet[eggBattler.name] == true, "Recruited Egg should receive a random name from names list, got: " .. tostring(eggBattler.name))
end)

test("USE_ITEM single-target item enters state 2 when usable", function()
    local sess = session.GameSession.new(loader)
    sess:addItem(1, 1) -- HP Tonic (id 1)
    local hero = session.Battler.new({ id = "hero", name = "Hero", hp = 10, maxHp = 50, level = 1 }, 1)
    hero.hp = 10
    sess.party = { hero }

    local ctx = {
        session = sess,
        loader = loader,
        v = { tab = 1, state = 1, idx = 1, _guard = 0 }
    }

    interpreter.runImmediate({ { cmd = "USE_ITEM", itemIndex = 1, target = 0 } }, ctx)

    assert(ctx.v.state == 2, "State should transition to 2 (target selection)")
    assert(ctx.v.targetIdx == 1, "Target index should default to 1")
    assert((sess.inventory[1] or 0) == 1, "Item should NOT be consumed before target pick")
end)

test("Detailed effect feedback for stat-up and skill learning", function()
    local sess = session.GameSession.new(loader)
    sess:addItem(45, 1) -- Tome: Wind Blade
    sess:addItem(46, 1) -- Whetstone Draught
    local hero = session.Battler.new({ id = "hero", name = "Hero", hp = 50, maxHp = 50, atk = 10, level = 1 }, 1)
    sess.party = { hero }

    -- Test Tome: Wind Blade (learn_skill)
    local ctx = {
        session = sess,
        loader = loader,
        v = { tab = 1, state = 2, idx = 1, targetIdx = 1, _guard = 0 }
    }

    interpreter.runImmediate({ { cmd = "USE_ITEM", itemIndex = 1, target = 1 } }, ctx)
    assert(ctx.v.lastItemResult.success == true, "Learn skill item should succeed")
    assert(ctx.v.popupText:find("Hero learns Wind Blade"), "Feedback text should include skill name: " .. tostring(ctx.v.popupText))

    -- Test Whetstone Draught (param_plus ATK)
    ctx.v.state = 1
    ctx.v.idx = 1
    interpreter.runImmediate({ { cmd = "USE_ITEM", itemIndex = 1, target = 1 } }, ctx)
    assert(ctx.v.lastItemResult.success == true, "Param plus item should succeed")
    assert(ctx.v.popupText:find("ATK rises by 2"), "Feedback text should include stat boost details: " .. tostring(ctx.v.popupText))
end)

print("=== Item Menu Tests Completed: " .. passed .. " passed, " .. failed .. " failed ===")
assert(failed == 0, "Some item menu unit tests failed!")
