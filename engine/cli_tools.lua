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

-- Renderer-facing fixtures should show geometry in front of the camera, not
-- begin pressed against a wall. Pick the nearest clear two-tile view to the
-- authored spawn so lighting, landmarks, and map context remain representative.
local function positionAtClearCorridor(vSession)
    local grid = vSession.mapGrid or {}
    local originX, originY = vSession.playerX or 1, vSession.playerY or 1
    local originDir = vSession.playerDir
    local directions = {
        { id = "N", dx = 0, dy = -1 },
        { id = "E", dx = 1, dy = 0 },
        { id = "S", dx = 0, dy = 1 },
        { id = "W", dx = -1, dy = 0 },
    }
    local function isFloor(x, y)
        return grid[y] and grid[y][x] == "."
    end
    local best = nil
    for y, row in ipairs(grid) do
        for x = 1, #row do
            if isFloor(x, y) then
                for _, direction in ipairs(directions) do
                    if isFloor(x + direction.dx, y + direction.dy)
                        and isFloor(x + direction.dx * 2, y + direction.dy * 2) then
                        local distance = math.abs(x - originX) + math.abs(y - originY)
                        local turnPenalty = direction.id == originDir and 0 or 1
                        local score = distance * 4 + turnPenalty
                        if not best or score < best.score then
                            best = { x = x, y = y, dir = direction.id, score = score }
                        end
                    end
                end
            end
        end
    end
    if best then
        vSession.playerX = best.x
        vSession.playerY = best.y
        vSession.playerDir = best.dir
        return best.x, best.y, best.dir
    end
    error("renderer fixture: map has no three-cell clear corridor", 0)
end
cli.positionAtClearCorridor = positionAtClearCorridor

-- golden-ui and screenshot harnesses drive scripted key sequences
-- (goldenScript / screenshotScript) through scene_host.keypressed exactly
-- like real input, which means the title scene's "Continue" reaches the
-- SAME LOAD_GAME/LIST_SAVES commands a player uses -- and those read the
-- developer's actual save directory (engine/savegame.lua), not anything
-- scoped to the harness's synthetic session. A save file left over from
-- manual playtesting makes the script silently load it and jump the
-- harness into whatever scene it was saved from, so captured traces (and
-- G3) depend on what happens to be on disk instead of only on the code.
-- Stubbing the module for the harness's duration makes every slot read
-- empty on every machine, matching what the golden reference was recorded
-- against.
local function withHermeticSaves(fn)
    local savegame = require("engine.savegame")
    local originalList = savegame.list
    local originalLoad = savegame.load
    savegame.list = function() return {} end
    savegame.load = function() return nil, "no save (headless harness)" end
    local ok, err = pcall(fn)
    savegame.list = originalList
    savegame.load = originalLoad
    if not ok then error(err, 0) end
end

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

        -- Effekseer tracks must preview too, or the editor silently shows an
        -- animation missing its most visible layer. The preview canvas is
        -- 240x240, not the game's 256x240, so the camera is retargeted -- and
        -- effects are cleared first so a previous preview cannot bleed in.
        local effekseer = require("presentation.effekseer")
        effekseer.init(loader)
        effekseer.setViewport(240, 240)
        effekseer.reset()

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
            -- The rect the preview's dummy sprite occupies, so the editor
            -- previews an animation's anchor exactly as battle resolves it
            -- (one implementation -- the preview never re-derives placement).
            local previewRect = { x = 120 - cellW / 2, y = 160 - cellH, w = cellW, h = cellH }

            -- Sprite drawing function for stencil test
            local function drawSprite()
                love.graphics.draw(texture, spriteQuad, drawX, drawY, 0, tf.scaleX, tf.scaleY, cellW / 2, cellH)
            end

            -- Back-layer particles render behind the sprite.
            love.graphics.setColor(1, 1, 1, 1)
            animation_player.drawParticles(dummyTarget, previewRect, drawSprite, "back")
            -- Same seam battle uses: the drawer owns the rect, so it resolves
            -- the anchor and spawns. One implementation, not a preview copy.
            effekseer.spawnFor(dummyTarget, previewRect)

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
            animation_player.drawParticles(dummyTarget, previewRect, drawSprite, "front")

            -- Effects above the sprite, below the flash -- the same ordering
            -- frame_renderer uses in game.
            effekseer.draw()

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
            effekseer.update(step)
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

-- Deterministic native-resolution capture suite. Each scene contributes its
-- initial state and every authored goldenScript step. The editor server owns
-- decoding the returned PNGs into the disposable workspace directory.
function cli.runScreenshots(loader, gameWidth, gameHeight)
    -- How far into an effect's life the capture lands. Small enough that short
    -- effects are still alive, large enough to be past frame 0's empty spawn.
    local EFFECT_CAPTURE_SECONDS = 0.15
    local json = require("data.json")
    local scene_host = require("engine.scene_host")
    local exploration = require("engine.exploration")
    local viewport_3d = require("presentation.viewport_3d")
    local frame_renderer = require("presentation.frame_renderer")
    local window_renderer = require("presentation.window_renderer")
    local dock = require("presentation.dock")
    local stringPictures = require("presentation.string_picture_renderer")
    local imagePictures = require("presentation.image_picture_renderer")
    local captures = {}
    local captureClock = 0

    local function slug(value)
        local s = tostring(value or ""):lower():gsub("[^%w_-]+", "-")
        return s:gsub("^%-+", ""):gsub("%-+$", "")
    end

    local function capture(path, vSession)
        local canvas = love.graphics.newCanvas(gameWidth, gameHeight)
        love.graphics.setCanvas({ canvas, depth = true, stencil = true })
            love.graphics.clear(0, 0, 0, 1, true, true)
        love.graphics.setColor(1, 1, 1, 1)
        frame_renderer.draw(scene_host, renderer, vSession, loader, gameHeight)
        love.graphics.setCanvas()
        local png = canvas:newImageData():encode("png")
        table.insert(captures, {
            path = path,
            image = love.data.encode("string", "base64", png),
            scene = tostring(scene_host.getCurrent() or ""),
        })
    end

    local settleCanvas = love.graphics.newCanvas(gameWidth, gameHeight)
    local function drawWarmup(vSession)
        love.graphics.setCanvas({ settleCanvas, depth = true, stencil = true })
        love.graphics.clear(0, 0, 0, 1, true, true)
        love.graphics.setColor(1, 1, 1, 1)
        frame_renderer.draw(scene_host, renderer, vSession, loader, gameHeight)
        love.graphics.setCanvas()
    end

    local function sceneById(id)
        for _, candidate in ipairs(loader.scenes or {}) do
            if tostring(candidate.id) == tostring(id) then return candidate end
        end
        return nil
    end

    local function advancePresentation(dt)
        captureClock = captureClock + dt
        renderer.update(dt)
        stringPictures.update(dt)
        imagePictures.update(dt)
    end

    -- Bring every visual system to a stable, post-transition frame without
    -- sleeping. Declarative windows and the persistent dock use real-time
    -- clocks in live play, so logical scene updates alone cannot settle them.
    local function settleForCapture(vSession)
        local state = scene_host.getCurrentState()
        local sceneDef = sceneById(scene_host.getCurrent())
        if not state or not sceneDef then return end

        -- Freeze effect time for the whole settle; released at the end.
        require("presentation.effekseer").setSuppressed(true)

        -- Seed/finish scene windows before the warm-up so even windows that
        -- have never drawn get their complete resting geometry immediately.
        window_renderer.finishAnimationsForCapture(state, sceneDef.windows)
        drawWarmup(vSession)

        -- The first warm-up starts a dock morph. Complete it through the dock's
        -- deterministic seam, draw once to materialize its content windows,
        -- then finish those windows too.
        dock.__finishTransition()
        window_renderer.finishAnimationsForCapture(state, sceneDef.windows)
        drawWarmup(vSession)
        window_renderer.finishAnimationsForCapture(dock.__store())
        window_renderer.finishAnimationsForCapture(state, sceneDef.windows)

        -- Advance renderer-owned animation tracks and picture motion/reveal.
        -- Scene logic itself is deliberately not advanced here.
        advancePresentation(1)

        -- Effects are the one thing the settle must NOT fast-forward. Panels
        -- and gauges want to be at rest; an effect at rest is an effect that
        -- already finished, and most are far shorter than the 1s settle. So
        -- effect time is frozen for the settle above and advanced here by a
        -- small fixed amount instead, capturing effects mid-life and
        -- deterministically. Without this, G5 -- the only gate that can see
        -- effects at all -- is blind to every effect shorter than a second.
        local efk = require("presentation.effekseer")
        efk.setSuppressed(false)
        efk.update(EFFECT_CAPTURE_SECONDS)
    end

    local function resetPresentation()
        -- Effects outlive the scene that spawned them (Effekseer owns their
        -- lifetime), so without this a leftover effect would bleed into the
        -- next scene's capture and make G5 order-dependent.
        require("presentation.effekseer").reset()
        -- The small-battler idle clock is module-level and accumulates for the
        -- life of the process. Without rewinding it, every scene's sprite frames
        -- depend on how much time the scenes captured BEFORE it consumed, so
        -- editing one scene's script reddens unrelated frames and G5 is
        -- order-dependent.
        require("presentation.small_battlers").reset()
        dock.reset()
        stringPictures.clear()
        imagePictures.clear()
        require("presentation.scene_transition").clear()
        require("presentation.subtractive_transition").clear()
        require("presentation.ui_anim").reset()
        require("presentation.animation_player").reset()
    end

    -- Generated dungeon maps ordinarily seed from wall-clock time. Screenshot
    -- output must be reproducible, so pin only the map-load call and restore
    -- os.time immediately afterward.
    local function loadHarnessMap(vSession, mapIndex)
        local originalTime = os.time
        os.time = function() return 12345 end
        local okLoad, loadErr = pcall(function()
            exploration.loadMap(vSession, mapIndex)
        end)
        os.time = originalTime
        if not okLoad then error(loadErr, 0) end
    end

    local originalGetTime = love.timer.getTime
    love.timer.getTime = function() return captureClock end
    local ok, err = pcall(function()
      withHermeticSaves(function()
        require("presentation.ui").init()
        -- Effects must be capturable, or G5 -- the only gate that can see them
        -- -- would be blind to exactly the thing it was built for. Degrades to
        -- a no-op when the shim DLL is absent, so the gate still runs on a
        -- machine with no native build.
        require("presentation.effekseer").init(loader)
        for _, sceneDef in ipairs(loader.scenes or {}) do
            captureClock = 0
            math.randomseed(12345)
            -- Effect randomness is seeded per scene for the same reason the
            -- Lua RNG is: otherwise a frame containing a live effect depends
            -- on how many effects earlier scenes happened to play, and cannot
            -- be held as a reference.
            require("presentation.effekseer").setRandomSeed(12345)
            local vSession = makeHarnessSession(loader)
            _G.activeSession = vSession
            resetPresentation()
            renderer.init(vSession)
            scene_host.init(nil)

            local sceneId = tostring(sceneDef.id)
            local folder = slug(sceneDef.kind or "scene") .. "/" .. slug(sceneId)
            local ctx = {
                session = vSession, loader = loader,
                party = vSession.party, events = {},
            }

            if sceneId == "map" then
                loadHarnessMap(vSession, 1)
                positionAtClearCorridor(vSession)
                viewport_3d.init()
                scene_host.push(sceneDef.id, ctx)
            elseif sceneId == "battle" then
                local dungeonMapIndex = 1
                for index, mapData in ipairs(loader.maps or {}) do
                    if mapData.safe ~= true then
                        dungeonMapIndex = index
                        break
                    end
                end
                loadHarnessMap(vSession, dungeonMapIndex)
                positionAtClearCorridor(vSession)
                viewport_3d.init()
                require("engine.scenes.battle").triggerTestBattle()
            else
                -- A scene declaring `backdrop: "map"` is composited over the
                -- world in play, so capturing it over a void tested a
                -- composite that never occurs -- and with semitransparent
                -- windowskins that is precisely what needs testing. Ten of the
                -- seventeen scenes were captured that way because the map load
                -- was hard-coded to map/battle/dialogue; it is driven off the
                -- scene's own declaration instead.
                if sceneDef.backdrop == "map" then
                    loadHarnessMap(vSession, 1)
                    positionAtClearCorridor(vSession)
                    viewport_3d.init()
                end
                scene_host.push(sceneDef.id, ctx)
            end

            local state = scene_host.getCurrentState()
            if sceneId == "shop" and state then
                local keys = {}
                for k in pairs(loader.shops or {}) do table.insert(keys, tostring(k)) end
                table.sort(keys)
                local shopData = keys[1] and loader.shops[keys[1]]
                if shopData then
                    state.v.shopName = shopData.name or "Shop"
                    state.v.items = {}
                    for _, shopItem in ipairs(shopData.items or {}) do
                        local item = loader.getItem(shopItem.id)
                        if item then
                            table.insert(state.v.items, {
                                id = item.id, name = item.name, icon = item.icon,
                                description = item.description,
                                cost = shopItem.price or item.cost or 0,
                            })
                        end
                    end
                    state.v.count = #state.v.items
                end
            elseif sceneId == "dialogue" and state then
                -- The map load moved to the generic `backdrop: "map"` path
                -- above, which routes through loadHarnessMap and therefore
                -- pins os.time; calling exploration.loadMap directly here
                -- skipped that pin.
                state.v.dialogueMode = "choice"
                state.v.dialogueSpeaker = "Alicia"
                state.v.dialoguePortrait = "NPC_Alicia"
                state.v.dialogueText = "Welcome. What would you like to do?"
                state.v.dialogueWaiting = false
                state.v.dialogueOptions = { "Buy Consumables", "Talk", "Leave" }
                state.v.dialogueCursorIdx = 1
                state.winState = {}
                state.windowOrder = {}
                for _, window in ipairs(sceneDef.windows or {}) do
                    state.winState[window.id] = { open = true }
                    table.insert(state.windowOrder, window.id)
                end
            end

            settleForCapture(vSession)
            capture(folder .. "/00-initial.png", vSession)
            -- G5's Effekseer coverage. A dedicated FROZEN fixture effect
            -- (assets/effects/_gate/, never edited) played on an enemy in its
            -- own isolated frame, so the effekseer code path -- placement,
            -- orientation, batch flush, GL state -- is gated permanently
            -- without any in-use effect's authoring churn reddening the gate.
            -- Deliberately after the initial capture and before the scripted
            -- steps' state changes, and captured to its own file, so it cannot
            -- perturb any other reference.
            if sceneId == "battle" then
                local bv = require("engine.scenes.battle").getState()
                local fixtureTarget = bv and bv.battle and bv.battle.enemies and bv.battle.enemies[1]
                if fixtureTarget then
                    local animation_player = require("presentation.animation_player")
                    local efk = require("presentation.effekseer")
                    -- Deliberately NOT settleForCapture again: the scene is
                    -- already settled, and a second settle advances a
                    -- presentation clock that is not reset between scenes --
                    -- which shifted sprite animation frames in every scene
                    -- captured after battle. One warm-up draw is enough to let
                    -- the drawer spawn the effect (the track is due at t0=0),
                    -- then only EFFECT time advances before the capture.
                    animation_player.play("system.gate_fixture", fixtureTarget)
                    drawWarmup(vSession)
                    efk.update(EFFECT_CAPTURE_SECONDS)
                    capture(folder .. "/99-effekseer-fixture.png", vSession)
                    animation_player.stop(fixtureTarget)
                    efk.reset()

                    -- skill.attack, the first MIGRATED effect, gated on the
                    -- real in-use asset (owner call 01.08.2026).
                    --
                    -- The scripted steps cannot cover it: settleForCapture
                    -- suppresses effect time and advances a whole second, so
                    -- any frame captured after an action resolves shows the
                    -- aftermath, never the effect. That is precisely the gap
                    -- roadmap 6.5.1f left open. Same isolated recipe as the
                    -- fixture above, and its own file so it perturbs nothing.
                    --
                    -- Unlike the frozen fixture this WILL redden when the
                    -- effect is retouched. That is the accepted cost of gating
                    -- the asset that actually ships: confirm the change was
                    -- intended, then recapture.
                    animation_player.play("skill.attack", fixtureTarget)
                    drawWarmup(vSession)
                    efk.update(EFFECT_CAPTURE_SECONDS)
                    capture(folder .. "/98-skill-attack.png", vSession)
                    animation_player.stop(fixtureTarget)
                    efk.reset()
                end
            end

            for index, step in ipairs(sceneDef.screenshotScript or sceneDef.goldenScript or {}) do
                scene_host.update(0.1, ctx)
                advancePresentation(0.1)
                scene_host.keypressed(step.key, ctx)
                settleForCapture(vSession)
                capture(string.format(
                    "%s/%02d-after-%s.png", folder, index, slug(step.key or "step")
                ), vSession)
            end
        end
      end)
    end)
    love.timer.getTime = originalGetTime

    love.graphics.setCanvas()
    print("SCREENSHOTS BEGIN")
    print(json.encode(ok and {
        width = gameWidth, height = gameHeight, captures = captures,
    } or {
        error = tostring(err), captures = captures,
    }))
    print("SCREENSHOTS END")
    if not ok then error(err, 0) end
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

        local pw, ph = 320, 104
        local previewCanvas = love.graphics.newCanvas(pw, ph)
        love.graphics.setCanvas(previewCanvas)
        love.graphics.clear(0, 0, 0, 1)
        love.graphics.setColor(1, 1, 1, 1)
        ui.drawPanel(4, 4, pw - 8, ph - 8)
        local previewLines = {
            "Il1| MW @# 0123456789",
            "AÇÃO bênção coração",
            "HP 99/99  MP 32/48",
            "SABAN attacks the Wight.",
            "The rite remembers its heirs.",
        }
        for i, line in ipairs(previewLines) do
            ui.drawString(line, 12, 12 + (i - 1) * ui.lineHeight)
        end
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
        if x or y or dir then
            if x then vSession.playerX = tonumber(x) + 1 end
            if y then vSession.playerY = tonumber(y) + 1 end
            if dir then vSession.playerDir = dir end
        else
            positionAtClearCorridor(vSession)
        end

        viewport_3d.init()

        local pw, ph = 256, 144
        local previewCanvas = love.graphics.newCanvas(pw, ph)
        love.graphics.setCanvas({ previewCanvas, depth = true, stencil = true })
        love.graphics.clear(0, 0, 0, 1, true, true)
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

-- Image-authored geometry contact sheet. The asset is installed only in a
-- temporary in-memory tileset, so a preview can never change campaign data,
-- procedural placement or golden captures.
--
-- Renders down a genuine one-cell corridor rather than at a head-on wall:
-- displacement is only legible obliquely, and a flat-on view mostly tests
-- albedo. Each asset is captured undisplaced and displaced so the pair shows
-- what the height field actually contributed.
function cli.runPreviewGeometry(assetPath, loader, overlayPath)
    local json = require("data.json")
    local payload = { captures = {}, width = 256, height = 144 }
    local ok, err = pcall(function()
        local viewport_3d = require("presentation.viewport_3d")
        local geometry = require("engine.geometry")
        local base = assert(loader.tilesets.dungeon_default, "dungeon_default tileset missing")
        local spec = geometry.check(assetPath)
        -- An overlay makes this a COMPOSITION preview: base surface plus a
        -- surface fixture, meshed as one coherent surface.
        local layers = { assetPath }
        if overlayPath then
            geometry.check(overlayPath)
            layers[#layers + 1] = overlayPath
        end
        payload.asset = { id = spec.id, topology = spec.topology, role = spec.role,
            surface = spec.surface, heightScale = spec.heightScale, layers = layers }

        -- The final composed pair, always emitted: it is the diagnostic that
        -- says whether a problem is in the art, the composition or the mesh.
        local albedoField, heightField = geometry.debugFields(layers)
        payload.fields = {
            albedo = love.data.encode("string", "base64", albedoField:encode("png")),
            height = love.data.encode("string", "base64", heightField:encode("png")),
        }
        viewport_3d.init()
        for _, displaced in ipairs({ false, true }) do
            -- Resolver output is cached by tileset identity, so each case needs
            -- a distinct ephemeral identity.
            local tilesetId = "geometry_preview_" .. tostring(displaced)
            loader.tilesets[tilesetId] = {
                id = tilesetId, texture = base.texture,
                tileWidth = base.tileWidth, tileHeight = base.tileHeight,
                base = base.base, doors = {},
                -- An object fixture stands in the cell; a surface fixture
                -- belongs on the wall face. Previewing either in the other's
                -- placement says nothing useful about the asset.
                features = displaced and { {
                    id = "preview", geometry = overlayPath and layers or assetPath,
                    role = spec.role == "objectFixture" and "floor_feature" or "wall_feature",
                } } or {},
            }
            -- An object fixture needs room to be walked around; a surface
            -- fixture is judged down a one-cell corridor, where oblique
            -- viewing is what makes displacement legible.
            local width, height = 14, spec.role == "objectFixture" and 7 or 3
            local grid = {}
            for y = 1, height do
                grid[y] = {}
                for x = 1, width do
                    grid[y][x] = (y == 1 or y == height or x == 1 or x == width) and "#" or "."
                end
            end
            local previewSession = session.GameSession.new(loader)
            previewSession.mapGrid = grid
            previewSession.currentMapData = {
                tileset = tilesetId, ceilingStyle = "solid", events = {},
            }
            previewSession.generatedFeatures = {}
            if displaced and spec.role == "objectFixture" then
                -- A few spaced along the corridor floor: near enough to read
                -- the silhouette, far enough to judge it at distance.
                for _, featureX in ipairs({ 6, 8, 10 }) do
                    previewSession.generatedFeatures[#previewSession.generatedFeatures + 1] =
                        { x = featureX, y = 3, material = "preview" }
                end
            elseif displaced then
                -- Cover both corridor walls so displacement changes the whole
                -- side profile rather than one distant panel.
                for featureX = 4, width - 2 do
                    previewSession.generatedFeatures[#previewSession.generatedFeatures + 1] =
                        { x = featureX, y = 0, material = "preview" }
                    previewSession.generatedFeatures[#previewSession.generatedFeatures + 1] =
                        { x = featureX, y = height - 1, material = "preview" }
                end
            end
            -- An object fixture is judged on its silhouette from every side,
            -- not just head-on: a shell that reads well from the front can be
            -- a slab from the side. A surface fixture only ever presents its
            -- one face, so one viewpoint is the honest test for it.
            -- Session player coordinates are ONE-based while generated feature
            -- placements are zero-based, so an object placed at y=2 stands on
            -- player row 3. Getting this wrong puts the camera inside the
            -- object or inside a wall.
            local viewpoints = { { x = 4, y = 2, dir = "E", angle = "front" } }
            if spec.role == "objectFixture" then
                viewpoints[1] = { x = 3, y = 4, dir = "E", angle = "front" }
                -- Stand in the row BESIDE the middle object and look across
                -- it: a shell that reads well head-on can still be a slab in
                -- profile, and only this view shows that.
                -- Two cells back, not one: pressed right against the object
                -- the near plane clips it and nothing about the profile reads.
                viewpoints[#viewpoints + 1] = { x = 9, y = 6, dir = "N", angle = "side" }
            end
            for _, viewpoint in ipairs(viewpoints) do
                for _, wireframe in ipairs({ false, true }) do
                    previewSession.playerX = viewpoint.x
                    previewSession.playerY = viewpoint.y
                    previewSession.playerDir = viewpoint.dir
                    local canvas = love.graphics.newCanvas(payload.width, payload.height)
                    love.graphics.setCanvas({ canvas, depth = true, stencil = true })
                    love.graphics.clear(0, 0, 0, 1, true, true)
                    -- Wireframe is a driver-level mode, so it shows the exact
                    -- triangulation the GPU receives rather than a redrawing
                    -- of what the compiler believes it emitted.
                    if wireframe then love.graphics.setWireframe(true) end
                    viewport_3d.draw(previewSession)
                    if wireframe then love.graphics.setWireframe(false) end
                    love.graphics.setCanvas()
                    payload.captures[#payload.captures + 1] = {
                        displaced = displaced, angle = viewpoint.angle,
                        wireframe = wireframe,
                        image = love.data.encode("string", "base64",
                            canvas:newImageData():encode("png")),
                    }
                    viewport_3d.invalidateStructure(previewSession)
                end
            end
            loader.tilesets[tilesetId] = nil
        end
    end)
    loader.tilesets["geometry_preview_true"] = nil
    loader.tilesets["geometry_preview_false"] = nil
    love.graphics.setCanvas()
    if not ok then payload = { error = tostring(err) } end
    print("GEOMETRY PREVIEW BEGIN")
    print(json.encode(payload))
    print("GEOMETRY PREVIEW END")
end

-- Deterministic headless 3D renderer profile. `flush` makes each sample include
-- command submission instead of measuring only Lua-side queue construction.
function cli.runProfile3D(mapId, frameCount, loader)
    local json = require("data.json")
    local exploration = require("engine.exploration")
    local viewport_3d = require("presentation.viewport_3d")
    local mapIdx
    for idx, map in ipairs(loader.maps or {}) do
        if tostring(map.id) == tostring(mapId) then mapIdx = idx break end
    end
    if not mapIdx then error("map not found: " .. tostring(mapId)) end

    local session = makeHarnessSession(loader)
    -- Generated dungeon maps normally seed from wall-clock time. Pin that
    -- input so repeated profiles compare the same topology and draw workload.
    local originalTime = os.time
    os.time = function() return 1735689600 end
    local loaded, loadError = pcall(exploration.loadMap, session, mapIdx)
    os.time = originalTime
    if not loaded then error(loadError, 0) end
    positionAtClearCorridor(session)
    viewport_3d.init()
    local canvas = love.graphics.newCanvas(256, 240)
    love.graphics.setCanvas({ canvas, depth = true, stencil = true })

    local function renderSample()
        love.graphics.clear(0, 0, 0, 1, true, true)
        local started = love.timer.getTime()
        viewport_3d.draw(session)
        love.graphics.flushBatch()
        return (love.timer.getTime() - started) * 1000
    end
    collectgarbage("collect")
    local statsBefore = love.graphics.getStats()
    local luaKbBefore = collectgarbage("count")
    local coldMs = renderSample()
    for _ = 1, 20 do renderSample() end

    local count = math.max(1, math.floor(tonumber(frameCount) or 300))
    local samples, total = {}, 0
    for i = 1, count do
        samples[i] = renderSample()
        total = total + samples[i]
    end
    table.sort(samples)
    local function percentile(p)
        return samples[math.max(1, math.min(count, math.ceil(count * p)))]
    end
    local statsAfter = love.graphics.getStats()
    local structure = viewport_3d.prepareStructure(session)
    local frameStats = viewport_3d.getLastFrameStats()
    local batchCount, residentVertices, selectedNodes = 0, 0, 0
    for _, batch in pairs(structure.surfaceBatches or {}) do
        batchCount = batchCount + 1
        residentVertices = residentVertices + #(batch.vertices or {})
        selectedNodes = selectedNodes + #(batch.selected or {})
    end
    love.graphics.setCanvas()
    local payload = {
        mapId = mapId,
        frames = count,
        coldMs = coldMs,
        meanMs = total / count,
        medianMs = percentile(0.50),
        p95Ms = percentile(0.95),
        p99Ms = percentile(0.99),
        minMs = samples[1],
        maxMs = samples[count],
        approximateFps = 1000 / (total / count),
        drawCallsPerFrame = ((statsAfter.drawcalls or 0) - (statsBefore.drawcalls or 0)) / (count + 21),
        canvasSwitchesPerFrame = ((statsAfter.canvasswitches or 0) - (statsBefore.canvasswitches or 0)) / (count + 21),
        textureMemoryBytes = statsAfter.texturememory,
        luaMemoryDeltaKb = collectgarbage("count") - luaKbBefore,
        structuralCacheHits = structure.hits,
        textureBatches = batchCount,
        residentStructuralVertices = residentVertices,
        selectedStructuralNodes = selectedNodes,
        persistentBatchDraws = frameStats.persistentBatchDraws,
        dynamicMeshDraws = frameStats.dynamicMeshDraws,
        modelDraws = frameStats.modelDraws,
        worldEffectHandles = frameStats.worldEffectHandles,
        dynamicByCategory = frameStats.dynamicByCategory,
        dynamicSourceQuads = frameStats.dynamicSourceQuads,
        queuedSurfaces = frameStats.queuedSurfaces,
    }
    print("PROFILE 3D BEGIN")
    print(json.encode(payload))
    print("PROFILE 3D END")
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
        positionAtClearCorridor(vSession)
        if vSession.currentMapData then
            vSession.currentMapData.fog = fogSpec
        end

        viewport_3d.init()

        local pw, ph = 512, 288
        local baseCanvas = love.graphics.newCanvas(256, 144)
        local previewCanvas = love.graphics.newCanvas(pw, ph)
        previewCanvas:setFilter("nearest", "nearest")

        love.graphics.setCanvas({ baseCanvas, depth = true, stencil = true })
        love.graphics.clear(0, 0, 0, 1, true, true)
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
  withHermeticSaves(function()
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

        -- Track how much of each event list has been logged, so we only log
        -- NEW events and never re-log an accumulated ctx.events.
        --
        -- Keyed by the LIST, not a single counter (fixed 29.07.2026). A shared
        -- counter was silently lossy: scene_host.runHook gives each hook a
        -- fresh ctx.events, so any hook returning fewer events than the
        -- previous high-water mark logged NOTHING at all -- `for i = 5, 2` just
        -- doesn't run. That is why declarative scenes' traces are so short, and
        -- it made G3 diffs misleading: removing two commands from one hook
        -- could make unrelated events from a later hook appear, as though the
        -- engine had gained behaviour it always had.
        local loggedCounts = setmetatable({}, { __mode = "k" })

        local function logNewEvents(events)
            if not events then return end
            for i = (loggedCounts[events] or 0) + 1, #events do
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
            loggedCounts[events] = #events
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
  end)
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
