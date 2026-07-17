package.path = package.path .. ";../?.lua;?.lua"

-- Mock love for config
_G.love = {
    filesystem = {
        getInfo = function() return false end,
        read = function() return "{}" end
    }
}

local battleSystem = require("engine.battle")

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

print("=== Testing engine.battle ===")

test("Battle.new initializes correctly", function()
    local mockSession = {
        getActiveParty = function()
            return {
                { name = "Ally 1" },
                { name = "Ally 2" },
                { name = "Ally 3" },
                { name = "Ally 4" }
            }
        end
    }

    local mockEnemies = {
        { name = "Enemy 1" },
        { name = "Enemy 2" }
    }

    local vBattle = battleSystem.Battle.new(mockSession, mockEnemies)

    assert(vBattle.session == mockSession, "Session not set correctly")
    assert(vBattle.enemies == mockEnemies, "Enemies not set correctly")
    assert(#vBattle.allies == 4, "Allies not set correctly")
    assert(vBattle.allies[1].name == "Ally 1", "Ally 1 mismatch")
    assert(vBattle.round == 1, "Round should start at 1")
    assert(type(vBattle.log) == "table", "Log should be an empty table")
    assert(#vBattle.log == 0, "Log should be empty")
end)

test("Battle.new handles empty party and empty enemies", function()
    local mockSession = {
        getActiveParty = function()
            return {}
        end
    }

    local mockEnemies = {}

    local vBattle = battleSystem.Battle.new(mockSession, mockEnemies)

    assert(vBattle.session == mockSession, "Session not set correctly")
    assert(vBattle.enemies == mockEnemies, "Enemies not set correctly")
    assert(#vBattle.allies == 0, "Allies not set correctly")
    assert(#vBattle.enemies == 0, "Enemies not set correctly")
    assert(vBattle.round == 1, "Round should start at 1")
    assert(type(vBattle.log) == "table", "Log should be an empty table")
    assert(#vBattle.log == 0, "Log should be empty")
end)

print(string.format("=== Tests completed: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    error("Tests failed")
end
