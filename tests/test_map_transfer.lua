-- Map transfer used to be two things: a hardcoded `TELEPORT` action in
-- main.lua that could only ever descend one floor, and a LOAD_MAP command that
-- was declared interactive without being compiled -- so in a map or common
-- event it produced no node and the event silently stopped. These tests pin
-- the single remaining path.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local exploration = require("engine.exploration")
local formula = require("engine.formula")
local savegame = require("engine.savegame")
local usability = require("engine.usability")

print("[TEST] Starting map transfer tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local portalItem = loader.getItem(197)
local safeUseSession = sessionModule.GameSession.new(loader)
safeUseSession.currentMapData = loader.maps[1]
check(not usability.canUseItem(portalItem, nil, { session = safeUseSession, isField = true }),
    "Town Portal is refused in town before it can be consumed")
safeUseSession.currentMapData = loader.maps[2]
check(usability.canUseItem(portalItem, nil, { session = safeUseSession, isField = true }),
    "Town Portal is usable inside the dungeon")

-- LOAD_MAP inside an event compiles to a real node. When it was listed in
-- INTERACTIVE_COMPILE_IDS with no branch, `nodes` came back empty here and the
-- Developer Room's exit tile went nowhere.
local nodes = {}
local first = interpreter.compileTop(nodes, { { cmd = "LOAD_MAP", mapId = 1 } },
    "t", "done", { loader = loader })
check(first ~= nil and nodes[first] ~= nil,
    "LOAD_MAP in an event compiles to a node instead of a dead end")
check(nodes[first] and nodes[first].action == "RUN_IMMEDIATE",
    "and it runs immediately, because a map transfer asks the player nothing")

-- Depth is read off the map, so every transfer keeps it true.
local sess = sessionModule.GameSession.new(loader)
sess:initializeStartingParty()

exploration.loadMap(sess, 2)
check(sess.dungeonFloor == 1, "entering Floor 1 puts the party at depth 1")
check(formula.sessionView(sess).floor == 1,
    "and the `floor` token reports it -- it used to always read 1")

exploration.loadMap(sess, 6)
check(sess.dungeonFloor == 5, "Floor 5 is depth 5")

-- The old counter only ever incremented, so walking back to town left the
-- party "deep" for enemy levels and recruitment.
exploration.loadMap(sess, 1)
check(sess.dungeonFloor == 0, "returning to Town puts the party back at depth 0")

-- Descending from Floor 5 reached Floor 5 again under the old maxFloor=5 clamp,
-- which made the deepest authored map unreachable.
local function descend(fromMapId)
    local s = sessionModule.GameSession.new(loader)
    s:initializeStartingParty()
    exploration.loadMap(s, fromMapId)
    local ctx = { session = s, loader = loader, events = {}, party = s.party }
    interpreter.runImmediate({ { cmd = "LOAD_MAP", mapId = "session.floor + 2" } }, ctx)
    return s
end
check(descend(2).currentMapIndex == 3, "the stairs on Floor 1 lead to Floor 2")
local sanctum = descend(6)
check(sanctum.currentMapIndex == 7 and sanctum.dungeonFloor == 6,
    "and the stairs on Floor 5 reach the Sanctum, which the old clamp hid")

-- A generated floor is one place for the life of the expedition. Descending
-- away and climbing back must restore its geometry, fog, events, and landmark
-- positions rather than rolling a replacement.
local route = sessionModule.GameSession.new(loader)
route:initializeStartingParty()
exploration.loadMap(route, 2, { arrival = "entrance" })
local originalGrid = route.mapGrid
local originalEvents = route.currentMapData.events
local entranceX, entranceY = route.currentMapData.entranceX, route.currentMapData.entranceY
local exitX, exitY = route.currentMapData.exitX, route.currentMapData.exitY
route.visitedGrid[2][2] = true
exploration.loadMap(route, 3, { arrival = "entrance" })
exploration.loadMap(route, 2, { arrival = "exit" })
check(route.mapGrid == originalGrid and route.currentMapData.events == originalEvents,
    "climbing back restores the exact generated floor instead of regenerating it")
check(route.visitedGrid[2][2] == true,
    "restored floors retain their fog-of-war history")
check(route.currentMapData.entranceX == entranceX and route.currentMapData.entranceY == entranceY
    and route.currentMapData.exitX == exitX and route.currentMapData.exitY == exitY,
    "restored floors retain both staircase landmarks")
check(math.abs(route.playerX - exitX) + math.abs(route.playerY - exitY) == 1,
    "climbing up arrives beside the previous floor's exit")

local hasEntrance = false
for _, ev in ipairs(route.currentMapData.events or {}) do
    if ev.scriptId == 40 then hasEntrance = true end
end
check(hasEntrance, "every generated floor has physical stairs back up")

-- A Town Portal is temporary travel, not a new expedition or a regenerated
-- floor. Returning through it restores the exact tile and facing.
route.playerX, route.playerY, route.playerDir = 7, 8, "W"
local expeditionCount = route.party[1].history.expeditions
local portalCtx = { session = route, loader = loader, events = {}, party = route.party }
interpreter.runImmediate({ { cmd = "PORTAL_TO_TOWN" } }, portalCtx)
check(route.currentMapIndex == 1 and route.portalReturn ~= nil and route.flags.portal_open == true,
    "PORTAL_TO_TOWN opens a resumable route and moves the party to safety")
interpreter.runImmediate({ { cmd = "RETURN_TO_PORTAL" } }, portalCtx)
check(route.currentMapIndex == 2 and route.playerX == 7 and route.playerY == 8 and route.playerDir == "W",
    "RETURN_TO_PORTAL restores the exact dungeon tile and facing")
check(route.party[1].history.expeditions == expeditionCount,
    "temporary portal travel does not count as a new expedition")
check(route.portalReturn == nil and route.flags.portal_open == nil,
    "the return trip closes the temporary portal")

local completedRoute = route.mapGrid
exploration.loadMap(route, 1)
exploration.loadMap(route, 2, { arrival = "entrance" })
check(route.mapGrid ~= completedRoute,
    "a new expedition receives a fresh floor instead of reusing the completed route")

-- Off-floor snapshots and an open portal both survive save/load.
exploration.loadMap(route, 3, { arrival = "entrance" })
route.portalReturn = { mapIndex = 2, playerX = 4, playerY = 5, playerDir = "S" }
local restored = savegame.deserialize(savegame.serialize(route, loader, "map"), loader)
check(restored.mapStates[2] and restored.mapStates[2].mapGrid,
    "generated floor snapshots survive save/load")
check(restored.portalReturn and restored.portalReturn.mapIndex == 2
    and restored.portalReturn.playerX == 4,
    "an open portal destination survives save/load")

-- The bottom of the dungeon is expressed by authoring no stairs there, not by
-- a number in system.json that has to be kept in step with the map list.
local deepest = loader.maps[7]
local hasStairs = false
for _, ev in ipairs((deepest and deepest.events) or {}) do
    if ev.scriptId == 1 then hasStairs = true end
end
check(not hasStairs, "the deepest floor carries no stairs event")
local bottomSession = sessionModule.GameSession.new(loader)
bottomSession:initializeStartingParty()
exploration.loadMap(bottomSession, 7, { arrival = "entrance" })
local generatedBottomHasStairs = false
for _, ev in ipairs(bottomSession.currentMapData.events or {}) do
    if ev.scriptId == 1 then generatedBottomHasStairs = true end
end
check(not generatedBottomHasStairs,
    "generation respects the deepest floor's missing down-stairs marker")

-- Fail loud rather than dropping the party into an empty world.
check(not pcall(exploration.loadMap, sess, 999),
    "a transfer to a map that does not exist raises")

print(string.format("=== Map Transfer Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then error(failed .. " map transfer test(s) failed") end
