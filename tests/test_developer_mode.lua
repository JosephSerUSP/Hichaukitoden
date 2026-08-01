-- Developer mode is a property of the launch, not of a session, so it must
-- survive every path that builds a new session. The one that used to lose it
-- was LOAD_GAME: RESET_SESSION carried the flag by hand and loading did not,
-- so a developer who loaded a save was silently returned to ordinary mode.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local savegame = require("engine.savegame")
local formula = require("engine.formula")
local interpreter = require("engine.interpreter")

print("[TEST] Starting developer mode tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local launchFlag = sessionModule.developerMode

-- Ordinary launch: nothing is a developer session, and the title menu formula
-- that picks between the two menus sees false rather than nil.
sessionModule.developerMode = false
local plain = sessionModule.GameSession.new(loader)
check(plain.developerMode == false, "an ordinary launch builds ordinary sessions")
check(formula.sessionView(plain).developerMode == false,
    "and data reads it as false, not nil")

-- Developer launch: the flag reaches sessions built afterwards, including the
-- one a save round-trip reconstructs.
sessionModule.developerMode = true
local dev = sessionModule.GameSession.new(loader)
dev:initializeStartingParty()
check(dev.developerMode == true, "a developer launch builds developer sessions")
check(formula.sessionView(dev).developerMode == true, "and data can read it")

local data = savegame.serialize(dev, loader, "map")
local restored = savegame.deserialize(data, loader)
check(restored.developerMode == true, "a loaded save is still a developer session")

-- The flag describes the launch, so it must not be written into the save --
-- an ordinary launch loading a developer's save is an ordinary session.
sessionModule.developerMode = false
local afterPlainLaunch = savegame.deserialize(data, loader)
check(afterPlainLaunch.developerMode == false,
    "and an ordinary launch loading that same save is not")

-- The title's Developer Room command is intentionally available in an
-- ordinary launch. Its RESET_SESSION override makes that one fresh session a
-- real developer session, without changing the launch-wide default.
local resetCtx = { session = afterPlainLaunch, loader = loader, events = {} }
interpreter.runImmediate({ { cmd = "RESET_SESSION", developerMode = "true" } }, resetCtx)
check(resetCtx.session.developerMode == true,
    "RESET_SESSION can explicitly create a developer-room session")
check(sessionModule.developerMode == false,
    "the developer-room override does not change the launch default")

sessionModule.developerMode = launchFlag

print(string.format("=== Developer Mode Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " developer mode test(s) failed", failed) end
