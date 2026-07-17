local ui = require("presentation.ui")
local viewport_3d = require("presentation.viewport_3d")
local exploration = require("engine.exploration")
local battleSystem = require("engine.battle")
local director = require("engine.director")
local traits = require("engine.traits")
local config = require("engine.config")
local small_battlers = require("presentation.small_battlers")
local battle_layout = require("presentation.battle_layout")
local actor_status = require("presentation.actor_status")
local animation_player = require("presentation.animation_player")
local gradient_shader  = require("presentation.gradient_shader")

local renderer = {}

-- Battle layout accessor: engine.json override -> built-in default.
-- Defaults + override lookup live in presentation/battle_layout.lua,
-- shared with actor_status.lua (breaks the require cycle that would
-- otherwise exist between the two modules).
local function layoutVal(key)
    return battle_layout.get(renderer.session, key)
end

local damagePopups = {}
local portraitCache = {}
-- B.5 small battler cache/animation clock live in presentation/small_battlers.lua
-- (shared with the generic window renderer's sprite list rows)

-- B.0: per-character text reveal (battle log lines + dialogue TEXT nodes).
-- Elapsed advances in renderer.update. The battle log tracker walks the log
-- sequentially (cursor = index of the line currently animating); the
-- dialogue tracker resets when its node changes. ui.textRevealDelay <= 0
-- disables the effect.
local battleLogReveal = { cursor = 0, elapsed = 0 }
local dialogueReveal = { node = nil, elapsed = 0 }

-- Victory-window EXP gauge animation (keyed by the victory info table's
-- identity; a new battle produces a new table and re-seeds the animation).
local victoryAnim = { source = nil, members = {}, stage = 0, displayedGold = 0 }

local function revealDelay()
    return (config.ui and config.ui.textRevealDelay) or 0
end

-- Number of characters of `text` currently visible for `elapsed` seconds.
local function revealedCount(text, elapsed)
    local delay = revealDelay()
    if delay <= 0 then return #text end
    return math.min(#text, math.floor(elapsed / delay))
end

-- overhaul-7 A1: animation constants and timing are owned by
-- presentation/animation_player.lua using data/animations.json entries.
-- The small_battlers module still provides the dead-tint constant for
-- game-state dead display.

local function getPortrait(id)
    if not id or id == "" then return nil end
    -- Battlers without a spriteKey fall back to their numeric actor id
    id = tostring(id)
    if portraitCache[id] then return portraitCache[id] end
    
    local paths = {
        "assets/portraits/" .. id .. ".png",
        "assets/portraits/NPC_" .. id .. ".png",
        "assets/portraits/" .. id:lower() .. ".png",
        "assets/portraits/" .. id:sub(1,1):upper() .. id:sub(2):lower() .. ".png"
    }
    for _, p in ipairs(paths) do
        if love.filesystem.getInfo(p) then
            local img = love.graphics.newImage(p)
            img:setFilter("nearest", "nearest")
            portraitCache[id] = img
            return img
        end
    end
    return nil
end

local function drawSlicedPortrait(portraitId, x, y, targetW, targetH)
    local portrait = getPortrait(portraitId)
    if not portrait then return end
    
    local w = portrait:getWidth()
    local h = portrait:getHeight()
    
    -- If it's a sheet (width > 128)
    if w > 128 then
        local fw = 128
        local col = 0 -- default neutral column
        local quad = love.graphics.newQuad(col * fw, 0, fw, h, w, h)
        love.graphics.draw(portrait, quad, x, y, 0, targetW / fw, targetH / h)
    else
        love.graphics.draw(portrait, x, y, 0, targetW / w, targetH / h)
    end
end

local townBg
function renderer.init(session)
    renderer.session = session
    ui.init()
    if love.filesystem.getInfo("assets/locationArt/TownAlencar.png") then
        townBg = love.graphics.newImage("assets/locationArt/TownAlencar.png")
        townBg:setFilter("nearest", "nearest")
    end
    damagePopups = {}
end

-- overhaul-7 A1: per-enemy animation state is now owned by
-- presentation/animation_player.lua. The `deadEnemyFlags` table tracks
-- which enemies are game-state dead (separate from animation effects).
-- Animation timers, tints, blend modes, and transforms are queried from
-- the animation player at draw time.
local deadEnemyFlags = {}

local function updatePopupGlyph(glyph, dt, gravity, bounceRetain)
    glyph.vy = glyph.vy + gravity * dt
    glyph.x = glyph.x + glyph.vx * dt
    glyph.y = glyph.y + glyph.vy * dt
    if glyph.y >= 0 and glyph.vy > 0 then
        glyph.y = 0
        if glyph.bounceCount < 2 then
            glyph.vy = -glyph.vy * bounceRetain
            glyph.vx = glyph.vx * 0.6
            glyph.bounceCount = glyph.bounceCount + 1
        else
            glyph.vy = 0
            glyph.vx = 0
        end
    end
end

function renderer.initBattleAnims(enemies)
    animation_player.reset()
    deadEnemyFlags = {}
    for i, enemy in ipairs(enemies) do
        animation_player.play("system.enemy_slide_in", enemy)
    end
end

function renderer.triggerDeathAnim(enemyIdx)
    local enemy = renderer.activeBattle and renderer.activeBattle.enemies[enemyIdx]
    if enemy then
        deadEnemyFlags[enemy] = true
        animation_player.play("system.death", enemy)
    end
end

function renderer.triggerActionFlash(enemyIdx, flashType)
    local enemy = renderer.activeBattle and renderer.activeBattle.enemies[enemyIdx]
    if enemy then
        local entryId = (flashType == "action") and "system.action_flash" or "system.damage_flash"
        animation_player.play(entryId, enemy)
    end
end

-- Damage feedback (flash + shake) for a battler. Keyed by battler identity
-- in presentation/small_battlers.lua, so the same state is visible to
-- actor_status.draw and window_renderer.lua's party-shaped list rows alike.
function renderer.triggerSmallDamage(target)
    small_battlers.triggerDamage(target)
end

function renderer.update(dt)
    local gravity = config.physics and config.physics.gravity or 480
    local bounceRetain = config.physics and config.physics.bounceVelocityRetain or 0.45
    for i = #damagePopups, 1, -1 do
        local p = damagePopups[i]
        p.revealElapsed = p.revealElapsed + dt
        if p.revealElapsed >= (p.spawnDelay or 0) then
            local activeElapsed = p.revealElapsed - (p.spawnDelay or 0)
            for _, glyph in ipairs(p.glyphs) do
                if not glyph.active and activeElapsed >= glyph.startDelay then
                    glyph.active = true
                end
                if glyph.active then
                    if p.isText then
                        glyph.elapsed = glyph.elapsed + dt
                        local t = math.min(1, glyph.elapsed / 0.4)
                        glyph.y = -28 * t * (2 - t)
                    else
                        updatePopupGlyph(glyph, dt, gravity, bounceRetain)
                    end
                end
            end
        end
        p.life = p.life - dt
        if p.life <= 0 then table.remove(damagePopups, i) end
    end
    -- overhaul-7 A1: animation player owns all battler animation timing
    animation_player.update(dt)
    animation_player.updateParticles(dt)
    small_battlers.updateAnims(dt)
    
    -- Smoothly interpolate party HP and the shared party MP pool
    local session = renderer.session
    if session then
        if renderer.activeBattle then
            for _, enemy in ipairs(renderer.activeBattle.enemies) do
                if not enemy.displayedHp then enemy.displayedHp = enemy.hp end
                enemy.displayedHp = enemy.displayedHp + (enemy.hp - enemy.displayedHp) * 8 * dt
                if math.abs(enemy.hp - enemy.displayedHp) < 0.1 then enemy.displayedHp = enemy.hp end
            end
        end
        
        if session.party then
            for _, c in ipairs(session.party) do
                if not c.displayedHp then c.displayedHp = c.hp end
                c.displayedHp = c.displayedHp + (c.hp - c.displayedHp) * 8 * dt
                if math.abs(c.hp - c.displayedHp) < 0.1 then c.displayedHp = c.hp end
            end
        end
        
        if not session.displayedMp then session.displayedMp = session.mp end
        session.displayedMp = session.displayedMp + (session.mp - session.displayedMp) * 8 * dt
        if math.abs(session.mp - session.displayedMp) < 0.1 then session.displayedMp = session.mp end
    end
    
    -- B.5: Advance small battler animation timer (shared, drives all party sprite animations)
    small_battlers.update(dt)

    -- B.0: advance text-reveal timers (reset happens at the draw sites when
    -- the tracked line/node changes)
    battleLogReveal.elapsed = battleLogReveal.elapsed + dt
    dialogueReveal.elapsed = dialogueReveal.elapsed + dt

    -- Victory-window EXP gauges animate toward their post-battle values,
    -- rolling over and incrementing the level as thresholds are crossed.
    -- Stage 0 = ready (press ENTER to start), 1 = draining, 2 = done.
    -- Gold grant drains from X→0 while party total rises from pre→post.
    if victoryAnim.source and victoryAnim.stage == 1 then
        local info = victoryAnim.source
        local speed = (config.battle_screen and config.battle_screen.victoryExpPerSecond) or 30
        local expPerLevel = info.expPerLevel or 15

        -- Animate EXP gauges
        for i, m in ipairs(info.members or {}) do
            local a = victoryAnim.members[i]
            if a and (a.level < m.toLevel or a.exp < m.toExp) then
                a.exp = a.exp + speed * dt
                local needed = a.level * expPerLevel
                while a.exp >= needed and a.level < m.toLevel do
                    a.exp = a.exp - needed
                    a.level = a.level + 1
                    needed = a.level * expPerLevel
                end
                if a.level >= m.toLevel and a.exp >= m.toExp then
                    a.level = m.toLevel
                    a.exp = m.toExp
                end
            end
        end

        -- Animate gold drain-down: grant amount (displayedGoldDrain) ticks
        -- from victoryInfo.gold toward 0; party total displayedPartyGold
        -- ticks from preGold toward preGold + victoryInfo.gold.
        local gs = speed * 3 * dt
        victoryAnim.displayedGoldDrain = math.max(0, (victoryAnim.displayedGoldDrain or info.gold) - gs)
        local targetGold = (victoryAnim.preGold or 0) + info.gold
        victoryAnim.displayedPartyGold = math.min(targetGold, (victoryAnim.displayedPartyGold or victoryAnim.preGold or 0) + gs)

        -- Check if all drains complete → advance to stage 2
        local allDone = victoryAnim.displayedGoldDrain <= 0
            and victoryAnim.displayedPartyGold >= targetGold
        for i, m in ipairs(info.members or {}) do
            local a = victoryAnim.members[i]
            if a and (a.level < m.toLevel or a.exp < m.toExp) then
                allDone = false
            end
        end
        if allDone then
            victoryAnim.stage = 2
        end
    end
end

-- Expose victory animation stage so battle.handleTransition can check it.
renderer.getVictoryStage = function() return victoryAnim.stage end

-- Dialogue text-reveal control for the input layer: a confirm press while
-- text is still revealing completes it instead of advancing the node.
function renderer.isDialogueRevealing()
    local node = dialogueReveal.node
    if not node or node.type ~= "TEXT" then return false end
    local content = node.content or ""
    return revealedCount(content, dialogueReveal.elapsed) < #content
end

function renderer.finishDialogueReveal()
    dialogueReveal.elapsed = math.huge
end

function renderer.isBattleLogRevealing(combatLog)
    local cursor = battleLogReveal.cursor
    if not combatLog or cursor == 0 or cursor > #combatLog then return false end
    local current = combatLog[cursor] or ""
    return revealedCount(current, battleLogReveal.elapsed) < #current
end

function renderer.finishBattleLogReveal()
    battleLogReveal.elapsed = math.huge
end

function renderer.addDamagePopup(text, x, y, color, isText)
    isText = isText or (not text:match("^[%d%+%- ]+$"))
    local scatter = config.physics and config.physics.horizontalScatter or 40
    local lifeSpan = config.battle_screen and config.battle_screen.damagePopupLife or 1.1
    local popupConfig = config.battle_screen and config.battle_screen.popup or {}
    local characterDelay = popupConfig.characterDelay or 0
    
    -- Find if there are existing active/pending popups at the same (x, y) coordinates
    local sameLocCount = 0
    for _, p in ipairs(damagePopups) do
        if math.abs(p.x - x) < 5 and math.abs(p.y - y) < 5 then
            sameLocCount = sameLocCount + 1
        end
    end
    local spawnDelay = sameLocCount * 0.45 -- 0.45s delay per active popup at this location

    local glyphs = {}
    for i = 1, #text do
        table.insert(glyphs, {
            char = text:sub(i, i),
            startDelay = (i - 1) * characterDelay,
            active = false,
            elapsed = 0,
            x = 0,
            y = 0,
            vy = -160,
            vx = isText and 0 or math.random(-scatter, scatter),
            bounceCount = 0
        })
    end
    table.insert(damagePopups, {
        text = text,
        x = x,
        y = y,
        color = color or {1, 1, 1, 1},
        life = lifeSpan + spawnDelay,
        revealElapsed = 0,
        spawnDelay = spawnDelay,
        isText = isText,
        glyphs = glyphs
    })
end

-- Renders the mini-map in a small panel
local function drawMinimap(x, y, size)
    local grid = renderer.session.mapGrid
    if not grid then return end
    
    local px, py = renderer.session.playerX, renderer.session.playerY
    local tileSize = 4
    
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x, y, #grid[1] * tileSize + 4, #grid * tileSize + 4)
    love.graphics.setColor(0.3, 0.3, 0.4, 0.8)
    love.graphics.rectangle("line", x, y, #grid[1] * tileSize + 4, #grid * tileSize + 4)
    
    for gy = 1, #grid do
        for gx = 1, #grid[gy] do
            if renderer.session.visitedGrid[gy][gx] then
                local cell = grid[gy][gx]
                
                -- Check for coordinate-based event at this tile (0-indexed coordinates)
                local mapEvent = nil
                if renderer.session.currentMapData and renderer.session.currentMapData.events then
                    for _, ev in ipairs(renderer.session.currentMapData.events) do
                        if ev.x == gx - 1 and ev.y == gy - 1 then
                            mapEvent = ev
                            break
                        end
                    end
                end
                
                if mapEvent then
                    -- Marker color precedence: the map event's own
                    -- minimapColor, else the linked common event's default,
                    -- else light blue for generic NPCs / shops.
                    local evColor = mapEvent.minimapColor
                    if not evColor and mapEvent.scriptId and renderer.session.loader and renderer.session.loader.commonEvents then
                        local ce = renderer.session.loader.commonEvents[tostring(mapEvent.scriptId)]
                        evColor = ce and ce.minimapColor or nil
                    end
                    if evColor then
                        love.graphics.setColor(evColor[1] or 0, evColor[2] or 0, evColor[3] or 0, evColor[4] or 1)
                    else
                        love.graphics.setColor(0.4, 0.6, 1, 1)
                    end
                elseif cell == "#" then
                    love.graphics.setColor(0.2, 0.2, 0.2, 1)
                else
                    love.graphics.setColor(0.4, 0.4, 0.4, 1)
                end
                love.graphics.rectangle("fill", x + 2 + (gx - 1) * tileSize, y + 2 + (gy - 1) * tileSize, tileSize - 1, tileSize - 1)
            end
        end
    end
    
    -- Draw player position as blinking red pixel
    local blink = math.floor(love.timer.getTime() * 4) % 2 == 0
    if blink then
        love.graphics.setColor(1, 0, 0, 1)
    else
        love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.rectangle("fill", x + 2 + (px - 1) * tileSize, y + 2 + (py - 1) * tileSize, tileSize - 1, tileSize - 1)
end


-- Renders the Town Scene
function renderer.drawTown(selectedIdx)
    -- Draw Town Background
    if townBg then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(townBg, 0, 0, 0, 256/townBg:getWidth(), ui.toPx(18)/townBg:getHeight())
    else
        love.graphics.clear(0.1, 0.1, 0.15, 1)
    end
    
    -- Town Options
    ui.drawPanel(ui.toPx(1), ui.toPx(1), ui.toPx(13), ui.toPx(15))
    ui.drawString("TOWN SQUARE", ui.toPx(2), ui.toPx(2), {1, 0.85, 0.5, 1})
    
    -- Town options are data-driven (system.town.options)
    local townOptions = (config.town and config.town.options) or {}
    for i, opt in ipairs(townOptions) do
        local color = (i == selectedIdx) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local optY = ui.toPx(2) + i * ui.lineHeight
        if i == selectedIdx then
            small_battlers.draw("Cursor", ui.toPx(2) + 2, optY, 8)
        end
        ui.drawString(opt.label or "???", ui.toPx(2) + 12, optY, color)
    end
end

-- Renders the Map Scene
function renderer.drawMap()
    viewport_3d.draw(renderer.session)
    
    -- Mini-map overlay
    drawMinimap(170, 6, 6)
    
    -- Coordinates & Facing Overlay
    ui.drawString("X:" .. renderer.session.playerX .. " Y:" .. renderer.session.playerY .. " [" .. renderer.session.playerDir .. "]", 6, 6, {1, 1, 0.7, 0.8})
    
    -- Front action prompt if any
    local frontTile, tx, ty = exploration.getFrontTile(renderer.session)
    local hasEvent = false
    if tx and ty and renderer.session.currentMapData and renderer.session.currentMapData.events then
        for _, ev in ipairs(renderer.session.currentMapData.events) do
            if ev.x == tx - 1 and ev.y == ty - 1 then
                hasEvent = true
                break
            end
        end
    end

    if (frontTile and frontTile ~= "#" and frontTile ~= ".") or hasEvent then
        local label = "INTERACT [SPACE]"
        if frontTile == "E" then label = "STAIRS DOWN [SPACE]"
        elseif frontTile == "S" then label = "STAIRS UP [SPACE]"
        elseif frontTile == "R" then label = "RECOVERY [SPACE]"
        elseif frontTile == "T" then label = "TREASURE [SPACE]"
        end
        ui.drawPanel(60, 105, 136, 26)
        ui.drawString(label, 64, 112, {1, 1, 0.5, 1}, "center", 128)
    end
end

-- Renders the Dialogue / Graph Walker Scene
function renderer.drawDialogue(walker, selectIdx)
    -- Render background under dialogue
    viewport_3d.draw(renderer.session)
    
    local node = walker:getCurrentNode()
    if not node then return end
    
    -- Draw portrait if speaker has one
    local portraitId = node.speaker or walker.graph.portrait
    if portraitId then
        love.graphics.setColor(1, 1, 1, 1)
        drawSlicedPortrait(portraitId, ui.toPx(1), ui.toPx(2), ui.toPx(10), ui.toPx(14))
    end
    
    -- Dialogue window
    local winX = portraitId and ui.toPx(12) or ui.toPx(1)
    local winW = portraitId and ui.toPx(19) or ui.toPx(30)
    ui.drawPanel(winX, ui.toPx(1), winW, ui.toPx(16))
    
    -- Speaker name
    local speakerName = node.speaker
    if speakerName and speakerName ~= "" then
        -- Parse \eventName if present
        local rName = string.gsub(walker.eventName or "??", "%%", "%%%%")
        speakerName = string.gsub(speakerName, "\\eventName", rName)
        ui.drawString(speakerName, winX + ui.toPx(1), ui.toPx(2), {1, 0.9, 0.4, 1})
    end
    
    if node.type == "TEXT" then
        -- B.0: reveal the text character by character (ui.textRevealDelay)
        if dialogueReveal.node ~= node then
            dialogueReveal.node = node
            dialogueReveal.elapsed = 0
        end
        local content = node.content or ""
        local shown = content:sub(1, revealedCount(content, dialogueReveal.elapsed))
        ui.drawString(shown, winX + ui.toPx(1), (ui.toPx(4) + (config.windowLayout and config.windowLayout.headerSpacing or 0)), {1, 1, 1, 1}, "left", winW - ui.toPx(2), walker.eventName)
        ui.drawString("[Press SPACE]", winX + ui.toPx(1), ui.toPx(14), {0.6, 0.6, 0.6, 1}, "right", winW - ui.toPx(3))
    elseif node.type == "CHOICE" then
        ui.drawString(node.content or "Choose option:", winX + ui.toPx(1), (ui.toPx(4) + (config.windowLayout and config.windowLayout.headerSpacing or 0)), {1, 1, 1, 1}, "left", winW - ui.toPx(2), walker.eventName)
        for i, opt in ipairs(node.options or {}) do
            local color = (i == selectIdx) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local optY = ui.toPx(5) + i * ui.lineHeight
            if i == selectIdx then
                small_battlers.draw("Cursor", winX + ui.toPx(1) + 2, optY, 8)
            end
            ui.drawString(opt.label, winX + ui.toPx(1) + 12, optY, color)
        end
    end
end

-- The 2x2 party grid is now a thin arrangement loop: every party member's
-- cell content (sprite, icons, name, HP text, HP bar, windowskin panel) is
-- drawn by actor_status.draw — the SAME function any scene's party list
-- uses (owner direction 11.07.2026: one actor-status thing, called once
-- per member, everywhere a party is shown).
function renderer.drawPartyGrid(x, y, selectedIdx, session, showCursor)
    for i = 1, 4 do
        local c = session.party[i]
        local slotX, slotY = actor_status.gridSlot(x, y, i, session)
        local isSel = (showCursor and i == selectedIdx)
        if c then
            actor_status.draw(c, slotX, slotY, isSel, session)
        else
            actor_status.drawEmpty(slotX, slotY, isSel, session)
        end
    end
end


-- Maps a battler to the screen position where damage popups should spawn.
-- Used by main.lua so popup coordinates always match the drawn battle layout.
function renderer.getBattlerCoords(battleState, session, target)
    if battleState then
        for idx, enemy in ipairs(battleState.enemies) do
            if enemy == target then
                local spacing = layoutVal("enemyRowWidth") / #battleState.enemies
                local ex = layoutVal("enemyStartX") + (idx - 1) * spacing
                return ex + layoutVal("enemyPopupOffsetX"), layoutVal("enemyPopupY")
            end
        end

        -- Read layout coordinates dynamically from the "party" window configuration
        local loaderRef = session and session.loader
        local layouts = loaderRef and loaderRef.engine and loaderRef.engine.windowLayout
        local partyLayout = layouts and layouts.party or {}
        local px = partyLayout.x or 0
        local py = partyLayout.y or 18
        local title = partyLayout.title
        local contentX = partyLayout.contentX or partyLayout.textX or 1
        local contentY = partyLayout.contentY or (title and title ~= "" and 2 or 1)

        local gridX = ui.toPx(px + contentX)
        local gridY = ui.toPx(py + contentY)
        local cols = partyLayout.gridColumns or 2

        -- Shared 2x2 slot arithmetic (matches drawPartyGrid exactly)
        for idx, c in ipairs(session.party) do
            if c == target then
                local slotX, slotY = actor_status.gridSlot(gridX, gridY, idx, session, cols)
                return slotX + layoutVal("slotPopupOffsetX"), slotY + layoutVal("slotPopupOffsetY")
            end
        end
    end
    return layoutVal("fallbackX"), layoutVal("fallbackY")
end

-- F2 (overhaul-6): the shared party HUD (console + MP + 2x2 grid) is now the
-- declarative "party" window in presentation/window_renderer.lua, drawn for
-- every scene by main.lua's drawSharedPartyHud — no legacy party HUD remains.

local function getHoveredTargets(bv, combatState, selectedIndex, spellSelect, itemSelect, livingMembers, activeMemberIdx)
    if combatState ~= "input" then return {} end
    local session = renderer.session
    if not session or not bv then return {} end
    
    local memberInfo = livingMembers and livingMembers[activeMemberIdx]
    if not memberInfo then return {} end
    local monster = memberInfo.actor

    -- Unified targeting selector mode (T2)
    if bv.targetSelect then
        local pending = bv.pendingAction
        if not pending then return {} end
        
        local targeting = require("engine.targeting")
        local spec = pending.targetSpec
        local exp = targeting.expand(spec)
        
        local candidates = targeting.getCandidates(monster, spec, bv.battle, pending.skill or pending.item)
        if #candidates == 0 then return {} end
        
        if exp.count == "all" then
            return candidates
        else
            local idx = bv.targetIndex or 1
            if idx < 1 then idx = 1 end
            if idx > #candidates then idx = #candidates end
            bv.targetIndex = idx
            return { candidates[idx] }
        end
    end

    return {}
end

local function getBattlerRect(target, battleState, session)
    if not battleState or not session or not target then return nil, nil, nil, nil end
    local tx, ty, tw, th
    
    -- Is it an enemy?
    local isEnemy = false
    local enemyIdx = nil
    for idx, enemy in ipairs(battleState.enemies) do
        if enemy == target then
            isEnemy = true
            enemyIdx = idx
            break
        end
    end
    
    if isEnemy then
        local spacing = layoutVal("enemyRowWidth") / #battleState.enemies
        local ex = layoutVal("enemyStartX") + (enemyIdx - 1) * spacing
        local ey = layoutVal("enemyY")
        local portrait = getPortrait(target.spriteKey or target.id)
        tw = portrait and layoutVal("enemySpriteSize") or layoutVal("enemyFallbackSize")
        th = tw
        tx = ex
        ty = ey
    else
        -- It's a party member
        local allyIdx = nil
        for idx, c in ipairs(session.party) do
            if c == target then
                allyIdx = idx
                break
            end
        end
        
        if allyIdx then
            local loaderRef = session.loader
            local layouts = loaderRef and loaderRef.engine and loaderRef.engine.windowLayout
            local partyLayout = layouts and layouts.party or {}
            local px = partyLayout.x or 0
            local py = partyLayout.y or 18
            local title = partyLayout.title
            local contentX = partyLayout.contentX or partyLayout.textX or 1
            local contentY = partyLayout.contentY or (title and title ~= "" and 2 or 1)

            local gridX = ui.toPx(px + contentX)
            local gridY = ui.toPx(py + contentY)
            local cols = partyLayout.gridColumns or 2
            local slotX, slotY = actor_status.gridSlot(gridX, gridY, allyIdx, session, cols)
            
            local colW, rowH = actor_status.cellSize(session)
            tx = slotX - 2
            ty = slotY - 2
            tw = colW - 2
            th = rowH - 2
        end
    end
    return tx, ty, tw, th
end

local function drawArrow(x1, y1, x2, y2)
    local angle = math.atan2(y2 - y1, x2 - x1)
    local size = 8
    
    -- Translucent glow line
    love.graphics.setLineWidth(4)
    love.graphics.setColor(1, 0.9, 0.4, 0.3)
    love.graphics.line(x1, y1, x2, y2)
    
    -- Brighter inner line
    love.graphics.setLineWidth(2)
    love.graphics.setColor(1, 0.9, 0.4, 0.7)
    love.graphics.line(x1, y1, x2, y2)
    
    -- Arrowhead
    local ax = x2 - size * math.cos(angle - math.pi / 6)
    local ay = y2 - size * math.sin(angle - math.pi / 6)
    local bx = x2 - size * math.cos(angle + math.pi / 6)
    local by = y2 - size * math.sin(angle + math.pi / 6)
    love.graphics.polygon("fill", x2, y2, ax, ay, bx, by)
end

function renderer.drawBattle(battleState, combatLog, combatState, selectedIndex, spellSelect, itemSelect, livingMembers, activeMemberIdx, victoryInfo, victoryStage)
    renderer.activeBattle = battleState
    
    -- Draw 3D dungeon view behind battle scene
    viewport_3d.draw(renderer.session)
    
    -- Subtle darkened overlay (not too heavy)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, layoutVal("viewportOverlayW"), layoutVal("viewportOverlayH"))
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Render enemies portraits in viewport with animations driven by the
    -- animation player (overhaul-7 A1): slide-in, damage/action flash,
    -- death effect — all from data/animations.json entries.
    local spacing = layoutVal("enemyRowWidth") / #battleState.enemies
    for idx, enemy in ipairs(battleState.enemies) do
        local portrait = getPortrait(enemy.spriteKey or enemy.id)
        local ex = layoutVal("enemyStartX") + (idx - 1) * spacing
        local ey = layoutVal("enemyY")
        
        -- Query animation player for current transform, tint, blend, gradient
        local xf    = animation_player.getTransform(enemy)
        local tint  = animation_player.getTint(enemy)
        local blend = animation_player.getBlendMode(enemy)
        local isDeathPlaying = animation_player.isPlaying(enemy, "system.death")
        local isDead = deadEnemyFlags[enemy]

        local spriteW = layoutVal("enemySpriteSize")
        local spriteH = layoutVal("enemySpriteSize")

        -- Anchor at bottom-center of the sprite slot (matches preview).
        -- ex/ey is the top-left of the slot; anchorX/Y is the bottom-center.
        local anchorX = ex + spriteW / 2
        local anchorY = ey + spriteH

        -- Query shake offset and apply it along with transform offsets
        local shakeOff = animation_player.getShakeOffset(enemy)
        local drawX = anchorX + xf.offsetX + shakeOff
        local drawY = anchorY + xf.offsetY

        local partX = drawX
        local partY = drawY

        -- drawEnemySprite draws around (drawX, drawY) as bottom-center origin.
        local function drawEnemySprite()
            if portrait then
                local sx = xf.scaleX * spriteW / portrait:getWidth()
                local sy = xf.scaleY * spriteH / portrait:getHeight()
                -- ox/oy: draw with bottom-center as the pivot so scale/offset
                -- animate from the same anchor the preview uses.
                love.graphics.draw(portrait, drawX, drawY, 0, sx, sy,
                    portrait:getWidth() / 2, portrait:getHeight())
            else
                local fw = layoutVal("enemyFallbackSize")
                love.graphics.rectangle("fill",
                    drawX - fw * xf.scaleX / 2,
                    drawY - fw * xf.scaleY,
                    fw * xf.scaleX, fw * xf.scaleY)
            end
        end

        if not isDead then
            love.graphics.setColor(1, 1, 1, 1)
            animation_player.drawParticles(enemy, partX, partY, drawEnemySprite, "back")
        end

        if isDeathPlaying then
            -- Death animation: tint/blend/transform/gradient from animation player
            if blend then love.graphics.setBlendMode(blend) end
            if tint then
                love.graphics.setColor(tint.color[1], tint.color[2], tint.color[3], tint.alpha)
            else
                love.graphics.setColor(0.6, 0, 0.9, 1)
            end
            gradient_shader.drawWithGradient(enemy, drawEnemySprite, animation_player)
            love.graphics.setBlendMode("alpha")
        elseif not isDead then
            -- Normal draw with gradient map
            love.graphics.setColor(1, 1, 1, 1)
            gradient_shader.drawWithGradient(enemy, drawEnemySprite, animation_player)

            -- Tint flash overlay
            if tint and blend then
                love.graphics.setBlendMode(blend)
                love.graphics.setColor(tint.color[1], tint.color[2], tint.color[3], tint.alpha)
                drawEnemySprite()
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, 1)
            end

            love.graphics.setColor(1, 1, 1, 1)
            animation_player.drawParticles(enemy, partX, partY, drawEnemySprite, "front")

            local maxHp = enemy:getMaxHp(renderer.session)
            love.graphics.setColor(1,1,1,1)
            local enemyIconW = actor_status.drawElementIcons(traits.getElements(enemy, renderer.session), ex, layoutVal("enemyNameY") - 4, renderer.session)
            ui.drawString(enemy.name, ex + enemyIconW, layoutVal("enemyNameY"), {1, 1, 1, 1})
            ui.drawBar(ex, layoutVal("enemyHpBarY"), layoutVal("enemyHpBarWidth"), layoutVal("enemyHpBarHeight"), enemy.displayedHp or enemy.hp, maxHp, {0.8, 0, 0}, {1, 0.3, 0.3})
        end
        -- isDead without isDeathPlaying: enemy has fully faded, don't draw anything
    end
    
    -- Slim dialogue at the top of the screen during Battle Resolution.
    -- B.8: two lines — the previous entry dimmed above the latest one.
    -- B.0: lines reveal character by character, strictly one at a time —
    -- when several lines land in one log advance, each animates at the
    -- bottom slot before the next begins (owner feedback 10.07.2026).
    if combatState == "log" then
        ui.drawPanel(layoutVal("logPanelX"), layoutVal("logPanelY"), layoutVal("logPanelWidth"), layoutVal("logPanelHeight"))
        if battleLogReveal.cursor > #combatLog then
            -- Log was cleared (new battle / showMessage): restart
            battleLogReveal.cursor = math.min(1, #combatLog)
            battleLogReveal.elapsed = 0
        elseif battleLogReveal.cursor == 0 and #combatLog > 0 then
            battleLogReveal.cursor = 1
            battleLogReveal.elapsed = 0
        end
        local current = combatLog[battleLogReveal.cursor] or ""
        local shownCount = revealedCount(current, battleLogReveal.elapsed)
        if shownCount >= #current and battleLogReveal.cursor < #combatLog then
            battleLogReveal.cursor = battleLogReveal.cursor + 1
            battleLogReveal.elapsed = 0
            current = combatLog[battleLogReveal.cursor] or ""
            shownCount = revealedCount(current, 0)
        end
        local previous = combatLog[battleLogReveal.cursor - 1] or ""
        ui.drawString(previous, layoutVal("logTextX"), layoutVal("logTextY"), {0.55, 0.55, 0.55, 1}, "left", layoutVal("logTextLimit"))
        ui.drawString(current:sub(1, shownCount), layoutVal("logTextX"), layoutVal("logTextY") + layoutVal("logLineSpacing"), {1, 1, 1, 1}, "left", layoutVal("logTextLimit"))
        ui.drawString("[SPACE]", layoutVal("logSpaceX"), layoutVal("logSpaceY"), {0.5, 0.5, 0.5, 1}, "right", 40)
    end
    
    -- Bottom status console: party grid. Battler commands no longer live
    -- inside it (B.7). The summoner is not a battle participant
    -- (overhaul-6 F1) and has no status display here.
    local consoleY = ui.toPx(layoutVal("consoleTileY"))
    local consoleH = ui.toPx(layoutVal("consoleTileH"))
    local textX = ui.toPx(layoutVal("consoleTextTileX"))
    local headerY = consoleY + ui.toPx(layoutVal("headerTileOffset"))

    -- B.7: the battler command menu is its own single-line window spanning
    -- the full width, flush above the status console; it opens during input
    -- and closes outside it. No turn-name header (owner feedback 10.07.2026).
    if combatState == "input" then
        -- overhaul-6 F1: the summoner is not a battle participant; every
        -- living member is an active creature with its own command list
        -- (Attack/Skill/Defend/Item/Flee). F7 adds Item as a per-creature
        -- command: selecting it opens an inventory submenu here.
        local memberInfo = livingMembers and livingMembers[activeMemberIdx]
        local loader = renderer.session.loader

        local entries, helps = {}, {}
        local monster = memberInfo and memberInfo.actor
        if spellSelect then
            for _, skId in ipairs((monster and monster.skills) or {}) do
                local sk = loader.getSkill(skId)
                if sk then
                    table.insert(entries, sk.name)
                    table.insert(helps, sk.description or "")
                end
            end
            if #entries == 0 then entries = { "(No skills)" } end
        elseif itemSelect then
            -- F7: inventory submenu. List is the id-sorted non-empty
            -- inventory, matching USE_ITEM's ordering and battle.lua's
            -- applyItem so the highlighted row maps to the committed index.
            local inv = renderer.session and renderer.session.inventory or {}
            local stacks = {}
            for itemId, qty in pairs(inv) do
                if qty > 0 then table.insert(stacks, itemId) end
            end
            table.sort(stacks)
            for _, id in ipairs(stacks) do
                local it = loader.getItem(id)
                if it then
                    table.insert(entries, (it.name or "?") .. " x" .. tostring(inv[id]))
                    table.insert(helps, it.description or "")
                end
            end
            if #entries == 0 then entries = { "(No items)" } end
        else
            entries = loader.getTermList("battle.commands_monster", { "Attack", "Skill", "Defend", "Item", "Flee" })
            helps = loader.getTermList("battle.help_monster", {
                "Strike with a basic attack.",
                "Use one of this creature's skills.",
                "Brace to reduce incoming damage.",
                "Use an item from the inventory.",
                "Attempt to escape the battle.",
            })
        end

        local barH = ui.toPx(layoutVal("commandBarTileH"))
        local barY = consoleY - barH
        local barW = ui.toPx(layoutVal("consoleTileW"))
        ui.drawPanel(0, barY, barW, barH)
        local rowY = barY + layoutVal("commandBarTextYOffset")
        local slot = (barW - textX * 2) / math.max(1, #entries)
        for i, label in ipairs(entries) do
            local isDim = (label == "(No skills)")
            local color = isDim and {0.5, 0.5, 0.5, 1}
                or ((i == selectedIndex) and {1, 1, 0.5, 1} or {1, 1, 1, 1})
            local drawX = textX + math.floor((i - 1) * slot)
            if not isDim and i == selectedIndex then
                small_battlers.draw("Cursor", drawX + 2, rowY, 8)
            end
            ui.drawString(label, drawX + 12, rowY, color)
        end

        -- Help window: same panel as the battle log, describing the selected
        -- command or skill (owner feedback 10.07.2026).
        local helpText = helps[selectedIndex] or ""
        if helpText ~= "" then
            ui.drawPanel(layoutVal("logPanelX"), layoutVal("logPanelY"), layoutVal("logPanelWidth"), layoutVal("logPanelHeight"))
            ui.drawString(helpText, layoutVal("logTextX"), layoutVal("logTextY"), {1, 1, 1, 1}, "left", layoutVal("logTextLimit"))
        end
    end

    local session = renderer.session

    -- Draw party stats in a 2x2 grid on right side of bottom console
    local highlightIdx = 0
    local showHighlight = false
    if combatState == "input" then
        -- overhaul-6 F1: memberInfo.index is the party slot (1-4) directly,
        -- no summoner-offset adjustment needed anymore.
        local memberInfo = livingMembers and livingMembers[activeMemberIdx]
        if memberInfo then
            highlightIdx = memberInfo.index
            showHighlight = true
        end
    end
    -- F2 (overhaul-6): the shared party HUD (console + MP + 2x2 grid) is the
    -- declarative "party" window, drawn by main.lua's drawSharedPartyHud so
    -- every scene uses the ONE shared HUD (no legacy duplicate).

    -- B.9: dedicated victory window (combatState set by battle.handleTransition;
    -- Shows the battle's gold and base EXP grant, plus per-member animated EXP
    -- gauges with To Next. Stage 0 = ready (press ENTER), 1 = draining,
    -- 2 = done (press SPACE to dismiss).
    if combatState == "victory" and victoryInfo then
        if victoryAnim.source ~= victoryInfo then
            victoryAnim.source = victoryInfo
            victoryAnim.stage = 0
            victoryAnim.displayedGoldDrain = victoryInfo.gold or 0
            victoryAnim.preGold = session.gold - (victoryInfo.gold or 0)
            victoryAnim.displayedPartyGold = victoryAnim.preGold
            victoryAnim.members = {}
            for i, m in ipairs(victoryInfo.members or {}) do
                victoryAnim.members[i] = { level = m.fromLevel, exp = m.fromExp }
            end
        end
        -- Sync stage from scene state (battle.handleTransition sets it)
        if victoryAnim.stage == 0 and victoryStage == 1 then
            victoryAnim.stage = 1
        end

        local vx, vy = ui.toPx(layoutVal("victoryPanelTileX")), ui.toPx(layoutVal("victoryPanelTileY"))
        local vw, vh = ui.toPx(layoutVal("victoryPanelTileW")), ui.toPx(layoutVal("victoryPanelTileH"))
        ui.drawPanel(vx, vy, vw, vh, session.loader.getTerm("battle.victory_title", "VICTORY!"))

        local contentX = vx + 10
        local gaugeEndX = contentX + layoutVal("victoryGaugeWidth")
        local ty = vy + 22

        -- Gold grant drains from X→0 while EXP value is static.
        -- Party total gold (at bottom of window) rises from pre→post.
        local drainGold = math.floor((victoryAnim.displayedGoldDrain or victoryInfo.gold or 0) + 0.5)
        local drainStr = "+" .. drainGold .. "G"
        ui.drawString(drainStr .. "  EXP +" .. (victoryInfo.exp or 0), contentX, ty, {1, 0.9, 0.4, 1})

        -- Always draw member rows with gauges (pre-drain values in stage 0,
        -- then animate during stage 1+).
        ty = ty + layoutVal("victoryLineSpacing")
        local expPerLevel = victoryInfo.expPerLevel or 15
        local rowH = layoutVal("victoryRowHeight")
        for i, m in ipairs(victoryInfo.members or {}) do
            local a = victoryAnim.members[i] or { level = m.fromLevel, exp = m.fromExp }
            local needed = a.level * expPerLevel
            local rowY = ty + (i - 1) * rowH
            local leveled = a.level > m.fromLevel
            -- Name on left, "Next: X" right-justified to gauge end, same line
            ui.drawString(m.name .. "  Lv " .. a.level .. (leveled and "  LV UP!" or ""), contentX, rowY, leveled and {1, 1, 0.5, 1} or {1, 1, 1, 1})
            -- "Next:" shares the line with the name; hide it while "LV UP!"
            -- is showing or the two overlap (owner feedback 10.07.2026).
            if not leveled then
                ui.drawString("Next: " .. math.max(0, math.ceil(needed - a.exp)), contentX, rowY, {0.7, 0.7, 0.7, 1}, "right", gaugeEndX - contentX)
            end
            -- Gauge at full width below the name line
            ui.drawBar(contentX, rowY + 10, layoutVal("victoryGaugeWidth"), layoutVal("victoryGaugeHeight"), a.exp, needed, {0.2, 0.5, 0.2}, {0.4, 0.9, 0.4})
        end

        -- Party total gold at the bottom of the window
        local partyGold = math.floor((victoryAnim.displayedPartyGold or victoryAnim.preGold or 0) + 0.5)
        local totalGoldY = vy + vh - 16
        ui.drawString("Gold: " .. partyGold .. " G", contentX, totalGoldY, {1, 0.85, 0.5, 1})

        -- Bottom prompt: ENTER to start drain, SPACE to dismiss when done
        local prompt = (victoryAnim.stage == 0) and "[ENTER]" or (victoryAnim.stage == 2 and "[SPACE]" or "")
        if prompt ~= "" then
            ui.drawString(prompt, vx + vw - 50, vy + vh - 12, {0.5, 0.5, 0.5, 1}, "right", 40)
        end
    end

    -- Full-screen flash overlay (screen_flash tracks), above everything —
    -- same compositing as the editor preview channel (main.lua's
    -- runPreviewAnim draws it last over the whole canvas). Animations play
    -- per-target, so scan every battler for an active flash; first hit wins
    -- (overlapping flashes don't stack — matches the preview, which only
    -- ever has one target). 256x240 is the game's logical resolution.
    local flash
    for _, e in ipairs(battleState.enemies) do
        flash = animation_player.getScreenFlash(e)
        if flash then break end
    end
    if not flash then
        for _, a in ipairs(battleState.allies or {}) do
            flash = animation_player.getScreenFlash(a)
            if flash then break end
        end
    end
    if flash then
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(flash.color[1], flash.color[2], flash.color[3], flash.alpha)
        love.graphics.rectangle("fill", 0, 0, 256, 240)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

function renderer.drawTargetReticles(bv, combatState, selectedIndex, spellSelect, itemSelect, livingMembers, activeMemberIdx)
    if combatState ~= "input" or not bv then return end
    
    local session = renderer.session
    if not session then return end
    
    local battleState = bv.battle

    local targets = getHoveredTargets(bv, combatState, selectedIndex, spellSelect, itemSelect, livingMembers, activeMemberIdx)
    for _, target in ipairs(targets) do
        local tx, ty, tw, th = getBattlerRect(target, battleState, session)
        if tx and ty and tw and th then
            ui.drawTargetReticle(tx, ty, tw, th)
        end
    end
end

function renderer.drawDamagePopups()
    love.graphics.push("all")
    for _, p in ipairs(damagePopups) do
        if p.revealElapsed >= (p.spawnDelay or 0) then
            local activeElapsed = p.revealElapsed - (p.spawnDelay or 0)
            local alpha = math.min(1, p.life * 2)
            local col = { p.color[1], p.color[2], p.color[3], alpha }
            local textOffset = 0
            local font = p.isText and ui.getPopupTextFont() or ui.getPopupNumberFont()
            font = font or love.graphics.getFont()
            for _, glyph in ipairs(p.glyphs) do
                if activeElapsed >= glyph.startDelay then
                    -- Opacity is shared across the popup, not reset for each
                    -- glyph, so every character fades out in sync.
                    ui.drawString(glyph.char, p.x + textOffset + glyph.x, p.y + glyph.y, col, nil, nil, nil, font)
                end
                textOffset = textOffset + font:getWidth(glyph.char)
            end
        end
    end
    love.graphics.pop()
end

-- drawShop deleted: the shop is a declarative scene now ("draw": "windows"
-- in scenes.json) — the generic window renderer draws it from its hooks.

return renderer
