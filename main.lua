local loader = require("data.loader")
local session = require("engine.session")
local exploration = require("engine.exploration")
local battleSystem = require("engine.battle")
local director = require("engine.director")
local renderer = require("presentation.renderer")
local scene_host = require("engine.scene_host")
local traits = require("engine.traits")
local effects = require("engine.effects")
local interpreter = require("engine.interpreter")
local flow = require("engine.flow")
local savegame = require("engine.savegame")
require("engine.scenes.battle")
local viewport_3d = require("presentation.viewport_3d")
local small_battlers = require("presentation.small_battlers")
local frame_renderer = require("presentation.frame_renderer")
local door_transition = require("presentation.door_transition")

-- Setup currentScene interceptor on _G
setmetatable(_G, {
    __index = function(t, k)
        if k == "currentScene" then
            return scene_host.getCurrent()
        end
        return rawget(t, k)
    end,
    __newindex = function(t, k, v)
        if k == "currentScene" then
            local curr = scene_host.getCurrent()
            if curr ~= v then
                -- if popping (e.g. from crafting back to menu)
                if scene_host.getPrevious() == v then
                    scene_host.pop()
                else
                    scene_host.goto_scene(v)
                end
            end
        else
            rawset(t, k, v)
        end
    end
})

-- Game resolution dimensions
local gameWidth, gameHeight = 256, 240
local canvas
local scale, scaleX, scaleY = 1, 1, 1

-- Global Session and State Router

local function getPopupFormat(key)
    if config.battle_screen and config.battle_screen.popup and config.battle_screen.popup[key] then
        return config.battle_screen.popup[key]
    end
    -- Fallbacks
    if key == "damageFormat" then return "-{0}" end
    if key == "damageColor" then return {1, 0.2, 0.2, 1} end
    if key == "healFormat" then return "+{0}" end
    if key == "healColor" then return {0.2, 1, 0.2, 1} end
    if key == "critFormat" then return "CRITICAL!" end
    if key == "critColor" then return {1, 0.2, 0.2, 1} end
    if key == "deadFormat" then return "DEAD" end
    if key == "deadColor" then return {0.6, 0.6, 0.6, 1} end
    if key == "stateFormat" then return "{0}" end
    if key == "stateColor" then return {0.8, 0.4, 1.0, 1} end
    return ""
end

activeSession = nil

local isTestBattle = false
local isValidateMode = false
local isSaveTestMode = false
local cliCampaignRoot = nil
local isPreviewSceneMode = false
local previewSceneId = nil
local isPreviewWindowMode = false
local previewWindowId = nil
local previewWindowMockSpec = nil
local isPreviewFontMode = false
local previewFontName = nil
local previewFontSize = nil
local isPreviewMapMode = false
local previewMapId = nil
local previewMapX = nil
local previewMapY = nil
local previewMapDir = nil
local isPreviewFogMode = false
local previewFogSpec = nil
local previewFogMapId = nil
local isEngineStateMode = false
local isReachabilityMode = false
local isGoldenMode = false
local isGoldenUIMode = false
local isScreenshotMode = false
local isDeveloperMode = false
local triggerTestBattle


-- Battle State now lives entirely in scene_host (engine/scenes/battle.lua,
-- accessed via v.*). The former main.lua battle globals were removed after
-- the battle->scene migration; nothing referenced them.

-- Dialogue State
local activeWalker
local dialogueSelectIdx = 1
local eventWaitRemaining = 0
local eventSkipLabel = nil
-- Set when a BATTLE command starts a fight from inside an event; consumed by
-- the battle scene's outcome hook to resume the event at its onVictory or
-- onDefeat branch. Nil for a battle the player simply walked into.
local pendingBattleResume

-- Menu State


local inputCooldown = 0

-- Auto-repeat state (update-driven, not OS key repeat)
local heldKeys = {}  -- key → { holdTime = seconds, lastFire = count }

-- Forward declarations (defined later in the file, called by update loop)
local handleKeyPressed
local handleDialogueAction
-- Bound to runEventCommands once it is defined; the presentation seam's
-- runCommonEvent hook is registered before that point in the file.
local runEventCommandsRef

local server = require("engine.server")
config = require("engine.config")

-- Config accessor with fallback for missing keys
local function conf(group, key, default)
    local g = config[group]
    if g and g[key] ~= nil then return g[key] end
    return default
end

-- Database validation for `lovec . validate` lives in engine/validator.lua
-- (cross-reference integrity plus a scripted battle round). main.lua only
-- dispatches to it from the CLI branch in love.load.

-- Golden-master battle log validation

-- Golden-master UI log validation: drives a scripted input sequence through
-- each scene in the registry via scene_host, capturing the normalized UI
-- event log. Events are logged in `window|action|target|value` format between
-- UI GOLDEN BEGIN/END markers (matching the pattern used by capture scripts).
-- Deterministic mock session shared by the golden-ui harness and the E5
-- scene preview: fixed seed, starting party, crafting ingredients in
-- inventory so list-driven scenes have real content to show.
local cli_tools = require("engine.cli_tools")
local validator = require("engine.validator")

-- Presentation seam (24.07.2026): the engine asks presentation questions and
-- re-points it at a swapped session through these hooks instead of requiring
-- presentation modules from engine/ (see interpreter.bindPresentation).
interpreter.bindPresentation({
    rebindSession = function(sess)
        renderer.init(sess)
    end,
    isBattleLogRevealing = function(combatLog)
        return renderer.isBattleLogRevealing(combatLog)
    end,
    finishBattleLogReveal = function()
        renderer.finishBattleLogReveal()
    end,
    isAnimationPlaying = function()
        return require("presentation.animation_player").isAnythingPlaying()
    end,
    getVictoryStage = function()
        return renderer.getVictoryStage()
    end,
    showStringPicture = function(spec)
        require("presentation.string_picture_renderer").show(spec)
    end,
    moveStringPicture = function(spec)
        require("presentation.string_picture_renderer").move(spec)
    end,
    eraseStringPicture = function(id, duration)
        require("presentation.string_picture_renderer").erase(id, duration)
    end,
    clearStringPictures = function()
        require("presentation.string_picture_renderer").clear()
    end,
    showImagePicture = function(spec)
        require("presentation.image_picture_renderer").show(spec)
    end,
    moveImagePicture = function(spec)
        require("presentation.image_picture_renderer").move(spec)
    end,
    eraseImagePicture = function(id, duration)
        require("presentation.image_picture_renderer").erase(id, duration)
    end,
    clearImagePictures = function()
        require("presentation.image_picture_renderer").clear()
    end,
    setSubtractiveFade = function(spec)
        require("presentation.subtractive_transition").set(spec)
    end,
    enableEventSkip = function(label)
        eventSkipLabel = label
    end,
    disableEventSkip = function()
        eventSkipLabel = nil
    end,
    -- An item asked to run a common event (the Forbidden Lamp shape). The
    -- engine cannot do this itself: CALL_COMMON_EVENT compiles to a dialogue
    -- node and immediate mode refuses it, so effects.lua raises a request and
    -- the host -- which owns the graph walker and the dialogue scene -- starts
    -- it through the same path a map event uses. Bound late (runEventCommands
    -- is defined further down) via a forward local.
    runCommonEvent = function(id)
        local ce = loader.commonEvents and loader.commonEvents[tostring(id)]
        if not ce or not ce.commands then return false end
        if not runEventCommandsRef then return false end
        runEventCommandsRef(ce, ce.commands)
        return true
    end,
})


function love.load(arg)
    -- Seed the RNG with the current time so normal gameplay (outside the
    -- validation/golden/preview harnesses) gets a fresh, non-deterministic
    -- party/inventory every run. The harnesses below reseed to a fixed value
    -- (12345) for reproducible golden logs, so this only affects real play.
    math.randomseed(os.time())
    scene_host.init("title")
    print("--------------------------------------------------")
    print("HICHAUKITODEN GAME LOADED (WITH INPUT COOLDOWN FIX)")
    print("--------------------------------------------------")
    
    -- Check for CLI arguments (test-battle, validate)
    if arg then
        local i = 1
        while i <= #arg do
            local val = arg[i]
            if val == "test-battle" then
                isTestBattle = true
            elseif val == "validate" then
                isValidateMode = true
            elseif val == "engine-state" then
                isEngineStateMode = true
            elseif val == "reachability" then
                isReachabilityMode = true
            elseif val == "golden" then
                isGoldenMode = true
            elseif val == "golden-ui" then
                isGoldenUIMode = true
            elseif val == "screenshots" then
                isScreenshotMode = true
            elseif val == "preview-scene" then
                isPreviewSceneMode = true
                previewSceneId = arg[i + 1]
                i = i + 1
            elseif val == "preview-window" then
                -- mockSpecJSON is always passed (the server supplies "{}"
                -- when there's no mock binding) so parsing never has to
                -- guess whether the next arg is data or another flag.
                isPreviewWindowMode = true
                previewWindowId = arg[i + 1]
                previewWindowMockSpec = arg[i + 2]
                i = i + 2
            elseif val == "preview-anim" then
                isPreviewAnimMode = true
                previewAnimId = arg[i + 1]
                previewAnimJson = arg[i + 2]
                previewAnimSprite = arg[i + 3]
                i = i + 3
            elseif val == "preview-font" then
                isPreviewFontMode = true
                previewFontName = arg[i + 1]
                previewFontSize = arg[i + 2]
                i = i + 2
            elseif val == "preview-map" then
                -- x/y/dir are all optional (default spawn is used when
                -- omitted), so only consume the next slots as positional
                -- values while they exist and aren't another recognized
                -- flag (e.g. a trailing campaign=<name>) -- a fixed
                -- 4-slot consume here would swallow that flag as if it
                -- were the x-coordinate and crash on tonumber(nil).
                local function isPositional(v)
                    return v ~= nil and not v:match("^campaign=")
                end
                isPreviewMapMode = true
                previewMapId = arg[i + 1]
                if isPositional(arg[i + 2]) then previewMapX = arg[i + 2]; i = i + 1 end
                if isPositional(arg[i + 2]) then previewMapY = arg[i + 2]; i = i + 1 end
                if isPositional(arg[i + 2]) then previewMapDir = arg[i + 2]; i = i + 1 end
                i = i + 1
            elseif val == "preview-fog" then
                isPreviewFogMode = true
                previewFogSpec = arg[i + 1]
                if arg[i + 2] and not arg[i + 2]:match("^campaign=") then
                    previewFogMapId = arg[i + 2]
                    i = i + 1
                end
                i = i + 1
            elseif val == "savetest" then
                isSaveTestMode = true
            elseif val == "unittest" then
                isUnitTestMode = true
            elseif val == "developer" then
                isDeveloperMode = true
            elseif val:match("^campaign=") then
                -- Overrides the campaign.json pointer for this run (used by
                -- the generator's validate loops): campaign=<name> loads
                -- campaigns/<name>/ instead of the resolved default.
                cliCampaignRoot = "campaigns/" .. val:sub(#"campaign=" + 1)
            end
            i = i + 1
        end
    end

    if isSaveTestMode then
        loader.init(cliCampaignRoot)
        local s = session.GameSession.new(loader)
        s:initializeStartingParty()
        exploration.loadMap(s, 1)
        local origGold, origPartyName, origPX, origPY = s.gold, s.party[1] and s.party[1].name, s.playerX, s.playerY
        s.expBank = 42
        savegame.save(s, loader, "map", "savetest")
        local data = savegame.load("savetest", loader)
        assert(data, "load returned nil")
        local loaded, scene = savegame.deserialize(data, loader)
        assert(loaded.gold == origGold, "gold mismatch")
        assert(loaded.expBank == 42, "expBank mismatch")
        assert(loaded.party[1] and loaded.party[1].name == origPartyName, "party[1] name mismatch")
        assert(loaded.playerX == origPX and loaded.playerY == origPY, "player pos mismatch")
        assert(scene == "map", "scene mismatch: " .. tostring(scene))
        savegame.delete("savetest")
        print("SAVETEST OK")
        love.event.quit(0)
        return
    end

    if isUnitTestMode then
        loader.init(cliCampaignRoot)
        dofile("tests/test_traits.lua")
        dofile("tests/test_recruitment.lua")
        dofile("tests/test_target_redirection.lua")
        dofile("tests/test_permadeath_wards.lua")
        dofile("tests/test_item_menu_targeting.lua")
        dofile("tests/test_element_affinity.lua")
        dofile("tests/test_craft.lua")
        dofile("tests/test_item_vocabulary.lua")
        dofile("tests/test_damage_model.lua")
        dofile("tests/test_state_ticks.lua")
        dofile("tests/test_status_infliction.lua")
        dofile("tests/test_forced_action.lua")
        dofile("tests/test_mpd_economy.lua")
        dofile("tests/test_growth.lua")
        dofile("tests/test_progress.lua")
        dofile("tests/test_promotion.lua")
        dofile("tests/test_transform.lua")
        dofile("tests/test_developer_mode.lua")
        dofile("tests/test_map_transfer.lua")
        dofile("tests/test_battle_commands.lua")
        dofile("tests/test_troops.lua")
        dofile("tests/test_early_balance.lua")
        dofile("tests/test_datalog.lua")
        dofile("tests/test_dock.lua")
        print("ALL UNIT TESTS OK")
        if love.event and love.event.quit then love.event.quit(0) end
        return
    end

    -- E5: headless scene preview for the editor canvas, then quit.
    if isPreviewSceneMode then
        loader.init(cliCampaignRoot)
        cli_tools.runPreviewScene(previewSceneId, loader, gameWidth, gameHeight)
        love.event.quit(0)
        return
    end

    if isScreenshotMode then
        loader.init(cliCampaignRoot)
        cli_tools.runScreenshots(loader, gameWidth, gameHeight)
        love.event.quit(0)
        return
    end

    -- E12: headless single-window preview for the Windows tab, then quit.
    if isPreviewWindowMode then
        loader.init(cliCampaignRoot)
        cli_tools.runPreviewWindow(previewWindowId, previewWindowMockSpec, loader, gameWidth, gameHeight)
        love.event.quit(0)
        return
    end

    -- Font picker preview: renders the REAL ui.drawPanel/ui.drawString path
    -- with a candidate font+size, then quits. Never touches data/system.json.
    if isPreviewFontMode then
        loader.init(cliCampaignRoot)
        cli_tools.runPreviewFont(previewFontName, tonumber(previewFontSize))
        love.event.quit(0)
        return
    end

    -- A3: headless animation preview, then quit.
    if isPreviewAnimMode then
        loader.init(cliCampaignRoot)
        cli_tools.runPreviewAnim(previewAnimId, previewAnimJson, previewAnimSprite, loader)
        love.event.quit(0)
        return
    end

    -- Headless raycaster preview, then quit.
    if isPreviewMapMode then
        loader.init(cliCampaignRoot)
        cli_tools.runPreviewMap(previewMapId, previewMapX, previewMapY, previewMapDir, loader)
        love.event.quit(0)
        return
    end

    if isPreviewFogMode then
        loader.init(cliCampaignRoot)
        cli_tools.runPreviewFog(previewFogSpec, previewFogMapId, loader)
        love.event.quit(0)
        return
    end

    -- Generated ground truth for docs/ENGINE-STATE.md (G4). Prints the report
    -- between markers; tools/golden/check-state.* captures and diffs it.
    if isEngineStateMode then
        loader.init(cliCampaignRoot)
        local ok, report = pcall(require("engine.engine_state").build, loader)
        if ok then
            print("ENGINE STATE BEGIN")
            print(report)
            print("ENGINE STATE END")
        else
            print("ENGINE STATE FAIL: " .. tostring(report))
        end
        love.event.quit(ok and 0 or 1)
        return
    end

    -- Advisory reachability report: content that resolves but that nothing can
    -- produce or trigger (`lovec . reachability`). Deliberately not a gate --
    -- see the header of engine/reachability.lua -- so it always exits 0.
    if isReachabilityMode then
        loader.init(cliCampaignRoot)
        local ok, report = pcall(require("engine.reachability").build, loader)
        if ok then
            print(report)
        else
            print("REACHABILITY FAIL: " .. tostring(report))
        end
        love.event.quit(ok and 0 or 1)
        return
    end

    -- Headless data validation: check database cross-references and simulate
    -- a battle round, then quit. Run via `lovec . validate` (used by CI/tools).
    if isValidateMode then
        loader.init(cliCampaignRoot)
        local ok, err
        if isGoldenMode then
            ok, err = pcall(cli_tools.runGolden, loader)
        elseif isGoldenUIMode then
            ok, err = pcall(cli_tools.runGoldenUI, loader)
        else
            ok, err = pcall(validator.run, loader)
        end

        if ok and not isGoldenMode then
            print("VALIDATE OK")
        elseif not ok then
            print("VALIDATE FAIL:\n" .. tostring(err))
        end
        love.event.quit(ok and 0 or 1)
        return
    end
    
    love.graphics.setDefaultFilter("nearest", "nearest")
    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    love.resize(love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Initialize database loader
    loader.init(cliCampaignRoot)
    
    -- Initialize activeSession. The developer flag is set on the module before
    -- the first session exists, so every session built afterwards -- including
    -- the ones LOAD_GAME and F6 deserialize -- carries it too.
    session.developerMode = isDeveloperMode
    activeSession = session.GameSession.new(loader)
    activeSession:initializeStartingParty()
    
    -- Initialize renderer graphics
    renderer.init(activeSession)

    -- E10: the boot-time scene_host.init("title") ran before the loader was
    -- ready, so the title scene's on_enter (which builds its windows) could
    -- not run. Re-enter it now that session and loader exist.
    scene_host.init(nil)
    scene_host.push("title", { session = activeSession, loader = loader, party = activeSession.party })

    -- Initialize 3D viewport textures
    viewport_3d.init()

    -- Effekseer needs a live GL context, so it initialises here rather than at
    -- require time. A missing shim DLL logs once and disables effects instead
    -- of raising, so a clean checkout still runs (owner decision 30.07.2026,
    -- docs/design/renderer-3d-roadmap.md 10.3).
    require("presentation.effekseer").init()
    
    -- Start developer server
    server.start()
    
    -- If in test battle mode, launch immediately into battle
    if isTestBattle then
        triggerTestBattle()
    end
end

-- Mirrors the live GraphWalker's current node into the dialogue scene's
-- v table every frame, so the windows-drawn dialogue scene (data/scenes.json
-- "dialogue") can bind to it via ordinary formula/list content blocks.
-- handleKeyPressed still drives activeWalker/dialogueSelectIdx directly
-- (unchanged) -- this only feeds the draw side. dialogueText carries the FULL
-- line and dialogueRevealElapsed the clock (renderer.getDialogueText /
-- renderer.dialogueRevealElapsed, the same dialogueReveal tracker
-- isDialogueRevealing/finishDialogueReveal use); the message window's text
-- widget does the wrapping and slicing, since only it knows the real width.
local function finishDialogueToMap()
    local function returnToMap()
        activeSession.locationArt = nil
        require("presentation.location_renderer").clear()
        scene_host.goto_scene("map")
    end

    if activeSession.locationArt then
        if not door_transition.isActive() then
            door_transition.beginExit(returnToMap)
        end
    else
        returnToMap()
    end
end

-- Close the current message before an event action (including fades, map
-- loads, and scene changes) starts.  The dialogue scene mirrors its TEXT node
-- into v during update, so without this explicit clear a transition begun
-- from keypressed() can draw one frame with the previous line still cached.
-- Choices deliberately retain the preceding question and do not use this.
local function clearDialogueMessage()
    local state = scene_host.getCurrentState()
    if not state or not state.v then return end
    state.v.dialogueText = ""
    state.v.dialogueSpeaker = ""
    state.v.dialogueWaiting = false
end

local function syncDialogueWindowState()
    local state = scene_host.getCurrentState()
    if not state then return end
    -- Dead-walker guard: a dialogue whose walker has ended (or was lost)
    -- with the scene still current would otherwise soft-lock -- there is no
    -- ESC exit from dialogue by design. Returning from a pushed scene
    -- (shop) with the conversation finished behind it lands here too.
    local node = activeWalker and activeWalker:getCurrentNode()
    if not node then
        finishDialogueToMap()
        return
    end
    state.v = state.v or {}
    local v = state.v

    if node.type == "TEXT" then
        v.dialogueMode = "text"
        local speaker = node.speaker
        if speaker and speaker ~= "" then
            local rName = string.gsub(activeWalker.eventName or "??", "%%", "%%%%")
            speaker = string.gsub(speaker, "\\eventName", rName)
        end
        v.dialogueSpeaker = speaker or ""
        v.dialogueExpression = math.max(1, math.min(5, math.floor(tonumber(node.expression) or 1)))
        -- The FULL line goes to the window; the window's text widget wraps
        -- and slices it against its own real draw width (see the text
        -- block's `reveal` field in engine.json). This used to re-derive
        -- the wrap width from the static rect here, which was a tile too
        -- wide AND blind to the portrait-driven runtime width -- so the
        -- draw-time printf disagreed and re-flowed words mid-reveal.
        v.dialogueText = renderer.getDialogueText(node)
        v.dialogueRevealElapsed = renderer.dialogueRevealElapsed()
        -- Drives the animated waiting-for-input marker on the message
        -- window (waitInput formula), replacing the old "[Press SPACE]".
        v.dialogueWaiting = not renderer.isDialogueRevealing()
        -- Portrait PERSISTS across speakerless narration lines and CHOICE
        -- nodes (only a new speaker/portrait replaces it); the namebox above
        -- clears instead, since it tracks who's speaking line by line. v is
        -- fresh per scene push, so nothing leaks between conversations.
        local portrait = node.speaker or (activeWalker.graph and activeWalker.graph.portrait)
        if portrait and portrait ~= "" then
            v.dialoguePortrait = portrait
        end
    elseif node.type == "CHOICE" then
        v.dialogueMode = "choice"
        -- Speaker/portrait intentionally left as whatever the last TEXT node
        -- set -- the question that led to these choices stays visible above
        -- them, same as the legacy renderer kept the same window open.
        v.dialogueWaiting = false
        local opts = {}
        for _, opt in ipairs(node.options or {}) do
            table.insert(opts, opt.label)
        end
        v.dialogueOptions = opts
        v.dialogueCursorIdx = dialogueSelectIdx

        -- RPG Maker rule: the choice strip grows up from the dialog box's
        -- bottom (fitRows), and when the retained TEXT wouldn't fit in what
        -- remains above it, the text clears to make room. Geometry comes
        -- from the scene's own window defs so layout edits stay data-only;
        -- wrapped-line count is an estimate (measure/width), biased to
        -- clearing early rather than overlapping.
        local text = v.dialogueText or ""
        if text ~= "" then
            local ui = require("presentation.ui")
            local sceneDef = loader.getScene("dialogue")
            local msgDef
            for _, wd in ipairs((sceneDef and sceneDef.windows) or {}) do
                if wd.id == "dialogue_message" then msgDef = wd end
            end
            local boxH = ui.toPx((msgDef and msgDef.rect and msgDef.rect.h) or 12)
            local boxW = ui.toPx((msgDef and msgDef.rect and msgDef.rect.w) or 24)
            local stripH = #opts * ui.lineHeight + ui.toPx(3)
            local availH = boxH - stripH - 12
            local lines = 0
            for chunk in (text .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(ui.measureText(chunk) / math.max(1, boxW - 24)))
            end
            if lines * ui.lineHeight > availH then
                v.dialogueText = ""
            end
        end
    end
end

function love.update(dt)
    renderer.update(dt)
    require("presentation.string_picture_renderer").update(dt)
    require("presentation.image_picture_renderer").update(dt)
    require("presentation.subtractive_transition").update(dt)
    door_transition.update(dt)
    server.update(dt)
    if server.configReloaded then
        server.configReloaded = false
        local ui = require("presentation.ui")
        if config.ui and config.ui.activeFont then
            ui.setFont(config.ui.activeFont, config.ui.fontSize)
        end
        if config.battle_screen and config.battle_screen.popup and config.battle_screen.popup.font then
            ui.loadPopupFont(config.battle_screen.popup.font, config.battle_screen.popup.fontSize)
        end
    end
    if activeSession then
        local prevTransition = activeSession.transitionTimer
        if activeSession.transitionTimer and activeSession.transitionTimer > 0 then
            activeSession.transitionTimer = activeSession.transitionTimer - dt
        end
        if activeSession.bumpTimer and activeSession.bumpTimer > 0 then
            activeSession.bumpTimer = activeSession.bumpTimer - dt
        end
        -- Decay per-key bump cooldowns (only blocks the same key that bumped)
        if activeSession.bumpCooldowns then
            for k, t in pairs(activeSession.bumpCooldowns) do
                local remaining = t - dt
                if remaining <= 0 then
                    activeSession.bumpCooldowns[k] = nil
                else
                    activeSession.bumpCooldowns[k] = remaining
                end
            end
        end

        -- When the transition animation finishes, immediately re-fire the held
        -- directional key so movement continues without waiting for the next
        -- auto-repeat tick (closing the gap between timer expiry and repeat).
        if prevTransition and prevTransition > 0
            and (not activeSession.transitionTimer or activeSession.transitionTimer <= 0)
            and scene_host.getCurrent() == "map" then
            local REPEAT_DIR_KEYS = { "up", "down", "left", "right",
                                      "w", "a", "s", "d", "q", "e" }
            for _, key in ipairs(REPEAT_DIR_KEYS) do
                if love.keyboard.isDown(key) then
                    local ctx = { session = activeSession, loader = loader, party = activeSession.party or {} }
                    if not scene_host.keypressed(key, ctx) then
                        handleKeyPressed(key)
                    end
                    break
                end
            end
        end
    end
    
    if inputCooldown > 0 then
        inputCooldown = inputCooldown - dt
    end
    
    local ctx = { session = activeSession, loader = loader }
    if scene_host.update(dt, ctx) then
        return
    end

    if scene_host.getCurrent() == "battle" then
        require("engine.scenes.battle").update(dt)
    end

    if scene_host.getCurrent() == "dialogue" then
        syncDialogueWindowState()
    end

    if eventWaitRemaining > 0 then
        eventWaitRemaining = math.max(0, eventWaitRemaining - dt)
        if eventWaitRemaining == 0 and activeWalker then
            activeWalker:advance()
            handleDialogueAction()
        end
    end

    if scene_host.getCurrent() == "cinematic"
        and activeWalker and not activeWalker:getCurrentNode() then
        eventSkipLabel = nil
        scene_host.goto_scene("map")
    end

    -- Shop: grant the pending item after the hook deducted gold
    if scene_host.getCurrent() == "shop" then
        local shopState = scene_host.getCurrentState()
        if shopState and shopState.v.pendingItem then
            activeSession:addItem(shopState.v.pendingItem, 1)
            shopState.v.pendingItem = nil
        end
    end

    -- ── Auto-repeat for held directional keys ────────────────────────────
    -- Driven by love.keyboard.isDown() + timers instead of OS key repeat,
    -- giving controlled initial delay and interval for menu scrolling and
    -- map movement. Routes through the input mapper (scene_host.keypressed)
    -- so rebindable controls work automatically.
    local REPEAT_DIR_KEYS = { "up", "down", "left", "right",
                              "w", "a", "s", "d", "q", "e" }
    local REPEAT_INITIAL  = conf("ui", "autoRepeatInitial", 0.3)
    local REPEAT_INTERVAL = conf("ui", "autoRepeatInterval", 0.06)

    for _, key in ipairs(REPEAT_DIR_KEYS) do
        if love.keyboard.isDown(key) then
            local state = heldKeys[key]
            if not state then
                heldKeys[key] = { holdTime = 0, lastFire = 0 }
                state = heldKeys[key]
            end
            state.holdTime = state.holdTime + dt
            if state.holdTime >= REPEAT_INITIAL then
                local elapsed = state.holdTime - REPEAT_INITIAL
                local fireCount = math.floor(elapsed / REPEAT_INTERVAL)
                if fireCount > state.lastFire then
                    state.lastFire = fireCount
                    local ctx = { session = activeSession, loader = loader, party = activeSession.party or {} }
                    if not scene_host.keypressed(key, ctx) then
                        handleKeyPressed(key)
                    end
                end
            end
        else
            heldKeys[key] = nil
        end
    end
end

-- F2 (overhaul-6): every scene draws the SAME declarative "party" window
-- (console + MP readout + 2x2 grid) via the generic window renderer. There is
-- no second/legacy party HUD anywhere. The Map scene already draws it through
-- its own scene state; battle/dialogue/town build a minimal party-only state
-- here so the ONE shared HUD appears in every scene (owner direction:
-- "there should be no place where the declarative one isn't used").
function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1) -- reset color at start of frame
    
    frame_renderer.draw(scene_host, renderer, activeSession, loader, gameHeight)
    
    if server.isActive() then
        local blueDotKey = "UI_BlueDot"
        local blueDot = small_battlers.get(blueDotKey)
        if blueDot then
            love.graphics.setBlendMode("add")
            local dotX = 32 * 8 - blueDot.cellW - 2   -- right edge of 256px virtual screen
            small_battlers.draw(blueDotKey, dotX, 2, blueDot.cellW)
            love.graphics.setBlendMode("alpha")
        end
    end
    
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1) -- reset color before drawing canvas to prevent dark tinting leak
    love.graphics.draw(canvas, scaleX, scaleY, 0, scale, scale)
end

local triggerBattle -- forward declaration

local function isSafeMap()
    if activeSession and activeSession.currentMapData then
        return activeSession.currentMapData.safe == true
    end
    return true
end

-- Fully restores HP/MP and revives the whole party
local function recoverParty()
    activeSession.mp = activeSession.maxMp
    for _, c in ipairs(activeSession.party) do
        c.hp = c:getMaxHp(activeSession)
        c:removeState("dead")
    end
    activeSession.summoner.hp = activeSession.summoner:getMaxHp(activeSession)
    activeSession.summoner:removeState("dead")
end

-- Field item use lives in the USE_ITEM command (engine/interpreter.lua) now;
-- the items scene drives it through its hooks.

-- Command compilation moved to engine/interpreter.lua (task A4); main.lua
-- keeps only this thin glue that supplies the loader and the recoverParty
-- callback the RECOVER_PARTY command needs.
local function interpreterCtx()
    return { loader = loader, recoverParty = recoverParty, session = activeSession }
end

local function compileCommands(nodes, commands, prefix, tailNodeId)
    return interpreter.compileTop(nodes, commands, prefix, tailNodeId, interpreterCtx())
end

local function openShop(shopId)
    -- Shops are stored as a string-keyed table (JSON object keys are always
    -- strings) even though shopId itself arrives as a number from dialogue
    -- graphs, so the lookup needs an explicit tostring() -- same pattern used
    -- for commonEvents lookups by scriptId elsewhere in this file.
    local shopData = loader.shops[tostring(shopId)]
    local shopName = (shopData and shopData.name) or tostring(shopId)

    -- Read max stock from system settings (default 20).
    local sys = loader and loader.system
    local defaultStock = (sys and sys.shopMaxStock) or 20

    local items = {}
    local maxCost = 0
    local maxTotalCost = 0
    if shopData and shopData.items then
        for _, shopItem in ipairs(shopData.items) do
            local allowed = true
            if shopItem.condition then
                local cond = shopItem.condition
                if cond:match("^level:(%d+)") then
                    local lvl = tonumber(cond:match("^level:(%d+)"))
                    allowed = (activeSession.summoner.level >= lvl)
                elseif cond:match("^flag:(.+)") then
                    local flag = cond:match("^flag:(.+)")
                    allowed = (activeSession.flags[flag] == true)
                elseif cond:match("^gold:(%d+)") then
                    local gold = tonumber(cond:match("^gold:(%d+)"))
                    allowed = (activeSession.gold >= gold)
                end
            end
            
            if allowed then
                local itemData = loader.getItem(shopItem.id)
                if itemData then
                    local cost = shopItem.price or itemData.cost or 0
                    local stock = shopItem.stock or defaultStock
                    maxCost = math.max(maxCost, cost)
                    maxTotalCost = math.max(maxTotalCost, cost * stock)
                    -- Plain table (not an __index proxy): the shop scene's
                    -- v:items list source copies row fields with pairs(),
                    -- which cannot see metatable fields. Price honors the
                    -- per-shop override set in the editor.
                    local item_presentation = require("presentation.item_presentation")
                    table.insert(items, item_presentation.enrich({
                        id = itemData.id,
                        name = itemData.name or "",
                        icon = itemData.icon or 0,
                        cost = cost,
                        stock = stock,
                    }, itemData, loader))
                end
            end
        end
    end

    -- Pad list prices only to the width of the most expensive listed item.
    local maxPrice = maxCost

    -- Push the shop scene and seed its v-state with shop data
    scene_host.push("shop", { session = activeSession, loader = loader, party = activeSession.party })
    local state = scene_host.getCurrentState()
    if state then
        state.v.shopName = shopName
        state.v.items = items
        state.v.count = #items
        state.v.idx = 1
        state.v.maxPrice = maxPrice
        state.v.maxTotalPrice = maxTotalCost
    end
end

handleDialogueAction = function()
    local node, nodeId = activeWalker:getCurrentNode()
    if not node then return end

    -- A cinematic common event may end its picture sequence by loading a map,
    -- selecting an illustrated location, and continuing with ordinary TEXT.
    -- TEXT needs the dialogue scene's windows/backdrop; leaving the walker in
    -- the deliberately empty cinematic scene produces a black soft-lock.
    if node.type == "TEXT" and scene_host.getCurrent() == "cinematic" then
        scene_host.goto_scene("dialogue")
    end

    if node.type == "ACTION" then
        if node.action == "RUN_IMMEDIATE" then
            -- Task A4b: a compiled run of non-interactive registry commands.
            -- Mutations (gold, items, states, flags) apply through the same
            -- handlers battle phases use; emitted text events render as
            -- dialogue lines by converting this node into a TEXT chain.
            local events = interpreter.runImmediate(node.commands, {
                session = activeSession,
                loader = loader,
                party = activeSession.party,
            })
            local texts = {}
            for _, ev in ipairs(events) do
                if ev.type == "text" and ev.text and ev.text ~= "" then
                    table.insert(texts, ev.text)
                end
            end
            if #texts > 0 then
                local tail = node.next
                node.type = "TEXT"
                node.content = texts[1]
                node.action = nil
                node.commands = nil
                local prev = node
                for k = 2, #texts do
                    local tid = nodeId .. "_imtext" .. k
                    activeWalker.graph.nodes[tid] = { type = "TEXT", content = texts[k], next = tail }
                    prev.next = tid
                    prev = activeWalker.graph.nodes[tid]
                end
            else
                activeWalker:advance()
                handleDialogueAction()
            end
        elseif node.action == "OPEN_SHOP" then
            openShop(node.shopId)
            -- Advance PAST the shop node now, while the shop scene sits on
            -- top: when it pops, the dialogue is already resting on the next
            -- node (typically the jump back to the hub CHOICE). Without this
            -- the walker stayed parked on the consumed ACTION node forever --
            -- no key could advance it, leaving the scene dead on return.
            activeWalker:advance()
            handleDialogueAction()
        elseif node.action == "OFFER_QUEST" then
            local quest = loader.getQuest(node.questId)
            activeSession.flags["quest:" .. node.questId .. ":active"] = true

            local evs
            if quest and quest.acceptHook then
                evs = interpreter.runImmediate(quest.acceptHook, { session = activeSession, quest = quest, questId = node.questId, loader = loader })
            else
                evs = flow.run("quest.offer", { session = activeSession, quest = quest, questId = node.questId, loader = loader })
            end

            local targetNode = node.acceptNode or node.next
            local texts = {}
            for _, ev in ipairs(evs or {}) do
                if ev.type == "text" and ev.text and ev.text ~= "" then
                    table.insert(texts, ev.text)
                end
            end

            if #texts > 0 then
                local prefix = "quest_offer_" .. node.questId .. "_" .. tostring(os.clock()):gsub("%.", "_")
                local tail = targetNode
                for k = 1, #texts do
                    local tid = prefix .. "_" .. k
                    activeWalker.graph.nodes[tid] = { type = "TEXT", content = texts[k] }
                end
                for k = 1, #texts - 1 do
                    activeWalker.graph.nodes[prefix .. "_" .. k].next = prefix .. "_" .. (k + 1)
                end
                activeWalker.graph.nodes[prefix .. "_" .. #texts].next = tail
                activeWalker:goToNode(prefix .. "_1")
                handleDialogueAction()
            else
                activeWalker:goToNode(targetNode)
                handleDialogueAction()
            end
        elseif node.action == "COMPLETE_QUEST" then
            local quest = loader.getQuest(node.questId)
            local evs
            if quest and quest.completeHook then
                evs = interpreter.runImmediate(quest.completeHook, { session = activeSession, quest = quest, questId = node.questId, loader = loader })
            else
                evs = flow.run("quest.complete", { session = activeSession, quest = quest, questId = node.questId, loader = loader })
            end

            local failed = false
            for _, ev in ipairs(evs or {}) do
                if ev.type == "quest_requirements_failed" then
                    failed = true
                    break
                end
            end

            local targetNode
            if failed then
                targetNode = node.declineNode or node.next
            else
                activeSession.flags["quest:" .. node.questId .. ":active"] = nil
                activeSession.flags["quest:" .. node.questId .. ":completed"] = true
                targetNode = node.completeNode or node.next
            end

            local texts = {}
            for _, ev in ipairs(evs or {}) do
                if ev.type == "text" and ev.text and ev.text ~= "" then
                    table.insert(texts, ev.text)
                end
            end

            if #texts > 0 then
                local prefix = "quest_complete_" .. node.questId .. "_" .. tostring(os.clock()):gsub("%.", "_")
                local tail = targetNode
                for k = 1, #texts do
                    local tid = prefix .. "_" .. k
                    activeWalker.graph.nodes[tid] = { type = "TEXT", content = texts[k] }
                end
                for k = 1, #texts - 1 do
                    activeWalker.graph.nodes[prefix .. "_" .. k].next = prefix .. "_" .. (k + 1)
                end
                activeWalker.graph.nodes[prefix .. "_" .. #texts].next = tail
                activeWalker:goToNode(prefix .. "_1")
                handleDialogueAction()
            else
                activeWalker:goToNode(targetNode)
                handleDialogueAction()
            end
        elseif node.action == "START_BATTLE" then
            -- Where to pick the event back up once the fight resolves. Held
            -- here rather than in the battle scene because the walker is the
            -- host's: the scene reports an outcome and knows nothing about
            -- events waiting on it.
            pendingBattleResume = {
                victoryNode = node.victoryNode,
                defeatNode = node.defeatNode,
            }
            triggerBattle(node.troop)
        elseif node.action == "CALL_COMMON_EVENT_ACTION" then
            local ce = loader.commonEvents and loader.commonEvents[tostring(node.commonEventId)]
            if ce and ce.commands then
                -- Build and inject sub-nodes into current walker graph dynamically
                local prefix = "ce_" .. node.commonEventId .. "_" .. tostring(os.clock()):gsub("%.", "_")
                local firstCeNode = compileCommands(activeWalker.graph.nodes, ce.commands, prefix, node.next)
                activeWalker:goToNode(firstCeNode)
                handleDialogueAction()
            else
                activeWalker:advance()
                handleDialogueAction()
            end
        elseif node.action == "WAIT_EVENT" then
            eventWaitRemaining = math.max(0, tonumber(node.duration) or 0)
            if eventWaitRemaining == 0 then
                activeWalker:advance()
                handleDialogueAction()
            end
        elseif node.action == "RECOVER_PARTY_ACTION" then
            recoverParty()

            node.type = "TEXT"
            node.content = loader.getTerm("events.recover_party", "Your party has been fully recovered!")
            node.action = nil
        else
            activeWalker:advance()
            handleDialogueAction()
        end
    end
end


-- Translates JSON command lists to dynamic conversation graphs
local function runEventCommands(eventTarget, commands)
    local activeEv = (type(eventTarget) == "table") and eventTarget or nil
    if activeSession then
        activeSession.activeEvent = activeEv
    end
    local ictx = interpreterCtx()
    if activeEv then
        ictx.event = activeEv
        ictx.eventId = activeEv.id
    end

    -- If this is a RECRUIT event, compile the actor's recruitment script
    local cType = commands and #commands == 1 and (commands[1].type or commands[1].cmd)
    if cType and (cType == "RECRUIT" or cType == "recruit" or cType == "RECRUIT_ACTOR") then
        local actorId = (activeEv and activeEv.actorId) or (commands[1] and commands[1].actorId)
        if not actorId and activeSession and activeSession.currentMapData and activeSession.currentMapData.recruits then
            local recruits = activeSession.currentMapData.recruits
            if #recruits > 0 then
                actorId = recruits[math.random(#recruits)]
            end
        end
        actorId = actorId or 1
        local actorData = loader.getActor(actorId)
        if actorData then
            -- The actor's recruit event IS an event: an ordinary command list,
            -- authored and editable like every other. engine/recruitment.lua
            -- used to BUILD one here from six preset types with the dialogue
            -- baked into Lua string concatenation -- a content template living
            -- in the engine, and the reason hostile recruitment never worked.
            commands = actorData.recruitEvent
            if not commands then
                error("actor " .. tostring(actorId) .. " ('" .. tostring(actorData.name)
                    .. "') is recruitable but authors no recruitEvent")
            end
        end
    end

    local eventTitle = (type(eventTarget) == "table" and (eventTarget.name or "Event")) or tostring(eventTarget or "Event")
    local graph = interpreter.runInteractive(commands, ictx)
    if not graph then return end
    graph.name = eventTitle

    activeWalker = director.GraphWalker.new(activeSession, graph)
    activeWalker.eventName = eventTitle
    scene_host.goto_scene((activeEv and activeEv.scene) or "dialogue")
    handleDialogueAction()
end
runEventCommandsRef = runEventCommands

local function eventAtMapCell(tx, ty)
    for _, rawEv in ipairs((activeSession.currentMapData or {}).events or {}) do
        if rawEv.x == tx - 1 and rawEv.y == ty - 1 then
            return exploration.resolvePage(rawEv, activeSession)
        end
    end
    return nil
end

local function commandsForMapEvent(ev)
    if not ev then return nil end
    if ev.scriptId then
        local commonEvent = loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)]
        return commonEvent and commonEvent.commands or nil
    end
    return ev.commands
end

local function enterDoorEvent(ev)
    local commands = commandsForMapEvent(ev)
    if not commands then return false end
    return door_transition.begin(function()
        runEventCommands(ev, commands)
    end)
end

local function checkStepEvents()
    local px, py = activeSession.playerX - 1, activeSession.playerY - 1
    if activeSession.currentMapData.events then
        for _, rawEv in ipairs(activeSession.currentMapData.events) do
            local ev = exploration.resolvePage(rawEv, activeSession)
            if ev.x == px and ev.y == py and (ev.trigger == "step" or ev.trigger == "touch") then
                local commands = nil
                if ev.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = ev.commands
                end
                
                if commands then
                    runEventCommands(ev, commands)
                    return true
                end
            end
        end
    end
    return false
end

triggerBattle = function(troopId)
    require("engine.scenes.battle").triggerBattle(troopId)
end

-- Resume an event that started a battle. Defeat normally ends the run before
-- this can fire (the scene hands off to game_over), so onDefeat is for the
-- battles a defeat is survivable in; an escape takes the defeat branch, since
-- the party did not win and the event should not proceed as though it had.
require("engine.scenes.battle").onResolved = function(outcome)
    local resume = pendingBattleResume
    pendingBattleResume = nil
    if not resume or not activeWalker then return end
    local target = (outcome == "victory") and resume.victoryNode or resume.defeatNode
    if not target or not activeWalker.graph or not activeWalker.graph.nodes[target] then
        return
    end
    activeWalker:goToNode(target)
    handleDialogueAction()
end

triggerTestBattle = function()
    require("engine.scenes.battle").triggerTestBattle()
end

-- Map a battler to screen coordinates on the battle scene.
local function getTargetCoords(target)
    return require("engine.scenes.battle").getTargetCoords(target)
end

-- Action handling for key presses
-- Loads the "quicksave" slot: rebuilds activeSession from the save data,
-- switches campaign root if the save was made against a different one, and
-- resets the scene stack to the scene it was saved from (mirrors the
-- title/RESET_SESSION boot sequence in love.load / interpreter.lua).
function quickLoad()
    local data, err = savegame.load("quicksave", loader)
    if not data then
        print("[savegame] load failed: " .. tostring(err))
        return
    end
    if data.campaignRoot and data.campaignRoot ~= loader.root then
        loader.init(data.campaignRoot)
        require("engine.config").load()
    end
    local sess, sceneName = savegame.deserialize(data, loader)
    activeSession = sess
    renderer.init(activeSession)
    scene_host.init(nil)
    scene_host.push(sceneName or "map", { session = activeSession, loader = loader, party = activeSession.party })
    print("Game loaded.")
end

handleKeyPressed = function(key)
    if inputCooldown > 0 then return end
    if not activeSession then return end
    if door_transition.isActive() then return end

    if eventSkipLabel and activeWalker
        and (key == "escape" or key == "backspace") then
        local target = activeWalker.graph
            and activeWalker.graph.labels
            and activeWalker.graph.labels[eventSkipLabel]
        if not target then
            error("event skip references unknown label '" .. tostring(eventSkipLabel) .. "'", 0)
        end
        eventWaitRemaining = 0
        activeWalker:goToNode(target)
        handleDialogueAction()
        return
    end

    local ctx = { session = activeSession, loader = loader, party = activeSession.party or {} }
    if scene_host.keypressed(key, ctx) then
        return
    end

    -- E10: title ESC is handled by the scene's on_cancel hook (moves the
    -- cursor to Exit instead of instant-quitting). Map's ESC (opening the
    -- party cursor + command overlay) is likewise fully handled by the map
    -- scene's own on_cancel hook above. Dialogue deliberately has NO escape
    -- exit: conversations advance only through their own TEXT/CHOICE flow
    -- (RPG Maker convention), and the dead-walker guard in love.update
    -- returns to the map if a dialogue ever ends up with no current node.

    -- E10: title input is fully handled by the title scene's data hooks
    -- (scene_host.keypressed above), so no legacy title branch remains.
    if scene_host.getCurrent() == "map" then
        -- MOVEMENT (forward/backward/strafe) is blocked while any transition
        -- animation is playing, preventing a disorienting mismatch between
        -- the grid state and the mid-animation camera.  TURNS are exempt so
        -- the player can rotate freely while stepping.
        --
        -- Turns ARE blocked during another turn (no queued turns), but
        -- allowed during steps for responsive cornering.

        -- Strafe (q/e) has no scene_host hook mapping, so it isn't caught
        -- by the map scene's FALLBACK dance above; guard it here directly
        -- so it can't move the party while the cursor/command overlay
        -- (v.mode ~= 0) is open.
        local mapState = scene_host.getCurrentState()
        if (key == "q" or key == "e") and mapState and mapState.v.mode and mapState.v.mode ~= 0 then
            return
        end
        local moved = false
        if key == "up" or key == "w" then
            if activeSession.transitionTimer and activeSession.transitionTimer > 0 then return end
            if activeSession.bumpCooldowns and activeSession.bumpCooldowns[key] then return end
            moved = exploration.moveForward(activeSession)
            if moved then
                activeSession.bumpCooldowns = {}  -- any success clears all cooldowns
                local d = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionTimer = d
                activeSession.transitionDuration = d
                activeSession.transitionDir = "forward"
            else
                local _, tx, ty = exploration.getFrontTile(activeSession)
                local wallEvent = eventAtMapCell(tx, ty)
                if wallEvent and wallEvent.wallEvent and wallEvent.trigger == "bump"
                    and enterDoorEvent(wallEvent) then
                    activeSession.bumpCooldowns = {}
                    return
                end
            end
            if not moved and (not activeSession.bumpTimer or activeSession.bumpTimer <= 0) then
                activeSession.bumpTimer = conf("ui", "bumpDuration", 0.12)
                activeSession.bumpCooldowns = activeSession.bumpCooldowns or {}
                activeSession.bumpCooldowns[key] = conf("ui", "bumpCooldown", 0.5)
                activeSession.bumpNudgeKey = key
            end
        elseif key == "down" or key == "s" then
            if activeSession.transitionTimer and activeSession.transitionTimer > 0 then return end
            if activeSession.bumpCooldowns and activeSession.bumpCooldowns[key] then return end
            moved = exploration.moveBackward(activeSession)
            if moved then
                activeSession.bumpCooldowns = {}
                local d = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionTimer = d
                activeSession.transitionDuration = d
                activeSession.transitionDir = "backward"
            elseif not activeSession.bumpTimer or activeSession.bumpTimer <= 0 then
                activeSession.bumpTimer = conf("ui", "bumpDuration", 0.12)
                activeSession.bumpCooldowns = activeSession.bumpCooldowns or {}
                activeSession.bumpCooldowns[key] = conf("ui", "bumpCooldown", 0.5)
                activeSession.bumpNudgeKey = key
            end
        elseif key == "left" or key == "a" then
            -- Block turn-while-turning so the animation can complete, but
            -- allow turns during a step animation (responsive cornering).
            if activeSession.transitionTimer and activeSession.transitionTimer > 0
                and activeSession.transitionDir
                and (activeSession.transitionDir == "turn_left" or activeSession.transitionDir == "turn_right") then
                return
            end
            exploration.turnLeft(activeSession)
            activeSession.bumpCooldowns = {}  -- turning resets all cooldowns
            local d = conf("ui", "turnTransitionDuration", 0.225)
            activeSession.transitionTimer = d
            activeSession.transitionDuration = d
            activeSession.transitionDir = "turn_left"
        elseif key == "right" or key == "d" then
            if activeSession.transitionTimer and activeSession.transitionTimer > 0
                and activeSession.transitionDir
                and (activeSession.transitionDir == "turn_left" or activeSession.transitionDir == "turn_right") then
                return
            end
            exploration.turnRight(activeSession)
            activeSession.bumpCooldowns = {}
            local d = conf("ui", "turnTransitionDuration", 0.225)
            activeSession.transitionTimer = d
            activeSession.transitionDuration = d
            activeSession.transitionDir = "turn_right"
        elseif key == "q" then
            if activeSession.transitionTimer and activeSession.transitionTimer > 0 then return end
            if activeSession.bumpCooldowns and activeSession.bumpCooldowns[key] then return end
            moved = exploration.strafeLeft(activeSession)
            if moved then
                activeSession.bumpCooldowns = {}
                local d = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionTimer = d
                activeSession.transitionDuration = d
                activeSession.transitionDir = "strafe_left"
            elseif not activeSession.bumpTimer or activeSession.bumpTimer <= 0 then
                activeSession.bumpTimer = conf("ui", "bumpDuration", 0.12)
                activeSession.bumpCooldowns = activeSession.bumpCooldowns or {}
                activeSession.bumpCooldowns[key] = conf("ui", "bumpCooldown", 0.5)
                activeSession.bumpNudgeKey = key
            end
        elseif key == "e" then
            if activeSession.transitionTimer and activeSession.transitionTimer > 0 then return end
            if activeSession.bumpCooldowns and activeSession.bumpCooldowns[key] then return end
            moved = exploration.strafeRight(activeSession)
            if moved then
                activeSession.bumpCooldowns = {}
                local d = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionTimer = d
                activeSession.transitionDuration = d
                activeSession.transitionDir = "strafe_right"
            elseif not activeSession.bumpTimer or activeSession.bumpTimer <= 0 then
                activeSession.bumpTimer = conf("ui", "bumpDuration", 0.12)
                activeSession.bumpCooldowns = activeSession.bumpCooldowns or {}
                activeSession.bumpCooldowns[key] = conf("ui", "bumpCooldown", 0.5)
                activeSession.bumpNudgeKey = key
            end
        elseif key == "space" or key == "return" then
            local frontTile, tx, ty = exploration.getFrontTile(activeSession)
            
            -- Check for coordinate-based events from the map's JSON array
            local eventObj = eventAtMapCell(tx, ty)
            
            if eventObj and (eventObj.trigger == nil or eventObj.trigger == "interact" or eventObj.trigger == "touch") then
                local commands = commandsForMapEvent(eventObj)
                
                if commands then
                    runEventCommands(eventObj, commands)
                end
            end
        end
        
        if moved then
            -- Per-step trait effects (MOVE_HEAL, ...) are data-authored in the
            -- exploration.step flow, so a new per-step trait needs no host
            -- change here. Runs before event/encounter resolution and on every
            -- map, safe or not.
            flow.run("exploration.step", { session = activeSession, party = activeSession.party })
            local triggered = checkStepEvents()
            if not triggered and not isSafeMap() then
                for _, ev in ipairs(flow.run("battle.encounter_check", { session = activeSession })) do
                    if ev.type == "encounter" then triggerBattle() end
                end
            end
        end
        
    elseif scene_host.getCurrent() == "dialogue" then
        local node = activeWalker:getCurrentNode()
        if node then
            if node.type == "TEXT" then
                if key == "space" or key == "return" then
                    -- B.0: a confirm press while text is revealing completes
                    -- it; only a second press advances the dialogue.
                    if renderer.isDialogueRevealing() then
                        renderer.finishDialogueReveal()
                    else
                        local nextNode = node.next
                            and activeWalker.graph
                            and activeWalker.graph.nodes[node.next]
                        if not nextNode or nextNode.type == "ACTION" then
                            clearDialogueMessage()
                        end
                        activeWalker:advance()
                        dialogueSelectIdx = 1
                        handleDialogueAction()
                        if not activeWalker:getCurrentNode() then
                            finishDialogueToMap()
                        end
                    end
                end
            elseif node.type == "CHOICE" then
                if key == "up" or key == "w" then
                    dialogueSelectIdx = (dialogueSelectIdx - 2) % #node.options + 1
                elseif key == "down" or key == "s" then
                    dialogueSelectIdx = dialogueSelectIdx % #node.options + 1
                elseif key == "space" or key == "return" then
                    activeWalker:selectChoice(dialogueSelectIdx)
                    dialogueSelectIdx = 1
                    handleDialogueAction()
                    if not activeWalker:getCurrentNode() then
                        finishDialogueToMap()
                    end
                elseif (key == "escape" or key == "backspace") and node.cancelOption then
                    activeWalker:selectChoice(node.cancelOption)
                    dialogueSelectIdx = 1
                    handleDialogueAction()
                    if not activeWalker:getCurrentNode() then
                        finishDialogueToMap()
                    end
                end
            end
        end
        
    end
end

function love.keypressed(key, scancode, isrepeat)
    local repeat_event = isrepeat or (type(scancode) == "boolean" and scancode)
    if repeat_event then return end
    
    -- If in test battle mode, only handle popup triggers and ignore/block other inputs
    if isTestBattle then
        if key == "space" or key == "p" then
            local bv = require("engine.scenes.battle").getState()
            local b = bv.battle
            if b and activeSession then
                local targets = {}
                for _, e in ipairs(b.enemies) do
                    table.insert(targets, e)
                end
                for _, c in ipairs(activeSession.party) do
                    table.insert(targets, c)
                end
                table.insert(targets, activeSession.summoner)
                
                if #targets > 0 then
                    local target = targets[math.random(#targets)]
                    local isHeal = math.random() < 0.25
                    local val = isHeal and math.random(5, 20) or math.random(5, 30)
                    local isCrit = not isHeal and math.random() < 0.1
                    local txt = isCrit and getPopupFormat("critFormat") or (isHeal and getPopupFormat("healFormat") or getPopupFormat("damageFormat"))
                    txt = txt:gsub("{0}", tostring(val))
                    
                    local x, y = getTargetCoords(target)
                    if x and y then
                        local col = isCrit and getPopupFormat("critColor") or (isHeal and getPopupFormat("healColor") or getPopupFormat("damageColor"))
                        renderer.addDamagePopup(txt, x, y, col)
                        -- E8: exercise smallBattler damage feedback in test mode
                        if not isHeal then
                            local isEnemy = false
                            for _, e in ipairs(b.enemies) do
                                if e == target then isEnemy = true break end
                            end
                            if not isEnemy then
                                renderer.triggerSmallDamage(target)
                            end
                        end
                    end
                end
            end
        end
        return -- Block all other keys from progressing state/crashing
    end
    
    if inputCooldown > 0 then return end
    if key == "f11" then
        local full = not love.window.getFullscreen()
        love.window.setFullscreen(full, "desktop")
        if full then
            print("Fullscreen ON")
        else
            print("Fullscreen OFF")
        end
        return
    end

    if key == "f9" then
        if server.isActive() then
            server.stop()
            print("Developer server stopped.")
        else
            server.start()
        end
        return
    end

    -- Quicksave/quickload: only meaningful while actually playing (the
    -- "map" is the only scene with a resumable position --
    -- see engine/savegame.lua's serializeMap comment), never during the
    -- isTestBattle dev harness (blocked by the early return above).
    if key == "f5" then
        local scene = scene_host.getCurrent()
        if activeSession and scene == "map" then
            savegame.save(activeSession, loader, scene, "quicksave")
            print("Game saved.")
        end
        return
    elseif key == "f6" then
        quickLoad()
        return
    end

    handleKeyPressed(key)
end

-- heldKeys is declared at module level (near inputCooldown); this handler
-- clears the tracked state so the update loop stops repeating on release.
function love.keyreleased(key)
    heldKeys[key] = nil
end

function love.resize(w, h)
    scale = math.min(w / gameWidth, h / gameHeight)
    scale = math.max(1, math.floor(scale))
    scaleX = math.floor((w - gameWidth * scale) / 2)
    scaleY = math.floor((h - gameHeight * scale) / 2)
end
