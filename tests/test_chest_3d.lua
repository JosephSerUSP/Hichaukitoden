local viewport_3d = require("presentation.viewport_3d")
local world_focus = require("presentation.world_focus")
local session = require("engine.session")
local exploration = require("engine.exploration")
local interpreter = require("engine.interpreter")
local savegame = require("engine.savegame")
local validator = require("engine.validator")
local loader = require("data.loader")

print("=== TEST CHEST 3D ===")
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

-- 1. Camera Pitch & Unified CPU Camera-Space Depth Helper
local d0 = viewport_3d.cameraSpaceDepth(10, 5, 0, 5, 5, 0.5, 1, 0, 0)
check(math.abs(d0 - 5.0) < 1e-5, "cameraSpaceDepth neutral pitch")

local pitchRad = math.rad(25)
local dPitched = viewport_3d.cameraSpaceDepth(10, 5, 0, 5, 5, 0.5, 1, 0, pitchRad)
local expectedPitched = 5.0 * math.cos(pitchRad) - (-0.5) * math.sin(pitchRad)
check(math.abs(dPitched - expectedPitched) < 1e-5, "cameraSpaceDepth pitched depth calculation")

-- Screen-space horizon & low object direction verification:
-- Positive pitch (looking down) shifts horizon geometry and low floor objects UPWARD on screen.
local horizPitchedPos = 0.0 * math.cos(pitchRad) + 5.0 * math.sin(pitchRad) -- > 0 (moved UP on screen)
local horizPitchedNeg = 0.0 * math.cos(-pitchRad) + 5.0 * math.sin(-pitchRad) -- < 0 (moved DOWN on screen)
check(horizPitchedPos > 0, "Positive pitch shifts horizon upward")
check(horizPitchedNeg < 0, "Negative pitch shifts horizon downward")

-- 2. Presentation Resolution (3-State Map/Page & Common Event Canonical Absence)
local mockLoader = {
    commonEvents = {
        ["12"] = {
            id = 12,
            name = "Chest",
            model = "assets/models/dungeon/dungeon_chest.obj",
            interactionFocus = { kind = "low_prop" },
            sprite = "assets/sprites/OBJ_TreasureChest_001.png"
        }
    }
}
local mockSession = { loader = mockLoader }

-- Base event inherits from CE
local baseEv = { scriptId = 12 }
local pres1 = viewport_3d.resolveEventPresentation(baseEv, mockSession)
check(pres1.visual == "model", "Base event resolves model from CE")
check(pres1.model == "assets/models/dungeon/dungeon_chest.obj", "Model path resolves correctly")
check(pres1.interactionFocus and pres1.interactionFocus.kind == "low_prop", "Focus preset resolves correctly")

-- Page overrides model with false (suppressed) -> falls back to sprite
local evWithPage = {
    scriptId = 12,
    pages = {
        { model = false, sprite = "assets/sprites/OBJ_TreasureChest_001.png" }
    }
}
local pres2 = viewport_3d.resolveEventPresentation(evWithPage, mockSession)
check(pres2.visual == "sprite", "Page suppressing model falls back to sprite")

-- 3. collectEventModelPlacements(session) Helper
local testMap = {
    id = "test_map_3d",
    events = {
        { id = 1, x = 3, y = 4, scriptId = 12 },
        { id = 2, x = 5, y = 6, sprite = "assets/sprites/OBJ_TreasureChest_001.png" }
    }
}
mockSession.currentMapData = testMap
local placements = viewport_3d.collectEventModelPlacements(mockSession)
check(#placements == 1, "collectEventModelPlacements returns 1 model placement")
check(placements[1].x == 4.5 and placements[1].y == 5.5, "Model placement cell center coordinates correct")
check(placements[1].model == "assets/models/dungeon/dungeon_chest.obj", "Model placement model path matches")

-- 4. Fail-Loud Focus Error Propagation & State Reset in world_focus
local okUnknown, errUnknown = pcall(function()
    world_focus.begin("non_existent_preset", { x = 1, y = 1 }, mockSession, nil)
end)
check(not okUnknown and string.find(tostring(errUnknown), "unknown focus preset"), "Unknown focus preset fails loud")

world_focus.begin({ kind = "low_prop" }, { x = 1, y = 1 }, mockSession, function()
    error("Simulated event failure inside focus callback", 0)
end)

local okUpdate, errUpdate = pcall(function()
    world_focus.update(0.3) -- triggers duration finish and fires callback
end)
check(not okUpdate and string.find(tostring(errUpdate), "Simulated event failure"), "Focus update re-throws callback error loud")
check(not world_focus.isActive(), "Focus state resets after callback error")

-- 5. Exact emptyCtx Assertion for CHANGE_ITEM random
local emptyMapSession = {
    currentMapData = { id = "empty_map", treasures = {} },
    loader = mockLoader
}
local emptyCtx = {
    session = emptyMapSession,
    loader = mockLoader,
    events = {}
}

local okRandom, errRandom = pcall(function()
    interpreter.runImmediate({ { cmd = "CHANGE_ITEM", item = "random", count = 1 } }, emptyCtx)
end)
check(not okRandom and string.find(tostring(errRandom), "missing or empty treasures array"), "CHANGE_ITEM random on empty treasures fails loud")

-- 6. Multi-Floor Save/Load Persistence Lifecycle Test
local s = session.GameSession.new(loader)
s:initializeStartingParty()
exploration.loadMap(s, 1) -- Load Floor 1

-- Find or insert chest event on Floor 1
local f1Events = s.currentMapData.events or {}
local chestEv = nil
for _, e in ipairs(f1Events) do
    if e.scriptId == 12 then chestEv = e break end
end
if not chestEv then
    chestEv = { id = 999, x = 2, y = 2, scriptId = 12 }
    table.insert(f1Events, chestEv)
    s.currentMapData.events = f1Events
end

-- Erase chest event on Floor 1 via ERASE_EVENT command
interpreter.runImmediate({ { cmd = "ERASE_EVENT" } }, { session = s, eventId = chestEv.id })

-- Transfer to Floor 2 (which saves Floor 1 state into s.mapStates[1])
exploration.loadMap(s, 2)
check(s.currentMapIndex == 2, "Session transferred to Floor 2")

-- Save session on Floor 2
savegame.save(s, loader, "map", "test_chest_save")

-- Load saved game
local rawSave = savegame.load("test_chest_save", loader)
check(rawSave ~= nil, "Saved game data exists")
local loadedSession, loadedScene = savegame.deserialize(rawSave, loader)
check(loadedSession.currentMapIndex == 2, "Loaded session starts on Floor 2")

-- Return to Floor 1 and assert chest remains erased
exploration.loadMap(loadedSession, 1)
local activeEventsF1 = loadedSession.currentMapData.events or {}
local foundChest = false
for _, e in ipairs(activeEventsF1) do
    if e.id == chestEv.id then foundChest = true break end
end
check(not foundChest, "Chest event remains erased on Floor 1 after save/load cycle")

-- Cleanup test save
savegame.delete("test_chest_save")

-- 7. Validator Regression Tests
local badLoader1 = {}
for k, v in pairs(loader) do badLoader1[k] = v end
badLoader1.maps = {
    {
        id = 1, name = "Bad Treasures Map",
        treasures = { [1] = "1", [3] = "2" }, -- Sparse array hole!
        events = {}
    }
}
local okVal1, errVal1 = pcall(function() validator.run(badLoader1) end)
check(not okVal1 and string.find(tostring(errVal1), "is sparse at index 2"), "Validator catches sparse treasures array")

local badLoader2 = {}
for k, v in pairs(loader) do badLoader2[k] = v end
badLoader2.maps = {
    {
        id = 1, name = "Missing Treasures Map",
        events = {
            { x = 1, y = 1, commands = { { cmd = "CHANGE_ITEM", item = "random" } } }
        }
    }
}
local okVal2, errVal2 = pcall(function() validator.run(badLoader2) end)
check(not okVal2 and string.find(tostring(errVal2), "missing or empty treasures array"), "Validator catches missing treasures array when random loot used")

require("tests.fail_fast")("test_chest_3d", failed, passed)
