local ui = require("presentation.ui")
local viewport_3d = require("presentation.viewport_3d")
local exploration = require("engine.exploration")
local battleSystem = require("engine.battle")
local director = require("engine.director")
local traits = require("engine.traits")
local config = require("engine.config")
local small_battlers = require("presentation.small_battlers")
local battle_layout = require("presentation.battle_layout")
local battler_geometry = require("presentation.battler_geometry")
local actor_status = require("presentation.actor_status")
local animation_player = require("presentation.animation_player")
local gradient_shader  = require("presentation.gradient_shader")
local detection = require("engine.detection")
local compareIds = require("engine.inventory").compareIds

local renderer = {}

-- Direction constants matching viewport_3d.lua, used by the rotating minimap
local MINIMAP_DIR_ORDER = { "N", "E", "S", "W" }
local MINIMAP_DIR_ANGLES = {
    N = -math.pi / 2,
    E = 0,
    S = math.pi / 2,
    W = math.pi,
}

local function minimapTurnRightDir(dir)
    local idx = 1
    for i, d in ipairs(MINIMAP_DIR_ORDER) do
        if d == dir then idx = i; break end
    end
    return MINIMAP_DIR_ORDER[idx % 4 + 1]
end

local function minimapTurnLeftDir(dir)
    local idx = 1
    for i, d in ipairs(MINIMAP_DIR_ORDER) do
        if d == dir then idx = i; break end
    end
    return MINIMAP_DIR_ORDER[(idx - 2) % 4 + 1]
end

local lerpAngle = ui.lerpAngle

-- Battle layout accessor: engine.json override -> built-in default.
-- Defaults + override lookup live in presentation/battle_layout.lua,
-- shared with actor_status.lua (breaks the require cycle that would
-- otherwise exist between the two modules).
local function layoutVal(key)
    return battle_layout.get(renderer.session, key)
end

local damagePopups = {}
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

-- Byte-count prefix that never splits a multibyte UTF-8 character: if the
-- cut lands inside a codepoint (next byte is a continuation byte), snap
-- back to the previous boundary. love.graphics.printf hard-errors on
-- malformed UTF-8, and dialogue text carries em dashes/curly quotes.
local function utf8Prefix(text, n)
    if n >= #text then return text end
    local nextByte = text:byte(n + 1)
    while n > 0 and nextByte and nextByte >= 0x80 and nextByte < 0xC0 do
        n = n - 1
        nextByte = text:byte(n + 1)
    end
    return text:sub(1, n)
end

-- overhaul-7 A1: animation constants and timing are owned by
-- presentation/animation_player.lua using data/animations.json entries.
-- The small_battlers module still provides the dead-tint constant for
-- game-state dead display.

-- Delegates to the shared resolver in ui.lua (also used by
-- window_renderer's data-authored portrait blocks) so both drawing paths
-- try the same "NPC_" prefix / case-variant filename fallbacks.
local function getBigBattler(battler)
    return ui.resolveBigBattlerImage(battler and battler.actorData and battler.actorData.bigBattler)
end

-- Placement itself is battler_geometry's job (the single authority); this
-- module only binds its session and bigBattler cache to it.

function renderer.init(session)
    renderer.session = session
    ui.init()
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

-- Owner feedback (17.07.2026): enemies should enter with a small timing
-- offset per slot, the same idea as damage popups' spawnDelay staggering
-- same-location hits — a cleaner, more readable arrival than all of them
-- sliding in on the exact same frame.
local ENEMY_ENTRY_STAGGER_MS = 120

function renderer.initBattleAnims(enemies)
    animation_player.reset()
    deadEnemyFlags = {}
    for i, enemy in ipairs(enemies) do
        animation_player.play("system.enemy_slide_in", enemy, (i - 1) * ENEMY_ENTRY_STAGGER_MS)
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
-- Compares against the pre-wrapped form when one is cached so "done"
-- means the same thing the draw path means by it.
function renderer.isDialogueRevealing()
    local node = dialogueReveal.node
    if not node or node.type ~= "TEXT" then return false end
    local content = dialogueReveal.wrapped or node.content or ""
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

-- Renders the mini-map in a small panel, rotated so the player's facing
-- direction always points upward. Supports mid-animation turn interpolation.
--
-- Camera follows the player (RPG Maker style): the viewport is always centred
-- on the player unless doing so would expose void beyond the map edges, in
-- which case the viewport shifts to stay clamped (no void shown).  If the map
-- is smaller than the viewport, the entire map is centred.
--
-- A tile includes its black gap pixel (tileSize px per tile), so the panel is
-- sized as n * tileSize + 2 — exactly 1 px of background on each side.
-- Minimap colours for detected traps/secrets. Distinct from event colours so a
-- sensed danger never reads as an ordinary interactable.
local DETECT_COLORS = {
    trap    = { 1, 0.35, 0.1, 1 },   -- warning orange
    secret  = { 0.5, 0.9, 1, 1 },    -- pale cyan
    default = { 1, 1, 0.4, 1 },
}

local function drawMinimap(x, y, radius)
    local session = renderer.session
    local grid = session.mapGrid
    if not grid then return end

    local px, py = session.playerX, session.playerY
    local tileSize = 2       -- each tile = 1 coloured + 1 black gap
    radius = radius or 6     -- tiles visible in each direction from the player

    local gridW, gridH = #grid[1], #grid
    local visW = radius * 2 + 1
    local visH = radius * 2 + 1

    -- ── 1. Viewport bounds (RPG Maker camera) ─────────────────────────────
    -- Start player-centred, then shift when clamped to map edges.  For maps
    -- smaller than the viewport, centre the entire map.
    local startGx = px - radius
    local endGx   = px + radius
    local startGy = py - radius
    local endGy   = py + radius

    if gridW <= visW then
        startGx, endGx = 1, gridW
    elseif startGx < 1 then
        endGx = endGx + (1 - startGx)
        startGx = 1
    elseif endGx > gridW then
        startGx = startGx - (endGx - gridW)
        endGx = gridW
    end

    if gridH <= visH then
        startGy, endGy = 1, gridH
    elseif startGy < 1 then
        endGy = endGy + (1 - startGy)
        startGy = 1
    elseif endGy > gridH then
        startGy = startGy - (endGy - gridH)
        endGy = gridH
    end

    -- Visual centre (rotation pivot) — midpoint of the visible tile range
    local centreTileX = (startGx + endGx) / 2
    local centreTileY = (startGy + endGy) / 2

    -- ── 2. Panel sizing ───────────────────────────────────────────────────
    -- A tile occupies tileSize px (coloured + black gap).  Panel adds 1 px
    -- of true black on each side.
    local numTilesX = endGx - startGx + 1
    local numTilesY = endGy - startGy + 1
    local panelW = numTilesX * tileSize + 2
    local panelH = numTilesY * tileSize + 2

    -- Render overflow tiles outside the panel (and beyond the map) so
    -- rotation doesn't abruptly clip at the edges.  Tiles beyond the map
    -- limits are drawn as walls.  The scissor rect hides the excess.
    local overflow     = 2
    local renderStartGx = startGx - overflow
    local renderEndGx   = endGx   + overflow
    local renderStartGy = startGy - overflow
    local renderEndGy   = endGy   + overflow

    -- ── 3. Camera angle (turn interpolation) ──────────────────────────────
    local cAngle = MINIMAP_DIR_ANGLES[session.playerDir]
    if session.transitionTimer and session.transitionTimer > 0 then
        local frac = session.transitionTimer / 0.15
        if session.transitionDir == "turn_left" then
            local prevDir = minimapTurnRightDir(session.playerDir)
            local prevAngle = MINIMAP_DIR_ANGLES[prevDir]
            cAngle = lerpAngle(prevAngle, cAngle, 1.0 - frac)
        elseif session.transitionDir == "turn_right" then
            local prevDir = minimapTurnLeftDir(session.playerDir)
            local prevAngle = MINIMAP_DIR_ANGLES[prevDir]
            cAngle = lerpAngle(prevAngle, cAngle, 1.0 - frac)
        end
    end

    local rot = -(cAngle + math.pi / 2)   -- forward → screen-up

    -- ── 4. Background panel (no border) ───────────────────────────────────
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x, y, panelW, panelH)

    -- ── 5. Rotation pivot in screen pixels ────────────────────────────────
    -- centreTile maps to the midpoint of a tile (coloured part).  With
    -- tileSize=2 each tile sits at positions: coloured (1 px), gap (1 px),
    -- so the tile centre = pos + 0.5.
    local rotCx = x + 1 + (centreTileX - startGx) * tileSize + (tileSize - 1) / 2
    local rotCy = y + 1 + (centreTileY - startGy) * tileSize + (tileSize - 1) / 2

    -- ── 6. Map tiles (rotated, clipped to panel) ─────────────────────────
    -- Overflow tiles render outside the panel but the scissor hides them,
    -- giving a smooth appearance during rotation.
    local prevSx, prevSy, prevSw, prevSh = love.graphics.getScissor()
    love.graphics.setScissor(x, y, panelW, panelH)

    love.graphics.push()
    love.graphics.translate(rotCx, rotCy)
    love.graphics.rotate(rot)

    for gy = renderStartGy, renderEndGy do
        for gx = renderStartGx, renderEndGx do
            local dx = gx - centreTileX
            local dy = gy - centreTileY

            -- Detected traps/secrets (SEE_TRAPS / SEE_WALLS) show up even on
            -- tiles the party has never walked, which is the whole point of a
            -- creature's senses: they mark danger AHEAD. Resolution lives in
            -- engine/detection.lua; this only picks the colour.
            local detected = nil
            if gx >= 1 and gx <= gridW and gy >= 1 and gy <= gridH
                and session.currentMapData then
                for _, ev in ipairs(session.currentMapData.events or {}) do
                    if ev.x == gx - 1 and ev.y == gy - 1 and detection.isRevealed(session, ev) then
                        detected = ev.meta.detect
                        break
                    end
                end
                if not detected then
                    for _, ov in ipairs(session.currentMapData.overrides or {}) do
                        if ov.x == gx - 1 and ov.y == gy - 1 and detection.isRevealed(session, ov) then
                            detected = ov.meta.detect
                            break
                        end
                    end
                end
            end

            if gx < 1 or gx > gridW or gy < 1 or gy > gridH then
                -- Beyond map limits: draw as wall
                love.graphics.setColor(0.2, 0.2, 0.2, 1)
                love.graphics.rectangle("fill", dx * tileSize, dy * tileSize, tileSize - 1, tileSize - 1)
            elseif detected and not session.visitedGrid[gy][gx] then
                -- Sensed but unvisited: draw the marker on otherwise-unknown map.
                local c = DETECT_COLORS[detected] or DETECT_COLORS.default
                love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
                love.graphics.rectangle("fill", dx * tileSize, dy * tileSize, tileSize - 1, tileSize - 1)
            elseif session.visitedGrid[gy][gx] then
                local cell = grid[gy][gx]

                -- Event marker at this tile
                local mapEvent = nil
                if session.currentMapData and session.currentMapData.events then
                    for _, ev in ipairs(session.currentMapData.events) do
                        if ev.x == gx - 1 and ev.y == gy - 1 then
                            mapEvent = ev
                            break
                        end
                    end
                end

                if detected then
                    -- A sensed trap/secret keeps its detection colour on
                    -- visited tiles too, so it stays legible after you pass it.
                    local c = DETECT_COLORS[detected] or DETECT_COLORS.default
                    love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
                elseif mapEvent then
                    local evColor = mapEvent.minimapColor
                    if not evColor and mapEvent.scriptId and session.loader and session.loader.commonEvents then
                        local ce = session.loader.commonEvents[tostring(mapEvent.scriptId)]
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
                love.graphics.rectangle("fill", dx * tileSize, dy * tileSize, tileSize - 1, tileSize - 1)
            end
        end
    end

    -- ── 7. Player marker (inside rotation, at player's tile offset) ───────
    local blink = math.floor(love.timer.getTime() * 4) % 2 == 0
    love.graphics.setColor(blink and 1 or 1, blink and 0 or 1, blink and 0 or 1, 1)
    local ms = tileSize - 1
    love.graphics.rectangle("fill",
        (px - centreTileX) * tileSize,
        (py - centreTileY) * tileSize,
        ms, ms)

    love.graphics.pop()  -- transform (push/translate/rotate)

    -- Restore previous scissor (if any)
    if prevSx then
        love.graphics.setScissor(prevSx, prevSy, prevSw, prevSh)
    else
        love.graphics.setScissor()
    end
end


-- Renders the Town Scene
-- Renders the Map Scene
local eventLabelAnim = { label = nil, target = nil, changedAt = 0 }

local function drawAnimatedEventLabel(label)
    local now = love.timer.getTime()
    if label ~= eventLabelAnim.target then
        eventLabelAnim.target = label
        eventLabelAnim.changedAt = now
        if label then eventLabelAnim.label = label end
    end
    local shown = eventLabelAnim.label
    if not shown then return end
    local duration = 0.18
    local p = math.min(1, (now - eventLabelAnim.changedAt) / duration)
    local open = eventLabelAnim.target ~= nil
    local amount = open and p or (1 - p)
    amount = 1 - (1 - amount) * (1 - amount)
    if not open and p >= 1 then
        eventLabelAnim.label = nil
        return
    end

    local screenW = ui.toPx(ui.screenWidthTiles)
    local fullW = math.max(120, ui.measureText(shown) + 16)
    local fullH = 26
    local w = math.max(16, fullW * amount)
    local h = math.max(8, fullH * amount)
    local x = math.floor((screenW - w) / 2)
    local y = 118 - h / 2
    ui.drawPanel(x, y, w, h)
    love.graphics.push("all")
    love.graphics.setScissor(x, y, w, h)
    ui.drawString(shown, math.floor((screenW - fullW) / 2) + 4, 112,
        {1, 1, 0.5, 1}, "center", fullW - 8)
    love.graphics.pop()
end

function renderer.drawMap()
    viewport_3d.draw(renderer.session)
    
    -- Mini-map overlay, half a tile from top-right corner
    local mmPanelW = (6 * 2 + 1) * 2 + 2  -- 13 tiles * 2 + 2 = 28
    drawMinimap(ui.toPx(ui.screenWidthTiles) - mmPanelW - math.floor(ui.tileSize / 2), math.floor(ui.tileSize / 2), 6)
    
    -- Coordinates & Facing Overlay
    ui.drawString("X:" .. renderer.session.playerX .. " Y:" .. renderer.session.playerY .. " [" .. renderer.session.playerDir .. "]", 6, 6, {1, 1, 0.7, 0.8})
    
    -- Front action prompt / event label box if any
    local frontTile, tx, ty = exploration.getFrontTile(renderer.session)
    local targetEvent = nil
    if tx and ty and renderer.session.currentMapData and renderer.session.currentMapData.events then
        for _, rawEv in ipairs(renderer.session.currentMapData.events) do
            if rawEv.x == tx - 1 and rawEv.y == ty - 1 then
                targetEvent = exploration.resolvePage(rawEv, renderer.session)
                break
            end
        end
    end

    if (frontTile and frontTile ~= "#" and frontTile ~= ".") or targetEvent then
        local displayLabel = nil
        if targetEvent then
            if targetEvent.label and targetEvent.label ~= "" then
                displayLabel = targetEvent.label
            elseif targetEvent.scriptId and renderer.session.loader and renderer.session.loader.commonEvents then
                local ce = renderer.session.loader.commonEvents[tostring(targetEvent.scriptId)]
                if ce and ce.label and ce.label ~= "" then
                    displayLabel = ce.label
                end
            end
            if not displayLabel and targetEvent.name and targetEvent.name ~= "" and targetEvent.name ~= "Trigger" and targetEvent.name ~= "Event" then
                displayLabel = targetEvent.name
            end
        end

        if not displayLabel then
            if frontTile == "E" then displayLabel = "Stairs Down"
            elseif frontTile == "S" then displayLabel = "Stairs Up"
            elseif frontTile == "R" then displayLabel = "Recovery"
            elseif frontTile == "T" then displayLabel = "Treasure"
            else displayLabel = "Interact"
            end
        end

        if require("presentation.door_transition").isActive() then
            displayLabel = nil
        end
        drawAnimatedEventLabel(displayLabel)
    else
        drawAnimatedEventLabel(nil)
    end
end

-- Character-by-character reveal for the current dialogue TEXT node's
-- content, shared by the windows-drawn dialogue scene (main.lua's v-sync
-- reads this every frame) and renderer.isDialogueRevealing/
-- finishDialogueReveal, which all key off the same dialogueReveal tracker.
-- wrapPx (optional): pre-wrap the FULL text to hard breaks at that pixel
-- width ONCE per node, so the reveal can't shift wrap points mid-word --
-- printf re-wrapping a growing string is what made long lines jumpy.
function renderer.getRevealedDialogueText(node, wrapPx)
    if not node or node.type ~= "TEXT" then return "" end
    if dialogueReveal.node ~= node then
        dialogueReveal.node = node
        dialogueReveal.elapsed = 0
        dialogueReveal.wrapped = nil
    end
    if not dialogueReveal.wrapped then
        local content = node.content or ""
        dialogueReveal.wrapped = wrapPx and ui.wrapText(content, wrapPx) or content
    end
    local content = dialogueReveal.wrapped
    return utf8Prefix(content, revealedCount(content, dialogueReveal.elapsed))
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


-- The "party" window's grid origin (px, tiles->px converted) + column count
-- live in battler_geometry, the one battler-placement authority.

-- Maps a battler to the screen position where damage popups should spawn.
-- Used by main.lua so popup coordinates always match the drawn battle layout:
-- same rect, same anchor resolver the sprite and its animations use, so a
-- number can no longer float somewhere its creature isn't.
function renderer.getBattlerCoords(battleState, session, target)
    local rect = battler_geometry.rect(battleState, session, target, getBigBattler)
    if rect then
        return battler_geometry.popupAnchor(session, rect)
    end
    return layoutVal("fallbackX"), layoutVal("fallbackY")
end

-- F2 (overhaul-6): the shared party HUD (console + MP + 2x2 grid) is now the
-- declarative "party" window in presentation/window_renderer.lua, drawn for
-- every scene by main.lua's drawSharedPartyHud — no legacy party HUD remains.

local function getHoveredTargets(bv, combatState, selectedIndex, skillSelect, itemSelect, livingMembers, activeMemberIdx)
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

-- The box a target reticle frames: the rect's `frame`, which is the portrait
-- itself for an enemy and the whole status cell for a party member.
local function getBattlerRect(target, battleState, session)
    if not session or not target then return nil, nil, nil, nil end
    local rect = battler_geometry.rect(battleState, session, target, getBigBattler)
    if not rect then return nil, nil, nil, nil end
    return rect.frameX, rect.frameY, rect.frameW, rect.frameH
end

-- Summoner rework battle-windows conversion: the monolithic drawBattle is
-- split into standalone functions, one per window, each still reading its
-- geometry from battleLayout (data/engine.json) exactly as before — the
-- "windows" conversion makes each region's EXISTENCE and visibility
-- data-authored (scenes.json), not its fine pixel layout, which stays in
-- the shared battleLayout config exactly like every other battle draw
-- call already does (SPEC 2.1: no per-scene coordinate math). The command
-- console is the one piece that genuinely moved to the generic "command"
-- style window (data-listed rows via v.commandRows) since its content is
-- now built by the battle scene's own scripts, not this module.

-- Enemy row: viewport background + darken overlay + per-enemy sprites with
-- their full animation/shader/particle treatment (unchanged from before).
-- bgFadeOverride (0..1, defeat sequence stage 0 — owner feedback
-- 17.07.2026): when set, replaces the normal subtle 0.35 darken with an
-- animated value ramping toward fully black, drawn BEHIND the enemy
-- sprites (same as the normal overlay) so "the background fades" reads as
-- its own beat, distinct from the later full-screen fade that covers the
-- monsters too (renderer.drawDefeatFadeOverlay).
function renderer.drawEnemyRowWindow(battleState, bgFadeOverride)
    if not battleState then return end
    renderer.activeBattle = battleState

    -- Draw 3D dungeon view behind battle scene
    viewport_3d.draw(renderer.session)

    local bgAlpha = bgFadeOverride or 0.35
    love.graphics.setColor(0, 0, 0, bgAlpha)
    love.graphics.rectangle("fill", 0, 0, layoutVal("viewportOverlayW"), layoutVal("viewportOverlayH"))
    love.graphics.setColor(1, 1, 1, 1)

    -- Render full-body enemy battlers in viewport with animations driven by the
    -- animation player (overhaul-7 A1): slide-in, damage/action flash,
    -- death effect — all from data/animations.json entries.
    for idx, enemy in ipairs(battleState.enemies) do
        local bigBattler = getBigBattler(enemy)
        
        -- Query animation player for current transform, tint, blend, gradient
        local xf    = animation_player.getTransform(enemy)
        local tint  = animation_player.getTint(enemy)
        local blend = animation_player.getBlendMode(enemy)
        local isDeathPlaying = animation_player.isPlaying(enemy, "system.death")
        local isDead = deadEnemyFlags[enemy]

        -- Source pixels are screen pixels. Positioning owns only the
        -- bottom-centre anchor; authored size, overlap and clipping are kept.
        local rect = battler_geometry.enemyRect(
            renderer.session, idx, #battleState.enemies, bigBattler)
        local _, slotWidth = battler_geometry.enemySlot(
            renderer.session, idx, #battleState.enemies)
        local anchorX, anchorY = rect.x + rect.w / 2, rect.y + rect.h

        -- Query shake offset and apply it along with transform offsets
        local shakeOff = animation_player.getShakeOffset(enemy)
        local drawX = anchorX + xf.offsetX + shakeOff
        local drawY = anchorY + xf.offsetY

        -- drawEnemySprite draws around (drawX, drawY) as bottom-center origin.
        local function drawEnemySprite()
            if bigBattler then
                love.graphics.draw(bigBattler, drawX, drawY, 0, xf.scaleX, xf.scaleY,
                    bigBattler:getWidth() / 2, bigBattler:getHeight())
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
            animation_player.drawParticles(enemy, rect, drawEnemySprite, "back", renderer.session)
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
            animation_player.drawParticles(enemy, rect, drawEnemySprite, "front", renderer.session)

            -- Enemy info block: element icons + name + HP gauge. Geometry and
            -- every on/off switch come from engine.json battleLayout
            -- (enemyInfo*), anchored to this creature's feet rather than an
            -- absolute row, so it tracks the sprite instead of drifting from it.
            local info = battler_geometry.enemyInfo(renderer.session, rect, slotWidth)
            if info then
                local maxHp = enemy:getMaxHp(renderer.session)
                love.graphics.setColor(1, 1, 1, 1)
                local enemyIconW = 0
                if info.showElements then
                    enemyIconW = actor_status.drawElementIcons(
                        traits.getElements(enemy, renderer.session),
                        info.x, info.nameY - 4, renderer.session)
                end
                if info.showName then
                    ui.drawString(enemy.name, info.x + enemyIconW, info.nameY, {1, 1, 1, 1})
                end
                if info.showHpBar then
                    ui.drawBar(info.x, info.barY, info.width, info.barHeight,
                        enemy.displayedHp or enemy.hp, maxHp,
                        {0.8, 0, 0}, {1, 0.3, 0.3})
                end
            end
        end
        -- isDead without isDeathPlaying: enemy has fully faded, don't draw anything
    end
end

-- Battle log: slim 2-line reveal panel (previous line dimmed above the
-- currently-revealing one) + [SPACE] prompt. Visible only while
-- v.combatState == "log" — the window's `visible` formula handles that.
function renderer.drawBattleLogWindow(combatLog)
    combatLog = combatLog or {}
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
    ui.drawString(utf8Prefix(current, shownCount), layoutVal("logTextX"), layoutVal("logTextY") + layoutVal("logLineSpacing"), {1, 1, 1, 1}, "left", layoutVal("logTextLimit"))
    ui.drawString("[SPACE]", layoutVal("logSpaceX"), layoutVal("logSpaceY"), {0.5, 0.5, 0.5, 1}, "right", 40)
end

-- Victory window: gold/EXP drain animation with per-member gauges. Visible
-- only while v.combatState == "victory" (window `visible` formula).
function renderer.drawVictoryPanelWindow(session, victoryInfo, victoryStage, v)
    if not victoryInfo then return end
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

    -- Gold grant drains from X→0 while EXP value is static. The spoils
    -- text itself is no longer drawn on the victory panel (owner request:
    -- the battle_help window shows it instead) — published onto the scene
    -- var table each frame so battle_help's data-driven text can read it.
    local drainGold = math.floor((victoryAnim.displayedGoldDrain or victoryInfo.gold or 0) + 0.5)
    local partyGoldPreview = math.floor((victoryAnim.displayedPartyGold or victoryAnim.preGold or 0) + 0.5)
    if v then
        v.victorySpoilsText = "+" .. drainGold .. "G  EXP +" .. (victoryInfo.exp or 0) .. "\nGold: " .. partyGoldPreview .. " G"
    end

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

    -- Bottom prompt: ENTER to start drain, SPACE to dismiss when done
    local prompt = (victoryAnim.stage == 0) and "[ENTER]" or (victoryAnim.stage == 2 and "[SPACE]" or "")
    if prompt ~= "" then
        ui.drawString(prompt, vx + vw - 50, vy + vh - 12, {0.5, 0.5, 0.5, 1}, "right", 40)
    end
end

-- Full-screen flash overlay (screen_flash tracks), above everything — same
-- compositing as the editor preview channel. Not a window: a screen-space
-- post effect, always called directly regardless of scene draw mode (same
-- treatment as drawDamagePopups). Animations play per-target, so scan every
-- battler for an active flash; first hit wins (matches the preview, which
-- only ever has one target). 256x240 is the game's logical resolution.
-- Defeat sequence, FINAL stage only (owner feedback, 17.07.2026): a
-- full-canvas black fade covering everything, including the monsters --
-- the earlier "background fades" beat is a separate, viewport-only
-- overlay drawn behind the enemy sprites (drawEnemyRowWindow's
-- bgFadeOverride). Driven by v.defeatFinalFade — see battle.update's DEFEAT_STAGE*_DUR.
function renderer.drawDefeatFadeOverlay(alpha)
    if not alpha or alpha <= 0 then return end
    love.graphics.setColor(0, 0, 0, math.min(1, alpha))
    love.graphics.rectangle("fill", 0, 0, 256, 240)
    love.graphics.setColor(1, 1, 1, 1)
end

function renderer.drawScreenFlashOverlay(battleState)
    if not battleState then return end
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

local function getActionTargetCandidates(act, slotActor, battleState, session)
    if not act or not act.type then return {}, false end
    local loader = require("data.loader")
    local targeting = require("engine.targeting")
    
    if act.type == "attack" then
        if act.target then
            return { act.target }, false
        end
        return {}, false
    elseif act.type == "skill" then
        local sk = act.id and loader.getSkill(act.id)
        local spec = sk and sk.target or "enemy"
        local exp = targeting.expand(spec)
        local isRandom = (exp.mode == "random")
        if isRandom or exp.count == "all" then
            local candidates = targeting.getCandidates(slotActor, spec, battleState, sk)
            return candidates, isRandom
        else
            if act.target then
                return { act.target }, false
            else
                local candidates = targeting.getCandidates(slotActor, spec, battleState, sk)
                return candidates, false
            end
        end
    elseif act.type == "item" then
        local items = {}
        if session and session.inventory then
            for itemId, qty in pairs(session.inventory) do
                if qty > 0 then table.insert(items, itemId) end
            end
            table.sort(items, compareIds)
        end
        local itemId = act.itemIndex and items[act.itemIndex]
        local item = itemId and loader.getItem(itemId)
        local spec = item and item.target or "ally"
        local exp = targeting.expand(spec)
        local isRandom = (exp.mode == "random")
        if isRandom or exp.count == "all" then
            local candidates = targeting.getCandidates(slotActor, spec, battleState, item)
            return candidates, isRandom
        else
            if act.target then
                return { act.target }, false
            else
                local candidates = targeting.getCandidates(slotActor, spec, battleState, item)
                return candidates, false
            end
        end
    end
    return {}, false
end

function renderer.drawTargetIndicators(bv, combatState)
    if combatState ~= "input" or not bv then return end
    local session = renderer.session
    if not session or not bv.battle then return end

    local battleState = bv.battle
    local collected = bv.collectedActions or {}
    local targetsMap = {}

    for slotIdx = 1, 4 do
        local c = session.party and session.party[slotIdx]
        if c and not c:isDead() then
            local act = collected[slotIdx]
            if act then
                local candidates, isRandom = getActionTargetCandidates(act, c, battleState, session)
                for _, trg in ipairs(candidates) do
                    if trg then
                        if not targetsMap[trg] then targetsMap[trg] = {} end
                        local exists = false
                        for _, existing in ipairs(targetsMap[trg]) do
                            if existing.slot == slotIdx then
                                exists = true
                                break
                            end
                        end
                        if not exists then
                            table.insert(targetsMap[trg], { slot = slotIdx, isRandom = isRandom })
                        end
                    end
                end
            end
        end
    end

    local dist = layoutVal("targetIndicatorDistance") or 8
    local blinkSpeed = layoutVal("targetIndicatorBlinkSpeed") or 0.25
    local tick = math.floor(love.timer.getTime() / blinkSpeed)

    for targetBattler, slotList in pairs(targetsMap) do
        if #slotList > 0 then
            table.sort(slotList, function(a, b) return a.slot < b.slot end)
            
            local targetX, targetY = nil, nil
            local targetDist = dist
            local isEnemy = false
            local enemyIdx = nil
            for idx, enemy in ipairs(battleState.enemies or {}) do
                if enemy == targetBattler then
                    isEnemy = true
                    enemyIdx = idx
                    break
                end
            end

            -- Slot numbers ride on the same rect everything else uses: on the
            -- enemy's info block for enemies, on the status cell for allies.
            if isEnemy then
                local rect = battler_geometry.enemyRect(session, enemyIdx,
                    #battleState.enemies, getBigBattler(targetBattler))
                local _, slotWidth = battler_geometry.enemySlot(session, enemyIdx, #battleState.enemies)
                local info = battler_geometry.enemyInfo(session, rect, slotWidth)
                if info then
                    local rightEdge = info.x + info.width - 4
                    local indicatorDist = dist
                    if #slotList > 1 then
                        indicatorDist = math.min(dist, math.max(0, (info.width - 15) / (#slotList - 1)))
                    end
                    local totalW = (#slotList - 1) * indicatorDist + 7
                    targetX = rightEdge - totalW + (layoutVal("targetIndicatorEnemyOffsetX") or 0)
                    targetY = info.nameY - 4 + (layoutVal("targetIndicatorEnemyOffsetY") or 0)
                    targetDist = indicatorDist
                end
            else
                local rect = battler_geometry.rect(battleState, session, targetBattler)
                if rect and rect.side == "party" then
                    local totalW = (#slotList - 1) * dist + 7
                    targetX = rect.frameX + rect.frameW - totalW
                        + (layoutVal("targetIndicatorAllyOffsetX") or 0)
                    targetY = rect.frameY + 4 + (layoutVal("targetIndicatorAllyOffsetY") or 0)
                end
            end

            if targetX and targetY then
                if #slotList == 1 then
                    local phase = tick % 2
                    if phase == 0 then
                        local info = slotList[1]
                        local color = info.isRandom and {1, 0.3, 0.3, 1} or {1, 1, 1, 1}
                        ui.drawString(tostring(info.slot), targetX, targetY, color)
                    end
                else
                    local phase = tick % #slotList
                    for i = 1, #slotList do
                        if (i - 1) == phase then
                            local info = slotList[i]
                            local color = info.isRandom and {1, 0.3, 0.3, 1} or {1, 1, 1, 1}
                            local offsetX = (i - 1) * targetDist
                            ui.drawString(tostring(info.slot), targetX + offsetX, targetY, color)
                        end
                    end
                end
            end
        end
    end
end

function renderer.drawTargetReticles(bv, combatState, selectedIndex, skillSelect, itemSelect, livingMembers, activeMemberIdx)
    if combatState ~= "input" or not bv then return end
    
    local session = renderer.session
    if not session then return end
    
    local battleState = bv.battle

    local targets = getHoveredTargets(bv, combatState, selectedIndex, skillSelect, itemSelect, livingMembers, activeMemberIdx)
    for _, target in ipairs(targets) do
        local tx, ty, tw, th = getBattlerRect(target, battleState, session)
        if tx and ty and tw and th then
            ui.drawTargetReticle(tx, ty, tw, th)
        end
    end

    renderer.drawTargetIndicators(bv, combatState)
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
