local session = require("engine.session")
local battleSystem = require("engine.battle")
local renderer = require("presentation.renderer")

local cli = {}

-- Deterministic mock session shared by the golden-ui harness and the E5
-- scene preview: fixed seed, starting party, crafting ingredients in
-- inventory so list-driven scenes have real content to show.
local function makeHarnessSession(loader)
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
cli.makeHarnessSession = makeHarnessSession

function cli.runPreviewAnim(animId, animJson, spritePath, loader)
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
function cli.runPreviewScene(sceneId, loader, gameWidth, gameHeight)
    local json = require("data.json")
    local payload
    local ok, err = pcall(function()
        local vSession = makeHarnessSession(loader)
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

        -- The dialogue scene's v-state is fed per-frame by main.lua's
        -- syncDialogueWindowState in-game; seed the preview with a
        -- representative choice-mode state so all three windows (portrait,
        -- message, choices) show content instead of empty frames.
        if tostring(sceneDef.id) == "dialogue" then
            local st = sh.getCurrentState()
            if st and st.v.dialogueMode == nil then
                st.v.dialogueMode = "choice"
                st.v.dialogueSpeaker = "Alicia"
                st.v.dialoguePortrait = "NPC_Alicia"
                st.v.dialogueText = "Oh! H-hello! Welcome to my shop. Please look around!"
                st.v.dialogueWaiting = false
                st.v.dialogueOptions = { "Buy Consumables", "Talk", "Leave" }
                st.v.dialogueCursorIdx = 1
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

function cli.runPreviewWindow(windowId, mockSpecJSON, loader, gameWidth, gameHeight)
    local json = require("data.json")
    local payload
    local ok, err = pcall(function()
        local spec = {}
        if mockSpecJSON and mockSpecJSON ~= "" then
            local decoded = json.decode(mockSpecJSON)
            if type(decoded) == "table" then spec = decoded end
        end

        local vSession = makeHarnessSession(loader)
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
function cli.runPreviewFont(name, size)
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

-- Headless raycaster preview (`lovec . preview-map <mapId> [x] [y] [dir]`):
-- loads the given map by id, positions the camera, and dumps the actual
-- viewport_3d render to a PNG -- for checking tileset/door/sky/lighting
-- changes (docs/design/raycaster-tileset-lighting.md) without opening the
-- interactive window.
function cli.runPreviewMap(mapId, x, y, dir, loader)
    local json = require("data.json")
    local payload = {}
    local ok, err = pcall(function()
        local exploration = require("engine.exploration")
        local viewport_3d = require("presentation.viewport_3d")

        local mapIdx
        for idx, m in ipairs(loader.maps or {}) do
            if tostring(m.id) == tostring(mapId) then mapIdx = idx break end
        end
        if not mapIdx then error("map not found: " .. tostring(mapId)) end

        local vSession = makeHarnessSession(loader)
        exploration.loadMap(vSession, mapIdx)
        if x then vSession.playerX = tonumber(x) + 1 end
        if y then vSession.playerY = tonumber(y) + 1 end
        if dir then vSession.playerDir = dir end

        viewport_3d.init()

        local pw, ph = 256, 144
        local previewCanvas = love.graphics.newCanvas(pw, ph)
        love.graphics.setCanvas(previewCanvas)
        love.graphics.clear(0, 0, 0, 1)
        viewport_3d.draw(vSession)
        love.graphics.setCanvas()

        local fileData = previewCanvas:newImageData():encode("png")
        payload.image = love.data.encode("string", "base64", fileData)
        payload.width = pw
        payload.height = ph
        payload.playerX, payload.playerY, payload.playerDir = vSession.playerX, vSession.playerY, vSession.playerDir
    end)
    if not ok then
        payload = { error = tostring(err) }
        love.graphics.setCanvas() -- draw() may have failed mid-canvas; always leave it unset
    end
    print("PREVIEW BEGIN")
    print(json.encode(payload))
    print("PREVIEW END")
end

-- Headless fog preview (`lovec . preview-fog <fogSpecJson> [mapId]`):
-- loads a map (or the first map), overrides its fog settings with fogSpecJson,
-- and renders a 3D viewport frame to PNG base64 for the editor preview pane.
function cli.runPreviewFog(fogSpecJson, mapId, loader)
    local json = require("data.json")
    local payload = {}
    local ok, err = pcall(function()
        local exploration = require("engine.exploration")
        local viewport_3d = require("presentation.viewport_3d")

        local fogSpec = json.decode(fogSpecJson or "{}") or {}
        local mapIdx = 1
        if mapId and mapId ~= "" then
            for idx, m in ipairs(loader.maps or {}) do
                if tostring(m.id) == tostring(mapId) then mapIdx = idx break end
            end
        end

        local vSession = makeHarnessSession(loader)
        exploration.loadMap(vSession, mapIdx)
        if vSession.currentMapData then
            vSession.currentMapData.fog = fogSpec
        end

        viewport_3d.init()

        local pw, ph = 512, 288
        local baseCanvas = love.graphics.newCanvas(256, 144)
        local previewCanvas = love.graphics.newCanvas(pw, ph)
        previewCanvas:setFilter("nearest", "nearest")

        love.graphics.setCanvas(baseCanvas)
        love.graphics.clear(0, 0, 0, 1)
        viewport_3d.draw(vSession)

        love.graphics.setCanvas(previewCanvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(baseCanvas, 0, 0, 0, 2, 2)
        love.graphics.setCanvas()

        local fileData = previewCanvas:newImageData():encode("png")
        payload.image = love.data.encode("string", "base64", fileData)
        payload.width = pw
        payload.height = ph
    end)
    if not ok then
        payload = { error = tostring(err) }
        love.graphics.setCanvas()
    end
    print("PREVIEW BEGIN")
    print(json.encode(payload))
    print("PREVIEW END")
end

function cli.runGoldenUI(loader)
    local LOGGED_EVENT_TYPES = {
        open_window = true,
        close_window = true,
        set_text = true,
        set_list = true,
        set_cursor = true,
        focus_window = true
    }
    local vSession = makeHarnessSession(loader)

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

-- ---------------------------------------------------------------------------
-- G2 golden battle harness.
--
-- Fixtures are authored in data/goldenBattles.json, not written here, so
-- battle coverage grows the same way scene coverage does (a scene earns a G3
-- trace by authoring `goldenScript`, with no engine edits). That symmetry is
-- the point: while this harness was hardcoded there was exactly one encounter
-- for years, and a whole damage layer could be added without G2 noticing.
--
-- Read straight from data/ rather than through the loader on purpose. Fixtures
-- are a build artifact, not campaign content -- campaigns/<name>/ roots are
-- drop-in alternates of the loaded file set, and golden logs are only recorded
-- against the default campaign anyway.
-- ---------------------------------------------------------------------------
local GOLDEN_FIXTURES = "data/goldenBattles.json"

local function logEvents(events)
    for _, ev in ipairs(events) do
        if ev.type ~= "play_anim" and ev.type ~= "wait" then
            local t = ev.type or ""
            local a = ev.actor and ev.actor.name or ""
            local trg = ev.target and ev.target.name or ""
            local v = ev.value or ""
            local s = ev.state or ""
            print(string.format("%s|%s|%s|%s|%s", t, a, trg, tostring(v), s))
            -- Criticals are damage multipliers, so without their own line a
            -- crit and an ordinary hit for the same total are indistinguishable
            -- to G2 -- and crit rate is rolled per hit, exactly the kind of
            -- thing that regresses silently. Emitted as an extra line rather
            -- than a sixth column so the common case leaves the log unchanged.
            if ev.critical then
                print(string.format("critical|%s|%s||", a, trg))
            end
        end
    end
end

-- "e2" -> enemies[2], "p1" -> party[1]. Unknown or out-of-range refs raise:
-- a fixture that silently targeted nil would produce a plausible-looking log.
local function resolveTarget(spec, party, enemies)
    if spec == nil then return nil end
    local kind, idx = tostring(spec):match("^([pe])(%d+)$")
    if not kind then
        error("golden fixture: bad target '" .. tostring(spec) .. "' (expected p<n> or e<n>)", 0)
    end
    local list = (kind == "p") and party or enemies
    local battler = list[tonumber(idx)]
    if not battler then
        error("golden fixture: target '" .. tostring(spec) .. "' does not exist", 0)
    end
    return battler
end

local function buildBattler(loader, vSession, actorId, level, hp)
    local actorData = loader.getActor(actorId)
    if not actorData then
        error("golden fixture: no actor with id " .. tostring(actorId), 0)
    end
    local b = session.Battler.new(actorData, level)
    b.hp = hp or b:getMaxHp(vSession)
    return b
end

local function runEncounter(loader, encounter, defaultLevel)
    local level = encounter.level or defaultLevel
    local vSession = session.GameSession.new(loader)
    vSession.party = {}
    for _, actorId in ipairs(encounter.party or {}) do
        table.insert(vSession.party, buildBattler(loader, vSession, actorId, level))
    end

    local enemies = {}
    for _, spec in ipairs(encounter.enemies or {}) do
        table.insert(enemies, buildBattler(loader, vSession, spec.actor, spec.level or level, spec.hp))
    end

    local vBattle = battleSystem.Battle.new(vSession, enemies)
    for _, round in ipairs(encounter.rounds or {}) do
        local actions = {}
        for _, a in ipairs(round) do
            actions[a.slot] = {
                type = a.type,
                id = a.id,
                target = resolveTarget(a.target, vSession.party, enemies),
            }
        end
        logEvents(vBattle:resolveRound(actions))
    end
end

function cli.runGolden(loader)
    local contents = love.filesystem.read(GOLDEN_FIXTURES)
    if not contents then
        error("golden fixtures missing: " .. GOLDEN_FIXTURES, 0)
    end
    local fixtures = require("data.json").decode(contents)

    for _, fixture in ipairs(fixtures) do
        -- Seeded once per fixture, not per encounter: encounters within a
        -- fixture deliberately share one RNG stream.
        math.randomseed(fixture.seed or 12345)

        print("GOLDEN BEGIN")
        print(string.format("battle|%s|name|%s", tostring(fixture.id), fixture.name or ""))
        for _, encounter in ipairs(fixture.encounters or {}) do
            runEncounter(loader, encounter, fixture.level or 1)
        end
        print("GOLDEN END")
    end
end

return cli
