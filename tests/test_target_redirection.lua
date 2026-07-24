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

local battle = require("engine.battle")
local session = require("engine.session")
local loader = require("data.loader")
local savegame = require("engine.savegame")

-- Mock loader data
loader.terms = {
    battle = {
        target_dead = "{0}'s target is already dead!"
    }
}

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

print("=== Testing Target Redirection & Target Dead Feedback ===")

test("Target dead with autoRedirect disabled emits feedback message", function()
    local sess = session.GameSession.new(loader)
    sess.autoRedirect = false

    local hero = session.Battler.new({ id = "hero", name = "Hero", hp = 100, level = 1 }, 1)
    hero.hp = 100
    sess.party = { hero }

    local enemy1 = session.Battler.new({ id = "e1", name = "Goblin A", hp = 0, level = 1 }, 1)
    enemy1.hp = 0
    enemy1:addState("dead")
    local enemy2 = session.Battler.new({ id = "e2", name = "Goblin B", hp = 50, level = 1 }, 1)
    enemy2.hp = 50

    local b = battle.Battle.new(sess, { enemy1, enemy2 })

    local actions = {
        [1] = { type = "attack", target = enemy1 }
    }

    local roundEvents = b:resolveRound(actions)

    local foundMsg = false
    for _, ev in ipairs(roundEvents) do
        if ev.type == "text" and ev.text == "Hero's target is already dead!" then
            foundMsg = true
            break
        end
    end

    assert(foundMsg, "Expected 'Hero's target is already dead!' text event in roundEvents")
end)

test("Target dead with autoRedirect enabled redirects to living target", function()
    local sess = session.GameSession.new(loader)
    sess.autoRedirect = true

    local hero = session.Battler.new({ id = "hero", name = "Hero", hp = 100, level = 1 }, 1)
    hero.hp = 100
    sess.party = { hero }

    local enemy1 = session.Battler.new({ id = "e1", name = "Goblin A", hp = 0, level = 1 }, 1)
    enemy1.hp = 0
    enemy1:addState("dead")
    local enemy2 = session.Battler.new({ id = "e2", name = "Goblin B", hp = 50, level = 1 }, 1)
    enemy2.hp = 50

    local b = battle.Battle.new(sess, { enemy1, enemy2 })

    local actions = {
        [1] = { type = "attack", target = enemy1 }
    }

    local roundEvents = b:resolveRound(actions)

    local redirected = false
    for _, ev in ipairs(roundEvents) do
        if ev.type == "action" and ev.target == enemy2 then
            redirected = true
            break
        end
    end

    assert(redirected, "Expected action target to be redirected to Goblin B")
end)

test("Target dead with autoRedirect enabled but no living targets emits feedback message", function()
    local sess = session.GameSession.new(loader)
    sess.autoRedirect = true

    local hero = session.Battler.new({ id = "hero", name = "Hero", hp = 100, level = 1 }, 1)
    hero.hp = 100
    sess.party = { hero }

    local enemy1 = session.Battler.new({ id = "e1", name = "Goblin A", hp = 0, level = 1 }, 1)
    enemy1.hp = 0
    enemy1:addState("dead")
    local enemy2 = session.Battler.new({ id = "e2", name = "Goblin B", hp = 0, level = 1 }, 1)
    enemy2.hp = 0
    enemy2:addState("dead")

    local b = battle.Battle.new(sess, { enemy1, enemy2 })

    -- Mock isVictory to return false for this test step so turn execution runs
    b.isVictory = function() return false end

    local actions = {
        [1] = { type = "attack", target = enemy1 }
    }

    local roundEvents = b:resolveRound(actions)

    local foundMsg = false
    for _, ev in ipairs(roundEvents) do
        if ev.type == "text" and ev.text == "Hero's target is already dead!" then
            foundMsg = true
            break
        end
    end

    assert(foundMsg, "Expected fallback feedback message when all targets are dead")
end)

test("Savegame serialization preserves autoRedirect option", function()
    local sess = session.GameSession.new(loader)
    sess.autoRedirect = true

    local data = savegame.serialize(sess, loader, "town")
    assert(data.autoRedirect == true, "Serialized data should contain autoRedirect = true")

    local restored = savegame.deserialize(data, loader)
    assert(restored.autoRedirect == true, "Deserialized session should restore autoRedirect = true")
end)

test("Item usage on dead target with autoRedirect disabled emits feedback message", function()
    local sess = session.GameSession.new(loader)
    sess.autoRedirect = false

    local hero = session.Battler.new({ id = "hero", name = "Hero", hp = 100, level = 1 }, 1)
    hero.hp = 100
    sess.party = { hero }

    local enemy1 = session.Battler.new({ id = "e1", name = "Goblin A", hp = 0, level = 1 }, 1)
    enemy1.hp = 0
    enemy1:addState("dead")
    local enemy2 = session.Battler.new({ id = "e2", name = "Goblin B", hp = 50, level = 1 }, 1)
    enemy2.hp = 50

    local b = battle.Battle.new(sess, { enemy1, enemy2 })

    local itemObj = { id = 1, name = "Bomb", target = "enemy" }
    local actions = {
        [1] = { type = "item", item = itemObj, target = enemy1 }
    }

    local roundEvents = b:resolveRound(actions)

    local foundMsg = false
    for _, ev in ipairs(roundEvents) do
        if ev.type == "text" and ev.text == "Hero's target is already dead!" then
            foundMsg = true
            break
        end
    end

    assert(foundMsg, "Expected item target dead feedback message")
end)

print(string.format("=== Tests completed: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    os.exit(1)
end
