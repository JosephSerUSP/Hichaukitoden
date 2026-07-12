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

-- Config-driven animation constants (flash/shake/dead tint) and the
-- damage-feedback state keyed by battler identity now live in
-- presentation/small_battlers.lua, shared with the window renderer's
-- party-shaped list rows (owner direction 11.07.2026: one drawer, one
-- state table, so a party member's status cell looks and behaves
-- identically everywhere it's drawn).
local animVal = small_battlers.animVal

-- Shared battler status cell: a windowskin panel behind the (x, y,-anchored)
-- content region, then the animated sprite (small_battlers.draw handles
-- dead tint / flash / shake) at (x, y). Used by BOTH the party grid slots
-- and the summoner status box; window_renderer.lua's drawList calls the
-- same small_battlers.draw for party-shaped list rows, so a party member's
-- status looks and behaves identically everywhere (owner direction
-- 11.07.2026). x/y stay the exact anchor the existing name/HP/bar math
-- already uses — only a padded panel is newly drawn behind it. Returns
-- the sprite's width footprint (0 if none drawn).
local function drawBattlerStatusCell(battler, x, y, w, h, spriteSize)
    ui.drawPanel(x - 2, y - 2, w, h)
    local spriteKey = (battler.actorData and (battler.actorData.smallBattler or battler.actorData.spriteKey)) or battler.spriteKey
    local dead = battler.isDead and battler:isDead()
    if spriteKey and small_battlers.draw(spriteKey, x, y, spriteSize, dead, battler) then
        return spriteSize - 2
    end
    return 0
end

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

-- The summoner's display name, taken from actor data instead of a hardcoded
-- string so renaming the protagonist in the editor updates every UI panel.
local function summonerName()
    local s = renderer.session and renderer.session.summoner
    return (s and s.name or "Alex"):upper()
end

-- Summoner status block (name, HP, MP with bars), shared by the battle
-- console and the out-of-battle HUD so the layout is identical in and out
-- of battle and HP is visible everywhere (owner feedback 10.07.2026).
-- baseY is the top of the containing panel; offsets come from battleLayout.
local function drawSummonerStatus(baseY)
    local session = renderer.session
    local summoner = session.summoner
    local x = layoutVal("summonerStatusX")
    local nameY = baseY + layoutVal("summonerNameYOffset")
    local spriteSize = 24

    -- Shared battler status cell (windowskin panel + animated sprite) —
    -- same drawer the party grid and any scene's party rows use.
    local cellW = spriteSize + 2 + layoutVal("summonerMpBarWidth") + 4
    local cellH = 51
    local spriteOffsetX = 0
    if summoner then
        spriteOffsetX = drawBattlerStatusCell(summoner, x, nameY, cellW, cellH, spriteSize)
    end

    -- Use same yOff logic as party grid for vertical alignment
    local yOff = spriteOffsetX > 0 and -4 or 4
    local adjY = nameY + yOff   -- matches party grid's slot.y + yOff
    local contentX = x + spriteOffsetX

    -- Name (slot.y + yOff in party grid)
    ui.drawString(summonerName(), contentX, adjY, {1, 0.85, 0.5, 1})

    local maxHpSummoner = summoner and summoner:getMaxHp(session) or 0
    local hpDisplay = summoner and (summoner.displayedHp or summoner.hp) or 0
    local hpColor = (summoner and summoner:isDead()) and {0.5, 0.5, 0.5, 1} or {1, 1, 1, 1}

    -- HP text: matches partyGridHpYOffset (11) from adjY
    ui.drawString(math.floor(hpDisplay + 0.5) .. "/" .. maxHpSummoner, contentX, adjY + 11, hpColor)
    -- HP bar: matches partyGridHpBarYOffset (22) from adjY → 11px gap from text top
    ui.drawBar(contentX, adjY + 22, layoutVal("summonerMpBarWidth"), layoutVal("partyGridHpBarHeight"), hpDisplay, maxHpSummoner, {0.8, 0, 0}, {1, 0.3, 0.3})

    local dispMp = session.displayedMp or session.mp
    -- MP text: 11px below HP bar end (HP bar at adjY+22, 3px tall → ends at adjY+25)
    local mpTextY = adjY + 33
    ui.drawString(math.floor(dispMp + 0.5) .. "/" .. session.maxMp, contentX, mpTextY, {1, 1, 1, 1})
    -- MP bar: 11px gap from MP text top (same pattern as HP: textY + 11)
    ui.drawBar(contentX, mpTextY + 11, layoutVal("summonerMpBarWidth"), layoutVal("partyGridHpBarHeight"), dispMp, session.maxMp, {0, 0.4, 0.8}, {0.2, 0.7, 1})
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
    small_battlers.resetAnims()
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
        battleAnims[enemyIdx].flashTimer = animVal("flashDuration")
        battleAnims[enemyIdx].flashType = flashType or "action"
    end
end

-- Damage feedback (flash + shake) for a party small battler or the
-- summoner. Keyed by battler identity in presentation/small_battlers.lua,
-- so the same state is visible to drawBattlerStatusCell (battle/map HUD)
-- and window_renderer.lua's party-shaped list rows alike.
function renderer.triggerSmallDamage(target)
    small_battlers.triggerDamage(target)
end

function renderer.update(dt)
    -- The closing animation timer is owned by love.update in main.lua (it
    -- performs the scene switch and sets the input cooldown). Decrementing it
    -- here too made the two race: when this copy hit zero first, the scene
    -- never switched and the menu popped back open.

    local gravity = config.physics and config.physics.gravity or 480
    local bounceRetain = config.physics and config.physics.bounceVelocityRetain or 0.45
    for i = #damagePopups, 1, -1 do
        local p = damagePopups[i]
        p.revealElapsed = p.revealElapsed + dt
        for _, glyph in ipairs(p.glyphs) do
            if not glyph.active and p.revealElapsed >= glyph.startDelay then
                glyph.active = true
            end
            if glyph.active then updatePopupGlyph(glyph, dt, gravity, bounceRetain) end
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
    small_battlers.updateAnims(dt)
    
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

function renderer.addDamagePopup(text, x, y, color)
    local scatter = config.physics and config.physics.horizontalScatter or 40
    local lifeSpan = config.battle_screen and config.battle_screen.damagePopupLife or 1.1
    local popupConfig = config.battle_screen and config.battle_screen.popup or {}
    local characterDelay = popupConfig.characterDelay or 0
    local glyphs = {}
    for i = 1, #text do
        table.insert(glyphs, {
            char = text:sub(i, i),
            startDelay = (i - 1) * characterDelay,
            active = false,
            x = 0,
            y = 0,
            vy = -160,
            vx = math.random(-scatter, scatter),
            bounceCount = 0
        })
    end
    table.insert(damagePopups, {
        text = text,
        x = x,
        y = y,
        color = color or {1, 1, 1, 1},
        life = lifeSpan,
        revealElapsed = 0,
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

-- Render HUD/Party details in the bottom panel — the same summoner status
-- block and party grid geometry as the battle console.
local function drawHUD(x, y, w, h)
    ui.drawPanel(x, y, w, h)
    drawSummonerStatus(y)
    renderer.drawPartyGrid(ui.toPx(layoutVal("partyGridTileX")), y + ui.toPx(layoutVal("headerTileOffset")), 0, renderer.session, false)
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
    
    -- Town options are data-driven (system.town.options)
    local townOptions = (config.town and config.town.options) or {}
    for i, opt in ipairs(townOptions) do
        local color = (i == selectedIdx) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local prefix = (i == selectedIdx) and "> " or "  "
        ui.drawString(prefix .. (opt.label or "???"), ui.toPx(2), ui.toPx(2) + i * ui.lineHeight, color)
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
            local prefix = (i == selectIdx) and "> " or "  "
            ui.drawString(prefix .. opt.label, winX + ui.toPx(1), ui.toPx(5) + i * ui.lineHeight, color)
        end
    end
    
    drawHUD(0, ui.toPx(18), ui.toPx(32), ui.toPx(12))
end

-- The 2x2 party grid is now a thin arrangement loop: every party member's
-- cell content (sprite, icons, name, HP text, HP bar, windowskin panel) is
-- drawn by actor_status.draw — the SAME function any scene's party list
-- uses (owner direction 11.07.2026: one actor-status thing, called once
-- per member, everywhere a party is shown).
function renderer.drawPartyGrid(x, y, selectedIdx, session, showCursor)
    local colW, rowH = actor_status.cellSize(session)
    local gridCoords = {
        { x = x, y = y },
        { x = x + colW, y = y },
        { x = x, y = y + rowH },
        { x = x + colW, y = y + rowH }
    }
    for i = 1, 4 do
        local c = session.party[i]
        local slot = gridCoords[i]
        local isSel = (showCursor and i == selectedIdx)
        if c then
            actor_status.draw(c, slot.x, slot.y, isSel, session)
        else
            actor_status.drawEmpty(slot.x, slot.y, isSel, session)
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

        local gridX = ui.toPx(layoutVal("partyGridTileX"))
        local gridY = ui.toPx(layoutVal("consoleTileY")) + ui.toPx(layoutVal("headerTileOffset"))
        -- Same 2x2 slot arithmetic as drawPartyGrid
        for idx, c in ipairs(session.party) do
            if c == target then
                local col = (idx - 1) % 2
                local row = math.floor((idx - 1) / 2)
                local slotX = gridX + col * layoutVal("partyGridColWidth")
                local slotY = gridY + row * layoutVal("partyGridRowHeight")
                return slotX + layoutVal("slotPopupOffsetX"), slotY + layoutVal("slotPopupOffsetY")
            end
        end
        if target == session.summoner then
            return layoutVal("summonerPopupX"), ui.toPx(layoutVal("consoleTileY")) + layoutVal("summonerPopupYOffset")
        end
    end
    return layoutVal("fallbackX"), layoutVal("fallbackY")
end

function renderer.drawBattle(battleState, combatLog, combatState, selectedIndex, spellSelect, livingMembers, activeMemberIdx, victoryInfo, victoryStage)
    renderer.activeBattle = battleState
    
    -- Draw 3D dungeon view behind battle scene
    viewport_3d.draw(renderer.session)
    
    -- Subtle darkened overlay (not too heavy)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, layoutVal("viewportOverlayW"), layoutVal("viewportOverlayH"))
    love.graphics.setColor(1, 1, 1, 1)
    
    -- Render enemies portraits in viewport with slide-in and death animations
    local spacing = layoutVal("enemyRowWidth") / #battleState.enemies
    for idx, enemy in ipairs(battleState.enemies) do
        local anim = battleAnims[idx] or { slideTimer = 0, deathTimer = -1, dead = false }
        local portrait = getPortrait(enemy.spriteKey or enemy.id)
        local ex = layoutVal("enemyStartX") + (idx - 1) * spacing
        local ey = layoutVal("enemyY")
        
        -- Slide-in offset: start offscreen right, slide to position
        local slideOff = 0
        if anim.slideTimer > 0 then
            slideOff = layoutVal("enemySlideOffset") * (anim.slideTimer / 0.35)
        end
        local drawX = ex + slideOff
        
        if anim.dead and anim.deathTimer >= 0 then
            -- Death animation: additive blend, purple tint, fade to black
            local t = anim.deathTimer / 0.9  -- 1.0 = just died, 0.0 = done
            local alpha = t
            love.graphics.setBlendMode("add")
            if portrait then
                love.graphics.setColor(0.6 * alpha, 0, 0.9 * alpha, alpha)
                love.graphics.draw(portrait, drawX, ey + (1-t)*layoutVal("enemyDeathYOffset"), 0, layoutVal("enemySpriteSize")/portrait:getWidth(), layoutVal("enemySpriteSize")/portrait:getHeight())
            else
                love.graphics.setColor(0.6*alpha, 0, 0.9*alpha, alpha)
                love.graphics.rectangle("fill", drawX, ey + (1-t)*layoutVal("enemyDeathYOffset"), layoutVal("enemyFallbackSize"), layoutVal("enemyFallbackSize"))
            end
            love.graphics.setBlendMode("alpha")
        elseif not anim.dead then
            if portrait then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(portrait, drawX, ey, 0, layoutVal("enemySpriteSize")/portrait:getWidth(), layoutVal("enemySpriteSize")/portrait:getHeight())
            else
                love.graphics.setColor(0.8, 0.1, 0.1, 1)
                love.graphics.rectangle("fill", drawX, ey, layoutVal("enemyFallbackSize"), layoutVal("enemyFallbackSize"))
            end
            
            -- Apply action/damage flash overlay
            if anim.flashTimer and anim.flashTimer > 0 then
                love.graphics.setBlendMode("add")
                local flashDur = animVal("flashDuration")
                local flashCol = animVal(anim.flashType == "action" and "flashColorAction" or "flashColorDamage")
                love.graphics.setColor(flashCol[1], flashCol[2], flashCol[3], flashDur > 0 and (anim.flashTimer / flashDur) or 0)
                if portrait then
                    love.graphics.draw(portrait, drawX, ey, 0, layoutVal("enemySpriteSize")/portrait:getWidth(), layoutVal("enemySpriteSize")/portrait:getHeight())
                else
                    love.graphics.rectangle("fill", drawX, ey, layoutVal("enemyFallbackSize"), layoutVal("enemyFallbackSize"))
                end
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(1, 1, 1, 1)
            end
            
            local maxHp = enemy:getMaxHp(renderer.session)
            love.graphics.setColor(1,1,1,1)
            local enemyIconW = actor_status.drawElementIcons(traits.getElements(enemy, renderer.session), ex, layoutVal("enemyNameY") - 4, renderer.session)
            ui.drawString(enemy.name, ex + enemyIconW, layoutVal("enemyNameY"), {1, 1, 1, 1})
            ui.drawBar(ex, layoutVal("enemyHpBarY"), layoutVal("enemyHpBarWidth"), layoutVal("enemyHpBarHeight"), enemy.displayedHp or enemy.hp, maxHp, {0.8, 0, 0}, {1, 0.3, 0.3})
        end
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
    
    -- Bottom status console: summoner status (left, B.1/B.6) + party grid
    -- (right). Battler commands no longer live inside it (B.7).
    local consoleY = ui.toPx(layoutVal("consoleTileY"))
    local consoleH = ui.toPx(layoutVal("consoleTileH"))
    local textX = ui.toPx(layoutVal("consoleTextTileX"))
    local headerY = consoleY + ui.toPx(layoutVal("headerTileOffset"))

    ui.drawPanel(ui.toPx(layoutVal("consoleTileX")), consoleY, ui.toPx(layoutVal("consoleTileW")), consoleH)

    -- B.7: the battler command menu is its own single-line window spanning
    -- the full width, flush above the status console; it opens during input
    -- and closes outside it. No turn-name header (owner feedback 10.07.2026).
    if combatState == "input" then
        local memberInfo = livingMembers and livingMembers[activeMemberIdx]
        local isSummoner = (not memberInfo or memberInfo.type == "summoner")
        local loader = renderer.session.loader

        local entries, helps = {}, {}
        if isSummoner then
            if spellSelect then
                -- Real spell names + MP costs from summoner.spells / skills.json
                for _, spellId in ipairs((config.summoner and config.summoner.spells) or {}) do
                    if type(spellId) == "table" then spellId = spellId.id end
                    local sk = loader.getSkill(spellId)
                    if sk then
                        table.insert(entries, sk.name .. " (" .. (sk.mpCost or 0) .. "MP)")
                        table.insert(helps, sk.description or "")
                    end
                end
            else
                entries = loader.getTermList("battle.commands_summoner", { "Attack", "Spell", "Item", "Flee" })
                helps = loader.getTermList("battle.help_summoner", {
                    "Strike with a basic attack.",
                    "Cast a spell from the grimoire.",
                    "Use an item from the inventory.",
                    "Attempt to escape the battle.",
                })
            end
        else
            local monster = memberInfo.actor
            if spellSelect then
                for _, skId in ipairs(monster.skills or {}) do
                    local sk = loader.getSkill(skId)
                    if sk then
                        table.insert(entries, sk.name)
                        table.insert(helps, sk.description or "")
                    end
                end
                if #entries == 0 then entries = { "(No skills)" } end
            else
                entries = loader.getTermList("battle.commands_monster", { "Attack", "Skill", "Defend", "Flee" })
                helps = loader.getTermList("battle.help_monster", {
                    "Strike with a basic attack.",
                    "Use one of this creature's skills.",
                    "Brace to reduce incoming damage.",
                    "Attempt to escape the battle.",
                })
            end
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
            local prefix = (not isDim and i == selectedIndex) and "> " or "  "
            ui.drawString(prefix .. label, textX + math.floor((i - 1) * slot), rowY, color)
        end

        -- Help window: same panel as the battle log, describing the selected
        -- command or skill (owner feedback 10.07.2026).
        local helpText = helps[selectedIndex] or ""
        if helpText ~= "" then
            ui.drawPanel(layoutVal("logPanelX"), layoutVal("logPanelY"), layoutVal("logPanelWidth"), layoutVal("logPanelHeight"))
            ui.drawString(helpText, layoutVal("logTextX"), layoutVal("logTextY"), {1, 1, 1, 1}, "left", layoutVal("logTextLimit"))
        end
    end

    -- B.1/B.6: summoner status — the same shared block the HUD uses
    local session = renderer.session
    drawSummonerStatus(consoleY)

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
    renderer.drawPartyGrid(ui.toPx(layoutVal("partyGridTileX")), headerY, highlightIdx, session, showHighlight)

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

    -- Draw active damage popups
    love.graphics.push("all")
    for _, p in ipairs(damagePopups) do
        local alpha = math.min(1, p.life * 2)
        local col = { p.color[1], p.color[2], p.color[3], alpha }
        local textOffset = 0
        local font = love.graphics.getFont()
        for _, glyph in ipairs(p.glyphs) do
            if p.revealElapsed >= glyph.startDelay then
                -- Opacity is shared across the popup, not reset for each
                -- glyph, so every character fades out in sync.
                ui.drawString(glyph.char, p.x + textOffset + glyph.x, p.y + glyph.y, col)
            end
            textOffset = textOffset + font:getWidth(glyph.char)
        end
    end
    love.graphics.pop()
end

-- drawShop deleted: the shop is a declarative scene now ("draw": "windows"
-- in scenes.json) — the generic window renderer draws it from its hooks.

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

    -- status_detail removed: STATUS is a declarative scene now
    -- (scenes.json 'status'), pushed by the menu instead of a sub-scene.
    
    -- Quadratic ease-out slide-in animation
    local slideDur = config.ui and config.ui.menuSlideDuration or 0.22
    local slideProgress
    if renderer.closing and renderer.closingScene == "menu" then
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
    local mainOpts = session.loader.getTermList("menu.main_options", { "ITEMS", "STATUS", "EQUIP", "EXIT" })
    for i, opt in ipairs(mainOpts) do
        local isSel = (subScene == "main" and i == mainIdx)
        local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local prefix = isSel and ">" or " "
        ui.drawString(prefix .. opt, leftX + 0.5 * ui.tileSize, (ui.toPx(4) + (config.windowLayout and config.windowLayout.headerSpacing or 0)) + (i - 1) * ui.lineHeight, color)
    end
    
    -- Gold and Floor stats inside left menu column below the options
    local statsY = math.max(12.5, 4.0 + #mainOpts * 2.0)
    ui.drawString("GOLD", leftX + 0.5 * ui.tileSize, ui.toPx(statsY), {0.6, 0.6, 0.6, 1})
    ui.drawString(session.gold .. " G", leftX + 0.5 * ui.tileSize, ui.toPx(statsY + 1.0), {1, 0.9, 0.3, 1})
    
    local mapTitle = "Town"
    if session.currentMapData then
        mapTitle = session.currentMapData.title or "1"
    end
    ui.drawString("FLOOR", leftX + 0.5 * ui.tileSize, ui.toPx(statsY + 2.25), {0.6, 0.6, 0.6, 1})
    ui.drawString(mapTitle, leftX + 0.5 * ui.tileSize, ui.toPx(statsY + 3.25), {1, 1, 1, 1}, "left", ui.toPx(6.75))
    
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
        renderer.drawPartyGrid(rightX + 1 * ui.tileSize, (ui.toPx(4) + (config.windowLayout and config.windowLayout.headerSpacing or 0)), rightIdx, session, showCursor)
        
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
            ui.drawString(summonerName() .. "'S CREATURES", textLeftMargin, bottomY + 3 * ui.tileSize, {1, 0.85, 0.5, 1})
            ui.drawString("Manage your active summon spirits and modify equipment parameters.", textLeftMargin, bottomY + 4.75 * ui.tileSize, {0.7, 0.7, 0.7, 1}, "left", ui.toPx(28))
        end
        
    elseif subScene == "exit_confirm" then
        ui.drawString("Exit Hichaukitoden?", rightX + 1 * ui.tileSize, (ui.toPx(4) + (config.windowLayout and config.windowLayout.headerSpacing or 0)), {1, 1, 1, 1})
        
        local isYes = (rightIdx == 1)
        local isNo = (rightIdx == 2)
        ui.drawString((isYes and "> " or "  ") .. "YES (Quit to Desktop)", rightX + 1 * ui.tileSize, ui.toPx(6.75), isYes and {1, 0.5, 0.5, 1} or {1, 1, 1, 1})
        ui.drawString((isNo and "> " or "  ") .. "NO (Resume Game)", rightX + 1 * ui.tileSize, ui.toPx(8.5), isNo and {1, 1, 0.5, 1} or {1, 1, 1, 1})
        
        ui.drawString("EXIT GAME", textLeftMargin, bottomY + 3 * ui.tileSize, {1, 0.5, 0.5, 1})
        ui.drawString("Select YES and press ENTER to safely quit the game. Select NO or press ESC to resume.", textLeftMargin, bottomY + 4.75 * ui.tileSize, {0.9, 0.9, 0.9, 1}, "left", ui.toPx(28))
    end
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
    
    -- B.3: slot rows show the equipped item's icon
    local function slotRow(idx, label, eq, y)
        local sel = (selectedSlotIdx == idx)
        local color = sel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        ui.drawString(sel and ">" or " ", ui.toPx(3) + ox, y, color)
        if eq and eq.icon and eq.icon > 0 then
            ui.drawIcon(eq.icon, ui.toPx(4) + ox, y - 1)
        end
        ui.drawString(label .. ": " .. (eq and eq.name or "[ EMPTY ]"), ui.toPx(5.75) + ox, y, color, "left", ui.toPx(15))
    end
    slotRow(1, "WPN", c.equipment[1], ui.toPx(6))
    slotRow(2, "AMR", c.equipment[2], ui.toPx(8.5))
    slotRow(3, "ACC", c.equipment[3], ui.toPx(11))
    
    -- Draw stats on the right (x = 18 tiles)
    local atk = traits.getParam(c, "atk", session)
    local def = traits.getParam(c, "def", session)
    local mat = traits.getParam(c, "mat", session)
    local mdf = traits.getParam(c, "mdf", session)
    ui.drawString("STATS", ui.toPx(18) + ox, ui.toPx(6), {0.5, 0.8, 1, 1})
    ui.drawString("ATK: " .. atk, ui.toPx(18) + ox, ui.toPx(7.75), {1, 1, 1, 1})
    ui.drawString("DEF: " .. def, ui.toPx(18) + ox, ui.toPx(8.75), {1, 1, 1, 1})
    ui.drawString("MAT: " .. mat, ui.toPx(18) + ox, ui.toPx(9.75), {1, 1, 1, 1})
    ui.drawString("MDF: " .. mdf, ui.toPx(18) + ox, ui.toPx(10.75), {1, 1, 1, 1})
    
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
        -- Dynamic spacing to fill the panel vertically
        local equipContentStart = ui.toPx(5.5)
        local equipPanelBottom = ui.toPx(2) + ui.toPx(16) - 8
        local equipVisibleCount = math.min(#list, startIdx + 9) - startIdx + 1
        local equipSpacing = math.max(ui.lineHeight, math.floor((equipPanelBottom - equipContentStart) / equipVisibleCount))
        for i = startIdx, math.min(#list, startIdx + 9) do
            local entry = list[i]
            local isSel = (i == rightIdx)
            local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = isSel and "> " or "  "
            local py = equipContentStart + count * equipSpacing
            -- Draw item icon if available
            local textX = ui.toPx(4)
            if entry.icon and entry.id ~= "empty" then
                ui.drawIcon(entry.icon, textX + 1 * ui.tileSize, py - 1)
                ui.drawString(prefix .. entry.name, textX + 3 * ui.tileSize, py, color)
            else
                ui.drawString(prefix .. entry.name, textX, py, color)
            end
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
