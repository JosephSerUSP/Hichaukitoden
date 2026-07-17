package.path = package.path .. ";../?.lua;?.lua"

-- Mock love for config
_G.love = {
    filesystem = {
        getInfo = function() return false end,
        read = function() return "{}" end
    }
}

local exploration = require("engine.exploration")
local config = require("engine.config")

-- Mock config dungeon values
config.dungeon = {
    genWidth = 21,
    genHeight = 21,
    genMinRooms = 4,
    genMaxRooms = 6,
    genMinRoomSize = 3,
    genMaxRoomSize = 5,
    exitScriptId = 1,
    exitSprite = "assets/sprites/NPC00.png"
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

print("=== Testing exploration.generateDungeon ===")

test("Dungeon is deterministic with seed", function()
    local mapData = {}
    local grid1, startX1, startY1, events1 = exploration.generateDungeon(mapData, 12345)
    local grid2, startX2, startY2, events2 = exploration.generateDungeon(mapData, 12345)

    assert(startX1 == startX2, "StartX should be equal")
    assert(startY1 == startY2, "StartY should be equal")
    assert(#events1 == #events2, "Number of events should be equal")
    for y = 1, #grid1 do
        for x = 1, #grid1[y] do
            assert(grid1[y][x] == grid2[y][x], "Grid at " .. x .. ", " .. y .. " should be equal")
        end
    end
end)

test("Respects mapData bounds", function()
    local mapData = { width = 15, height = 15 }
    local grid, startX, startY, events = exploration.generateDungeon(mapData, 123)

    assert(#grid == 15, "Grid height should be 15")
    assert(#grid[1] == 15, "Grid width should be 15")
end)

test("Uses config fallback bounds", function()
    local mapData = {}
    local grid, startX, startY, events = exploration.generateDungeon(mapData, 123)

    assert(#grid == 21, "Grid height should use config default (21)")
    assert(#grid[1] == 21, "Grid width should use config default (21)")
end)

test("Generates the exit event (ID 99)", function()
    local mapData = {}
    local grid, startX, startY, events = exploration.generateDungeon(mapData, 123)

    local foundExit = false
    for _, ev in ipairs(events) do
        if ev.id == 99 then
            foundExit = true
            assert(ev.scriptId == config.dungeon.exitScriptId, "Exit event should have the correct scriptId")
            assert(ev.sprite == config.dungeon.exitSprite, "Exit event should have the correct sprite")
            assert(ev.trigger == "interact", "Exit event should be trigger=interact")
            -- Verify it's in bounds (coords are 0-indexed in generated events, so bounds are 0 to width-1)
            assert(ev.x >= 0 and ev.x < 21, "Exit event X out of bounds")
            assert(ev.y >= 0 and ev.y < 21, "Exit event Y out of bounds")
        end
    end
    assert(foundExit, "Should generate an exit event")
end)

test("Places fixed and random custom events", function()
    local mapData = {
        events = {
            { id = 10, spawn = "Fixed", x = 5, y = 5, scriptId = 2, trigger = "step" },
            { id = 11, spawn = "Random", scriptId = 3 }
        }
    }
    local grid, startX, startY, events = exploration.generateDungeon(mapData, 123)

    local foundFixed = false
    local foundRandom = false

    for _, ev in ipairs(events) do
        if ev.id == 10 then
            foundFixed = true
            assert(ev.x == 5 and ev.y == 5, "Fixed event should be at 5,5")
            assert(ev.scriptId == 2, "Fixed event scriptId mismatch")
            assert(ev.trigger == "step", "Fixed event trigger mismatch")
        elseif ev.id == 11 then
            foundRandom = true
            assert(ev.scriptId == 3, "Random event scriptId mismatch")
            assert(ev.trigger == "interact", "Random event should default to interact trigger")
            assert(ev.x >= 0 and ev.y >= 0, "Random event should have valid coordinates")
        end
    end

    assert(foundFixed, "Fixed event not found")
    assert(foundRandom, "Random event not found")
end)

test("Start point is an open tile", function()
    local mapData = {}
    local grid, startX, startY, events = exploration.generateDungeon(mapData, 123)

    assert(grid[startY][startX] == ".", "Start point should be an open floor")
end)

print(string.format("=== Tests completed: %d passed, %d failed ===", passed, failed))

if failed > 0 then
    os.exit(1)
end
