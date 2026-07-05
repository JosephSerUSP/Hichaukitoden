local ui = require("presentation.ui")
local viewport_3d = require("presentation.viewport_3d")
local exploration = require("engine.exploration")
local battleSystem = require("engine.battle")
local director = require("engine.director")
local traits = require("engine.traits")
local config = require("engine.config")

local renderer = {}

local damagePopups = {}
local portraitCache = {}
local function getPortrait(id)
    if not id or id == "" then return nil end
    if portraitCache[id] then return portraitCache[id] end
    
    local paths = {
        "assets/portraits/" .. id .. ".png",
        "assets/portraits/NPC_" .. id .. ".png",
        "assets/portraits/" .. id:lower() .. ".png"
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

local function drawElementIcon(element, x, y)
    local id = 16 -- fallback grey gem/orb
    if element == "Black" then id = 15
    elseif element == "White" then id = 14
    elseif element == "Green" then id = 12
    elseif element == "Red" then id = 11
    elseif element == "Blue" then id = 13
    elseif element == "Yellow" then id = 17
    end
    ui.drawIcon(id, x, y - 2) -- y - 2 aligns 12x12 icon perfectly with text
end

local function drawElementIcons(elems, x, y)
    if not elems then return 0 end
    for i, elem in ipairs(elems) do
        drawElementIcon(elem, x + (i - 1) * 10, y)
    end
    return #elems * 10
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

-- Battle animation state per enemy: { slideTimer, deathTimer, dead, flashTimer, flashType }
local battleAnims = {}
local menuTimer = 0

renderer.closing = false
renderer.closingScene = ""
renderer.closingTimer = 0
renderer.closingTargetScene = ""
renderer.closingTargetSubScene = ""

function renderer.startClosing(closingScene, targetScene, targetSubScene)
    local slideDur = config.ui and config.ui.menuSlideDuration or 0.22
    renderer.closing = true
    renderer.closingScene = closingScene
    renderer.closingTimer = slideDur
    renderer.closingTargetScene = targetScene
    renderer.closingTargetSubScene = targetSubScene or ""
end

function renderer.resetMenuTimer()
    menuTimer = 0
end

function renderer.initBattleAnims(enemies)
    battleAnims = {}
    for i, enemy in ipairs(enemies) do
        battleAnims[i] = { slideTimer = 0.35, deathTimer = -1, dead = false, flashTimer = 0, flashType = "" }
    end
end

function renderer.triggerDeathAnim(enemyIdx)
    if battleAnims[enemyIdx] then
        battleAnims[enemyIdx].deathTimer = 0.9
        battleAnims[enemyIdx].dead = true
    end
end

function renderer.triggerActionFlash(enemyIdx, flashType)
    if battleAnims[enemyIdx] then
        battleAnims[enemyIdx].flashTimer = 0.35
        battleAnims[enemyIdx].flashType = flashType or "action"
    end
end

function renderer.update(dt)
    if renderer.closing then
        renderer.closingTimer = renderer.closingTimer - dt
        if renderer.closingTimer <= 0 then
            renderer.closing = false
            renderer.session.scene = renderer.closingTargetScene
            renderer.session.subScene = renderer.closingTargetSubScene
        end
    end

    local gravity = config.physics and config.physics.gravity or 480
    local bounceRetain = config.physics and config.physics.bounceVelocityRetain or 0.45
    for i = #damagePopups, 1, -1 do
        local p = damagePopups[i]
        p.vy = p.vy + gravity * dt
        p.x = p.x + (p.vx or 0) * dt
        p.y = p.y + p.vy * dt
        
        -- Bounce detection when falling past startY
        if p.y >= p.startY and p.vy > 0 then
            p.y = p.startY
            if p.bounceCount < 2 then
                p.vy = -p.vy * bounceRetain -- reverse velocity and reduce
                p.vx = (p.vx or 0) * 0.6
                p.bounceCount = p.bounceCount + 1
            else
                p.vy = 0
                p.vx = 0
            end
        end
        
        p.life = p.life - dt
        if p.life <= 0 then table.remove(damagePopups, i) end
    end
    for _, anim in ipairs(battleAnims) do
        if anim.slideTimer > 0 then
            anim.slideTimer = math.max(0, anim.slideTimer - dt)
        end
        if anim.deathTimer > 0 then
            anim.deathTimer = math.max(0, anim.deathTimer - dt)
        end
        if anim.flashTimer and anim.flashTimer > 0 then
            anim.flashTimer = math.max(0, anim.flashTimer - dt)
        end
    end
    
    -- Smoothly interpolate party HP and Summoner MP
    local session = renderer.session
    if session then
        menuTimer = menuTimer + dt
        
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
end

function renderer.addDamagePopup(text, x, y, color)
    local scatter = config.physics and config.physics.horizontalScatter or 40
    local lifeSpan = config.battle_screen and config.battle_screen.damagePopupLife or 1.1
    table.insert(damagePopups, {
        text = text,
        x = x,
        y = y,
        startY = y,
        color = color or {1, 1, 1, 1},
        vy = -160, -- launch upwards
        vx = math.random(-scatter, scatter), -- random horizontal direction
        bounceCount = 0,
        life = lifeSpan
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
                    if mapEvent.scriptId == 7 then
                        love.graphics.setColor(0, 0.8, 0, 1) -- Green for recovery
                    elseif mapEvent.scriptId == 12 then
                        love.graphics.setColor(0.8, 0.8, 0, 1) -- Yellow for treasures
                    elseif mapEvent.scriptId == 13 then
                        love.graphics.setColor(0.8, 0, 0, 1) -- Red for battles
                    elseif mapEvent.scriptId == 1 then
                        love.graphics.setColor(0, 0.8, 0.8, 1) -- Cyan for stairs
                    else
                        love.graphics.setColor(0.4, 0.6, 1, 1) -- Light blue for NPCs / shops
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

-- Render HUD/Party details in the bottom panel
local function drawHUD(x, y, w, h)
    ui.drawPanel(x, y, w, h)
    
    local session = renderer.session
    
    -- Draw Summoner MP stats on bottom left (identical to battle console)
    ui.drawString("ALEX", x + 1.25 * ui.tileSize, y + 1.75 * ui.tileSize, {1, 0.85, 0.5, 1})
    
    local dispMp = session.displayedMp or session.mp
    ui.drawString("MP: " .. math.floor(dispMp + 0.5) .. "/" .. session.maxMp, x + 1.25 * ui.tileSize, y + 3.25 * ui.tileSize, {0.6, 0.8, 1, 1})
    ui.drawBar(x + 1.25 * ui.tileSize, y + 4.75 * ui.tileSize, 10 * ui.tileSize, 4, dispMp, session.maxMp, {0, 0.4, 0.8}, {0.2, 0.7, 1})
    
    -- Draw active creatures in the unified 2x2 grid!
    renderer.drawPartyGrid(x + 16 * ui.tileSize, y + 0.75 * ui.tileSize, 0, session, false)
end

-- Renders the Title Scene
function renderer.drawTitle()
    love.graphics.clear(0.05, 0.05, 0.1, 1)
    
    -- Decorative retro background lines
    love.graphics.setColor(0.1, 0.15, 0.25, 0.3)
    for i = 0, 15 do
        love.graphics.line(0, i * 16, 256, i * 16 + 50)
    end
    
    ui.drawPanel(20, 30, 216, 60)
    ui.drawString("HICHAUKITODEN", 28, 48, {1, 0.9, 0.3, 1}, "center", 200)
    ui.drawString("First Person Crawler", 28, 66, {0.7, 0.8, 1, 0.8}, "center", 200)
    
    -- Menu options
    ui.drawPanel(50, 110, 156, 80)
    ui.drawString("Press ENTER to start", 58, 130, {1, 1, 1, 1}, "center", 140)
    ui.drawString("Press ESC to exit", 58, 154, {0.7, 0.7, 0.7, 1}, "center", 140)
    
    -- Copyright
    ui.drawString("(C) 2026 Developer", 10, 226, {0.4, 0.4, 0.4, 1})
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
    
    local options = { "Dungeon", "Weapon Shop", "Alicia Shop", "Rest (House)" }
    for i, opt in ipairs(options) do
        local color = (i == selectedIdx) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local prefix = (i == selectedIdx) and "> " or "  "
        ui.drawString(prefix .. opt, ui.toPx(2), ui.toPx(2) + i * ui.lineHeight * 2, color)
    end
    
    drawHUD(0, ui.toPx(18), ui.toPx(32), ui.toPx(12))
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
    
    drawHUD(0, ui.toPx(18), ui.toPx(32), ui.toPx(12))
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
    local speakerName = node.speaker or walker.graph.name or "???"
    ui.drawString(speakerName, winX + ui.toPx(1), ui.toPx(2), {1, 0.9, 0.4, 1})
    
    if node.type == "TEXT" then
        ui.drawString(node.content or "", winX + ui.toPx(1), ui.toPx(4), {1, 1, 1, 1}, "left", winW - ui.toPx(2))
        ui.drawString("[Press SPACE]", winX + ui.toPx(1), ui.toPx(14), {0.6, 0.6, 0.6, 1}, "right", winW - ui.toPx(3))
    elseif node.type == "CHOICE" then
        ui.drawString(node.content or "Choose option:", winX + ui.toPx(1), ui.toPx(4), {1, 1, 1, 1}, "left", winW - ui.toPx(2))
        for i, opt in ipairs(node.options or {}) do
            local color = (i == selectIdx) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = (i == selectIdx) and "> " or "  "
            ui.drawString(prefix .. opt.label, winX + ui.toPx(1), ui.toPx(5) + i * ui.lineHeight * 2, color)
        end
    end
    
    drawHUD(0, ui.toPx(18), ui.toPx(32), ui.toPx(12))
end

function renderer.drawPartyGrid(x, y, selectedIdx, session, showCursor)
    local gridCoords = {
        { x = x, y = y },
        { x = x + 8 * ui.tileSize, y = y },
        { x = x, y = y + 5 * ui.tileSize },
        { x = x + 8 * ui.tileSize, y = y + 5 * ui.tileSize }
    }
    for i = 1, 4 do
        local c = session.party[i]
        local slot = gridCoords[i]
        if c then
            local maxHp = c:getMaxHp(session)
            local isSel = (showCursor and i == selectedIdx)
            local color = isSel and {1, 1, 0.5, 1} or (c:isDead() and {0.5, 0.5, 0.5, 1} or {1, 1, 1, 1})
            local hpColor = c:isDead() and {0.5, 0.5, 0.5, 1} or {0.9, 0.9, 0.9, 1}
            
            local prefix = isSel and ">" or " "
            local iconW = drawElementIcons(c.actorData.elements, slot.x, slot.y)
            ui.drawString(prefix .. c.name, slot.x + iconW + 1, slot.y, color, "left", 60)
            
            local dispHp = c.displayedHp or c.hp
            ui.drawString(math.floor(dispHp + 0.5) .. "/" .. maxHp, slot.x + 8, slot.y + 11, hpColor)
            ui.drawBar(slot.x + 8, slot.y + 22, 52, 3, dispHp, maxHp, {0.8, 0, 0}, {1, 0.3, 0.3})
        else
            local isSel = (showCursor and i == selectedIdx)
            local prefix = isSel and ">" or " "
            ui.drawString(prefix .. "- EMPTY -", slot.x, slot.y + 8, {0.3, 0.3, 0.3, 1})
        end
    end
end

function renderer.drawBattle(battleState, combatLog, combatState, selectedIndex, spellSelect, livingMembers, activeMemberIdx)
    renderer.activeBattle = battleState
    
    -- Draw 3D dungeon view behind battle scene
    viewport_3d.draw(renderer.session)
    
    -- Subtle darkened overlay (not too heavy)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, 256, 140)
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Render enemies portraits in viewport with slide-in and death animations
    local spacing = 220 / #battleState.enemies
    for idx, enemy in ipairs(battleState.enemies) do
        local anim = battleAnims[idx] or { slideTimer = 0, deathTimer = -1, dead = false }
        local portrait = getPortrait(enemy.spriteKey or enemy.id)
        local ex = 18 + (idx - 1) * spacing
        local ey = 30
        
        -- Slide-in offset: start offscreen right, slide to position
        local slideOff = 0
        if anim.slideTimer > 0 then
            slideOff = 280 * (anim.slideTimer / 0.35)
        end
        local drawX = ex + slideOff
        
        if anim.dead and anim.deathTimer >= 0 then
            -- Death animation: additive blend, purple tint, fade to black
            local t = anim.deathTimer / 0.9  -- 1.0 = just died, 0.0 = done
            local alpha = t
            love.graphics.setBlendMode("add")
            if portrait then
                love.graphics.setColor(0.6 * alpha, 0, 0.9 * alpha, alpha)
                love.graphics.draw(portrait, drawX, ey + (1-t)*20, 0, 56/portrait:getWidth(), 56/portrait:getHeight())
            else
                love.graphics.setColor(0.6*alpha, 0, 0.9*alpha, alpha)
                love.graphics.rectangle("fill", drawX, ey + (1-t)*20, 50, 50)
            end
            love.graphics.setBlendMode("alpha")
        elseif not anim.dead then
            if portrait then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(portrait, drawX, ey, 0, 56/portrait:getWidth(), 56/portrait:getHeight())
            else
                love.graphics.setColor(0.8, 0.1, 0.1, 1)
                love.graphics.rectangle("fill", drawX, ey, 50, 50)
            end
            
            -- Apply action/damage flash overlay
            if anim.flashTimer and anim.flashTimer > 0 then
                love.graphics.setBlendMode("add")
                if anim.flashType == "action" then
                    love.graphics.setColor(0.8, 1.0, 1.0, anim.flashTimer / 0.35)
                else
                    love.graphics.setColor(1.0, 0.2, 0.2, anim.flashTimer / 0.35)
                end
                if portrait then
                    love.graphics.draw(portrait, drawX, ey, 0, 56/portrait:getWidth(), 56/portrait:getHeight())
                else
                    love.graphics.rectangle("fill", drawX, ey, 50, 50)
                end
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, 1)
            end
            
            local maxHp = enemy:getMaxHp(renderer.session)
            love.graphics.setColor(1,1,1,1)
            ui.drawString(enemy.name, ex, 90, {1, 1, 1, 1})
            ui.drawBar(ex, 104, 50, 4, enemy.displayedHp or enemy.hp, maxHp, {0.8, 0, 0}, {1, 0.3, 0.3})
        end
    end
    
    -- Slim dialogue at the top of the screen during Battle Resolution
    if combatState == "log" then
        ui.drawPanel(10, 6, 236, 32)
        local latestLog = combatLog[#combatLog] or ""
        ui.drawString(latestLog, 16, 12, {1, 1, 1, 1}, "left", 224)
        ui.drawString("[SPACE]", 200, 23, {0.5, 0.5, 0.5, 1}, "right", 40)
    end
    
    -- Bottom Command console
    local consoleY = ui.toPx(18)
    local consoleH = ui.toPx(12)
    local textX = ui.toPx(1)
    local headerY = consoleY + ui.toPx(1)
    
    ui.drawPanel(0, consoleY, ui.toPx(32), consoleH)
    
    if combatState == "input" then
        local memberInfo = livingMembers and livingMembers[activeMemberIdx]
        local isSummoner = (not memberInfo or memberInfo.type == "summoner")
        
        if isSummoner then
            ui.drawString("ALEX'S TURN (Inst.)", textX, headerY, {1, 0.85, 0.5, 1})
            local actions = { "Attack", "Spell", "Item", "Flee" }
            if spellSelect then
                ui.drawString("CAST SPELL (MP: " .. renderer.session.mp .. ")", textX, headerY, {0.5, 0.8, 1, 1})
                local spells = { "Cure (5MP)", "Protect (8MP)", "Wall (15MP)" }
                for i, spellName in ipairs(spells) do
                    local color = (i == selectedIndex) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                    local prefix = (i == selectedIndex) and "> " or "  "
                    ui.drawString(prefix .. spellName, textX, headerY + i * ui.lineHeight * 2, color)
                end
            else
                for i, actName in ipairs(actions) do
                    local color = (i == selectedIndex) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                    local prefix = (i == selectedIndex) and "> " or "  "
                    ui.drawString(prefix .. actName, textX, headerY + i * ui.lineHeight * 2, color)
                end
            end
        else
            -- Monster Turn
            local monster = memberInfo.actor
            ui.drawString(monster.name:upper() .. "'S TURN", textX, headerY, {1, 0.85, 0.5, 1})
            local actions = { "Attack", "Skill", "Defend", "Flee" }
            if spellSelect then
                ui.drawString("USE SKILL", textX, headerY, {0.5, 0.8, 1, 1})
                local skillsList = {}
                for _, skId in ipairs(monster.skills or {}) do
                    local sk = renderer.session.loader.getSkill(skId)
                    if sk then table.insert(skillsList, sk) end
                end
                if #skillsList == 0 then
                    ui.drawString("  (No skills)", textX, headerY + ui.lineHeight * 2, {0.5, 0.5, 0.5, 1})
                else
                    for i, sk in ipairs(skillsList) do
                        local color = (i == selectedIndex) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                        local prefix = (i == selectedIndex) and "> " or "  "
                        ui.drawString(prefix .. sk.name, textX, headerY + i * ui.lineHeight * 2, color)
                    end
                end
            else
                for i, actName in ipairs(actions) do
                    local color = (i == selectedIndex) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                    local prefix = (i == selectedIndex) and "> " or "  "
                    ui.drawString(prefix .. actName, textX, headerY + i * ui.lineHeight * 2, color)
                end
            end
        end
    else
        -- Log state console title
        ui.drawString("ALEX'S PARTY", textX, headerY, {1, 0.85, 0.5, 1})
        ui.drawString("Resolving actions...", textX, headerY + 16, {0.6, 0.6, 0.6, 1})
    end
    
    -- Draw Summoner MP stats on bottom left
    local session = renderer.session
    ui.drawString("ALEX", textX, consoleY + ui.toPx(6), {1, 0.85, 0.5, 1})
    ui.drawString("MP: " .. session.mp .. "/" .. session.maxMp, textX, consoleY + ui.toPx(8), {0.6, 0.8, 1, 1})
    ui.drawBar(textX, consoleY + ui.toPx(10), 10 * ui.tileSize, 4, session.mp, session.maxMp, {0, 0.4, 0.8}, {0.2, 0.7, 1})
    
    -- Draw party stats in a 2x2 grid on right side of bottom console
    local highlightIdx = 0
    local showHighlight = false
    if combatState == "input" then
        local memberInfo = livingMembers and livingMembers[activeMemberIdx]
        if memberInfo and memberInfo.type == "monster" then
            highlightIdx = memberInfo.index - 1
            showHighlight = true
        end
    end
    renderer.drawPartyGrid(ui.toPx(16), headerY, highlightIdx, session, showHighlight)
    
    -- Draw active damage popups
    love.graphics.push("all")
    for _, p in ipairs(damagePopups) do
        local alpha = math.min(1, p.life * 2)
        local col = { p.color[1], p.color[2], p.color[3], alpha }
        ui.drawString(p.text, p.x, p.y, col)
    end
    love.graphics.pop()
end

function renderer.drawShop(shopId, selectedIdx, shopItems)
    local slideDur = config.ui and config.ui.menuSlideDuration or 0.22
    local progress
    if renderer.closing and renderer.closingScene == "shop" then
        progress = math.max(0, math.min(1, renderer.closingTimer / slideDur))
    else
        progress = math.min(1, menuTimer / slideDur)
    end
    local ease = 1 - (1 - progress) * (1 - progress)
    local ox = (1 - ease) * ui.toPx(32.5)

    -- Draw shop background
    viewport_3d.draw(renderer.session)
    
    -- Draw shop title and item list
    ui.drawPanel(ui.toPx(1) + ox, ui.toPx(1), ui.toPx(30), ui.toPx(15))
    
    local titleText = "SHOP: " .. shopId:gsub("_", " "):upper()
    ui.drawString(titleText, ui.toPx(2) + ox, ui.toPx(2), {1, 0.85, 0.5, 1})
    
    if #shopItems == 0 then
        ui.drawString("No items available.", ui.toPx(3) + ox, ui.toPx(5), {0.6, 0.6, 0.6, 1})
    else
        -- Draw items list
        local start = math.max(1, selectedIdx - 4)
        local count = 0
        for i = start, math.min(#shopItems, start + 4) do
            local item = shopItems[i]
            local itemY = ui.toPx(4) + count * ui.lineHeight * 2
            local color = (i == selectedIdx) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = (i == selectedIdx) and "> " or "  "
            
            -- Draw icon
            if item.icon then
                ui.drawIcon(item.icon, ui.toPx(2.5) + ox, itemY + 1)
            end
            
            ui.drawString(prefix .. item.name, ui.toPx(4.25) + ox, itemY, color)
            ui.drawString(item.cost .. " G", ui.toPx(22.5) + ox, itemY, color, "right", ui.toPx(7.5))
            count = count + 1
        end
        
        -- Draw description for the selected item
        local selItem = shopItems[selectedIdx]
        if selItem then
            ui.drawString(selItem.description or "", ui.toPx(2) + ox, ui.toPx(14), {0.8, 0.8, 0.8, 1})
        end
    end
    
    ui.drawString("[ESC/BACK to exit]", ui.toPx(16.25) + ox, ui.toPx(2), {0.6, 0.6, 0.6, 1}, "right", ui.toPx(13.75))
    
    local bottomY = ui.toPx(18) + (1 - ease) * ui.toPx(14)
    drawHUD(0, bottomY, ui.toPx(32), ui.toPx(12))
end

local function drawDarkGradient()
    for i = 0, 24 do
        local y1 = (i / 24) * 244
        local y2 = ((i + 1) / 24) * 244
        local t = i / 24
        local r = 0.01 * (1 - t) + 0.00 * t
        local g = 0.02 * (1 - t) + 0.01 * t
        local b = 0.06 * (1 - t) + 0.02 * t
        local a = 0.92 * (1 - t) + 0.78 * t
        love.graphics.setColor(r, g, b, a)
        love.graphics.rectangle("fill", 0, y1, 256, y2 - y1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function renderer.drawMainMenu(mainIdx, activeCol, rightIdx, session, subScene)
    -- Dark gradient background overlay
    drawDarkGradient()

    if subScene == "status_detail" then
        local c = session.party[selectedCreatureIndex or rightIdx]
        if c then
            renderer.drawStatusDetail(c, session)
        end
        return
    end
    
    -- Quadratic ease-out slide-in animation
    local slideDur = config.ui and config.ui.menuSlideDuration or 0.22
    local slideProgress
    if renderer.closing and renderer.closingScene == "menu" then
        slideProgress = math.max(0, math.min(1, renderer.closingTimer / slideDur))
    elseif renderer.closing and renderer.closingScene == "items_list" then
        slideProgress = math.max(0, math.min(1, renderer.closingTimer / slideDur))
    else
        slideProgress = math.min(1, menuTimer / slideDur)
    end
    local ease = 1 - (1 - slideProgress) * (1 - slideProgress)
    
    local leftX = ui.toPx(1) - (1 - ease) * ui.toPx(10)
    local rightX = ui.toPx(10) + (1 - ease) * ui.toPx(24)
    local bottomY = ui.toPx(20) + (1 - ease) * ui.toPx(12)
    
    -- 1. Draw Left Menu Column
    ui.drawPanel(leftX, ui.toPx(1), ui.toPx(8), ui.toPx(18), "MENU")
    local mainOpts = { "ITEMS", "STATUS", "EQUIP", "EXIT" }
    for i, opt in ipairs(mainOpts) do
        local isSel = (subScene == "main" and i == mainIdx)
        local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local prefix = isSel and ">" or " "
        ui.drawString(prefix .. opt, leftX + 0.5 * ui.tileSize, ui.toPx(4) + (i - 1) * ui.toPx(2), color)
    end
    
    -- Gold and Floor stats inside left menu column below the options
    ui.drawString("GOLD", leftX + 0.5 * ui.tileSize, ui.toPx(12.5), {0.6, 0.6, 0.6, 1})
    ui.drawString(session.gold .. " G", leftX + 0.5 * ui.tileSize, ui.toPx(13.75), {1, 0.9, 0.3, 1})
    
    local mapTitle = "Town"
    if session.currentMapData then
        mapTitle = session.currentMapData.title or "1"
    end
    ui.drawString("FLOOR", leftX + 0.5 * ui.tileSize, ui.toPx(15.25), {0.6, 0.6, 0.6, 1})
    ui.drawString(mapTitle, leftX + 0.5 * ui.tileSize, ui.toPx(16.5), {1, 1, 1, 1}, "left", ui.toPx(6.75))
    
    -- 2. Draw Bottom Description Panel
    ui.drawPanel(ui.toPx(1), bottomY, ui.toPx(30), ui.toPx(9.5), "INFO")
    
    -- 3. Draw Right Details Panel based on selection
    local panelTitle = mainOpts[mainIdx]
    if subScene == "party_select" then
        panelTitle = "SELECT UNIT"
    elseif subScene == "exit_confirm" then
        panelTitle = "CONFIRM"
    end
    ui.drawPanel(rightX, ui.toPx(1), ui.toPx(21), ui.toPx(18), panelTitle)
    
    local textLeftMargin = ui.toPx(2)
    if subScene == "main" or subScene == "party_select" then
        -- Displays unit grid by default when browsing the main menu!
        local showCursor = (subScene == "party_select")
        renderer.drawPartyGrid(rightX + 1 * ui.tileSize, ui.toPx(4), rightIdx, session, showCursor)
        
        local selCreature = session.party[rightIdx]
        if selCreature then
            local maxHp = selCreature:getMaxHp(session)
            ui.drawString(selCreature.name:upper() .. " (L" .. selCreature.level .. ") - HP: " .. selCreature.hp .. "/" .. maxHp, textLeftMargin, bottomY + 3 * ui.tileSize, {1, 0.85, 0.5, 1})
            
            local atk = traits.getParam(selCreature, "atk", session)
            local def = traits.getParam(selCreature, "def", session)
            local mat = traits.getParam(selCreature, "mat", session)
            local mdf = traits.getParam(selCreature, "mdf", session)
            local statText = string.format("ATK:%-2d  DEF:%-2d  MAT:%-2d  MDF:%-2d", atk, def, mat, mdf)
            ui.drawString(statText, textLeftMargin, bottomY + 4.75 * ui.tileSize, {0.8, 0.9, 1, 1})
            
            local states = {}
            for _, stateInfo in ipairs(selCreature.states) do table.insert(states, stateInfo.id:upper()) end
            local stateStr = #states > 0 and table.concat(states, ", ") or "NORMAL"
            ui.drawString("STATUS: " .. stateStr, textLeftMargin, bottomY + 6.5 * ui.tileSize, {1, 1, 1, 1})
        else
            ui.drawString("ALEX'S CREATURES", textLeftMargin, bottomY + 3 * ui.tileSize, {1, 0.85, 0.5, 1})
            ui.drawString("Manage your active summon spirits and modify equipment parameters.", textLeftMargin, bottomY + 4.75 * ui.tileSize, {0.7, 0.7, 0.7, 1}, "left", ui.toPx(28))
        end
        
    elseif subScene == "items_list" then
        local items = {}
        for itemId, qty in pairs(session.inventory) do
            local item = session.loader.getItem(itemId)
            if item then
                table.insert(items, { item = item, qty = qty })
            end
        end
        
        if #items == 0 then
            ui.drawString("Inventory is empty.", rightX + 1 * ui.tileSize, ui.toPx(4), {0.5, 0.5, 0.5, 1})
            ui.drawString("No items to describe.", textLeftMargin, bottomY + 3 * ui.tileSize, {0.6, 0.6, 0.6, 1})
        else
            local startIdx = math.max(1, rightIdx - 7)
            local drawCount = 0
            for i = startIdx, math.min(#items, startIdx + 8) do
                local itEntry = items[i]
                local iy = ui.toPx(4) + drawCount * 11
                local isSel = (i == rightIdx)
                local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                local prefix = isSel and ">" or " "
                
                if itEntry.item.icon then
                    ui.drawIcon(itEntry.item.icon, rightX + 1.75 * ui.tileSize, iy - 1)
                end
                
                ui.drawString(prefix, rightX + 0.5 * ui.tileSize, iy, color)
                ui.drawString(itEntry.item.name, rightX + 3.5 * ui.tileSize, iy, color)
                ui.drawString("x" .. itEntry.qty, rightX + 17.5 * ui.tileSize, iy, color, "right", ui.toPx(3))
                drawCount = drawCount + 1
            end
            
            local selItem = items[rightIdx]
            if selItem then
                ui.drawString(selItem.item.name:upper(), textLeftMargin, bottomY + 3 * ui.tileSize, {1, 0.85, 0.5, 1})
                ui.drawString(selItem.item.description or "", textLeftMargin, bottomY + 4.75 * ui.tileSize, {0.9, 0.9, 0.9, 1}, "left", ui.toPx(28))
            end
        end
        
    elseif subScene == "exit_confirm" then
        ui.drawString("Exit Hichaukitoden?", rightX + 1 * ui.tileSize, ui.toPx(4), {1, 1, 1, 1})
        
        local isYes = (rightIdx == 1)
        local isNo = (rightIdx == 2)
        ui.drawString((isYes and "> " or "  ") .. "YES (Quit to Desktop)", rightX + 1 * ui.tileSize, ui.toPx(6.75), isYes and {1, 0.5, 0.5, 1} or {1, 1, 1, 1})
        ui.drawString((isNo and "> " or "  ") .. "NO (Resume Game)", rightX + 1 * ui.tileSize, ui.toPx(8.5), isNo and {1, 1, 0.5, 1} or {1, 1, 1, 1})
        
        ui.drawString("EXIT GAME", textLeftMargin, bottomY + 3 * ui.tileSize, {1, 0.5, 0.5, 1})
        ui.drawString("Select YES and press ENTER to safely quit the game. Select NO or press ESC to resume.", textLeftMargin, bottomY + 4.75 * ui.tileSize, {0.9, 0.9, 0.9, 1}, "left", ui.toPx(28))
    end
end

function renderer.drawStatusDetail(c, session)
    local slideDur = config.ui and config.ui.menuSlideDuration or 0.22
    local progress
    if renderer.closing and renderer.closingScene == "status_detail" then
        progress = math.max(0, math.min(1, renderer.closingTimer / slideDur))
    else
        progress = math.min(1, menuTimer / slideDur)
    end
    local ease = 1 - (1 - progress) * (1 - progress)
    local ox = (1 - ease) * ui.toPx(32.5)

    local panelX = ui.toPx(1) + ox
    local panelY = ui.toPx(1)
    local panelW = ui.toPx(30)
    local panelH = ui.toPx(28)
    
    ui.drawPanel(panelX, panelY, panelW, panelH, "STATUS: " .. c.name:upper())
    
    local contentX = panelX + ui.toPx(1)
    
    -- Header info (y = ui.toPx(4) i.e. 32px)
    local iconW = drawElementIcons(c.actorData.elements, contentX, ui.toPx(4))
    ui.drawString(c.name .. " L" .. c.level, contentX + iconW + 4, ui.toPx(4), {1, 0.85, 0.5, 1})
    ui.drawString("ROLE: " .. (c.actorData.role or "CREATURE"), contentX, ui.toPx(5.5), {0.7, 0.7, 0.7, 1})
    
    local maxHp = c:getMaxHp(session)
    ui.drawString("HP: " .. c.hp .. " / " .. maxHp, contentX, ui.toPx(7), {1, 1, 1, 1})
    ui.drawBar(contentX + ui.toPx(9), ui.toPx(7.25), ui.toPx(17.5), 4, c.hp, maxHp, {0.8, 0, 0}, {1, 0.3, 0.3})
    
    -- Stats Column (Left, y = ui.toPx(9.25))
    ui.drawString("STATS", contentX, ui.toPx(9.25), {0.5, 0.8, 1, 1})
    local atk = traits.getParam(c, "atk", session)
    local def = traits.getParam(c, "def", session)
    local mat = traits.getParam(c, "mat", session)
    local mdf = traits.getParam(c, "mdf", session)
    ui.drawString("ATK: " .. atk, contentX, ui.toPx(11), {1, 1, 1, 1})
    ui.drawString("DEF: " .. def, contentX, ui.toPx(12.5), {1, 1, 1, 1})
    ui.drawString("MAT: " .. mat, contentX, ui.toPx(14), {1, 1, 1, 1})
    ui.drawString("MDF: " .. mdf, contentX, ui.toPx(15.5), {1, 1, 1, 1})
    
    -- Equipment Column (Right, x = contentX + 13 tiles)
    local equipX = contentX + ui.toPx(13)
    ui.drawString("EQUIPMENT", equipX, ui.toPx(9.25), {0.5, 0.8, 1, 1})
    local eq1 = c.equipment[1] and c.equipment[1].name or "[ EMPTY ]"
    local eq2 = c.equipment[2] and c.equipment[2].name or "[ EMPTY ]"
    local eq3 = c.equipment[3] and c.equipment[3].name or "[ EMPTY ]"
    ui.drawString("WPN: " .. eq1, equipX, ui.toPx(11), {0.8, 0.8, 0.8, 1})
    ui.drawString("AMR: " .. eq2, equipX, ui.toPx(12.5), {0.8, 0.8, 0.8, 1})
    ui.drawString("ACC: " .. eq3, equipX, ui.toPx(14), {0.8, 0.8, 0.8, 1})
    
    -- Passives & Skills (y = ui.toPx(17.5))
    ui.drawString("PASSIVE TRAITS", contentX, ui.toPx(17.5), {1, 0.85, 0.5, 1})
    local passives = c.actorData.passives or {}
    local skills = c.actorData.skills or {}
    local totalTraits = #passives + #skills
    
    local itemDesc = "Browse active passive traits and battle skills."
    
    -- Draw passives inline
    local currentY = ui.toPx(19)
    local count = 1
    if #passives == 0 then
        ui.drawString("None", contentX, currentY, {0.6, 0.6, 0.6, 1})
    else
        local px = contentX
        for _, passId in ipairs(passives) do
            local p = session.loader.getPassive(passId) or { name = passId, description = "" }
            local isSel = (statusInspectMode and statusInspectIdx == count)
            local col = isSel and {1, 1, 0.5, 1} or {0.9, 0.9, 0.9, 1}
            local prefix = isSel and ">" or ""
            ui.drawString(prefix .. p.name, px, currentY, col)
            if isSel then itemDesc = p.name:upper() .. ": " .. (p.description or "Passive trait.") end
            px = px + #p.name * 6 + ui.toPx(1.5)
            count = count + 1
        end
    end
    
    ui.drawString("ACTIVE SKILLS", contentX, ui.toPx(21.5), {1, 0.85, 0.5, 1})
    currentY = ui.toPx(23)
    if #skills == 0 then
        ui.drawString("None", contentX, currentY, {0.6, 0.6, 0.6, 1})
    else
        local px = contentX
        for _, skId in ipairs(skills) do
            local s = session.loader.getSkill(skId) or { name = skId, description = "" }
            local isSel = (statusInspectMode and statusInspectIdx == count)
            local col = isSel and {1, 1, 0.5, 1} or {0.9, 0.9, 0.9, 1}
            local prefix = isSel and ">" or ""
            ui.drawString(prefix .. s.name, px, currentY, col)
            if isSel then itemDesc = s.name:upper() .. ": " .. (s.description or "Battle skill.") end
            px = px + #s.name * 6 + ui.toPx(1.5)
            count = count + 1
        end
    end
    
    -- Footer (y = ui.toPx(25.5)) displays descriptions when inspecting
    if statusInspectMode then
        ui.drawString(itemDesc, contentX, ui.toPx(25.5), {1, 1, 0.6, 1}, "left", ui.toPx(28))
        ui.drawString("[ESC: back to normal viewing]", contentX, ui.toPx(26.75), {0.5, 0.5, 0.5, 1}, "center", ui.toPx(28))
    else
        ui.drawString("[ESC: return to menu | SPACE: inspect traits]", contentX, ui.toPx(26.5), {0.5, 0.5, 0.5, 1}, "center", ui.toPx(28))
    end
end

function renderer.drawTargetSelector(selectedSubIdx, session)
    -- Dark gradient background overlay
    drawDarkGradient()
    
    ui.drawPanel(ui.toPx(3), ui.toPx(2), ui.toPx(26), ui.toPx(16), "SELECT TARGET")
    ui.drawString("Use item on whom?", ui.toPx(4), ui.toPx(4.5), {1, 1, 1, 1})
    
    -- Reuse the 2x2 Party Grid for target selection overlay!
    renderer.drawPartyGrid(ui.toPx(4), ui.toPx(6), selectedSubIdx, session, true)
    
    ui.drawPanel(ui.toPx(1), ui.toPx(19), ui.toPx(30), ui.toPx(10), "INFO")
    local selC = session.party[selectedSubIdx]
    if selC then
        local maxHp = selC:getMaxHp(session)
        ui.drawString("TARGET: " .. selC.name:upper(), ui.toPx(2), ui.toPx(19) + 23, {1, 0.85, 0.5, 1})
        ui.drawString("Level " .. selC.level .. " | HP: " .. selC.hp .. " / " .. maxHp, ui.toPx(2), ui.toPx(19) + 37, {0.9, 0.9, 0.9, 1})
    else
        ui.drawString("NO TARGET SELECTION", ui.toPx(2), ui.toPx(19) + 23, {0.5, 0.5, 0.5, 1})
    end
    ui.drawString("[ESC to cancel]", ui.toPx(2), ui.toPx(19) + 58, {0.6, 0.6, 0.6, 1})
end

function renderer.drawEquipMenu(c, selectedSlotIdx, session)
    local slideDur = config.ui and config.ui.menuSlideDuration or 0.22
    local progress
    if renderer.closing and renderer.closingScene == "equip_passive" then
        progress = math.max(0, math.min(1, renderer.closingTimer / slideDur))
    else
        progress = math.min(1, menuTimer / slideDur)
    end
    local ease = 1 - (1 - progress) * (1 - progress)
    local ox = (1 - ease) * ui.toPx(32.5)

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, 256, 244)
    love.graphics.setColor(1, 1, 1, 1)
    
    ui.drawPanel(ui.toPx(2) + ox, ui.toPx(3), ui.toPx(28), ui.toPx(15), "EQUIP: " .. c.name:upper())
    
    local eq1 = c.equipment[1]
    local eq2 = c.equipment[2]
    local eq3 = c.equipment[3]
    
    local slot1Text = "WPN: " .. (eq1 and eq1.name or "[ EMPTY ]")
    local slot2Text = "AMR: " .. (eq2 and eq2.name or "[ EMPTY ]")
    local slot3Text = "ACC: " .. (eq3 and eq3.name or "[ EMPTY ]")
    
    ui.drawString((selectedSlotIdx == 1 and "> " or "  ") .. slot1Text, ui.toPx(3) + ox, ui.toPx(6), selectedSlotIdx == 1 and {1, 1, 0.5, 1} or {1, 1, 1, 1}, "left", ui.toPx(15))
    ui.drawString((selectedSlotIdx == 2 and "> " or "  ") .. slot2Text, ui.toPx(3) + ox, ui.toPx(8.5), selectedSlotIdx == 2 and {1, 1, 0.5, 1} or {1, 1, 1, 1}, "left", ui.toPx(15))
    ui.drawString((selectedSlotIdx == 3 and "> " or "  ") .. slot3Text, ui.toPx(3) + ox, ui.toPx(11), selectedSlotIdx == 3 and {1, 1, 0.5, 1} or {1, 1, 1, 1}, "left", ui.toPx(15))
    
    -- Draw stats on the right (x = 18 tiles)
    local atk = traits.getParam(c, "atk", session)
    local def = traits.getParam(c, "def", session)
    local mat = traits.getParam(c, "mat", session)
    local mdf = traits.getParam(c, "mdf", session)
    ui.drawString("STATS", ui.toPx(18) + ox, ui.toPx(6), {0.5, 0.8, 1, 1})
    ui.drawString("ATK: " .. atk, ui.toPx(18) + ox, ui.toPx(7.75), {1, 1, 1, 1})
    ui.drawString("DEF: " .. def, ui.toPx(18) + ox, ui.toPx(9.25), {1, 1, 1, 1})
    ui.drawString("MAT: " .. mat, ui.toPx(18) + ox, ui.toPx(10.75), {1, 1, 1, 1})
    ui.drawString("MDF: " .. mdf, ui.toPx(18) + ox, ui.toPx(12.25), {1, 1, 1, 1})
    
    local bottomY = ui.toPx(20) + (1 - ease) * ui.toPx(12)
    ui.drawPanel(ui.toPx(1), bottomY, ui.toPx(30), ui.toPx(9.5), "INFO")
    local selEq = c.equipment[selectedSlotIdx]
    if selEq then
        ui.drawString(selEq.name:upper() .. " - Equipped", ui.toPx(2), bottomY + 23, {1, 0.85, 0.5, 1})
        ui.drawString(selEq.description or "No description.", ui.toPx(2), bottomY + 37, {0.9, 0.9, 0.9, 1}, "left", ui.toPx(28))
    else
        ui.drawString("EMPTY SLOT", ui.toPx(2), bottomY + 23, {0.5, 0.5, 0.5, 1})
        ui.drawString("Nothing equipped. Press ENTER to select equipment from your inventory.", ui.toPx(2), bottomY + 37, {0.9, 0.9, 0.9, 1}, "left", ui.toPx(28))
    end
end

local function getStatPreview(c, slotIdx, newItem, session)
    local prevItem = c.equipment[slotIdx]
    
    local oldAtk = traits.getParam(c, "atk", session)
    local oldDef = traits.getParam(c, "def", session)
    local oldMat = traits.getParam(c, "mat", session)
    local oldMdf = traits.getParam(c, "mdf", session)
    local oldMaxHp = c:getMaxHp(session)
    
    c.equipment[slotIdx] = (newItem.id == "empty") and nil or newItem
    
    local newAtk = traits.getParam(c, "atk", session)
    local newDef = traits.getParam(c, "def", session)
    local newMat = traits.getParam(c, "mat", session)
    local newMdf = traits.getParam(c, "mdf", session)
    local newMaxHp = c:getMaxHp(session)
    
    c.equipment[slotIdx] = prevItem
    
    local changes = {}
    if newMaxHp ~= oldMaxHp then table.insert(changes, string.format("HP:%d->%d", oldMaxHp, newMaxHp)) end
    if newAtk ~= oldAtk then table.insert(changes, string.format("ATK:%d->%d", oldAtk, newAtk)) end
    if newDef ~= oldDef then table.insert(changes, string.format("DEF:%d->%d", oldDef, newDef)) end
    if newMat ~= oldMat then table.insert(changes, string.format("MAT:%d->%d", oldMat, newMat)) end
    if newMdf ~= oldMdf then table.insert(changes, string.format("MDF:%d->%d", oldMdf, newMdf)) end
    
    if #changes == 0 then return "No changes." end
    return table.concat(changes, "  ")
end

function renderer.drawSelectEquipMenu(rightIdx, session, slotType, c, slotIdx)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, 256, 244)
    love.graphics.setColor(1, 1, 1, 1)
    
    ui.drawPanel(ui.toPx(3), ui.toPx(2), ui.toPx(26), ui.toPx(16), "SELECT " .. slotType:upper())
    
    -- Filter inventory for matching equipment items
    local list = {}
    table.insert(list, { id = "empty", name = "[ UNEQUIP ]", description = "Unequip the item in this slot." })
    for itemId, qty in pairs(session.inventory) do
        local item = session.loader.getItem(itemId)
        if item and item.type == "equipment" and item.equipType == slotType then
            table.insert(list, item)
        end
    end
    
    if #list == 1 then
        ui.drawString("No suitable equipment in inv.", ui.toPx(4), ui.toPx(5.5), {0.5, 0.5, 0.5, 1})
    else
        local startIdx = math.max(1, rightIdx - 8)
        local count = 0
        for i = startIdx, math.min(#list, startIdx + 9) do
            local isSel = (i == rightIdx)
            local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = isSel and "> " or "  "
            local py = ui.toPx(5.5) + count * 11
            ui.drawString(prefix .. list[i].name, ui.toPx(4), py, color)
            count = count + 1
        end
    end
    
    local bottomY = ui.toPx(19)
    ui.drawPanel(ui.toPx(1), bottomY, ui.toPx(30), ui.toPx(10), "INFO")
    local selItem = list[rightIdx]
    if selItem then
        ui.drawString(selItem.name:upper(), ui.toPx(2), bottomY + 23, {1, 0.85, 0.5, 1})
        ui.drawString(selItem.description or "No details.", ui.toPx(2), bottomY + 37, {0.9, 0.9, 0.9, 1}, "left", ui.toPx(28))
        
        if c and slotIdx then
            local previewStr = getStatPreview(c, slotIdx, selItem, session)
            ui.drawString("PREVIEW: " .. previewStr, ui.toPx(2), bottomY + 58, {1, 1, 0.5, 1})
        end
    end
end

return renderer
