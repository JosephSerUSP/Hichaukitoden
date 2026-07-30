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
    map = "party_status", items = "item_inspect", shop = "item_inspect", save_menu = "party_status",
    quest_log = "party_status", datalog = "party_status", options = "party_status",
    controls = "party_status", battle = "battle",
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

-- A CHOICE is embedded inside the still-open message panel. Pin all three
-- data-authored pieces because losing any one recreates either the black
-- message area (message hidden), a doubled frame (choice chrome), or a list
-- detached from the bottom of the dialogue box (fitRows).
local dialogueWindows = {}
for _, w in ipairs(registry.variants.dialogue.windows or {}) do
    dialogueWindows[w.id] = w
end
check(dialogueWindows.dialogue_message
        and dialogueWindows.dialogue_message.visible
            == "v.dialogueMode == 'text' or v.dialogueMode == 'choice'",
    "dialogue message remains visible behind a choice")
check(dialogueWindows.dialogue_choices
        and dialogueWindows.dialogue_choices.chrome == "none",
    "dialogue choices embed without drawing a second frame")
check(dialogueWindows.dialogue_choices
        and dialogueWindows.dialogue_choices.fitRows == "bottom",
    "embedded dialogue choices stay anchored to the panel bottom")

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
local initial = dock.__transition()
check(initial and initial.targetVariant == "party_status",
    "entering from no dock starts the party_status reveal")
check(initial and initial.from[1].w == 0 and initial.from[1].h == 0,
    "an initial dock reveal grows horizontally and vertically from zero")
dock.__finishTransition()
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

-- A different variant clears content, morphs its N shells, then populates the
-- destination. It does not inherit the outgoing variant's table.
drawScene("dialogue")
check(dock.variant() == "party_status", "content remains on the source variant during morph")
check(dock.__fading(), "a variant change starts a shell morph")
check(dock.__store()._dataWins["party"] ~= firstWin,
    "the destination starts from a clean content store")
dock.__finishTransition()
drawScene("dialogue")
check(dock.variant() == "dialogue", "dialogue content appears after shell geometry settles")

-- Leaving for a scene that wants no dock retires it.
drawScene("status")
check(dock.__fading(), "leaving the dock starts a two-axis shell collapse")
local retiring = dock.__transition()
check(retiring and retiring.to[1].w == 0 and retiring.to[1].h == 0,
    "retiring to no dock collapses horizontally and vertically")
dock.__finishTransition()
check(dock.variant() == nil, "a scene with no config.dock retires it after collapse")

-- The shell language is N-wide, not hardcoded to today's two-rect layouts.
registry.variants.test_three = {
    primary = "three_empty",
    shells = {
        { x = 0, y = 18, w = 8, h = 12 },
        { x = 8, y = 18, w = 8, h = 12 },
        { x = 16, y = 18, w = 16, h = 12 },
    },
    windows = {
        { id = "three_empty", rect = { x = 0, y = 18, w = 8, h = 12 }, content = {} },
    },
}
dock.reset()
drawScene("save_menu")
dock.__finishTransition()
drawScene("save_menu")
local threeScene = { id = "three", config = { dock = { variant = "test_three" } } }
dock.draw({ v = {} }, threeScene, ctx)
check(dock.__transition() and #dock.__transition().to == 3,
    "a destination may add a third horizontally-growing shell")
registry.variants.test_three = nil

-- Fail loud, never silently (AGENTS.md): a variant name with no registry
-- entry must raise rather than render nothing.
dock.reset()
local bogus = { id = "bogus", config = { dock = { variant = "no_such_variant" } } }
local ok = pcall(dock.draw, { v = {} }, bogus, ctx)
check(not ok, "an undeclared dock variant raises instead of silently drawing nothing")

print("=== Dock Tests: " .. passed .. " passed, " .. failed .. " failed ===")
if failed > 0 then error("dock tests failed") end
