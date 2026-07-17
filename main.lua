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
require("engine.scenes.battle")
local viewport_3d = require("presentation.viewport_3d")

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
local isPreviewSceneMode = false
local previewSceneId = nil
local isPreviewWindowMode = false
local previewWindowId = nil
local previewWindowMockSpec = nil
local isPreviewFontMode = false
local previewFontName = nil
local previewFontSize = nil
local isGoldenMode = false
local isGoldenUIMode = false
local triggerTestBattle
local runValidation

-- Scene States Cache
local townSelectedIdx = 1

-- Battle State now lives entirely in scene_host (engine/scenes/battle.lua,
-- accessed via v.*). The former main.lua battle globals were removed after
-- the battle->scene migration; nothing referenced them.

-- Dialogue State
local activeWalker
local dialogueSelectIdx = 1

-- Menu State


local inputCooldown = 0

local server = require("engine.server")
config = require("engine.config")

-- Config accessor with fallback for missing keys
local function conf(group, key, default)
    local g = config[group]
    if g and g[key] ~= nil then return g[key] end
    return default
end

-- Database validation for `lovec . validate`: cross-reference integrity plus
-- a scripted battle round, so data edits can be smoke-tested headlessly.

-- Golden-master battle log validation

-- Golden-master UI log validation: drives a scripted input sequence through
-- each scene in the registry via scene_host, capturing the normalized UI
-- event log. Events are logged in `window|action|target|value` format between
-- UI GOLDEN BEGIN/END markers (matching the pattern used by capture scripts).
-- Deterministic mock session shared by the golden-ui harness and the E5
-- scene preview: fixed seed, starting party, crafting ingredients in
-- inventory so list-driven scenes have real content to show.
local function makeHarnessSession()
    math.randomseed(12345)
    local vSession = session.GameSession.new(loader)
    vSession:initializeStartingParty()
    -- Give inventory items so crafting scenes have ingredients to select
    for _, item in ipairs(loader.items or {}) do
        if item.meta and item.meta.craftKind then
            vSession:addItem(item.id, 3)
        end
    end
    vSession:addItem(1, 5) -- HP Tonic
    return vSession
end

local function runPreviewAnim(animId, animJson, spritePath)
    local json = require("data.json")
    local payload
    local ok, err = pcall(function()
        local animDef = {}
        if animJson and animJson ~= "" then
            local decoded = json.decode(animJson)
            if type(decoded) == "table" then animDef = decoded end
        end

        -- Ensure loader animations contains the previewed anim definition
        loader.animations = loader.animations or {}
        loader.animations[animId] = animDef

        -- Reload animation player
        local animation_player = require("presentation.animation_player")
        animation_player.load(loader.animations)

        -- Load dummy battler sprite. Parse [k=v] tokens (fps/speed) the same
        -- way presentation/small_battlers does, then strip them to get the
        -- real file path — so animated sheets preview animated.
        local spriteOverrides = {}
        local cleanPath = (spritePath or ""):gsub("%[([^=]+)=([^%]]+)%]", function(k, v)
            spriteOverrides[k] = tonumber(v) or v
            return ""
        end)
        cleanPath = cleanPath:gsub("^%s*(.-)%s*$", "%1")

        local texture
        if cleanPath ~= "" and love.filesystem.getInfo(cleanPath) then
            texture = love.graphics.newImage(cleanPath)
        end
        if not texture then
            texture = love.graphics.newImage("assets/smallBattlers/pixie.png") -- fallback
        end
        texture:setFilter("nearest", "nearest")

        -- Frame slicing: square cells laid out in a row (matches the
        -- small_battlers convention). Idle animation advances by the sheet's
        -- fps (or speed*4, default 4) and loops across the preview.
        local texW, texH = texture:getDimensions()
        local cellH = texH
        local cellW = math.min(texW, cellH)
        local numFrames = math.max(1, math.floor(texW / cellW))
        local spriteRate = spriteOverrides.fps or (spriteOverrides.speed and 4 * spriteOverrides.speed) or 4
        local spriteQuad = love.graphics.newQuad(0, 0, cellW, cellH, texW, texH)

        local dummyTarget = { name = "dummy" }

        -- Run rendering steps at 20 FPS (0.05s intervals)
        local step = 0.05
        local durationMs = animDef.duration or 1000
        local duration = durationMs / 1000
        local elapsed = 0
        local frames = {}

        local previewCanvas = love.graphics.newCanvas(240, 240)
        local ui = require("presentation.ui")
        ui.init()

        -- Gradient-map shader: shared module (same shader used in battle).
        local gradient_shader = require("presentation.gradient_shader")

        animation_player.reset()
        animation_player.play(animId, dummyTarget)

        while elapsed <= duration do
            love.graphics.setCanvas({ previewCanvas, stencil = true })
            -- Opaque black, not transparent: additive blend tracks contribute
            -- no alpha, so on a transparent canvas blend-heavy animations
            -- (damage flash, death) would encode as fully invisible pixels.
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.setColor(1, 1, 1, 1)

            -- Query active transform, tint, blend and shake
            local tf = animation_player.getTransform(dummyTarget)
            local tint = animation_player.getTint(dummyTarget)
            local blendMode = animation_player.getBlendMode(dummyTarget) or "alpha"
            local shakeX = animation_player.getShakeOffset(dummyTarget)

            -- Center dummy sprite in a 240x240 canvas (anchor bottom-center).
            -- Pick the current animation frame from the sheet.
            local frame = math.floor(elapsed * spriteRate) % numFrames
            spriteQuad:setViewport(frame * cellW, 0, cellW, cellH)
            local drawX = 120 + tf.offsetX + shakeX
            local drawY = 160 + tf.offsetY -- draw baseline at Y=160

            -- Sprite drawing function for stencil test
            local function drawSprite()
                love.graphics.draw(texture, spriteQuad, drawX, drawY, 0, tf.scaleX, tf.scaleY, cellW / 2, cellH)
            end

            -- Back-layer particles render behind the sprite.
            love.graphics.setColor(1, 1, 1, 1)
            animation_player.drawParticles(dummyTarget, drawX, drawY, drawSprite, "back")

            -- Sprite through tint + gradient-map shader (if active).
            love.graphics.setBlendMode(blendMode)
            if tint then
                love.graphics.setColor(tint.color[1], tint.color[2], tint.color[3], tint.alpha)
            else
                love.graphics.setColor(1, 1, 1, 1)
            end
            gradient_shader.drawWithGradient(dummyTarget, drawSprite, animation_player)


            -- Front-layer particles render on top of the sprite.
            love.graphics.setColor(1, 1, 1, 1)
            animation_player.drawParticles(dummyTarget, drawX, drawY, drawSprite, "front")

            -- Full-screen flash overlay, above everything.
            local flash = animation_player.getScreenFlash(dummyTarget)
            if flash then
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], flash.alpha)
                love.graphics.rectangle("fill", 0, 0, 240, 240)
            end

            -- Reset graphics state
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(1, 1, 1, 1)

            -- Encode frame to PNG base64
            love.graphics.setCanvas()
            local fileData = previewCanvas:newImageData():encode("png")
            local b64 = love.data.encode("string", "base64", fileData)
            table.insert(frames, b64)

            -- Advance time
            animation_player.update(step)
            animation_player.updateParticles(step)
            elapsed = elapsed + step
        end

        payload = {
            animId = animId,
            frames = frames,
            gameWidth = 240,
            gameHeight = 240
        }
    end)
    if not ok then payload = { error = tostring(err) } end
    print("PREVIEW BEGIN")
    print(json.encode(payload))
    print("PREVIEW END")
end

-- E5: headless scene preview (`lovec . preview-scene <id>`). Pushes the
-- scene with the mock session, runs on_enter through the real interpreter,
-- and prints the MATERIALIZED window state (window_renderer.resolveState:
-- geometry + resolved rows/text/cursor) as one JSON document between
-- PREVIEW BEGIN/END markers. Errors become an { error } payload, never a
-- crash — a broken scene is when the author needs the preview most.
local function runPreviewScene(sceneId)
    local json = require("data.json")
    local payload
    local ok, err = pcall(function()
        local vSession = makeHarnessSession()
        local sceneDef
        for _, sc in ipairs(loader.scenes or {}) do
            if tostring(sc.id) == tostring(sceneId) then sceneDef = sc break end
        end
        if not sceneDef then
            payload = { error = "scene not found: " .. tostring(sceneId) }
            return
        end
        local sh = require("engine.scene_host")
        local ctx = { session = vSession, loader = loader, party = vSession.party, events = {} }
        sh.init(nil)
        sh.push(sceneDef.id, ctx) -- push runs on_enter when given a ctx

        -- The shop scene's v-state is seeded by openShop in-game; give the
        -- preview the equivalent (first shop by sorted key, deterministic)
        -- so its windows show real content instead of an empty list.
        if tostring(sceneDef.id) == "shop" then
            local st = sh.getCurrentState()
            if st and (st.v.items == nil or #st.v.items == 0) then
                local keys = {}
                for k in pairs(loader.shops or {}) do table.insert(keys, tostring(k)) end
                table.sort(keys)
                local shopData = keys[1] and loader.shops[keys[1]]
                if shopData then
                    st.v.shopName = shopData.name or "Shop"
                    st.v.items = {}
                    for _, shopItem in ipairs(shopData.items or {}) do
                        local itemData = loader.getItem(shopItem.id)
                        if itemData then
                            table.insert(st.v.items, {
                                id = itemData.id,
                                name = itemData.name or "",
                                icon = itemData.icon or 0,
                                description = itemData.description or "",
                                cost = shopItem.price or itemData.cost or 0,
                            })
                        end
                    end
                    st.v.count = #st.v.items
                end
            end
        end

        local wr = require("presentation.window_renderer")
        payload = wr.resolveState(sh.getCurrentState(), sceneDef, ctx)
        payload.sceneId = sceneDef.id
        payload.sceneName = sceneDef.name or ""
        payload.gameWidth = gameWidth
        payload.gameHeight = gameHeight

        -- 1:1 frame (owner feedback 10.07.2026): render the scene through
        -- the REAL presentation stack — windowskin, font, spacing — exactly
        -- like the golden-ui draw smoke does, and embed the PNG as base64.
        -- The JSON metadata above remains the hit-testing/edit model; the
        -- image is what the author sees. frameKind tells the editor which
        -- path produced it:
        --   "windows"     scene_host.draw ("draw": "windows" scenes)
        --   "legacy"      the same legacy renderer call love.draw makes for
        --                 this built-in id (menu/shop), with neutral state
        --   "declarative" the hook-declared windows via the window renderer
        --                 (built-in stubs like items/status whose real
        --                 in-game look is still legacy code inside the menu)
        do
            local okDraw, imgOrErr = pcall(function()
                local ui = require("presentation.ui")
                ui.init()
                local previewCanvas = love.graphics.newCanvas(gameWidth, gameHeight)
                love.graphics.setCanvas({ previewCanvas, stencil = true })
                love.graphics.clear(0, 0, 0, 1)
                love.graphics.setColor(1, 1, 1, 1)
                if sh.draw(ctx) then
                    payload.frameKind = "windows"
                else
                    renderer.init(vSession)
                    -- Settle the menu slide-in animation so panels are in
                    -- their resting position, exactly as after ~2s in-game.
                    renderer.update(1)
                    renderer.update(1)
                    local wrMod = require("presentation.window_renderer")
                    wrMod.draw(sh.getCurrentState(), sceneDef, ctx)
                    payload.frameKind = "declarative"
                end
                love.graphics.setCanvas()
                local fileData = previewCanvas:newImageData():encode("png")
                return love.data.encode("string", "base64", fileData)
            end)
            if okDraw then
                payload.image = imgOrErr
            else
                love.graphics.setCanvas()
                payload.imageError = tostring(imgOrErr)
            end
        end
    end)
    if not ok then payload = { error = tostring(err) } end
    print("PREVIEW BEGIN")
    print(json.encode(payload))
    print("PREVIEW END")
end

-- E12: headless SINGLE-WINDOW preview (`lovec . preview-window <windowId>
-- [mockSpecJSON]`) for the reusable-window editor tab. A raw windowLayout
-- entry has no scene — no hooks ever run — so this bypasses scene_host
-- entirely and builds a minimal one-window state directly from an
-- editor-supplied mock spec (list source / sample text / cursor), never
-- written to any data file. wr.draw/wr.resolveState are already generic
-- over state.winState/windowOrder (D13's "no scene-specific code" rule
-- paying off) so NO window_renderer.lua changes were needed to support
-- this — same resolution/render code path as the per-scene preview.
--
-- mockSpec fields (all optional): listId, format, priority, highlight,
-- sprite, gaugeValue, gaugeMax, gaugeColor, gaugeFill, text, cursor,
-- v (seeds flow-local vars for {v.x} expressions), config (seeds a
-- scene-config-shaped table for "config:key" list sources), siblings
-- (optional: { windowId = <mockWin fields>, ... } — a window that reads
-- sel('otherWindow') sees nil in true isolation, since sel() resolves
-- against whatever's in this preview's own state; listing just the
-- window(s) it depends on here resolves that WITHOUT turning this into a
-- full scene preview — only the windows the author explicitly listed
-- exist).
local function buildMockWin(spec)
    return {
        open = true,
        listId = spec.listId,
        format = spec.format,
        priority = spec.priority,
        highlight = spec.highlight,
        sprite = spec.sprite,
        gaugeValue = spec.gaugeValue,
        gaugeMax = spec.gaugeMax,
        gaugeColor = spec.gaugeColor,
        gaugeFill = spec.gaugeFill,
        text = spec.text,
        cursor = spec.cursor or 1,
    }
end

local function runPreviewWindow(windowId, mockSpecJSON)
    local json = require("data.json")
    local payload
    local ok, err = pcall(function()
        local spec = {}
        if mockSpecJSON and mockSpecJSON ~= "" then
            local decoded = json.decode(mockSpecJSON)
            if type(decoded) == "table" then spec = decoded end
        end

        local vSession = makeHarnessSession()
        local winState = { [windowId] = buildMockWin(spec) }
        local windowOrder = { windowId }
        for siblingId, siblingSpec in pairs(spec.siblings or {}) do
            winState[siblingId] = buildMockWin(siblingSpec)
            table.insert(windowOrder, siblingId)
        end
        local state = {
            v = spec.v or {},
            winState = winState,
            windowOrder = windowOrder,
        }
        -- Not a real scene: only .config is read (by the "config:key" list
        -- source), so a bare table with that one field is sufficient.
        local sceneData = { config = spec.config or {} }
        local ctx = { session = vSession, loader = loader, party = vSession.party, events = {} }

        local wr = require("presentation.window_renderer")
        payload = wr.resolveState(state, sceneData, ctx)
        payload.windowId = windowId
        payload.gameWidth = gameWidth
        payload.gameHeight = gameHeight

        local okDraw, imgOrErr = pcall(function()
            local ui = require("presentation.ui")
            ui.init()
            local previewCanvas = love.graphics.newCanvas(gameWidth, gameHeight)
            love.graphics.setCanvas({ previewCanvas, stencil = true })
            love.graphics.clear(0, 0, 0, 1)
            love.graphics.setColor(1, 1, 1, 1)
            wr.draw(state, sceneData, ctx)
            love.graphics.setCanvas()
            local fileData = previewCanvas:newImageData():encode("png")
            return love.data.encode("string", "base64", fileData)
        end)
        if okDraw then
            payload.image = imgOrErr
        else
            love.graphics.setCanvas()
            payload.imageError = tostring(imgOrErr)
        end
    end)
    if not ok then payload = { error = tostring(err) } end
    print("PREVIEW BEGIN")
    print(json.encode(payload))
    print("PREVIEW END")
end

-- Font picker preview (`lovec . preview-font <name> <size>`): draws a real
-- ui.drawPanel + ui.drawString sample using the actual engine 9-slice
-- windowskin and the requested font, so the editor's picker shows exactly
-- what the game will render instead of an approximation. name/size are
-- NOT written to config — this only overrides the in-memory font for the
-- one screenshot.
local function runPreviewFont(name, size)
    local json = require("data.json")
    local payload = {}
    local ok, err = pcall(function()
        local ui = require("presentation.ui")
        ui.init()
        ui.setFont(name, size)

        local pw, ph = 240, 64
        local previewCanvas = love.graphics.newCanvas(pw, ph)
        love.graphics.setCanvas(previewCanvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setColor(1, 1, 1, 1)
        ui.drawPanel(4, 4, pw - 8, ph - 8)
        ui.drawString("The Quick Brown Fox 0123", 12, 16)
        ui.drawString("HP 42/50  ATK 10  DEF 8", 12, 16 + ui.lineHeight + 4)
        love.graphics.setCanvas()

        local fileData = previewCanvas:newImageData():encode("png")
        payload.image = love.data.encode("string", "base64", fileData)
        payload.width = pw
        payload.height = ph
    end)
    if not ok then payload = { error = tostring(err) } end
    print("PREVIEW BEGIN")
    print(json.encode(payload))
    print("PREVIEW END")
end

local function runGoldenUI()
    local LOGGED_EVENT_TYPES = {
        open_window = true,
        close_window = true,
        set_text = true,
        set_list = true,
        set_cursor = true,
        focus_window = true
    }
    local vSession = makeHarnessSession()

    local scene_host = require("engine.scene_host")
    local interpreter = require("engine.interpreter")

    local originalRunImmediate = interpreter.runImmediate

    -- Scene input scripts live in scene data (scenes.json → goldenScript):
    -- a list of { key } steps that drive the scene's state machine through
    -- scene_host.keypressed(). Extra scenes get golden coverage by authoring
    -- a goldenScript, with no engine edits.

    for _, sceneDef in ipairs(loader.scenes or {}) do
        local sceneId = sceneDef.id
        if not sceneId then goto continue end

        local uiEvents = {}
        local currentCtx = {
            session = vSession,
            loader = loader,
            -- Hooks see the same ctx shape gameplay pushes (party.count
            -- formulas were silently false without this).
            party = vSession.party,
            events = {}
        }

        -- Track event count so we only log NEW events each hook call,
        -- not the entire accumulated ctx.events.
        local loggedEventCount = 0

        local function logNewEvents(events)
            if not events then return end
            for i = loggedEventCount + 1, #events do
                local ev = events[i]
                if LOGGED_EVENT_TYPES[ev.type] then
                    local w = ev.windowId or ""
                    local a = ev.type or ""
                    local t = ""
                    local v = ""
                    if ev.type == "set_text" then v = tostring(ev.text)
                    elseif ev.type == "set_list" then v = tostring(ev.listId)
                    elseif ev.type == "set_cursor" then v = tostring(ev.index) end
                    table.insert(uiEvents, string.format("%s|%s|%s|%s", w, a, t, v))
                end
            end
            loggedEventCount = #events
        end

        interpreter.runImmediate = function(cmds, ctx)
            local events = originalRunImmediate(cmds, ctx)
            logNewEvents(events)
            return events
        end

        scene_host.init(sceneId)

        -- Initialize scene state BEFORE driving the input sequence.
        -- on_enter sets v.state, v.idx, etc. so directional/confirm hooks
        -- operate on initialized variables.
        if sceneDef.hooks and next(sceneDef.hooks) then
            scene_host.runHook("on_enter", currentCtx)
        else
            -- Pre-seed uiEvents so the log shows on_enter:absent even
            -- when no events were generated
            table.insert(uiEvents, string.format("scene|%s|hook|on_enter:absent", tostring(sceneId)))
        end

        -- Drive the scripted input sequence
        local script = sceneDef.goldenScript or {}
        local stepIndex = 0
        for _, step in ipairs(script) do
            scene_host.update(0.1, currentCtx)
            scene_host.keypressed(step.key, currentCtx)

            -- Draw smoke test: scenes with declarative drawing exercise the
            -- window renderer at every step so a bad binding fails validate,
            -- not gameplay. Each step is rendered to an offscreen canvas and
            -- saved to the LOVE save directory (golden_ui_<scene>_<step>.png)
            -- for visual inspection. Prints stay outside the UI GOLDEN
            -- markers, so reference logs are unaffected.
            if sceneDef.draw == "windows" then
                stepIndex = (stepIndex or 0) + 1
                local okDraw, drawErr = pcall(function()
                    local smokeCanvas = love.graphics.newCanvas(256, 240)
                    love.graphics.setCanvas(smokeCanvas)
                    love.graphics.clear(0, 0, 0, 1)
                    love.graphics.setColor(1, 1, 1, 1)
                    scene_host.draw(currentCtx)
                    love.graphics.setCanvas()
                    smokeCanvas:newImageData():encode("png",
                        string.format("golden_ui_%s_%02d.png", tostring(sceneId), stepIndex))
                end)
                if not okDraw then
                    error("golden-ui draw smoke failed for scene '" .. tostring(sceneId) .. "': " .. tostring(drawErr), 0)
                end
            end
        end

        print("UI GOLDEN BEGIN")
        print(string.format("scene|%s|name|%s", tostring(sceneId), sceneDef.name or ""))

        for _, l in ipairs(uiEvents) do
            print(l)
        end
        print("UI GOLDEN END")
    end
    ::continue::

    interpreter.runImmediate = originalRunImmediate
end

local function runGolden()
    math.randomseed(12345)

    local vSession = session.GameSession.new(loader)

    -- Explicitly construct party and enemies
    vSession.party = {}

    -- Fixed party: High Pixie (2), Skeleton (3), Angel (4)
    local actIds = {2, 3, 4}
    for _, id in ipairs(actIds) do
        local actorData = loader.getActor(id)
        if actorData then
            local b = session.Battler.new(actorData, 1)
            b.hp = b:getMaxHp(vSession)
            table.insert(vSession.party, b)
        end
    end

    local enemies = {}
    for i=1, 3 do
        local enemyData = loader.getActor(1) -- Pixie
        if enemyData then
            local b = session.Battler.new(enemyData, 1)
            b.hp = b:getMaxHp(vSession)
            table.insert(enemies, b)
        end
    end

    local vBattle = battleSystem.Battle.new(vSession, enemies)

    local function logEvents(events)
        for _, ev in ipairs(events) do
            local t = ev.type or ""
            local a = ev.actor and ev.actor.name or ""
            local trg = ev.target and ev.target.name or ""
            local v = ev.value or ""
            local s = ev.state or ""
            print(string.format("%s|%s|%s|%s|%s", t, a, trg, tostring(v), s))
        end
    end

    print("GOLDEN BEGIN")

    -- overhaul-6 F1: the summoner is not a battle participant. All actions
    -- are indexed 1-4 directly by active-creature slot (no more +1 offset
    -- for a summoner-first instant action). This fixture uses a 3-member
    -- party (High Pixie, Skeleton, Angel).

    -- Round 1: all attack
    local actionsR1 = {}
    for i=1, 3 do
        if vSession.party[i] then
            actionsR1[i] = { type = "attack", target = enemies[1] }
        end
    end
    logEvents(vBattle:resolveRound(actionsR1))

    -- Round 2: skill (High Pixie casts its own soothingMote on itself) +
    -- defend (party[2]) + attack (party[3]). soothingMote used to arrive
    -- here as a summoner "spell"; the mechanic is gone (Summoner rework),
    -- but the same skill cast by its owner keeps the golden log identical.
    local actionsR2 = {}
    if vSession.party[1] then
        actionsR2[1] = { type = "skill", id = "soothingMote", target = vSession.party[1] }
    end

    if vSession.party[2] then actionsR2[2] = { type = "defend", target = vSession.party[2] } end
    if vSession.party[3] then actionsR2[3] = { type = "attack", target = enemies[2] } end

    logEvents(vBattle:resolveRound(actionsR2))

    -- Round 3: flee (party[1]) + attacks (party[2], party[3])
    local actionsR3 = {}
    if vSession.party[1] then actionsR3[1] = { type = "flee" } end
    if vSession.party[2] then actionsR3[2] = { type = "attack", target = enemies[2] } end
    if vSession.party[3] then actionsR3[3] = { type = "attack", target = enemies[2] } end
    logEvents(vBattle:resolveRound(actionsR3))

    -- One victory resolution against a 1-HP enemy
    local vSessionVic = session.GameSession.new(loader)
    vSessionVic.party = {}
    local bVic = session.Battler.new(loader.getActor(2), 1)
    bVic.hp = bVic:getMaxHp(vSessionVic)
    table.insert(vSessionVic.party, bVic)

    local enemiesVic = {}
    local bVicEnm = session.Battler.new(loader.getActor(1), 1)
    bVicEnm.hp = 1
    table.insert(enemiesVic, bVicEnm)

    local vBattleVic = battleSystem.Battle.new(vSessionVic, enemiesVic)
    local actionsVic = {}
    actionsVic[1] = { type = "attack", target = enemiesVic[1] }
    logEvents(vBattleVic:resolveRound(actionsVic))

    print("GOLDEN END")
end

runValidation = function()
    local problems = {}
    local function check(cond, msg)
        if not cond then table.insert(problems, msg) end
        return cond
    end

    -- Registry lookup sets from data/engine.json
    local validEffectTypes = {}
    for _, et in ipairs((loader.engine and loader.engine.effectTypes) or {}) do
        validEffectTypes[et.id] = true
    end
    local validTraitCodes = {}
    for _, tc in ipairs((loader.engine and loader.engine.traitCodes) or {}) do
        validTraitCodes[tc.code] = true
    end

    -- Meta system validation (C10)
    local registeredMeta = {}
    for _, mk in ipairs((loader.engine and loader.engine.metaKeys) or {}) do
        local applies = {}
        for _, coll in ipairs(mk.appliesTo or {}) do
            applies[coll] = true
        end
        registeredMeta[mk.key] = {
            type = mk.type,
            appliesTo = applies
        }
    end

    local undeclaredWarnings = 0
    local function validateMeta(metaObj, collName, entryId)
        if not metaObj then return end
        for k, v in pairs(metaObj) do
            local reg = registeredMeta[k]
            if reg then
                if not reg.appliesTo[collName] then
                    check(false, "meta key '" .. tostring(k) .. "' does not apply to collection '" .. collName .. "' (on entry '" .. tostring(entryId) .. "')")
                else
                    local ok = false
                    if reg.type == "number" then
                        ok = (type(v) == "number")
                    elseif reg.type == "string" then
                        ok = (type(v) == "string")
                    elseif reg.type == "flag" then
                        ok = (type(v) == "boolean")
                    end
                    check(ok, "meta key '" .. tostring(k) .. "' on entry '" .. tostring(entryId) .. "' in '" .. collName .. "' has wrong type (expected " .. reg.type .. ", got " .. type(v) .. ")")
                end
            else
                print("[validator] warning: undeclared meta key '" .. tostring(k) .. "' on entry '" .. tostring(entryId) .. "' in '" .. collName .. "'")
                undeclaredWarnings = undeclaredWarnings + 1
            end
        end
    end

    for _, actor in ipairs(loader.actors or {}) do
        validateMeta(actor.meta, "actors", actor.id or actor.name or "?")
    end
    for _, item in ipairs(loader.items or {}) do
        validateMeta(item.meta, "items", item.id or item.name or "?")
    end
    for _, ce in ipairs(loader.commonEvents or {}) do
        validateMeta(ce.meta, "commonEvents", ce.id or ce.name or "?")
    end

    local dictColls = {
        elements = loader.elements,
        maps = loader.maps,
        quests = loader.quests,
        shops = loader.shops,
        sounds = loader.sounds,
        themes = loader.themes,
        skills = loader.skills,
        passives = loader.passives,
        states = loader.states,
        roles = loader.roles
    }
    for collName, dict in pairs(dictColls) do
        for id, entry in pairs(dict or {}) do
            validateMeta(entry.meta, collName, id)
        end
    end

    if undeclaredWarnings > 0 then
        print("[validator] total undeclared meta warnings: " .. undeclaredWarnings)
    end
    local function checkTraits(traitList, ownerDesc)
        for _, tr in ipairs(traitList or {}) do
            check(validTraitCodes[tr.code], ownerDesc .. " uses unregistered trait code '" .. tostring(tr.code) .. "'")
        end
    end
    local function checkEffects(effList, ownerDesc)
        for _, eff in ipairs(effList or {}) do
            check(validEffectTypes[eff.type], ownerDesc .. " uses unregistered effect type '" .. tostring(eff.type) .. "'")
            if eff.type == "add_status" then
                check(loader.getState(eff.status), ownerDesc .. " references missing state '" .. tostring(eff.status) .. "'")
            end
        end
    end

    -- Actors must reference existing skills/passives/elements/roles
    for _, actor in ipairs(loader.actors) do
        for _, skId in ipairs(actor.skills or {}) do
            check(loader.getSkill(skId), "actor " .. tostring(actor.id) .. " references missing skill '" .. tostring(skId) .. "'")
        end
        for _, pId in ipairs(actor.passives or {}) do
            check(loader.getPassive(pId), "actor " .. tostring(actor.id) .. " references missing passive '" .. tostring(pId) .. "'")
        end
        for _, el in ipairs(actor.elements or {}) do
            check(loader.getElement(el), "actor " .. tostring(actor.id) .. " references missing element '" .. tostring(el) .. "'")
        end
        if actor.role then
            check(loader.getRole(actor.role), "actor " .. tostring(actor.id) .. " references missing role '" .. tostring(actor.role) .. "'")
        end
        checkTraits(actor.traits, "actor " .. tostring(actor.id))
    end

    -- Skills: effect types, states and elements must exist
    for id, skill in pairs(loader.skills) do
        checkEffects(skill.effects, "skill '" .. tostring(id) .. "'")
        if skill.element then
            check(loader.getElement(skill.element), "skill '" .. tostring(id) .. "' references missing element '" .. tostring(skill.element) .. "'")
        end
    end

    -- Passives/states/items: trait codes must be registered
    for id, passive in pairs(loader.passives) do
        checkTraits(passive.traits, "passive '" .. tostring(id) .. "'")
    end
    for id, state in pairs(loader.states) do
        checkTraits(state.traits, "state '" .. tostring(id) .. "'")
    end
    for _, item in ipairs(loader.items) do
        checkTraits(item.traits, "item " .. tostring(item.id))
        checkEffects(item.effects, "item " .. tostring(item.id))
    end

    -- Elements: affinity lists must point at registered elements
    for id, elem in pairs(loader.elements or {}) do
        for _, other in ipairs(elem.strongAgainst or {}) do
            check(loader.getElement(other), "element '" .. tostring(id) .. "' strongAgainst missing element '" .. tostring(other) .. "'")
        end
        for _, other in ipairs(elem.weakAgainst or {}) do
            check(loader.getElement(other), "element '" .. tostring(id) .. "' weakAgainst missing element '" .. tostring(other) .. "'")
        end
    end

    -- System config references
    local sys = loader.system or {}
    local combat = sys.combat or {}
    check(loader.getSkill(combat.defendSkillId or "defend"), "combat.defendSkillId references a missing skill")
    check(loader.getSkill(combat.attackSkillId or "attack"), "combat.attackSkillId references a missing skill")
    check(loader.getItem(combat.battleItem or 1), "combat.battleItem references a missing item")
    for i, opt in ipairs((sys.town and sys.town.options) or {}) do
        check(opt.label and opt.action, "town option #" .. i .. " is missing label/action")
    end

    -- Shop stock must reference existing items
    for shopId, shop in pairs(loader.shops or {}) do
        for _, stock in ipairs(shop.items or {}) do
            check(loader.getItem(stock.id), "shop " .. tostring(shopId) .. " stocks missing item '" .. tostring(stock.id) .. "'")
        end
    end

    -- Event scriptId links must resolve to a common event
    for _, map in ipairs(loader.maps or {}) do
        for _, ev in ipairs(map.events or {}) do
            if ev.scriptId then
                check(loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)] ~= nil,
                    "map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) ..
                    ") references missing common event '" .. tostring(ev.scriptId) .. "'")
            end
        end
    end

    -- Quest requirement/reward items must exist
    for qId, quest in pairs(loader.quests or {}) do
        for _, req in ipairs((quest.requirements or {}).items or {}) do
            check(loader.getItem(req.id), "quest '" .. tostring(qId) .. "' requires missing item '" .. tostring(req.id) .. "'")
        end
        for _, rew in ipairs((quest.rewards or {}).items or {}) do
            check(loader.getItem(rew.id), "quest '" .. tostring(qId) .. "' rewards missing item '" .. tostring(rew.id) .. "'")
        end
    end

    -- Conversation graphs (data/graphs/*.json): every node link must resolve
    -- and quest actions must reference quests.json entries. Graphs load ad
    -- hoc at runtime (director.startConversation), so a broken link only
    -- surfaces mid-dialogue without this sweep.
    do
        local json = require("data.json")
        for _, f in ipairs(love.filesystem.getDirectoryItems("data/graphs")) do
            if f:match("%.json$") then
                local contents = love.filesystem.read("data/graphs/" .. f)
                local okG, graph = pcall(json.decode, contents)
                if check(okG and type(graph) == "table", "graph '" .. f .. "' is not valid JSON")
                    and type(graph.nodes) == "table" then
                    local nodes = graph.nodes
                    check(graph.initialNode == nil or nodes[graph.initialNode] ~= nil,
                        "graph '" .. f .. "' initialNode '" .. tostring(graph.initialNode) .. "' does not exist")
                    for id, node in pairs(nodes) do
                        for _, key in ipairs({ "next", "trueNode", "falseNode" }) do
                            local link = node[key]
                            check(link == nil or nodes[link] ~= nil,
                                "graph '" .. f .. "' node '" .. tostring(id) .. "' links to missing node '" .. tostring(link) .. "'")
                        end
                        for _, opt in ipairs(node.options or {}) do
                            check(opt.target == nil or nodes[opt.target] ~= nil,
                                "graph '" .. f .. "' node '" .. tostring(id) .. "' choice links to missing node '" .. tostring(opt.target) .. "'")
                        end
                        for _, br in ipairs(node.branches or {}) do
                            check(br.target == nil or nodes[br.target] ~= nil,
                                "graph '" .. f .. "' node '" .. tostring(id) .. "' branch links to missing node '" .. tostring(br.target) .. "'")
                        end
                        if node.action == "OFFER_QUEST" or node.action == "COMPLETE_QUEST" then
                            check(loader.quests and loader.quests[tostring(node.questId)] ~= nil,
                                "graph '" .. f .. "' node '" .. tostring(id) .. "' references missing quest '" .. tostring(node.questId) .. "'")
                        end
                    end
                end
            end
        end
    end

    -- Simulated battle round with a starting party
    local vSession = session.GameSession.new(loader)
    vSession:initializeStartingParty()
    check(#vSession.party > 0, "new game produced an empty party")

    local enemyData = loader.getActor(1)
    if check(enemyData, "actor id 1 missing (needed for validation battle)") then
        local enemy = session.Battler.new(enemyData, 1)
        enemy.hp = enemy:getMaxHp(vSession)
        local vBattle = battleSystem.Battle.new(vSession, { enemy })

        -- Actions are slot-indexed 1-4 (no summoner slot; the old +1 offset
        -- and the "spell" opener died with the summoner-spell mechanic).
        local actions = {}
        for i = 1, 4 do
            if vSession.party[i] then
                actions[i] = { type = (i == 1) and "defend" or "attack", target = enemy }
            end
        end
        local events = vBattle:resolveRound(actions)
        check(#events > 0, "battle round produced no events")
    end

    -- Summoner rework: emergency wave, row defaults, REAP_FALLEN permadeath
    do
        local s = session.GameSession.new(loader)
        -- Level 3: a level-1 spirit's totalExp is 0, which would make the
        -- bank check vacuous.
        local function mk(id)
            local b = session.Battler.new(loader.getActor(id), 3)
            b.hp = b:getMaxHp(s)
            return b
        end
        s.party = { mk(2), mk(3), mk(4) }
        s.reserve = { mk(2), mk(3) }
        local wb = battleSystem.Battle.new(s, { mk(1) })
        check(s.party[1].row == "front" and s.party[3].row == "back",
            "Battle.new did not assign default rows by slot (1-2 front, 3-4 back)")

        -- Wipe the fielded party; the wave must deploy the whole reserve
        for i = 1, 3 do
            s.party[i].hp = 0
            s.party[i]:addState("dead")
        end
        local evs = {}
        check(wb:tryDeployWave(evs), "emergency wave did not deploy with reserves available")
        check(s.party[1] and not s.party[1]:isDead() and s.party[2] and not s.party[2]:isDead(),
            "emergency wave did not field the reserve spirits")
        check(next(s.reserve) == nil, "emergency wave left spirits in the reserve")
        check(#wb.fallen == 3, "emergency wave did not move the fallen party to battle.fallen")
        local sawWave = false
        for _, ev in ipairs(evs) do if ev.type == "wave" then sawWave = true end end
        check(sawWave, "emergency wave emitted no wave event")

        -- REAP_FALLEN: banks wave casualties + any dead party member, emits
        -- one reap event per fallen spirit carrying the battler as target
        -- (the presentation layer animates/captions each individually)
        s.party[2].hp = 0
        s.party[2]:addState("dead")
        local deadSpirit = s.party[2]
        local bankBefore = s.expBank or 0
        local okReap, reapEvs = pcall(interpreter.runImmediate,
            { { cmd = "REAP_FALLEN" } }, { session = s, battle = wb, loader = loader })
        check(okReap, "REAP_FALLEN failed: " .. tostring(reapEvs))
        if okReap then
            check((s.expBank or 0) > bankBefore, "REAP_FALLEN banked no EXP for the fallen")
            check(#wb.fallen == 0, "REAP_FALLEN did not clear battle.fallen")
            check(s.party[2] == nil, "REAP_FALLEN left a dead spirit in the party")
            check(s.party[1] ~= nil, "REAP_FALLEN removed a living spirit")
            check(#reapEvs == 4, "REAP_FALLEN should emit one reap event per fallen spirit (3 wave casualties + 1), got " .. tostring(#reapEvs))
            local sawTarget = false
            for _, ev in ipairs(reapEvs) do
                check(ev.type == "reap", "REAP_FALLEN emitted a non-reap event: " .. tostring(ev.type))
                if ev.target == deadSpirit then sawTarget = true end
            end
            check(sawTarget, "REAP_FALLEN's reap events did not carry the fallen battler as target")
        end

        -- Auto-field: reaping the whole party redeploys the reserve instead
        -- of leaving it empty (session:autoFieldIfEmpty, called by
        -- REAP_FALLEN). Wipe the newly-fielded party and reap again with an
        -- empty reserve to confirm the party is simply left empty then.
        for i = 1, 4 do
            if s.party[i] then s.party[i].hp = 0; s.party[i]:addState("dead") end
        end
        check(not s:isPartyEmpty(), "sanity: party should not read empty before the reap")
        interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, { session = s, battle = wb, loader = loader })
        check(s:isPartyEmpty(), "REAP_FALLEN with no reserve should leave the party empty")
        check(not s:autoFieldIfEmpty(), "autoFieldIfEmpty deployed from an empty reserve")

        -- With an empty reserve the wave must refuse (defeat stands)
        check(not wb:tryDeployWave({}), "emergency wave deployed from an empty reserve")
    end

    -- newgame.rollGold randomness testing
    do
        local newgame = require("engine.newgame")
        local orig_random = math.random

        -- Test with mocked config bounds
        local mockLoader = { system = { newGame = { goldMin = 10, goldMax = 20 } } }

        -- Force minimum
        math.random = function(min, max) return min end
        local goldMin = newgame.rollGold(mockLoader)
        check(goldMin == 10, "rollGold failed: expected min 10, got " .. tostring(goldMin))

        -- Force maximum
        math.random = function(min, max) return max end
        local goldMax = newgame.rollGold(mockLoader)
        check(goldMax == 20, "rollGold failed: expected max 20, got " .. tostring(goldMax))

        -- Test fallbacks
        local fallbackLoader = {}

        math.random = function(min, max) return min end
        local fbMin = newgame.rollGold(fallbackLoader)
        check(fbMin == 25, "rollGold failed: expected fallback min 25, got " .. tostring(fbMin))

        math.random = function(min, max) return max end
        local fbMax = newgame.rollGold(fallbackLoader)
        check(fbMax == 75, "rollGold failed: expected fallback max 75, got " .. tostring(fbMax))

        -- Restore original math.random
        math.random = orig_random
    end

    -- Formula sandbox: a representative reward-curve expression must compile
    -- and evaluate against a mock context (SPEC S5 / task A2).
    do
        local formulaEngine = require("engine.formula")
        local mockCtx = {
            enemy = { level = 4, hp = 30, maxHp = 40, atk = 12, def = 8, mat = 10, mdf = 9 },
            session = { gold = 100, mp = 20, maxMp = 30, floor = 3 },
        }
        local expr = "floor(enemy.maxHp * 0.5) + random(1, session.floor * 2) + round(enemy.level * 1.5)"
        local val, ferr = formulaEngine.eval(expr, mockCtx)
        check(ferr == nil and type(val) == "number" and val >= 27 and val <= 32,
            "formula sandbox failed reward-curve check: " .. tostring(ferr or val))
        -- The sandbox must reject environment escapes
        local _, escErr = formulaEngine.eval("os.time()", mockCtx)
        check(escErr ~= nil, "formula sandbox allowed access to os.*")
    end

    -- Validate skill and item animations (Task A2)
    for id, skill in pairs(loader.skills or {}) do
        if skill.animation then
            check(loader.animations and loader.animations[skill.animation] ~= nil, "skill '" .. tostring(id) .. "' references missing animation '" .. tostring(skill.animation) .. "'")
        end
    end
    for _, item in ipairs(loader.items or {}) do
        if item.animation then
            check(loader.animations and loader.animations[item.animation] ~= nil, "item '" .. tostring(item.id) .. "' references missing animation '" .. tostring(item.animation) .. "'")
        end
    end

    -- Validate skill and item targeting specs (Tasks T1 & T2).
    -- expand() ERRORS on unrecognized specs (no silent fallthrough), so the
    -- pcall here is the real gate: bad data fails G1, gameplay never sees it.
    -- Skills must always carry a target — battle calls expand(skill.target)
    -- directly, with no fallback like the item paths' `or "ally"`.
    local targeting = require("engine.targeting")
    for id, skill in pairs(loader.skills or {}) do
        check(skill.target ~= nil, "skill '" .. tostring(id) .. "' is missing a target spec")
        if skill.target then
            local ok, err = pcall(targeting.expand, skill.target)
            check(ok, "skill '" .. tostring(id) .. "' has invalid target spec '" .. tostring(skill.target) .. "'" .. (ok and "" or (": " .. tostring(err))))
        end
    end
    -- Items may omit target (the battle/field paths default to "ally").
    for _, item in ipairs(loader.items or {}) do
        if item.target then
            local ok, err = pcall(targeting.expand, item.target)
            check(ok, "item '" .. tostring(item.id) .. "' has invalid target spec '" .. tostring(item.target) .. "'" .. (ok and "" or (": " .. tostring(err))))
        end
    end

    -- Unified Event Engine Validator (SPEC A7)
    local scriptUsageCount = 0
    local deprecatedUsageCount = 0
    local registry = {}
    for _, c in ipairs((loader.engine and loader.engine.commands) or {}) do
        registry[c.id] = c
    end

    -- Handler coverage: every command the registry offers must actually be
    -- implemented. Without this, a registered-but-unimplemented command (a
    -- "stub") appears in the editor's palette and silently no-ops when a
    -- designer authors it — the dead-content failure this validator exists to
    -- prevent. Registry entries are a contract: an id needs a Lua handler (or
    -- an interpreter.compile case) to mean anything.
    for _, c in ipairs((loader.engine and loader.engine.commands) or {}) do
        check(interpreter.isImplemented(c.id),
            "engine.json registers command '" .. tostring(c.id) ..
            "' with no handler in engine/interpreter.lua (stub commands are not allowed)")
    end

    -- Mock context shared by every formula-compiling param check (the
    -- 'formula' type and E7's 'assignments' list-of-pairs type).
    local function buildFormulaMockCtx()
        return {
                        enemy = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        ally = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        target = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        a = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        b = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        session = { gold = 100, mp = 20, maxMp = 30, floor = 3, mapSafe = false, encounterRate = 0.1, itemCount = 3, equipCount = { 1, 1, 1 } },
                        combat = { minEnemies = 1, maxEnemies = 3, victoryGoldMin = 1, victoryGoldMax = 5, victoryExp = 10, baseFleeChance = 0.5, goldLossOnFleeMin = 1, goldLossOnFleeMax = 5, mpExhaustionDamage = 5 },
                        v = { roll = 0.5, bonus = 10, state = 1, disciplineIdx = 2, crafterIdx = 1, slot = 1, i1Idx = 3, i2Idx = 1, confirmIdx = 1, i1Id = 1, i2Id = 2, rouletteStep = 0, S = 10, idx = 1, count = 3, items = { { id = 1, cost = 50, name = "Item 1" }, { id = 2, cost = 100, name = "Item 2" }, { id = 3, cost = 200, name = "Item 3" } }, selectedDisciplineIdx = 2, selectedCrafterIdx = 1, selectedIngredient1Idx = 3, selectedIngredient2Idx = 1, cursorSlot = 1, confirmOptionIdx = 1, i1_item_id = 1, i2_item_id = 2, invCount = 3, rouletteDelay = 0.05, isAnomaly = false, yieldScore = 10, yieldAnomalyScore = 15, poolSize = 3, poolTargetIdx = 1, poolCurrentIdx = 1, resultItemId = 1, resultItemName = "Mock Item", opt = 1, subIdx = 1, selectedIdx = 1, targetIdx = 1, _guard = 0, eqIdx = 1, mode = 1, focus = "cmd", cmdIdx = 1, partyIdx = 1, memberIdx = 1, popupIdx = 1, seededCrafterIdx = 1, focusArea = "party", cursorIdx = 1, summonIdx = 1, summonPool = {}, popupCount = 1, popupOptions = {}, ritualMode = "summon", targetIsReserve = true, targetIndex = 1, pool = {}, poolIdx = 1, level = 1, baseLevel = 1, _stepDir = 1, mpCost = 0, expCost = 0, done = 0, titleText = "", previewText = "", costText = "", helpText = "", resultText = "", memberName = "", confirmOptions = {}, ritualPush = "", popupTargetIsReserve = true, popupTargetIndex = 1, page = 1, evoIdx = 1, evoPaths = {} },
                        party = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, fleeBonus = 0.1 },
                        enemies = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, fleeBonus = 0.1 },
                        ingredient1 = { id = 1, name = "Mock Ingredient 1", meta = { potency = 5, tier = 1, craftElement = "fire" } },
                        ingredient2 = { id = 2, name = "Mock Ingredient 2", meta = { potency = 3, tier = 0, craftElement = "water" } },
                        alpha = 0.5,
                        S = 10
        }
    end

    local function validateCommands(cmds, hostCtx, isImmediate, allowScript, ownerDesc)
        for _, cmd in ipairs(cmds or {}) do

            local id = cmd.cmd or cmd.type
            if id == nil then
                check(false, ownerDesc .. " uses unknown command 'nil' (missing cmd or type field)")
                goto continue
            end
            if id == "COMMENT" then
                -- COMMENT is accepted everywhere and never flagged.
                -- comment field is also accepted everywhere, which we just ignore.
                goto continue
            end

            local cmdDef = registry[id]
            check(cmdDef ~= nil, ownerDesc .. " uses unknown command '" .. tostring(id) .. "'")

            if cmdDef then
                if cmdDef.deprecatedBy then
                    deprecatedUsageCount = deprecatedUsageCount + 1
                end

                -- Check context
                local ctxAllowed = false
                for _, c in ipairs(cmdDef.contexts or {}) do
                    if c == "any" or c == hostCtx then ctxAllowed = true; break end
                end
                check(ctxAllowed, ownerDesc .. " uses command '" .. id .. "' in invalid context '" .. hostCtx .. "'")

                -- Check interactive in immediate mode
                if isImmediate and cmdDef.interactive then
                    check(false, ownerDesc .. " immediate mode cannot use interactive command '" .. id .. "'")
                end

                if id == "SCRIPT" then
                    scriptUsageCount = scriptUsageCount + 1
                    check(allowScript, ownerDesc .. " contains a SCRIPT command (S6 zero-SCRIPT rule)")
                end

                -- Validate params
                for _, paramDef in ipairs(cmdDef.params or {}) do
                    local val = cmd[paramDef.key]
                    if val ~= nil then

                if paramDef.type == "formula" then
                    local mockCtx = buildFormulaMockCtx()
                    local formulaEngine = require("engine.formula")
                    if type(val) == "string" and (val:match("^flag:") or val:match("^hasItem:")) then
                        -- Allow legacy condition strings
                    else
                        local ok, _, ferr = pcall(formulaEngine.eval, val, mockCtx)
                        check(ok and ferr == nil, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' failed to compile formula '" .. tostring(val) .. "': " .. tostring(ferr))
                    end
                elseif paramDef.type == "assignments" then
                    -- E7: list of { name, value } pairs; every value must
                    -- compile as a formula and every name be a non-empty
                    -- string. Rows are checked IN ORDER against one shared
                    -- mock context, assigning each result into mock v — the
                    -- same semantics the handler runs with, so later rows
                    -- reading earlier ones validate correctly. Any future
                    -- list-of-pairs command inherits this.
                    check(type(val) == "table", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a list of {name, value} rows")
                    if type(val) == "table" then
                        local formulaEngine = require("engine.formula")
                        local mockCtx = buildFormulaMockCtx()
                        for ai, a in ipairs(val) do
                            check(type(a) == "table" and type(a.name) == "string" and a.name ~= "",
                                ownerDesc .. " command '" .. id .. "' " .. paramDef.key .. "[" .. ai .. "] needs a non-empty string name")
                            if type(a) == "table" then
                                local ok, result, ferr = pcall(formulaEngine.eval, a.value, mockCtx)
                                check(ok and ferr == nil, ownerDesc .. " command '" .. id .. "' " .. paramDef.key .. "[" .. ai .. "] value failed to compile formula '" .. tostring(a.value) .. "': " .. tostring(ferr))
                                if type(a.name) == "string" and a.name ~= "" then
                                    -- Feed the row's result (or a neutral 1)
                                    -- forward for later rows' formulas.
                                    if ok and result ~= nil then mockCtx.v[a.name] = result
                                    else mockCtx.v[a.name] = 1 end
                                end
                            end
                        end
                    end
                elseif paramDef.type == "commands" then
                    -- val could be a list of commands, OR for CHOICE it could be a list of options where each option has .commands
                    -- Task A4b: nested lists of a NON-interactive block command
                    -- (IF, FOR_EACH, ...) always execute in immediate mode —
                    -- even in map/common hosts, where the RUN_IMMEDIATE bridge
                    -- runs them through runImmediate. Interactive commands
                    -- inside them would error at runtime, so flag them here.
                    local nestedImmediate = isImmediate or (cmdDef.interactive ~= true)
                    if id == "CHOICE" and type(val) == "table" then
                        for oi, opt in ipairs(val) do
                            if opt.commands then validateCommands(opt.commands, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> CHOICE opt") end
                            if opt.script then validateCommands(opt.script, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> CHOICE opt") end
                        end
                    else
                        validateCommands(val, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> nested")
                    end
elseif paramDef.type == "script" then
                            local chunk, err = load(val, "validator", "t", {})
                            check(chunk ~= nil, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' script syntax error: " .. tostring(err))
                        elseif paramDef.type == "text" then
                            check(type(val) == "string" or type(val) == "table", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a string or array")
                        elseif paramDef.type == "number" then
                            check(type(val) == "number", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a number")
                        elseif paramDef.type == "term" then
                            -- Ensure it's a string, resolution is implicit as getTerm falls back to the key, but we check type
                            check(type(val) == "string", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a string term")
                        elseif paramDef.key == "windowId" and val ~= nil then
                            check(type(val) == "string" and val ~= "", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' must be a valid window id string")
                        elseif paramDef.key == "scene" and val ~= nil then
                            -- Validate that if scene is provided, it references a valid scene ID or name
                            local foundScene = false
                            for _, s in ipairs(loader.scenes or {}) do
                                if tostring(s.id) == tostring(val) or s.name == val or s.kind == val then
                                    foundScene = true
                                    break
                                end
                            end
                            check(foundScene, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing scene '" .. tostring(val) .. "'")
                        elseif paramDef.type == "state" then
                            check(loader.getState(val), ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing state '" .. tostring(val) .. "'")
                        elseif paramDef.type == "item" then
                            check(val == "random" or loader.getItem(val), ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing item '" .. tostring(val) .. "'")
                        elseif paramDef.type == "scope" then
                            local validScopes = { enemies=true, living_enemies=true, allies=true, living_allies=true, party=true, slot_allies=true }
                            check(validScopes[val], ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' has invalid scope '" .. tostring(val) .. "'")
                        elseif paramDef.type == "battlerRef" then
                            -- Usually just a string like "target", "a", "b", "summoner", etc.
                            check(type(val) == "string" or type(val) == "table", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a valid battlerRef")
                        elseif paramDef.type == "commands" then
                            validateCommands(val, hostCtx, isImmediate or (cmdDef.interactive ~= true), allowScript, ownerDesc .. " -> nested")
                        end
                    end
                end
            end

            ::continue::
        end
    end

    -- Run the tree walker over all data files
    for _, map in ipairs(loader.maps or {}) do
        for i, ev in ipairs(map.events or {}) do
            local desc = "map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) .. ")"
            if ev.commands then
                validateCommands(ev.commands, "map", false, true, desc)
            end
            if ev.script then
                validateCommands(ev.script, "map", false, true, desc)
            end
        end
    end

    for ceId, ce in pairs(loader.commonEvents or {}) do
        if ce.commands then
            validateCommands(ce.commands, "common", false, true, "common event '" .. tostring(ceId) .. "'")
        end
        if ce.script then
            validateCommands(ce.script, "common", false, true, "common event '" .. tostring(ceId) .. "'")
        end
    end

    for phaseName, cmds in pairs((loader.flows or {}).battle or {}) do
        if type(cmds) == "table" then
            -- Default battle phases enforce zero-SCRIPT (S6)
            validateCommands(cmds, "battle_phase", true, false, "flows.json battle." .. phaseName)
        end
    end

    for phaseName, cmds in pairs((loader.flows or {})._test or {}) do
        if type(cmds) == "table" then
            validateCommands(cmds, "battle_phase", true, true, "flows.json _test." .. phaseName)
        end
    end



    -- Test flow.run execution: simple mock of context and interpreter commands
    do
        local origRunImmediate = interpreter.runImmediate
        local mockRunCalled = false
        local mockPassedCommands = nil
        local mockPassedCtx = nil
        interpreter.runImmediate = function(commands, ctx)
            mockRunCalled = true
            mockPassedCommands = commands
            mockPassedCtx = ctx
            return { { type = "mock_flow_event" } }
        end

        local mockLoader = {
            flows = {
                _test = {
                    mock_phase = { { cmd = "MOCK_CMD" } }
                }
            }
        }
        local mockCtx = { loader = mockLoader }

        -- Valid phase
        local evs = flow.run("_test.mock_phase", mockCtx)
        check(mockRunCalled, "flow.run did not call interpreter.runImmediate")
        check(mockPassedCommands and mockPassedCommands[1] and mockPassedCommands[1].cmd == "MOCK_CMD", "flow.run passed incorrect commands to interpreter")
        check(mockPassedCtx == mockCtx, "flow.run passed incorrect context to interpreter")
        check(evs and evs[1] and evs[1].type == "mock_flow_event", "flow.run did not return events from interpreter")

        -- Invalid phase
        mockRunCalled = false
        local emptyEvs = flow.run("_test.missing_phase", mockCtx)
        check(not mockRunCalled, "flow.run called interpreter for missing phase")
        check(type(emptyEvs) == "table" and #emptyEvs == 0, "flow.run did not return empty table for missing phase")

        interpreter.runImmediate = origRunImmediate
    end

    -- Interpreter immediate mode: the _test flow exercises every implemented
    -- non-interactive command (SPEC S1/S2; ROLL_ENCOUNTER/SPAWN_ENEMIES land
    -- with task A5d and are registry-only for now).
    do
        local tSession = session.GameSession.new(loader)
        tSession:initializeStartingParty()
        local tEnemy = session.Battler.new(loader.getActor(1), 1)
        tEnemy.hp = tEnemy:getMaxHp(tSession)
        local tCtx = {
            session = tSession,
            party = tSession.party,
            enemies = { tEnemy },
            target = tSession.party[1],
            a = tSession.party[1],
        }
        local okFlow, flowErr = pcall(flow.run, "_test.scene", tCtx)
        check(okFlow, "_test.scene flow failed: " .. tostring(flowErr))
        if okFlow then
            local sawDamage, sawScript, sawScene = false, false, false
            for _, ev in ipairs(tCtx.events or {}) do
                if ev.type == "damage" then sawDamage = true end
                if ev.type == "text" and tostring(ev.text):match("^script ran") then sawScript = true end
                if ev.type == "scene_change" then sawScene = true end
            end
            check(sawDamage, "_test.scene emitted no damage events (api.damage / DAMAGE broken)")
            check(sawScript, "_test.scene SCRIPT did not emit through api.emit")
            check(sawScene, "_test.scene SCENE_EVENT did not emit scene_change")
        end

        -- SCRIPT sandbox negative test: raw access must error by default
        check((loader.engine.scripting or {}).allowRawAccess == false,
            "engine.json scripting.allowRawAccess must default to false")
        local okEsc = pcall(flow.run, "_test.script_escape", { session = tSession })
        check(not okEsc, "SCRIPT sandbox allowed os.* access with allowRawAccess=false")

        -- Task A4b: the interactive-immediate bridge. A mixed command list
        -- must compile its contiguous non-interactive run (COMMENTs swallowed)
        -- into ONE RUN_IMMEDIATE node between the TEXT nodes, and executing
        -- that run must share flow-locals (SET_VAR -> IF) and emit text.
        do
            local nodes = {}
            local mixed = {
                { type = "TEXT", text = "before" },
                { cmd = "SET_VAR", name = "n", value = "2 + 3" },
                { cmd = "COMMENT", text = "swallowed into the run" },
                { cmd = "IF", condition = "v.n == 5", ["then"] = {
                    { cmd = "GAIN_GOLD", amount = "v.n" },
                    { cmd = "EMIT_TEXT", fallback = "bridge ran" },
                } },
                { type = "TEXT", text = "after" },
            }
            local firstId = interpreter.compile(nodes, mixed, "a4b", nil,
                { loader = loader, recoverParty = function() end, session = tSession })
            check(nodes[firstId] and nodes[firstId].type == "TEXT", "A4b: first mixed node should be TEXT")
            local runNode = nodes[firstId] and nodes[nodes[firstId].next]
            check(runNode and runNode.type == "ACTION" and runNode.action == "RUN_IMMEDIATE",
                "A4b: non-interactive run did not compile to RUN_IMMEDIATE")
            if runNode then
                check(#runNode.commands == 3, "A4b: run should group 3 commands (SET_VAR, COMMENT, IF), got " .. tostring(#runNode.commands))
                check(nodes[runNode.next] and nodes[runNode.next].type == "TEXT" and nodes[runNode.next].content == "after",
                    "A4b: RUN_IMMEDIATE must chain to the trailing TEXT node")
                local goldBefore = tSession.gold
                local okRun, evs = pcall(interpreter.runImmediate, runNode.commands,
                    { session = tSession, loader = loader, party = tSession.party })
                check(okRun, "A4b: RUN_IMMEDIATE execution failed: " .. tostring(evs))
                if okRun then
                    check(tSession.gold == goldBefore + 5, "A4b: SET_VAR -> IF -> GAIN_GOLD did not share flow-locals across the run")
                    local sawBridgeText = false
                    for _, ev in ipairs(evs) do
                        if ev.type == "text" and ev.text == "bridge ran" then sawBridgeText = true end
                    end
                    check(sawBridgeText, "A4b: EMIT_TEXT inside the run emitted no text event")
                end
            end
        end
    end

    -- Interactive compile sweep: every map event and common event must
    -- compile to a well-formed dialogue graph (all node links resolve).
    do
        local cSession = session.GameSession.new(loader)
        local cCtx = { loader = loader, recoverParty = function() end, session = cSession }
        local function checkGraph(desc, commands)
            if not commands or #commands == 0 then return end
            local nodes = {}
            local ok, firstOrErr = pcall(interpreter.compile, nodes, commands, "node", nil, cCtx)
            if not check(ok, desc .. " failed to compile: " .. tostring(firstOrErr)) then return end
            for id, node in pairs(nodes) do
                for _, key in ipairs({ "next", "trueNode", "falseNode" }) do
                    local link = node[key]
                    check(link == nil or nodes[link] ~= nil,
                        desc .. " node '" .. id .. "' links to missing node '" .. tostring(link) .. "'")
                end
                for _, opt in ipairs(node.options or {}) do
                    check(opt.target == nil or nodes[opt.target] ~= nil,
                        desc .. " choice option links to missing node '" .. tostring(opt.target) .. "'")
                end
            end
        end
        for _, map in ipairs(loader.maps or {}) do
            for _, ev in ipairs(map.events or {}) do
                checkGraph("map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) .. ")", ev.commands)
            end
        end
        for ceId, ce in pairs(loader.commonEvents or {}) do
            checkGraph("common event " .. tostring(ceId), ce.commands)
        end
    end



    -- Flows are the single source of truth for battle outcomes: the phases
    -- the hosts call unconditionally must exist and execute cleanly against
    -- a fresh session (behavioral regressions are covered by the golden
    -- battle log, tools/golden/check).
    for _, phase in ipairs({ "battle.victory", "battle.defeat", "battle.escaped", "battle.encounter_check" }) do
        check(flow.has(phase), "flows.json is missing required phase '" .. phase .. "'")
        if flow.has(phase) then
            local s = session.GameSession.new(loader)
            s:initializeStartingParty()
            for _, c in ipairs(s.party) do c.hp = math.max(1, math.floor(c:getMaxHp(s) / 2)) end
            local okPhase, phaseErr = pcall(flow.run, phase, { session = s, party = s.party, enemies = {} })
            check(okPhase, phase .. " flow failed to execute: " .. tostring(phaseErr))
        end
    end

    -- Item effects go through the same pipeline in and out of battle
    local item = loader.getItem(combat.battleItem or 1)
    if item and vSession.party[1] then
        for _, eff in ipairs(item.effects or {}) do
            effects.apply(eff, vSession.party[1], vSession.party[1], vSession)
        end
    end

    -- Traits evaluateCondition validation
    local function validateTraitsCondition()
        local battler = session.Battler.new(loader.getActor(1), 1)
        local maxHp = traits.getParam(battler, "maxHp", vSession)

        check(traits.evaluateCondition(nil, battler, vSession) == true, "nil condition must evaluate to true")
        check(traits.evaluateCondition("invalid", battler, vSession) == false, "invalid condition must evaluate to false")

        -- HP conditions
        battler.hp = 0 -- 0% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == true, "0% HP is < 50%")
        check(traits.evaluateCondition("HP<50%", battler, vSession) == true, "0% HP is < 50% without spaces")

        battler.hp = maxHp -- 100% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == false, "100% HP is not < 50%")

        battler.hp = math.ceil(maxHp * 0.5) -- >= 50% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == false, ">= 50% HP is not < 50%")

        battler.hp = math.floor(maxHp * 0.4) -- < 50% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == true, "< 50% HP is < 50%")
    end
    validateTraitsCondition()

    -- Scenes validation (C9)
    local function validateScenes()
        local formulaEngine = require("engine.formula")
        local mockItem1 = loader.getItem(1)
        local mockItem2 = loader.getItem(2)
        local mockCrafter = session.Battler.new(loader.getActor(1), 1)
        
        local mockCtx = {
            i1 = formulaEngine.itemView(mockItem1),
            i2 = formulaEngine.itemView(mockItem2),
            ingredient1 = formulaEngine.itemView(mockItem1),
            ingredient2 = formulaEngine.itemView(mockItem2),
            crafter = mockCrafter,
            alpha = 0.5,
            S = 10,
            v = {
                -- Crafting variables
                state = 1, disciplineIdx = 1, crafterIdx = 1, slot = 1,
                i1Idx = 1, i2Idx = 1, confirmIdx = 1, i1Id = 0, i2Id = 0,
                rouletteStep = 0, selectedDisciplineIdx = 1,
                selectedCrafterIdx = 1, selectedIngredient1Idx = 1,
                selectedIngredient2Idx = 1, cursorSlot = 1,
                confirmOptionIdx = 1, i1_item_id = 0, i2_item_id = 0,
                invCount = 0, rouletteDelay = 0, isAnomaly = false,
                yieldScore = 0, yieldAnomalyScore = 0, poolSize = 0,
                poolTargetIdx = 0, poolCurrentIdx = 0, resultItemId = 0,
                resultItemName = "",
                -- Common menu variables (D6 scenes)
                opt = 1, subIdx = 1, idx = 1, count = 1,
                selectedIdx = 1, _guard = 0, eqIdx = 1,
                -- Map scene's cursor/overlay state
                mode = 1, focus = "cmd", cmdIdx = 1, partyIdx = 1,
                memberIdx = 1, popupIdx = 1, confirmIdx = 1,
                seededCrafterIdx = 1,
                -- Reserve scene variables
                focusArea = "party", cursorIdx = 1, summonIdx = 1,
                summonPool = {}
            }
        }
        
        for _, scene in ipairs(loader.scenes or {}) do
            local sceneDesc = "scene '" .. tostring(scene.id) .. "' (" .. tostring(scene.name) .. ")"
            
            -- Generic config validation (D13): no scene-kind-specific checks.
            -- Any config key ending in "Formula" whose value is a string must
            -- compile against the mock scene context.
            for key, val in pairs(scene.config or {}) do
                if type(val) == "string" and key:match("Formula$") then
                    local ok, _, ferr = pcall(formulaEngine.eval, val, mockCtx)
                    check(ok and ferr == nil, sceneDesc .. " config." .. key .. " failed to compile: " .. tostring(ferr or ""))
                end
            end

            -- Scene-local named scripts (SCRIPT ref targets) must be strings
            -- with valid Lua syntax.
            for name, code in pairs(scene.scripts or {}) do
                check(type(code) == "string", sceneDesc .. " scripts." .. tostring(name) .. " must be a string")
                if type(code) == "string" then
                    local chunk, serr = load(code, "scene-script", "t", {})
                    check(chunk ~= nil, sceneDesc .. " scripts." .. tostring(name) .. " syntax error: " .. tostring(serr))
                end
            end

            -- Hook validation (all scene kinds).
            -- Zero-SCRIPT (S6) applies to built-in scenes only; extra
            -- (user-authored) scenes may use SCRIPT as their escape hatch
            -- (owner feedback 09.07.2026, FEEDBACK.md).
            local builtinSceneIds = {
                title = true, menu = true, items = true,
                status = true, shop = true,
            }
            local allowSceneScript = not builtinSceneIds[scene.id]
            -- SCRIPT commands may reference a scene-local named script via
            -- `ref` instead of inline `code`; every ref must resolve.
            local function checkScriptRefs(cmds, where)
                for _, cmd in ipairs(cmds or {}) do
                    if type(cmd) == "table" then
                        local id = cmd.cmd or cmd.type
                        if id == "SCRIPT" then
                            check(cmd.code ~= nil or cmd.ref ~= nil, where .. " SCRIPT has neither code nor ref")
                            if cmd.ref ~= nil then
                                check((scene.scripts or {})[cmd.ref] ~= nil, where .. " SCRIPT ref '" .. tostring(cmd.ref) .. "' not found in scene scripts")
                            end
                        end
                        for _, k in ipairs({ "then", "else", "commands" }) do
                            if type(cmd[k]) == "table" then checkScriptRefs(cmd[k], where) end
                        end
                    end
                end
            end
            if scene.hooks then
                for hookName, cmds in pairs(scene.hooks) do
                    validateCommands(cmds, "scene", true, allowSceneScript, sceneDesc .. " hook '" .. tostring(hookName) .. "'")
                    checkScriptRefs(cmds, sceneDesc .. " hook '" .. tostring(hookName) .. "'")
                end
            end

            -- S1w: validate data-authored windows array (if present).
            if scene.windows and type(scene.windows) == "table" and #scene.windows > 0 then
                local seenIds = {}
                for wi, winDef in ipairs(scene.windows) do
                    -- id required and unique per scene.
                    check(type(winDef.id) == "string" and winDef.id ~= "",
                        sceneDesc .. " windows[" .. wi .. "]: missing or non-string 'id'")
                    check(seenIds[winDef.id] == nil,
                        sceneDesc .. " windows[" .. wi .. "]: duplicate window id '" .. tostring(winDef.id) .. "'")
                    seenIds[winDef.id] = true

                    -- rect must be present with x,y,w,h (values may be exprs).
                    check(type(winDef.rect) == "table",
                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': missing 'rect'")
                    if type(winDef.rect) == "table" then
                        for _, dim in ipairs({ "x", "y", "w", "h" }) do
                            check(winDef.rect[dim] ~= nil,
                                sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': rect missing '" .. dim .. "'")
                        end
                    end

                    -- visible (optional) must be a string expression.
                    if winDef.visible ~= nil then
                        check(type(winDef.visible) == "string",
                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': 'visible' must be a string expression")
                    end

                    -- content must be an array of typed blocks.
                    check(type(winDef.content) == "table",
                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': missing 'content' array")
                    if type(winDef.content) == "table" then
                        for bi, block in ipairs(winDef.content) do
                            check(type(block) == "table" and type(block.type) == "string",
                                sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "]: missing or non-string 'type'")

                            local bt = block.type
                            if bt == "text" then
                                -- text block: a literal or {expr} template. The window
                                -- renderer never term-resolves text content (only "term:"
                                -- LIST sources go through loader.getTermList), so there is
                                -- nothing further to validate here beyond the string type.
                                check(type(block.text) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] text block: missing or non-string 'text'")
                            elseif bt == "list" then
                                check(type(block.listId) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: missing or non-string 'listId'")
                                -- format and cursor (optional) must be strings.
                                if block.format ~= nil then
                                    check(type(block.format) == "string",
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: 'format' must be a string")
                                end
                                if block.cursor ~= nil then
                                    check(type(block.cursor) == "string",
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: 'cursor' must be a string expression")
                                end
                                -- Verify known list sources resolve syntactically.
                                local src = block.listId or ""
                                local knownSources = { inventory = true, party = true, reserve = true,
                                    equipSlots = true, equipment = true }
                                if not knownSources[src] and not src:find("^config:") and not src:find("^v:")
                                    and not src:find("^static:") and not src:find("^term:") then
                                    print("[validator] warning: " .. sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] unknown list source '" .. src .. "'")
                                end
                                -- "term:" sources must resolve to a real terms.json list —
                                -- a typo'd path would otherwise render an empty list with no
                                -- error anywhere (S1w: term-key refs resolve or G1 fails).
                                if src:find("^term:") then
                                    local termPath = src:sub(6)
                                    local resolved = loader.getTermList(termPath, nil)
                                    check(type(resolved) == "table" and #resolved > 0,
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list source '" .. src .. "' does not resolve to a non-empty list in terms.json")
                                end
                            elseif bt == "gauge" then
                                -- gauge block: value and max are required exprs.
                                check(type(block.value) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge block: missing or non-string 'value'")
                                check(type(block.max) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge block: missing or non-string 'max'")
                                -- Optionally verify formulas compile.
                                if type(block.value) == "string" then
                                    local ok, _, ferr = pcall(formulaEngine.eval, block.value, mockCtx)
                                    check(ok and ferr == nil, sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge 'value' failed to compile: " .. tostring(ferr or ""))
                                end
                                if type(block.max) == "string" then
                                    local ok, _, ferr = pcall(formulaEngine.eval, block.max, mockCtx)
                                    check(ok and ferr == nil, sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge 'max' failed to compile: " .. tostring(ferr or ""))
                                end
                            elseif bt == "image" then
                                -- image block (v1): portraitField expr or path expr.
                                if block.portraitField ~= nil then
                                    check(type(block.portraitField) == "string",
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] image block: 'portraitField' must be a string expression")
                                end
                            else
                                -- Unknown block types: warn but don't fail (extensibility rule).
                                print("[validator] warning: " .. sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] unknown block type '" .. tostring(bt) .. "' — ignored at runtime")
                            end
                        end
                    end
                end
            end
        end
    end
    validateScenes()

    -- overhaul-7 A1: validate animation system reserved IDs
    local animation_player = require("presentation.animation_player")
    local RESERVED_SYSTEM_IDS = {
        "system.damage_flash",
        "system.damage_shake",
        "system.death",
        "system.small_damage",
        "system.enemy_slide_in",
        "system.heal",
        "system.reap",
    }
    for _, reservedId in ipairs(RESERVED_SYSTEM_IDS) do
        check(animation_player.getEntry(reservedId) ~= nil,
            "animation system: missing reserved entry '" .. reservedId .. "' in data/animations.json")
    end
    -- Check that all system-class entries have valid track structures
    -- (at minimum: each track has a known type and numeric duration)
    -- Must mirror what presentation/animation_player.lua actually implements:
    -- a system entry using an unimplemented type would silently no-op, which
    -- is exactly what this hard check exists to prevent. (text_flow was
    -- listed here without any player implementation — a leftover from the
    -- dropped healing_sparkle port; force_field was implemented but missing.)
    -- Assignable entries stay soft-validated on purpose: unknown track types
    -- fail soft at runtime so future types can ship in data first.
    local VALID_TRACK_TYPES = {
        tint = true, blend = true, transform = true,
        shake = true, particles = true, force_field = true,
        gradient_map = true, screen_flash = true,
    }
    for id, entry in pairs(loader.animations or {}) do
        if entry.class == "system" then
            check(type(entry.tracks) == "table",
                "animation system: entry '" .. tostring(id) .. "' missing tracks array")
            for ti, track in ipairs(entry.tracks or {}) do
                check(type(track) == "table",
                    "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " is not a table")
                if type(track) == "table" then
                    check(VALID_TRACK_TYPES[track.type],
                        "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " has unknown type '" .. tostring(track.type) .. "'")
                    check(type(track.duration) == "number",
                        "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " missing numeric duration")
                end
            end
        end
    end

    print("[validator] total SCRIPT usages: " .. scriptUsageCount)
    print("[validator] total deprecated usages: " .. deprecatedUsageCount)

    if #problems > 0 then
        error(table.concat(problems, "\n"), 0)
    end
end

function love.load(arg)
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
            elseif val == "golden" then
                isGoldenMode = true
            elseif val == "golden-ui" then
                isGoldenUIMode = true
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
            end
            i = i + 1
        end
    end

    -- E5: headless scene preview for the editor canvas, then quit.
    if isPreviewSceneMode then
        loader.init()
        runPreviewScene(previewSceneId)
        love.event.quit(0)
        return
    end

    -- E12: headless single-window preview for the Windows tab, then quit.
    if isPreviewWindowMode then
        loader.init()
        runPreviewWindow(previewWindowId, previewWindowMockSpec)
        love.event.quit(0)
        return
    end

    -- Font picker preview: renders the REAL ui.drawPanel/ui.drawString path
    -- with a candidate font+size, then quits. Never touches data/system.json.
    if isPreviewFontMode then
        loader.init()
        runPreviewFont(previewFontName, tonumber(previewFontSize))
        love.event.quit(0)
        return
    end

    -- A3: headless animation preview, then quit.
    if isPreviewAnimMode then
        loader.init()
        runPreviewAnim(previewAnimId, previewAnimJson, previewAnimSprite)
        love.event.quit(0)
        return
    end

    -- Headless data validation: check database cross-references and simulate
    -- a battle round, then quit. Run via `lovec . validate` (used by CI/tools).
    if isValidateMode then
        loader.init()
        local ok, err
        if isGoldenMode then
            ok, err = pcall(runGolden)
        elseif isGoldenUIMode then
            ok, err = pcall(runGoldenUI)
        else
            ok, err = pcall(runValidation)
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
    loader.init()
    
    -- Initialize activeSession
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
    
    -- Start developer server
    server.start()
    
    -- If in test battle mode, launch immediately into battle
    if isTestBattle then
        triggerTestBattle()
    end
end

function love.update(dt)
    renderer.update(dt)
    server.update(dt)
    if activeSession and activeSession.transitionTimer and activeSession.transitionTimer > 0 then
        activeSession.transitionTimer = activeSession.transitionTimer - dt
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

    -- Shop: grant the pending item after the hook deducted gold
    if scene_host.getCurrent() == "shop" then
        local shopState = scene_host.getCurrentState()
        if shopState and shopState.v.pendingItem then
            activeSession:addItem(shopState.v.pendingItem, 1)
            shopState.v.pendingItem = nil
        end
    end
end

-- F2 (overhaul-6): every scene draws the SAME declarative "party" window
-- (console + MP readout + 2x2 grid) via the generic window renderer. There is
-- no second/legacy party HUD anywhere. The Map scene already draws it through
-- its own scene state; battle/dialogue/town build a minimal party-only state
-- here so the ONE shared HUD appears in every scene (owner direction:
-- "there should be no place where the declarative one isn't used").
local function drawSharedPartyHud()
    local wr = require("presentation.window_renderer")
    local cursor = 0
    if scene_host.getCurrent() == "battle" then
        local bv = require("engine.scenes.battle").getState()
        if bv and bv.combatState == "input" then
            local memberInfo = bv.livingMembers and bv.livingMembers[bv.activeMemberIdx or 1]
            cursor = memberInfo and memberInfo.index or 0
        end
    end
    local state = {
        winState = { party = { open = true, listId = "party", cursor = cursor } },
        windowOrder = { "party" },
    }
    wr.draw(state, nil, { session = activeSession, loader = loader })
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1) -- reset color at start of frame
    
    local ctx = { session = activeSession, loader = loader }
    if scene_host.draw(ctx) then
        -- scene host handles drawing (currently does nothing for D1, but returns true if it has hooks)
    else
        if scene_host.getCurrent() == "town" then
        renderer.drawTown(townSelectedIdx)
        drawSharedPartyHud()
    elseif scene_host.getCurrent() == "map" then
        renderer.drawMap()
        -- The map's world is legacy-drawn (draw ~= "windows"), but its
        -- party bar / command overlay / member popup are data-authored
        -- windows layered on top via the generic renderer, same as any
        -- draw:"windows" scene.
        local mapState = scene_host.getCurrentState()
        local mapSceneData = loader.getScene("map")
        if mapState and mapSceneData then
            require("presentation.window_renderer").draw(mapState, mapSceneData, { session = activeSession, loader = loader })
        end
    elseif scene_host.getCurrent() == "dialogue" then
        renderer.drawDialogue(activeWalker, dialogueSelectIdx)
        drawSharedPartyHud()
    elseif scene_host.getCurrent() == "battle" then
        local bv = require("engine.scenes.battle").getState()
        renderer.drawBattle(bv.battle, bv.combatLog or {}, bv.combatState or "input", bv.selectedIndex or 1, bv.spellSelect or false, bv.itemSelect or false, bv.livingMembers or {}, bv.activeMemberIdx or 1, bv.victory, bv.victoryStage or 0)
        drawSharedPartyHud()
        renderer.drawTargetReticles(bv, bv.combatState or "input", bv.selectedIndex or 1, bv.spellSelect or false, bv.itemSelect or false, bv.livingMembers or {}, bv.activeMemberIdx or 1)
    end
    end
    
    renderer.drawDamagePopups()
    
    if server.isActive() then
        love.graphics.setColor(0.1, 0.4, 0.8, 0.8)
        love.graphics.rectangle("fill", 216, 2, 38, 9)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("DEV ON", 219, 3)
    end
    
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1) -- reset color before drawing canvas to prevent dark tinting leak
    love.graphics.draw(canvas, scaleX, scaleY, 0, scale, scale)
end

local handleDialogueAction -- forward declaration
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
    return interpreter.compile(nodes, commands, prefix, tailNodeId, interpreterCtx())
end

local function openShop(shopId)
    -- Shops are stored as a string-keyed table (JSON object keys are always
    -- strings) even though shopId itself arrives as a number from dialogue
    -- graphs, so the lookup needs an explicit tostring() -- same pattern used
    -- for commonEvents lookups by scriptId elsewhere in this file.
    local shopData = loader.shops[tostring(shopId)]
    local shopName = (shopData and shopData.name) or tostring(shopId)

    local items = {}
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
                    -- Plain table (not an __index proxy): the shop scene's
                    -- v:items list source copies row fields with pairs(),
                    -- which cannot see metatable fields. Price honors the
                    -- per-shop override set in the editor.
                    table.insert(items, {
                        id = itemData.id,
                        name = itemData.name or "",
                        icon = itemData.icon or 0,
                        description = itemData.description or "",
                        cost = shopItem.price or itemData.cost or 0,
                    })
                end
            end
        end
    end

    -- Push the shop scene and seed its v-state with shop data
    scene_host.push("shop", { session = activeSession, loader = loader, party = activeSession.party })
    local state = scene_host.getCurrentState()
    if state then
        state.v.shopName = shopName
        state.v.items = items
        state.v.count = #items
        state.v.idx = 1
    end
end

handleDialogueAction = function()
    local node, nodeId = activeWalker:getCurrentNode()
    if not node then return end

    if node.type == "ACTION" then
        if node.action == "RUN_IMMEDIATE" then
            -- Task A4b: a compiled run of non-interactive registry commands.
            -- Mutations (gold, items, states, flags) apply through the same
            -- handlers battle phases use; emitted text events render as
            -- dialogue lines by converting this node into a TEXT chain, the
            -- same trick GIVE_ITEM_ACTION uses.
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
        elseif node.action == "OFFER_QUEST" then
            activeSession.flags["quest:" .. node.questId .. ":active"] = true
            activeWalker:goToNode(node.acceptNode or node.next)
            handleDialogueAction()
        elseif node.action == "COMPLETE_QUEST" then
            activeSession.flags["quest:" .. node.questId .. ":active"] = nil
            activeSession.flags["quest:" .. node.questId .. ":completed"] = true
            if node.takeItem then
                activeSession:addItem(node.takeItem, -1)
            end
            activeWalker:goToNode(node.completeNode or node.next)
            handleDialogueAction()
        elseif node.action == "TELEPORT" then
            local maxFloor = conf("dungeon", "maxFloor", 5)
            activeSession.dungeonFloor = activeSession.dungeonFloor + 1
            if activeSession.dungeonFloor > maxFloor then
                activeSession.dungeonFloor = maxFloor
            end
            exploration.loadMap(activeSession, activeSession.dungeonFloor + 1)
            scene_host.goto_scene("map")
        elseif node.action == "START_BATTLE" then
            triggerBattle()
        elseif node.action == "GIVE_ITEM_ACTION" then
            local loot = conf("dungeon", "defaultLoot", 1) -- 1 = HP Tonic
            if activeSession.currentMapData.treasures and #activeSession.currentMapData.treasures > 0 then
                loot = activeSession.currentMapData.treasures[math.random(#activeSession.currentMapData.treasures)]
            end
            local item = loader.getItem(loot)
            activeSession:addItem(loot, 1)

            node.type = "TEXT"
            node.content = loader.formatTerm("events.found_item", "Found a {0}!", (item and item.name or loot))
            node.action = nil
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
local function runEventCommands(eventTitle, commands)
    local graph = interpreter.runInteractive(commands, interpreterCtx())
    if not graph then return end
    graph.name = eventTitle

    activeWalker = director.GraphWalker.new(activeSession, graph)
    activeWalker.eventName = eventTitle
    scene_host.goto_scene("dialogue")
    handleDialogueAction()
end

local function checkStepEvents()
    local px, py = activeSession.playerX - 1, activeSession.playerY - 1
    if activeSession.currentMapData.events then
        for _, ev in ipairs(activeSession.currentMapData.events) do
            if ev.x == px and ev.y == py and ev.trigger == "step" then
                local commands = nil
                if ev.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = ev.script
                end
                
                if commands then
                    runEventCommands(ev.name or "Event", commands)
                    return true
                end
            end
        end
    end
    return false
end

-- Triggers a conversation graph
local function triggerDialogue(graphName)
    local walker = director.startConversation(activeSession, graphName)
    if walker then
        activeWalker = walker
        dialogueSelectIdx = 1
        scene_host.goto_scene("dialogue")
        handleDialogueAction()
    end
end

triggerBattle = function()
    require("engine.scenes.battle").triggerBattle()
end

triggerTestBattle = function()
    require("engine.scenes.battle").triggerTestBattle()
end

-- Map a battler to screen coordinates on the battle scene.
local function getTargetCoords(target)
    return require("engine.scenes.battle").getTargetCoords(target)
end

-- Action handling for key presses
local function handleKeyPressed(key)
    if inputCooldown > 0 then return end
    if not activeSession then return end

    local ctx = { session = activeSession, loader = loader, party = activeSession.party or {} }
    if scene_host.keypressed(key, ctx) then
        return
    end

    if key == "escape" then
        -- E10: title ESC is handled by the scene's on_cancel hook (moves the
        -- cursor to Exit instead of instant-quitting). Map's ESC (opening
        -- the party cursor + command overlay) is likewise fully handled by
        -- the map scene's own on_cancel hook above — nothing left to do here.
        if scene_host.getCurrent() == "dialogue" then
            scene_host.goto_scene("map")
            return
        end
    end
    
    -- E10: title input is fully handled by the title scene's data hooks
    -- (scene_host.keypressed above), so no legacy title branch remains.
    if scene_host.getCurrent() == "town" then
        -- Town menu entries come from system.town.options (label + action),
        -- editable from the editor's System tab.
        local townOptions = conf("town", "options", {})
        local optCount = math.max(1, #townOptions)
        if key == "up" or key == "w" then
            townSelectedIdx = (townSelectedIdx - 2) % optCount + 1
        elseif key == "down" or key == "s" then
            townSelectedIdx = townSelectedIdx % optCount + 1
        elseif key == "return" or key == "space" then
            local opt = townOptions[townSelectedIdx]
            if opt then
                if opt.action == "enter_dungeon" then
                    activeSession.dungeonFloor = 1
                    exploration.loadMap(activeSession, opt.mapId or 2)
                    scene_host.goto_scene("map")
                elseif opt.action == "dialogue" then
                    triggerDialogue(opt.graph)
                elseif opt.action == "rest" then
                    recoverParty()
                    if opt.graph then triggerDialogue(opt.graph) end
                end
            end
        end
        
    elseif scene_host.getCurrent() == "map" then
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
            moved = exploration.moveForward(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "forward"
            end
        elseif key == "down" or key == "s" then
            moved = exploration.moveBackward(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "backward"
            end
        elseif key == "left" or key == "a" then
            exploration.turnLeft(activeSession)
            activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
            activeSession.transitionDir = "turn_left"
        elseif key == "right" or key == "d" then
            exploration.turnRight(activeSession)
            activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
            activeSession.transitionDir = "turn_right"
        elseif key == "q" then
            moved = exploration.strafeLeft(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "strafe_left"
            end
        elseif key == "e" then
            moved = exploration.strafeRight(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "strafe_right"
            end
        elseif key == "space" or key == "return" then
            local frontTile, tx, ty = exploration.getFrontTile(activeSession)
            
            -- Check for coordinate-based events from the map's JSON array
            local eventObj = nil
            if activeSession.currentMapData.events then
                for _, ev in ipairs(activeSession.currentMapData.events) do
                    if ev.x == tx - 1 and ev.y == ty - 1 then
                        eventObj = ev
                        break
                    end
                end
            end
            
            if eventObj and (eventObj.trigger == nil or eventObj.trigger == "interact") then
                local commands = nil
                if eventObj.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(eventObj.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = eventObj.script
                end
                
                if commands then
                    runEventCommands(eventObj.name or "Event", commands)
                end
            end
        end
        
        if moved then
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
                        activeWalker:advance()
                        dialogueSelectIdx = 1
                        handleDialogueAction()
                        if not activeWalker:getCurrentNode() then
                            scene_host.goto_scene("map")
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
                        scene_host.goto_scene("map")
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
    if key == "f9" then
        if server.isActive() then
            server.stop()
            print("Developer server stopped.")
        else
            server.start()
        end
        return
    end
    
    handleKeyPressed(key)
end

function love.resize(w, h)
    scale = math.min(w / gameWidth, h / gameHeight)
    scale = math.max(1, math.floor(scale))
    scaleX = math.floor((w - gameWidth * scale) / 2)
    scaleY = math.floor((h - gameHeight * scale) / 2)
end
