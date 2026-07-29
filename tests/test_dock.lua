-- The persistent bottom dock (SPEC 1.4, presentation/dock.lua).
--
-- The bug these pin: the dock used to be a window each scene declared for
-- itself, so scene_host.push -- which builds a fresh state table per scene --
-- destroyed and rebuilt it on every transition. The renderer keys its
-- animation clocks by the window TABLE, so a rebuilt table meant the dock
-- replayed its 0.24s grow-in every time the player opened a menu.
--
-- Test 1 is therefore the load-bearing one: after moving between two scenes
-- that want the same variant, the dock's window table must be the SAME table.
-- That identity IS the animation continuity; there is no separate flag to
-- assert. The screenshot and golden-UI harnesses cannot see any of this
-- (neither advances animation clocks, and resolveState does not feed the
-- dock), so it is checked here or nowhere.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local dock = require("presentation.dock")

print("[TEST] Starting dock tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()
local sess = sessionModule.GameSession.new(loader)
local ctx = { session = sess, loader = loader, party = sess.party }

local function sceneById(id)
    for _, s in ipairs(loader.scenes or {}) do
        if tostring(s.id) == id then return s end
    end
end

-- Every scene the dock is expected to serve, so a scene losing its
-- `config.dock` (or a typo in the variant name) fails here rather than
-- silently showing no dock at runtime.
local EXPECTED = {
    map = "party_status", items = "party_status", save_menu = "party_status",
    quest_log = "party_status", options = "party_status",
    controls = "party_status", battle = "party_status",
    dialogue = "dialogue",
}
for id, variant in pairs(EXPECTED) do
    local sceneData = sceneById(id)
    local cfg = sceneData and sceneData.config and sceneData.config.dock
    if type(cfg) == "string" then cfg = { variant = cfg } end
    check(cfg and cfg.variant == variant,
        "scene '" .. id .. "' declares dock variant '" .. variant .. "'")
end

local registry = loader.engine and loader.engine.dock
check(registry ~= nil, "data/engine.json declares a dock registry")
for _, variant in pairs(EXPECTED) do
    check(registry and registry.variants and registry.variants[variant] ~= nil,
        "the dock registry defines variant '" .. variant .. "'")
end

-- No scene may still carry its own copy of a dock window: that is exactly the
-- duplication the persistent dock replaced.
local dupes = {}
for _, s in ipairs(loader.scenes or {}) do
    for _, w in ipairs(s.windows or {}) do
        if w.id == "party" or w.id:match("^dialogue_") then
            table.insert(dupes, tostring(s.id) .. "/" .. w.id)
        end
    end
end
check(#dupes == 0,
    "no scene re-declares a dock-owned window (found: " .. table.concat(dupes, ", ") .. ")")

-- ---- Behaviour ---------------------------------------------------------
local function drawScene(id)
    dock.draw({ v = {} }, sceneById(id), ctx)
end

-- save_menu/options/quest_log are used rather than `items` because items'
-- dock declares a `visible` formula keyed on its scene state, so with a blank
-- v the renderer never materializes the window at all.
dock.reset()
drawScene("save_menu")
check(dock.variant() == "party_status", "entering a party_status scene shows that variant")

local firstWin = dock.__store()._dataWins["party"]
check(firstWin ~= nil, "the dock built its window table")

-- The load-bearing assertion: same variant across a scene change must reuse
-- the very same window table, so its animation clock is never restarted.
drawScene("options")
drawScene("quest_log")
check(dock.variant() == "party_status", "moving between party_status scenes keeps the variant")
check(dock.__store()._dataWins["party"] == firstWin,
    "the dock's window table SURVIVES the scene change (no animation replay)")
check(not dock.__fading(), "a same-variant transition starts no cross-fade")

-- A different variant cross-fades instead of cutting, and does not inherit
-- the outgoing variant's table.
drawScene("dialogue")
check(dock.variant() == "dialogue", "entering dialogue switches the dock variant")
check(dock.__fading(), "a variant change starts a cross-fade")
check(dock.__store()._dataWins["party"] ~= firstWin,
    "the incoming variant starts from a clean store")

-- Leaving for a scene that wants no dock retires it.
drawScene("status")
check(dock.variant() == nil, "a scene with no config.dock retires the dock")

-- Fail loud, never silently (AGENTS.md): a variant name with no registry
-- entry must raise rather than render nothing.
dock.reset()
local bogus = { id = "bogus", config = { dock = { variant = "no_such_variant" } } }
local ok = pcall(dock.draw, { v = {} }, bogus, ctx)
check(not ok, "an undeclared dock variant raises instead of silently drawing nothing")

print("=== Dock Tests: " .. passed .. " passed, " .. failed .. " failed ===")
if failed > 0 then error("dock tests failed") end
