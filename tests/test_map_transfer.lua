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

print("[TEST] Starting map transfer tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

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

-- The bottom of the dungeon is expressed by authoring no stairs there, not by
-- a number in system.json that has to be kept in step with the map list.
local deepest = loader.maps[7]
local hasStairs = false
for _, ev in ipairs((deepest and deepest.events) or {}) do
    if ev.scriptId == 1 then hasStairs = true end
end
check(not hasStairs, "the deepest floor carries no stairs event")

-- Fail loud rather than dropping the party into an empty world.
check(not pcall(exploration.loadMap, sess, 999),
    "a transfer to a map that does not exist raises")

print(string.format("=== Map Transfer Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then error(failed .. " map transfer test(s) failed") end
