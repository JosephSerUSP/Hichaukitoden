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

local actor_status = {}

local function layoutVal(session, key)
    return battle_layout.get(session, key)
end

-- Element orb icon ids come from system.json (ui.elementIcons); the table
-- below is only the fallback for older data files.
local DEFAULT_ELEMENT_ICONS = {
    Black = 15, White = 14, Green = 12, Red = 11, Blue = 13, Yellow = 17,
    default = 16
}

local function drawElementIcon(element, x, y, session)
    -- Icon comes from the element registry (data/elements.json); legacy
    -- ui.elementIcons config and the built-in table remain as fallbacks.
    local loaderRef = session and session.loader
    local registryEntry = loaderRef and loaderRef.elements and loaderRef.elements[element]
    local legacyIcons = (config.ui and config.ui.elementIcons) or DEFAULT_ELEMENT_ICONS
    local id = (registryEntry and registryEntry.icon)
        or legacyIcons[element]
        or legacyIcons.default
        or DEFAULT_ELEMENT_ICONS.default
    -- B.4: Displaced by 3px in x, 6px in y to align with name text
    ui.drawIcon(id, x + 3, y + 5)
end

-- Draw a single element icon at (x, y) with a uniform scale factor.
-- The shadow offset is also scaled so it remains visually consistent.
local function drawElementIconScaled(element, x, y, scale, session)
    local loaderRef = session and session.loader
    local registryEntry = loaderRef and loaderRef.elements and loaderRef.elements[element]
    local legacyIcons = (config.ui and config.ui.elementIcons) or DEFAULT_ELEMENT_ICONS
    local id = (registryEntry and registryEntry.icon)
        or legacyIcons[element]
        or legacyIcons.default
        or DEFAULT_ELEMENT_ICONS.default
    ui.drawIconScaled(id, x, y, scale)
end

-- Draw element icons for an actor, compacted into the space of a single tile.
--
-- Rules:
--   * If the actor has only one unique element → full-size icon.
--   * If the actor has 2+ unique elements → each icon is scaled down to
--     X = max(0.4, 1 - 0.2 * max(1, n - 3)) and arranged equidistantly
--     within the 12×12 px tile (diagonal for 2, triangle for 3, polygon
--     for n).
--   * If one element type appears more often than the others (dominant),
--     that element is drawn 0.2 larger and the rest 0.2 smaller.
--
-- @param  elems  array of element name strings (may contain duplicates)
-- @param  x, y   top-left corner of the tile area
-- @return        width consumed (always iconSize = 12)
local function drawElementIcons(elems, x, y, session)
    if not elems or #elems == 0 then return 0 end

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
    local radius = 4

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

-- The fixed footprint of one actor-status cell (engine.json battleLayout
-- partyGridColWidth/RowHeight, or the 64x40 built-in default). Callers
-- arranging multiple cells (renderer.drawPartyGrid's 2x2, window_renderer's
-- wrapping grid) use this instead of hardcoding numbers.
function actor_status.cellSize(session)
    return layoutVal(session, "partyGridColWidth"), layoutVal(session, "partyGridRowHeight")
end

-- Draws ONE party member's status cell at (x, y) — top-left anchor, cell
-- size from actor_status.cellSize(). This is verbatim the battle/map HUD's
-- party-grid slot rendering: windowskin panel, animated sprite (dead tint
-- via small_battlers), element icons + name on one line, HP text, HP bar —
-- so it looks and behaves identically wherever it's called.
function actor_status.draw(battler, x, y, isSelected, session)
    if not battler then return end
    local colW, rowH = actor_status.cellSize(session)
    local spriteSize = 24 -- B.5: default small battler cell size
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
    local spriteKey = (battler.actorData and (battler.actorData.smallBattler or battler.actorData.spriteKey)) or battler.spriteKey
    local spriteOffsetX = 0
    if spriteKey and small_battlers.draw(spriteKey, x, y + ui.lineHeight, spriteSize, dead, battler) then
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
    local nameClipW = math.max(1, slotContentEndX - nameX)
    -- Silently truncate name to fit within the column (~6px per char in
    -- 8px font). No ellipsis — just clean clipping.
    local maxNameChars = math.floor(nameClipW / 6)
    local displayName = (battler.name):sub(1, maxNameChars)
    ui.drawString(displayName, nameX, lineY, color, "left", 256)

    -- LINE 2 (mid): HP fraction text "current/max"
    local dispHp = battler.displayedHp or battler.hp
    ui.drawString(math.floor(dispHp + 0.5) .. "/" .. maxHp, x + layoutVal(session, "partyGridHpXOffset") + spriteOffsetX, y + layoutVal(session, "partyGridHpYOffset"), hpColor)

    -- LINE 3 (bottom): HP bar, constrained to the panel interior.
    local barX = x + layoutVal(session, "partyGridHpBarXOffset") + spriteOffsetX
    local barW = math.min(layoutVal(session, "partyGridHpBarWidth"), math.max(4, slotContentEndX - barX))
    ui.drawBar(barX, y + layoutVal(session, "partyGridHpBarYOffset"), barW, layoutVal(session, "partyGridHpBarHeight"), dispHp, maxHp, { 0.8, 0, 0 }, { 1, 0.3, 0.3 })
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
