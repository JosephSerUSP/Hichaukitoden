-- The ONE "actor status" cell: sprite + element icons + name + HP text +
-- HP bar, on a windowskin-backed panel, at a fixed size taken from
-- battle_layout (partyGridColWidth/RowHeight). Extracted verbatim from
-- renderer.drawPartyGrid's per-slot code (owner direction 11.07.2026: a
-- party member's status must be a single reusable thing, called once per
-- member wherever a party is shown — battle/map HUD, and any scene's
-- party list — not a bespoke look per screen).
--
-- renderer.lua's drawPartyGrid calls actor_status.draw() once per grid
-- slot; window_renderer.lua's "partyGrid" window style calls it once per
-- row, arranged in a wrapping grid, using the row's battlerRef (the real
-- battler object partyRows already keeps a reference to).
--
-- No dependency on renderer.lua (battle_layout.lua carries the shared
-- layout accessor) — avoids a require cycle since renderer.lua requires
-- this module.

local ui = require("presentation.ui")
local config = require("engine.config")
local traits = require("engine.traits")
local small_battlers = require("presentation.small_battlers")
local battle_layout = require("presentation.battle_layout")
local battler_geometry = require("presentation.battler_geometry")
local animation_player = require("presentation.animation_player")

local actor_status = {}

local function layoutVal(session, key)
    return battle_layout.get(session, key)
end

-- Element orb icon ids come from the element registry (data/elements.json).
-- The old system.json `ui.elementIcons` config and its hardcoded mirror table
-- were purged 24.07.2026 — nothing ever set the config, and the table's ids had
-- drifted out of sync with the registry. This is the only fallback left: the
-- iconset slot used for an element with no registry entry.
local UNKNOWN_ELEMENT_ICON = 16

local function drawElementIcon(element, x, y, session)
    -- Icon comes from the element registry (data/elements.json).
    local loaderRef = session and session.loader
    local registryEntry = loaderRef and loaderRef.elements and loaderRef.elements[element]
    local id = (registryEntry and registryEntry.icon) or UNKNOWN_ELEMENT_ICON
    -- B.4: Displaced by 3px in x, 6px in y to align with name text
    ui.drawIcon(id, x + 3, y + 5)
end

-- Draw a single element icon at (x, y) with a uniform scale factor.
-- The shadow offset is also scaled so it remains visually consistent.
local function drawElementIconScaled(element, x, y, scale, session)
    local loaderRef = session and session.loader
    local registryEntry = loaderRef and loaderRef.elements and loaderRef.elements[element]
    local id = (registryEntry and registryEntry.icon) or UNKNOWN_ELEMENT_ICON
    ui.drawIconScaled(id, x, y, scale)
end

-- Draw element icons for an actor, compacted into the space of a single tile.
--
-- Rules:
--   * If the actor has only one unique element → full-size icon.
--   * If the actor has 2+ unique elements → each icon is scaled down to
--     X = max(0.4, 1 - 0.2 * max(1, n - 3)) and arranged equidistantly
--     within the 8×8 px tile (diagonal for 2, triangle for 3, polygon
--     for n).
--   * If one element type appears more often than the others (dominant),
--     that element is drawn 0.2 larger and the rest 0.2 smaller.
--
-- @param  elems  array of element name strings (may contain duplicates)
-- @param  x, y   top-left corner of the tile area
-- @return        width consumed (always iconSize = 8)
local function drawElementIcons(elems, x, y, session)
    if not elems or #elems == 0 then return 0 end

    -- Shift all element icons up by 3px (applies to both the single-icon
    -- and multi-element orbit cases below, keeping them aligned).
    y = y - 3

    -- Count occurrences of each unique element type
    local uniqueList = {}
    local counts = {}
    for _, elem in ipairs(elems) do
        if counts[elem] then
            counts[elem] = counts[elem] + 1
        else
            counts[elem] = 1
            table.insert(uniqueList, elem)
        end
    end

    local n = #uniqueList

    -- Single unique element → full-size icon (existing behaviour)
    if n == 1 then
        drawElementIcon(uniqueList[1], x, y, session)
        return 12
    end

    -- Base scale: stays at 0.8 for 2–4 elements, then drops toward 0.4
    local baseScale = math.max(0.4, 1 - 0.2 * math.max(1, n - 3))

    -- Determine dominant element: one that appears strictly more than others
    local maxCount = 0
    for _, c in pairs(counts) do
        if c > maxCount then maxCount = c end
    end
    local dominantElem = nil
    local dominantCount = 0
    for _, elem in ipairs(uniqueList) do
        if counts[elem] == maxCount then
            dominantCount = dominantCount + 1
            dominantElem = elem
        end
    end
    if dominantCount ~= 1 then dominantElem = nil end  -- tie → no dominant

    -- The normal single-icon is drawn by drawElementIcon at (x+3, y+5)
    -- with size 12×12, so its visual centre is at (x+9, y+11).  Scaled
    -- icons must orbit this centre so they stay inside the same area.
    local cx = x + 9
    local cy = y + 11
    -- Orbit radius kept small so the scaled icons overlap slightly instead
    -- of sitting apart (multi-element case).
    local radius = 2

    -- Starting angle: diagonal (-3π/4) for 2 icons, 12-o'clock (-π/2) for 3+
    local startAngle = (n == 2) and (-3 * math.pi / 4) or (-math.pi / 2)

    for i, elem in ipairs(uniqueList) do
        local angle = startAngle + (i - 1) * (2 * math.pi / n)

        local s = baseScale
        if dominantElem then
            s = elem == dominantElem and (baseScale + 0.2) or (baseScale - 0.2)
        end

        -- drawElementIconScaled(element, px, py, s) draws the 12×12 image at
        -- (px, py) with scale s, so the centre of the drawn icon is at
        -- (px + 6*s, py + 6*s).  Solve for px, py so that centre lands at
        -- the orbit position (cx + cos(θ)*r,  cy + sin(θ)*r):
        --
        --   px = cx + cos(θ)*r - 6*s
        --   py = cy + sin(θ)*r - 6*s
        local px = cx + math.cos(angle) * radius - 6 * s
        local py = cy + math.sin(angle) * radius - 6 * s

        drawElementIconScaled(elem, px, py, s, session)
    end

    return 12   -- width consumed: one tile
end

-- Exposed for callers that draw element icons outside a full actor-status
-- cell (e.g. renderer.lua's enemy name row in drawBattle) — one
-- implementation, no duplicate copy.
actor_status.drawElementIcons = drawElementIcons

-- Cell footprint and slot arithmetic live in presentation/battler_geometry.lua
-- (the single battler-placement authority); these stay as the names existing
-- callers use. One implementation, so cell size and wrapping can never drift
-- between where a cell is drawn and what anchors to it.
actor_status.cellSize = battler_geometry.cellSize
actor_status.gridSlot = battler_geometry.gridSlot

-- Draws ONE party member's status cell at (x, y) — top-left anchor, cell
-- size from actor_status.cellSize(). This is verbatim the battle/map HUD's
-- party-grid slot rendering: windowskin panel, animated sprite (dead tint
-- via small_battlers), element icons + name on one line, HP text, HP bar —
-- so it looks and behaves identically wherever it's called.
-- Active-state display (24.07.2026). Three optional channels, all authored in
-- data/states.json, so a new state needs no presentation code:
--   icon              cycled in the party cell (below)
--   display.animation a looped data/animations.json entry applied while active
--                     (poison pulses green through a gradient_map track)
--   display.sprite    sprite behaviour flags, e.g. { static = true } for a
--                     sleeping/petrified creature that stops bobbing
--   display.hideIcon  suppress the icon (death already reads as tint + popup)
--
-- One icon slot cycling by priority, RPG Maker 2003 style (owner decision): a
-- party cell is ~68px wide, so several icons side by side would crowd out the
-- name and gauge.
local STATE_ICON_CYCLE_SECONDS = 0.9

local function stateDisplayList(battler, session)
    local list = {}
    for _, stateInfo in ipairs(battler.states or {}) do
        local def = session and session.loader and session.loader.getState(stateInfo.id)
        if def and def.icon and def.icon > 0 and not (def.display and def.display.hideIcon) then
            table.insert(list, def)
        end
    end
    -- Highest priority first, then by id so the cycle order is stable frame to
    -- frame (pairs order over states must never leak into what the player sees).
    table.sort(list, function(a, b)
        local pa, pb = a.priority or 0, b.priority or 0
        if pa ~= pb then return pa > pb end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end

-- Keeps each active state's looped animation running and drops the ones whose
-- state has expired. Polled from draw rather than hooked into addState/
-- removeState so it self-corrects after a load, a swap, or an equipment change.
function actor_status.syncStateAnimations(battler, session)
    if not battler then return end
    local wanted = {}
    for _, stateInfo in ipairs(battler.states or {}) do
        local def = session and session.loader and session.loader.getState(stateInfo.id)
        local entryId = def and def.display and def.display.animation
        if entryId then
            wanted[entryId] = true
            if not animation_player.isPlaying(battler, entryId) then
                animation_player.play(entryId, battler)
            end
        end
    end
    for _, stateInfo in ipairs(battler.stateAnimsPlaying or {}) do
        if not wanted[stateInfo] then
            animation_player.stopAnimation(battler, stateInfo)
        end
    end
    local playing = {}
    for entryId in pairs(wanted) do table.insert(playing, entryId) end
    battler.stateAnimsPlaying = playing
end

-- True when an active state pins the sprite still (petrification, sleep).
function actor_status.spriteIsStatic(battler, session)
    for _, stateInfo in ipairs(battler and battler.states or {}) do
        local def = session and session.loader and session.loader.getState(stateInfo.id)
        if def and def.display and def.display.sprite and def.display.sprite.static then
            return true
        end
    end
    return false
end

-- Draws the cycling state icon for a battler at (x, y). Returns the width used
-- (0 when the creature carries no displayable state).
function actor_status.drawStateIcon(battler, x, y, session)
    local list = stateDisplayList(battler, session)
    if #list == 0 then return 0 end
    local idx = 1
    if #list > 1 then
        idx = (math.floor(love.timer.getTime() / STATE_ICON_CYCLE_SECONDS) % #list) + 1
    end
    ui.drawIcon(list[idx].icon, x, y)
    return 10
end

function actor_status.draw(battler, x, y, isSelected, session)
    if not battler then return end
    local colW, rowH = actor_status.cellSize(session)
    local spriteSize = layoutVal(session, "partyGridSpriteSize")
    -- drawPanel starts at x - 2 and leaves a 4px border on each side. Keep
    -- text and gauges inside its right-hand interior edge (exclusive).
    local slotContentEndX = x + colW - 8

    local maxHp = battler:getMaxHp(session)
    local dead = battler:isDead()
    local color = isSelected and { 1, 1, 0.5, 1 } or (dead and { 0.5, 0.5, 0.5, 1 } or { 1, 1, 1, 1 })
    local hpColor = dead and { 0.5, 0.5, 0.5, 1 } or { 0.9, 0.9, 0.9, 1 }

    -- Windowskin panel behind the whole cell, then the animated sprite
    -- (dead tint / flash / shake handled by small_battlers.draw).
    ui.drawPanel(x - 2, y - 2, colW - 2, rowH - 2, nil, isSelected)
    battler.spriteStatic = actor_status.spriteIsStatic(battler, session)
    local spriteKey = battler.actorData and battler.actorData.smallBattler
    local spriteOffsetX = 0
    -- Sprite top offset comes from battler_geometry so the rect the popup /
    -- animation anchors resolve against is the box the sprite really occupies.
    local spriteY = y + battler_geometry.partySpriteTopOffset()
    if spriteKey and small_battlers.draw(spriteKey, x, spriteY, spriteSize, dead, battler, session) then
        spriteOffsetX = spriteSize - 2 -- 22px; content on lines 2–3 starts after it
    end

    if isSelected then
        small_battlers.draw("Cursor", x - 6, y, 8)
    end

    -- LINE 1: the name gets the full top line. The small battler begins on
    -- line 2, leaving this row clear even when the actor has a sprite.
    local lineY = y
    local iconW = drawElementIcons(traits.getElements(battler, session), x, lineY - 4, session)
    local nameX = x + iconW + layoutVal(session, "partyGridNameXOffset")
    -- Silently truncate the name to fit the column. No ellipsis — just clean
    -- clipping, now measured against the real font by the shared helper
    -- instead of the old ~6px-per-character guess.
    local displayName = ui.fitText(battler.name, math.max(1, slotContentEndX - nameX))
    ui.drawString(displayName, nameX, lineY, color, "left", 256)

    -- Cycling state icon, right-aligned on the name line so it never pushes
    -- the name around as states come and go.
    actor_status.syncStateAnimations(battler, session)
    actor_status.drawStateIcon(battler, slotContentEndX - 8, lineY - 4, session)

    -- LINE 2 (mid): current HP only, right-aligned above its gauge. Max HP is
    -- already communicated by the gauge and needlessly crowds compact cells.
    local dispHp = battler.displayedHp or battler.hp
    local barX = x + layoutVal(session, "partyGridHpBarXOffset") + spriteOffsetX
    local barW = math.min(layoutVal(session, "partyGridHpBarWidth"), math.max(4, slotContentEndX - barX - 1))
    local hpText = tostring(math.floor(dispHp + 0.5))
    local hpTextY = y + layoutVal(session, "partyGridHpYOffset")
    ui.drawString(hpText, barX + barW - ui.measureText(hpText),
        hpTextY, hpColor)

    -- LINE 3 (bottom): HP bar, constrained to the panel interior including
    -- the shared gauge primitive's one-pixel drop shadow.
    ui.drawBar(barX, ui.gaugeYBelowText(hpTextY), barW, ui.gaugeHeight,
        dispHp, maxHp, ui.gaugeColors.hp.dark, ui.gaugeColors.hp.light)
end

-- Placeholder for an empty party slot — matches drawPartyGrid's original
-- "- EMPTY -" text exactly (no panel, so an empty slot doesn't visually
-- compete with occupied ones).
function actor_status.drawEmpty(x, y, isSelected, session)
    local emptyY = y + layoutVal(session, "partyGridEmptyYOffset")
    if isSelected then
        small_battlers.draw("Cursor", x - 6, emptyY, 8)
    end
    ui.drawString("- EMPTY -", x + 6, emptyY, { 0.3, 0.3, 0.3, 1 })
end

return actor_status
