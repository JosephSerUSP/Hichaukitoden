-- Map-authored enemy level ranges are resolved by the reusable
-- SPAWN_ENEMIES command, not by the battle scene.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")

print("[TEST] Starting encounter level tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local function spawn(encounter)
    local sess = sessionModule.GameSession.new(loader)
    sess.currentMapData = { encounters = { encounter } }
    local ctx = { session = sess, loader = loader, events = {}, party = sess.party }
    interpreter.runImmediate({ { cmd = "SPAWN_ENEMIES", count = "1" } }, ctx)
    return ctx.events[1] and ctx.events[1].enemies[1], sess
end

local ranged, rangedSession = spawn({ id = 3, weight = 1, levelMin = 7, levelMax = 7 })
check(ranged and ranged.level == 7,
    "an authored encounter level is used to construct the enemy")
check(ranged and ranged.hp == ranged:getMaxHp(rangedSession),
    "a levelled enemy enters battle at full HP")

local legacy = spawn({ id = 3, weight = 1 })
check(legacy and legacy.level == loader.getActor(3).level,
    "an encounter with no range retains the actor's authored default level")

print(string.format("=== Encounter Level Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then error(failed .. " encounter level test(s) failed") end
