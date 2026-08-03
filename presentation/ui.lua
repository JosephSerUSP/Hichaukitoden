local config = require("engine.config")
local util = require("presentation.util")

local ui = {}

-- Shortest-path angle interpolation (radians), shared by the map/minimap
-- turn animation (renderer.lua) and the first-person viewport (viewport_3d.lua).
function ui.lerpAngle(a, b, t)
    local diff = b - a
    while diff < -math.pi do diff = diff + math.pi * 2 end
    while diff > math.pi do diff = diff - math.pi * 2 end
    return a + diff * t
end

local iconset
local iconSize = 8
local iconQuads = {}
-- Three windowskins, one per structural role (31.07.2026). `back` is the
-- semitransparent shell behind menus and panels -- the world view now renders
-- the full canvas height, so what shows through it is the 3D scene. `button`
-- and `buttonHighlight` are the solid skins for interactive cells (command
-- rows, party slots, tabs): a button that let the dungeon through would be
-- unreadable, so only shells are transparent.
local windowskinBack
local windowskinButton
local windowskinButtonHighlight
local targetSkin
local mainFont
local mainFontOffsetY = 0
local popupFont
local popupNumberFont
local popupTextFont

-- Shared portrait resolution (renderer.lua's legacy drawDialogue and the
-- data-authored window_renderer both need it): speaker/portrait keys in
-- data are inconsistent about the "NPC_" prefix (some conversations write
-- "Alicia", others "NPC_Barkeep" outright), so every caller tries the same
-- small set of filename variants rather than each guessing its own subset.
local portraitImageCache = {}
local bigBattlerImageCache = {}
local function resolveKeyedImage(id, directory, cache)
    if not id or id == "" then return nil end
    id = tostring(id)
    if cache[id] then return cache[id] end

    local safeId = id:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    local paths = {
        directory .. "/" .. id .. ".png",
        directory .. "/" .. safeId .. ".png",
        directory .. "/" .. id:lower() .. ".png",
        directory .. "/" .. id:sub(1, 1):upper() .. id:sub(2):lower() .. ".png"
    }
    for _, p in ipairs(paths) do
        if love.filesystem.getInfo(p) then
            local img = love.graphics.newImage(p)
            img:setFilter("nearest", "nearest")
            cache[id] = img
            return img
        end
    end
    return nil
end

function ui.resolvePortraitImage(id)
    if not id or id == "" then return nil end
    id = tostring(id)
    if portraitImageCache[id] then return portraitImageCache[id] end

    local safeId = id:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    local paths = {
        "assets/portraits/" .. id .. ".png",
        "assets/portraits/NPC_" .. id .. ".png",
        "assets/portraits/" .. safeId .. ".png",
        "assets/portraits/NPC_" .. safeId .. ".png",
        "assets/portraits/" .. id:lower() .. ".png",
        "assets/portraits/" .. id:sub(1, 1):upper() .. id:sub(2):lower() .. ".png"
    }
    for _, p in ipairs(paths) do
        if love.filesystem.getInfo(p) then
            local img = love.graphics.newImage(p)
            img:setFilter("nearest", "nearest")
            portraitImageCache[id] = img
            return img
        end
    end
    return nil
end

function ui.resolveBigBattlerImage(id)
    return resolveKeyedImage(id, "assets/bigBattlers", bigBattlerImageCache)
end

-- Draws sliced expression portraits.
-- Slices multi-expression columns (5-column sheets or w > 128).
-- If scaleToFit is true, scales frame to targetW x targetH (e.g. status menu panel).
-- Otherwise (scaleToFit false/nil), renders frame unscaled at 1:1 (e.g. dialogue).
function ui.drawSlicedPortrait(img, x, y, targetW, targetH, frame, scaleToFit)
    if not img then return end
    local w = img:getWidth()
    local h = img:getHeight()
    local fw = w
    if w >= 250 and w % 5 == 0 then
        fw = math.floor(w / 5)
    elseif w > 128 then
        fw = 128
    end

    local sx = scaleToFit and (targetW / fw) or 1
    local sy = scaleToFit and (targetH / h) or 1

    if fw < w then
        local frameCount = math.max(1, math.floor(w / fw))
        local column = math.max(1, math.min(frameCount, math.floor(tonumber(frame) or 1)))
        local quad = love.graphics.newQuad((column - 1) * fw, 0, fw, h, w, h)
        love.graphics.draw(img, quad, x, y, 0, sx, sy)
    else
        love.graphics.draw(img, x, y, 0, sx, sy)
    end
end

local panelQuads = {}
local targetQuads = {}

-- Parse string and replace \eventName and \c[x]
local function parseRichText(text, defaultColor, eventName)
    local result = text or ""
    if eventName and eventName ~= "" then
        result = string.gsub(result, "\\eventName", string.gsub(eventName, "%%", "%%%%"))
    else
        result = string.gsub(result, "\\eventName", "")
    end

    local chunks = {}
    local currentPos = 1
    local currentActiveColor = defaultColor

    local palette = config.ui and config.ui.textPalette
    if not palette then
        palette = {
            {1, 1, 1, 1},
            {0.2, 0.6, 1, 1},
            {1, 0.3, 0.3, 1},
            {0.3, 0.8, 0.3, 1},
            {0.3, 0.8, 0.8, 1},
            {0.8, 0.3, 0.8, 1},
            {1, 0.8, 0.2, 1},
            {0.6, 0.6, 0.6, 1}
        }
    end

    while true do
        local startIdx, endIdx, code = string.find(result, "\\c%[(%d+)%]", currentPos)
        if not startIdx then
            local remainder = string.sub(result, currentPos)
            if #remainder > 0 then
                table.insert(chunks, currentActiveColor)
                table.insert(chunks, remainder)
            end
            break
        end

        local before = string.sub(result, currentPos, startIdx - 1)
        if #before > 0 then
            table.insert(chunks, currentActiveColor)
            table.insert(chunks, before)
        end

        local colorIdx = tonumber(code)
        currentActiveColor = palette[colorIdx % #palette + 1] or defaultColor

        currentPos = endIdx + 1
    end

    return chunks
end

-- Load assets (called from renderer)
function ui.init()
    if love.filesystem.getInfo("assets/system/iconset.png") then
        iconset = love.graphics.newImage("assets/system/iconset.png")
        iconset:setFilter("nearest", "nearest")
    end
    
    local function loadSkin(name)
        local path = "assets/system/" .. name .. ".png"
        if not love.filesystem.getInfo(path) then return nil end
        local image = love.graphics.newImage(path)
        image:setFilter("nearest", "nearest")
        return image
    end

    -- All three skins share one quad layout, so the quads are built once. A
    -- skin whose file is missing falls back to `back` in drawPanel rather than
    -- being silently skipped -- a panel that draws nothing is worse than a
    -- panel wearing the wrong skin.
    windowskinBack = loadSkin("windowskin_back")
    windowskinButton = loadSkin("windowskin_button")
    windowskinButtonHighlight = loadSkin("windowskin_button_highlight")

    if windowskinBack then
        local wsW, wsH = windowskinBack:getDimensions()
        panelQuads.top = love.graphics.newQuad(40, 0, 16, 8, wsW, wsH)
        panelQuads.bot = love.graphics.newQuad(40, 24, 16, 8, wsW, wsH)
        panelQuads.left = love.graphics.newQuad(32, 8, 8, 16, wsW, wsH)
        panelQuads.right = love.graphics.newQuad(56, 8, 8, 16, wsW, wsH)
        panelQuads.tl = love.graphics.newQuad(32, 0, 8, 8, wsW, wsH)
        panelQuads.tr = love.graphics.newQuad(56, 0, 8, 8, wsW, wsH)
        panelQuads.bl = love.graphics.newQuad(32, 24, 8, 8, wsW, wsH)
        panelQuads.br = love.graphics.newQuad(56, 24, 8, 8, wsW, wsH)

        panelQuads.scrollTrack = love.graphics.newQuad(32, 32, 16, 16, wsW, wsH)
        panelQuads.scrollThumb = love.graphics.newQuad(48, 32, 16, 16, wsW, wsH)
        panelQuads.arrowUp = love.graphics.newQuad(40, 8, 16, 8, wsW, wsH)
        panelQuads.arrowDown = love.graphics.newQuad(40, 16, 16, 8, wsW, wsH)
    end

    if love.filesystem.getInfo("assets/system/UI_Target.png") then
        targetSkin = love.graphics.newImage("assets/system/UI_Target.png")
        targetSkin:setFilter("nearest", "nearest")

        local wsW, wsH = targetSkin:getDimensions()
        targetQuads.top = love.graphics.newQuad(8, 0, 16, 8, wsW, wsH)
        targetQuads.bot = love.graphics.newQuad(8, 24, 16, 8, wsW, wsH)
        targetQuads.left = love.graphics.newQuad(0, 8, 8, 16, wsW, wsH)
        targetQuads.right = love.graphics.newQuad(24, 8, 8, 16, wsW, wsH)
        targetQuads.tl = love.graphics.newQuad(0, 0, 8, 8, wsW, wsH)
        targetQuads.tr = love.graphics.newQuad(24, 0, 8, 8, wsW, wsH)
        targetQuads.bl = love.graphics.newQuad(0, 24, 8, 8, wsW, wsH)
        targetQuads.br = love.graphics.newQuad(24, 24, 8, 8, wsW, wsH)
    end
    
    -- Load active font from system config
    local fontName = config.ui and config.ui.activeFont or "Lucida"
    local fontSize = config.ui and config.ui.fontSize or 8
    mainFontOffsetY = config.ui and tonumber(config.ui.fontOffsetY) or 0

    ui.setFont(fontName, fontSize)

    -- Font normalization toggle: when true (default), Unicode characters not
    -- covered by pixel fonts (curly quotes, dashes, ellipsis, etc.) are
    -- mapped to ASCII equivalents so they render instead of showing [] boxes.
    -- Set "fontNormalize": false in system.json for fonts with full Unicode
    -- coverage (e.g. IBMPlexMono).
    fontNormalizeEnabled = (config.ui and config.ui.fontNormalize) ~= false

    -- Load active popup font from system config
    local popConf = config.battle_screen and config.battle_screen.popup or {}
    local popupFontName = popConf.font
    local popupFontSize = popConf.fontSize
    if popupFontName then
        ui.loadPopupFont(popupFontName, popupFontSize)
    end

    local numFontName = popConf.numberFont or popupFontName
    local numFontSize = popConf.numberFontSize or popupFontSize
    if numFontName then
        popupNumberFont = ui.loadFont(numFontName, numFontSize)
    end

    local textFontName = popConf.textFont or popupFontName
    local textFontSize = popConf.textFontSize or popupFontSize
    if textFontName then
        popupTextFont = ui.loadFont(textFontName, textFontSize)
    end
end

-- Exposed layout constants (use these instead of hardcoded numbers)
ui.fontSize   = 8
ui.tileSize   = 8    -- SNES-style 8x8 tile size grid
ui.lineHeight = ui.tileSize   -- exactly equal to tileHeight (8px)
ui.screenWidthTiles = 32   -- 256 / 8
ui.iconSize        = iconSize   -- expose for renderer use
ui.gaugeHeight     = 2
ui.gaugeColors = {
    hp = {
        dark = { 0.42, 0.16, 0.18 },
        light = { 0.82, 0.38, 0.34 },
    },
}

-- What a skill costs, by resource, so the player reads the resource before the
-- number (owner direction 01.08.2026). One table because these are also the
-- colours the gauges use: MP matches the party HUD's MP readout exactly, HP is
-- the HP gauge's light tone, and charges are the one resource with no gauge, so
-- yellow is theirs alone and never means anything else.
ui.costColors = {
    charges = { 1.00, 0.85, 0.25, 1 },
    mp      = { 0.80, 0.90, 1.00, 1 },
    hp      = { 0.82, 0.38, 0.34, 1 },
    -- An unaffordable/unavailable cost still shows its number, greyed: the
    -- player must be able to see WHAT they cannot pay, not just that they
    -- cannot act.
    blocked = { 0.45, 0.45, 0.45, 1 },
}

-- Whether a number is good or bad FOR THE HOLDER (item/skill trait readouts).
-- Deliberately not the cost colours: those name a resource, these name a
-- direction, and reusing one for the other would make yellow mean two things.
-- `label` is the noun beside the number -- dimmer than the number on purpose,
-- because in a 14-tile pane the value is what the player is scanning for.
ui.toneColors = {
    good    = { 0.45, 0.95, 0.50, 1 },
    bad     = { 1.00, 0.42, 0.42, 1 },
    neutral = { 0.90, 0.90, 0.90, 1 },
    label   = { 0.72, 0.72, 0.72, 1 },
}
ui.screenHeightTiles = 30   -- 240 / 8

-- Utility to convert tile coordinate to pixels
function ui.toPx(tiles)
    return tiles * ui.tileSize
end

-- Positions a gauge directly under the visible text row: the gauge acts as
-- the row's underline/base instead of floating below it with an arbitrary gap.
function ui.gaugeYBelowText(textY)
    return textY + ui.lineHeight
end

-- Shared content origin for every window renderer.  A title earns one extra
-- tile of vertical breathing room; an untitled panel starts at the normal
-- one-tile inset.  Individual layouts can override either coordinate.
function ui.panelContentOrigin(x, y, title, contentX, contentY)
    local hasTitle = title and title ~= ""
    return x + ui.toPx(contentX ~= nil and contentX or 1),
        y + ui.toPx(contentY ~= nil and contentY or (hasTitle and 2 or 1))
end

-- Draw RPG Maker 2003 styled windowskin panel
-- Layout specifications:
-- First 32x32: seamlessly tiling background
-- Next 32x32 (x=32..64, y=0..32): 8px borders
-- `role` selects the skin, all three sharing this quad layout:
--   nil / "back"             -- window shells and panels; semitransparent
--   "button"                 -- an interactive cell at rest
--   "button_highlight"       -- that same cell selected
-- The distinction is structural, not decorative: a shell shows the 3D world
-- through it, a button must stay readable, so the choice belongs to the
-- caller rather than to a boolean that only knew "selected or not".
-- The opening/closing rect for a panel, centred on its settled rect.
--
-- Both axes grow at the SAME pixel rate rather than at the same fraction of
-- their own length, so a wide button reaches full height long before it
-- reaches full width -- it unrolls sideways instead of inflating. The rate is
-- set so the longer axis completes exactly at p = 1, which keeps the caller's
-- authored duration meaning "time until fully open".
--
-- The result is a real rect, not a transform: callers pass it to drawPanel so
-- the windowskin is REBUILT at that size with proper borders, and scissor
-- their content to it rather than scaling the content.
function ui.rescaleRect(x, y, w, h, p)
    p = util.clamp01(p or 1)
    local reach = math.max(w, h) * p
    local nw = math.min(w, math.max(reach, math.min(w, 16)))
    local nh = math.min(h, math.max(reach, math.min(h, 9)))
    return x + (w - nw) / 2, y + (h - nh) / 2, nw, nh
end

-- A panel's title header, drawn on its own so a window whose surface is
-- supplied by something else (the dock's static shell) can keep the title
-- without drawing a second background to hang it on.
function ui.drawPanelTitle(title, x, y)
    love.graphics.setColor(1, 1, 0.7, 1)
    ui.drawString(title, x + ui.tileSize * 0.5, y)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Every interactive cell picks its skin the same way, so the mapping lives
-- here instead of being spelled out at each of the eight call sites.
function ui.buttonRole(selected)
    return selected and "button_highlight" or "button"
end

function ui.drawPanel(x, y, w, h, title, role)
    -- Snap to whole pixels before anything is measured from the rect.
    --
    -- The open/close animations ("grow") produce fractional rects, and the
    -- background pass derives its tiling bounds AND its scissor from them.
    -- At a fractional rect those two round differently from the border quads
    -- drawn at 8px offsets, so the interior stopped a fraction short of the
    -- frame and left an uncovered strip -- the seam between the tiled middle
    -- and the border that showed for the few frames a panel was animating.
    -- Rounding the two edges (rather than position and size separately) keeps
    -- the far edge from jittering as the near one rounds.
    local left, top = math.floor(x + 0.5), math.floor(y + 0.5)
    local right, bottom = math.floor(x + w + 0.5), math.floor(y + h + 0.5)
    x, y, w, h = left, top, right - left, bottom - top

    -- Below the windowskin's two 8px borders there is no interior left, so
    -- the top and bottom edges overlap and the panel reads as a single frame.
    -- That is legitimate for a short button (a 1.5-tile command slot is 12px)
    -- and the background pass below is inset by 4, so it still has area.
    -- Only genuinely degenerate geometry bails -- an animated dock shell
    -- passes through zero mid-collapse and must not reach LOVE's scissor.
    if w < 16 or h < 9 then return end
    love.graphics.push("all")

    local skin = windowskinBack
    if role == "button" then
        skin = windowskinButton or skin
    elseif role == "button_highlight" then
        skin = windowskinButtonHighlight or windowskinButton or skin
    end
    if skin then
        local wsW, wsH = skin:getDimensions()
        
        -- 1. Draw Background (from x=0, y=0, w=32, h=32) tiled seamlessly
        local bgW, bgH = 32, 32
        local startX = x + 4
        local startY = y + 4
        local endX = x + w - 4
        local endY = y + h - 4
        
        -- Set scissor to keep background strictly inside the window border margins
        local sx, sy, sw, sh = love.graphics.getScissor()
        love.graphics.intersectScissor(startX, startY, endX - startX, endY - startY)
        
        love.graphics.setColor(1, 1, 1, 1)
        for by = startY, endY - 1, bgH do
            for bx = startX, endX - 1, bgW do
                local drawW = math.min(bgW, endX - bx)
                local drawH = math.min(bgH, endY - by)
                local tileQuad = love.graphics.newQuad(0, 0, drawW, drawH, wsW, wsH)
                love.graphics.draw(skin, tileQuad, bx, by)
            end
        end
        love.graphics.setScissor(sx, sy, sw, sh) -- restore scissor
        
        -- 2. Draw 8px Edges (tiled/stretched)
        -- Clamped at 0: a panel shorter than its two borders would otherwise
        -- scale the side edges by a negative factor, flipping them upward.
        local edgeW = math.max(0, w - 16)
        local edgeH = math.max(0, h - 16)

        -- Top side edge (x=40, y=0, w=16, h=8)
        love.graphics.draw(skin, panelQuads.top, x + 8, y, 0, edgeW / 16, 1)

        -- Bottom side edge (x=40, y=24, w=16, h=8)
        love.graphics.draw(skin, panelQuads.bot, x + 8, y + h - 8, 0, edgeW / 16, 1)

        -- Left side edge (x=32, y=8, w=8, h=16)
        love.graphics.draw(skin, panelQuads.left, x, y + 8, 0, 1, edgeH / 16)

        -- Right side edge (x=56, y=8, w=8, h=16)
        love.graphics.draw(skin, panelQuads.right, x + w - 8, y + 8, 0, 1, edgeH / 16)

        -- 3. Draw 8px Corners
        love.graphics.draw(skin, panelQuads.tl, x, y)
        love.graphics.draw(skin, panelQuads.tr, x + w - 8, y)
        love.graphics.draw(skin, panelQuads.bl, x, y + h - 8)
        love.graphics.draw(skin, panelQuads.br, x + w - 8, y + h - 8)
    else
        -- Fallback
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.rectangle("fill", x + 2, y + 2, w, h, 2, 2)
        love.graphics.setColor(15/255, 20/255, 35/255, 0.95)
        love.graphics.rectangle("fill", x, y, w, h, 2, 2)
        love.graphics.setColor(120/255, 120/255, 140/255, 0.8)
        love.graphics.rectangle("line", x + 2, y + 2, w - 4, h - 4)
    end
    
    if title then ui.drawPanelTitle(title, x, y) end

    love.graphics.pop()
end

-- Draw RPG Maker 2003 styled targeting reticle using UI_Target.png
-- Layout specifications:
-- 32x32 image with 8px corners and 16px edges.
-- The reticle size alternates between the base target size and target size + 2.
function ui.drawTargetReticle(x, y, w, h)
    love.graphics.push("all")
    local skin = targetSkin or windowskinButton
    if skin then
        local wsW, wsH = skin:getDimensions()
        
        -- Oscillation offset: alternates between 0 and 2 every ~0.125 seconds
        local t = love.timer.getTime()
        local offset = math.floor(t * 8) % 2 == 0 and 0 or 2
        
        local rx = x - offset / 2
        local ry = y - offset / 2
        local rw = w + offset
        local rh = h + offset
        
        local edgeW = rw - 16
        local edgeH = rh - 16
        
        love.graphics.setColor(1, 1, 1, 1)
        
        -- Ensure quads are initialized for target (fallback to panelQuads if targetQuads not setup but we have targetSkin somehow, though init handles it)
        local q = (skin == targetSkin and targetQuads.top) and targetQuads or panelQuads

        -- Top side edge (x=8, y=0, w=16, h=8)
        love.graphics.draw(skin, q.top, rx + 8, ry, 0, edgeW / 16, 1)

        -- Bottom side edge (x=8, y=24, w=16, h=8)
        love.graphics.draw(skin, q.bot, rx + 8, ry + rh - 8, 0, edgeW / 16, 1)

        -- Left side edge (x=0, y=8, w=8, h=16)
        love.graphics.draw(skin, q.left, rx, ry + 8, 0, 1, edgeH / 16)

        -- Right side edge (x=24, y=8, w=8, h=16)
        love.graphics.draw(skin, q.right, rx + rw - 8, ry + 8, 0, 1, edgeH / 16)

        -- Draw 8px Corners
        love.graphics.draw(skin, q.tl, rx, ry)
        love.graphics.draw(skin, q.tr, rx + rw - 8, ry)
        love.graphics.draw(skin, q.bl, rx, ry + rh - 8)
        love.graphics.draw(skin, q.br, rx + rw - 8, ry + rh - 8)
    end
    love.graphics.pop()
end

-- Draw lean RPG Maker 2003 styled windowskin scrollbar with overflow arrows
-- Fits in a ultra-lean 2px width footprint along the right inner border of a list.
function ui.drawScrollbar(x, y, w, h, totalRows, visibleRows, startOffset)
    if totalRows <= visibleRows or totalRows <= 0 then return end

    love.graphics.push("all")

    -- The scrollbar is chrome on a shell but has to stay legible against
    -- whatever the transparent shell reveals, so it samples the solid button
    -- skin rather than `back`.
    local skin = windowskinButton or windowskinBack
    local maxScroll = totalRows - visibleRows
    local scrollPos = math.max(0, math.min(maxScroll, (startOffset or 1) - 1))

    -- 1. Lean 2px Rail / Track along right margin edge (x + w - 8)
    local railX = x + w - 8
    local railY = y + 8
    local railH = math.max(8, h - 16)

    if skin then
        local wsW, wsH = skin:getDimensions()
        -- Sample 2px vertical track slice from windowskin at (34, 33, 2, 14)
        local trackQuad = love.graphics.newQuad(34, 33, 2, 14, wsW, wsH)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(skin, trackQuad, railX, railY, 0, 1, railH / 14)
    else
        love.graphics.setColor(0.2, 0.25, 0.35, 0.6)
        love.graphics.rectangle("fill", railX, railY, 2, railH)
    end

    -- 2. Lean 2px Thumb Handle sampled directly from windowskin at (55, 33, 2, 14)
    local thumbH = math.max(6, math.floor(railH * (visibleRows / totalRows)))
    local thumbY = railY + math.floor((railH - thumbH) * (maxScroll > 0 and (scrollPos / maxScroll) or 0))

    if skin then
        local wsW, wsH = skin:getDimensions()
        -- Sample 2px vertical thumb slice from windowskin at (55, 33, 2, 14)
        local thumbQuad = love.graphics.newQuad(55, 33, 2, 14, wsW, wsH)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(skin, thumbQuad, railX, thumbY, 0, 1, thumbH / 14)
    else
        love.graphics.setColor(0.9, 0.95, 1.0, 1)
        love.graphics.rectangle("fill", railX, thumbY, 2, thumbH)
    end

    -- 3. Static 16x8 Up / Down Arrow Indicators (40,8 and 40,16) sampled from windowskin
    local arrowX = railX - 7
    local canScrollUp = (startOffset > 1)
    local canScrollDown = ((startOffset + visibleRows - 1) < totalRows)

    -- Up Arrow indicator (16x8) at top of rail (railY - 8)
    if skin and panelQuads.arrowUp then
        if canScrollUp then
            love.graphics.setColor(1, 1, 1, 1.0)
        else
            love.graphics.setColor(1, 1, 1, 0.25) -- Dim when inactive
        end
        love.graphics.draw(skin, panelQuads.arrowUp, arrowX, railY - 8)
    else
        local color = canScrollUp and COLOR_SELECTED or COLOR_DIM
        ui.drawString("^", railX - 2, railY - 6, color)
    end

    -- Down Arrow indicator (16x8) at bottom of rail (railY + railH)
    if skin and panelQuads.arrowDown then
        if canScrollDown then
            love.graphics.setColor(1, 1, 1, 1.0)
        else
            love.graphics.setColor(1, 1, 1, 0.25) -- Dim when inactive
        end
        love.graphics.draw(skin, panelQuads.arrowDown, arrowX, railY + railH)
    else
        local color = canScrollDown and COLOR_SELECTED or COLOR_DIM
        ui.drawString("v", railX - 2, railY + railH, color)
    end

    love.graphics.pop()
end

-- Normalize Unicode characters that the active pixel font may not cover
-- down to their closest ASCII equivalents so they render instead of showing
-- the missing-glyph box ([]). Only active when ui.fontNormalize is true
-- (config.ui.fontNormalize, defaults to on for pixel fonts like 04B_03__).
-- When loading a font that has full Unicode support (e.g. IBMPlexMono),
-- set "fontNormalize": false in system.json to skip this pass.
local fontNormalizeEnabled = true
local function normalizeText(text)
    if not fontNormalizeEnabled or not text then return text or "" end
    -- Replace Unicode characters not covered by pixel fonts with ASCII
    -- equivalents. Uses raw UTF-8 byte sequences (LuaJIT does not support
    -- the \u{NNNN} escape syntax).
    local normalized = text
        -- Curly single quotes: U+2018 (0xE2 0x80 0x98), U+2019 (0xE2 0x80 0x99)
        :gsub("\xE2\x80\x98", "'")
        :gsub("\xE2\x80\x99", "'")
        -- Curly double quotes: U+201C (0xE2 0x80 0x9C), U+201D (0xE2 0x80 0x9D)
        :gsub("\xE2\x80\x9C", '"')
        :gsub("\xE2\x80\x9D", '"')
        -- En dash U+2013, Em dash U+2014 (0xE2 0x80 0x93/0x94)
        :gsub("\xE2\x80\x93", "-")
        :gsub("\xE2\x80\x94", "-")
        -- Horizontal ellipsis U+2026 (0xE2 0x80 0xA6)
        :gsub("\xE2\x80\xA6", "...")
        -- Left/right double angle U+00AB/U+00BB (0xC2 0xAB/0xBB)
        :gsub("\xC2\xAB", "<<")
        :gsub("\xC2\xBB", ">>")
        -- No-break space U+00A0 (0xC2 0xA0)
        :gsub("\xC2\xA0", " ")
        -- Bullet U+2022 (0xE2 0x80 0xA2)
        :gsub("\xE2\x80\xA2", "*")
        -- Trade mark sign U+2122 (0xE2 0x84 0xA2)
        :gsub("\xE2\x84\xA2", "(TM)")
        -- Copyright U+00A9 (0xC2 0xA9), Registered U+00AE (0xC2 0xAE)
        :gsub("\xC2\xA9", "(C)")
        :gsub("\xC2\xAE", "(R)")
    return normalized
end

-- Draw text with drop shadow (crisp monochrome)
function ui.drawString(text, x, y, color, alignment, limit, eventName, font)
    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()
    if font == nil then y = y + mainFontOffsetY end
    
    color = color or {1, 1, 1, 1}
    alignment = alignment or "left"
    limit = limit or 256
    
    -- Set active font explicitly to ensure properties apply
    local drawFont = font or mainFont
    if drawFont then love.graphics.setFont(drawFont) end
    
    -- Normalize text to replace Unicode characters not covered by pixel fonts
    local parsedText = normalizeText(text or "")
    if eventName and eventName ~= "" then
        parsedText = string.gsub(parsedText, "\\eventName", string.gsub(eventName, "%%", "%%%%"))
    else
        parsedText = string.gsub(parsedText, "\\eventName", "")
    end

    if alignment == "right" and limit then
        limit = limit - ui.tileSize
    end

    if not string.find(parsedText, "\\c%[") then
        -- Fallback to simple printing
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.printf(parsedText, x + 1, y + 1, limit, alignment)
        love.graphics.setColor(color)
        love.graphics.printf(parsedText, x, y, limit, alignment)

        love.graphics.setColor(r, g, b, a)
        love.graphics.setFont(currentFont)
        return
    end

    local chunks = parseRichText(text, color, eventName)
    if #chunks == 0 then
        love.graphics.setColor(r, g, b, a)
        love.graphics.setFont(currentFont)
        return
    end

    local shadowChunks = {}
    for i, v in ipairs(chunks) do
        if type(v) == "table" then
            table.insert(shadowChunks, {0, 0, 0, 0.8})
        else
            table.insert(shadowChunks, v)
        end
    end

    -- Draw shadow (1px down, 1px right)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(shadowChunks, x + 1, y + 1, limit, alignment)
    
    -- Draw text
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(chunks, x, y, limit, alignment)
    
    love.graphics.setColor(r, g, b, a)
    love.graphics.setFont(currentFont)
end

-- Draw HP/MP status gauge
-- Shared cost/gain preview for any gauge (Summoner rework: "tinting a
-- portion of the gauge red... a single pixel", plus a slim label after
-- it). One implementation, used by every ui.drawBar call site — MP,
-- HP, EXP, gold, ritual/shop gauges alike (SPEC 2.1).
--
-- preview = {
--   delta       signed amount pending: negative = cost (tints the top
--               slice of the CURRENT fill, the part about to be spent),
--               positive = gain (tints the slice of empty gauge just
--               past current, the part about to be added).
--   costColor / gainColor   optional overrides (default red / green).
--   label       optional pre-formatted string ("cost: 12", "gain: 40"),
--               drawn slim and discreet immediately after the gauge.
-- }
local DEFAULT_PREVIEW_COST_COLOR = { 1, 0.2, 0.2, 1 }
local DEFAULT_PREVIEW_GAIN_COLOR = { 0.35, 1, 0.4, 1 }

local function drawBarPreview(x, y, w, h, current, maxVal, preview)
    if not preview or not preview.delta or preview.delta == 0 or maxVal <= 0 then return end
    local delta = preview.delta
    local innerW = w
    local pctCurrent = util.clamp01(current / maxVal)
    local color, spanFromPct, spanToPct

    if delta < 0 then
        color = preview.costColor or DEFAULT_PREVIEW_COST_COLOR
        local costVal = math.min(current, -delta)
        spanFromPct = math.max(0, (current - costVal) / maxVal)
        spanToPct = pctCurrent
    else
        color = preview.gainColor or DEFAULT_PREVIEW_GAIN_COLOR
        local gainVal = math.min(math.max(0, maxVal - current), delta)
        spanFromPct = pctCurrent
        spanToPct = math.min(1, (current + gainVal) / maxVal)
    end

    local spanFromPx = math.floor(innerW * spanFromPct)
    local spanToPx = math.ceil(innerW * spanToPct)
    local spanW = math.max(1, spanToPx - spanFromPx)
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x + spanFromPx, y, spanW, h)
end

function ui.drawBar(x, y, w, h, current, maxVal, color1, color2, preview)
    local r_old, g_old, b_old, a_old = love.graphics.getColor()

    -- Every gauge shares the same one-pixel drop shadow. Keeping this in the
    -- primitive prevents HP, MP, EXP, shop and ritual gauges from drifting
    -- into separate presentation rules.
    love.graphics.setColor(0, 0, 0, 0.65)
    love.graphics.rectangle("fill", x + 1, y + 1, w, h)

    -- Sunken dark navy channel background (matches windowskin frame tone)
    love.graphics.setColor(0.06, 0.08, 0.14, 0.95)
    love.graphics.rectangle("fill", x, y, w, h)

    local pct = util.clamp01(current / maxVal)
    local fillW = math.floor(w * pct)

    if fillW > 0 then
        color1 = color1 or { 0.2, 0.45, 0.85 }
        color2 = color2 or { 0.4, 0.7, 1.0 }
        for i = 0, h - 1 do
            local factor = (h > 1) and (i / (h - 1)) or 0
            local r = color1[1] * (1 - factor) + color2[1] * factor
            local g = color1[2] * (1 - factor) + color2[2] * factor
            local b = color1[3] * (1 - factor) + color2[3] * factor
            love.graphics.setColor(r, g, b, 1)
            love.graphics.rectangle("fill", x, y + i, fillW, 1)
        end
    end

    drawBarPreview(x, y, w, h, current, maxVal, preview)

    love.graphics.setColor(r_old, g_old, b_old, a_old)

    if preview and preview.label and preview.label ~= "" then
        local labelColor = (preview.delta or 0) < 0
            and (preview.costColor or DEFAULT_PREVIEW_COST_COLOR)
            or (preview.gainColor or DEFAULT_PREVIEW_GAIN_COLOR)
        ui.drawString(preview.label, x + w + 3, y + h - ui.fontSize, labelColor)
    end
end

local iconColumns = 10
local discreteHslPaletteShader
local cachedPalettes = {}

local function parseHexColor(hex)
    if type(hex) == "table" then return hex end
    if type(hex) ~= "string" then return {1, 1, 1, 1} end
    hex = hex:gsub("#", "")
    local r = (tonumber(hex:sub(1, 2), 16) or 255) / 255
    local g = (tonumber(hex:sub(3, 4), 16) or 255) / 255
    local b = (tonumber(hex:sub(5, 6), 16) or 255) / 255
    return { r, g, b, 1 }
end

local function initIconShader()
    if discreteHslPaletteShader then return discreteHslPaletteShader end
    local code = [[
        uniform vec4 u_palette[4];
        uniform float u_targetHue;
        uniform float u_hueTolerance;
        uniform float u_minimumSaturation;
        uniform float u_minimumLightness;
        uniform float u_maximumLightness;

        vec3 rgb2hsl(vec3 c) {
            float maxC = max(c.r, max(c.g, c.b));
            float minC = min(c.r, min(c.g, c.b));
            float lightness = (maxC + minC) * 0.5;
            if (maxC == minC) {
                return vec3(0.0, 0.0, lightness);
            }
            float delta = maxC - minC;
            float saturation = lightness > 0.5 ? delta / (2.0 - maxC - minC) : delta / (maxC + minC);
            float hue;
            if (maxC == c.r) {
                hue = (c.g - c.b) / delta + (c.g < c.b ? 6.0 : 0.0);
            } else if (maxC == c.g) {
                hue = (c.b - c.r) / delta + 2.0;
            } else {
                hue = (c.r - c.g) / delta + 4.0;
            }
            return vec3(hue / 6.0, saturation, lightness);
        }

        vec4 effect(vec4 color, Image texture, vec2 textureCoords, vec2 screenCoords) {
            vec4 source = Texel(texture, textureCoords);
            if (source.a < 0.01) {
                return vec4(0.0);
            }
            vec3 hsl = rgb2hsl(source.rgb);
            float hueDistance = abs(hsl.x - u_targetHue);
            hueDistance = min(hueDistance, 1.0 - hueDistance);

            bool keyed = (hueDistance <= u_hueTolerance &&
                          hsl.y >= u_minimumSaturation &&
                          hsl.z >= u_minimumLightness &&
                          hsl.z <= u_maximumLightness);

            if (!keyed) {
                return source * color;
            }

            float normalizedLightness = clamp(
                (hsl.z - u_minimumLightness) / max(0.0001, u_maximumLightness - u_minimumLightness),
                0.0, 1.0
            );

            // The four palette entries are CONTROL POINTS at 0, 1/3, 2/3, 1 --
            // not four buckets. Source icons are already colour-limited (a
            // typical 8x8 keys 3-6 distinct tones), so quantizing to four
            // steps discarded most of the shading that was there, and with a
            // 0.10-0.95 window the top bucket almost never fired. Interpolating
            // preserves the source's own gradation and lets the highlight
            // contribute in proportion. Blend is in sRGB, which is the space
            // the palette hexes were picked in.
            float rampPosition = normalizedLightness * 3.0;
            int lowStop = int(floor(rampPosition));
            if (lowStop < 0) lowStop = 0;
            if (lowStop > 2) lowStop = 2;
            float blend = clamp(rampPosition - float(lowStop), 0.0, 1.0);

            vec3 mapped = mix(u_palette[lowStop].rgb, u_palette[lowStop + 1].rgb, blend);
            return vec4(mapped * color.rgb, source.a * color.a);
        }
    ]]
    -- A swallowed compile error here would silently disable recoloring for the
    -- whole game and look exactly like "the palette wasn't set" -- the same
    -- silent-failure shape as the loader/dbPayload bugs. Raise instead, and let
    -- tests/test_icons.lua compile it on every run so a shader typo fails the
    -- gate rather than the frame.
    local ok, shaderOrErr = pcall(love.graphics.newShader, code)
    if not ok then
        error("icon palette shader failed to compile: " .. tostring(shaderOrErr), 0)
    end
    discreteHslPaletteShader = shaderOrErr
    return discreteHslPaletteShader
end

-- Exposed purely so the gate can prove the shader compiles on this driver.
ui.initIconShader = initIconShader

local function resolveIconQuad(id)
    if not id or id <= 0 or not iconset then return nil end
    local quad = iconQuads[id]
    if not quad then
        local col = (id - 1) % iconColumns
        local row = math.floor((id - 1) / iconColumns)
        quad = love.graphics.newQuad(col * iconSize, row * iconSize, iconSize, iconSize, iconset:getDimensions())
        iconQuads[id] = quad
    end
    return quad
end

function ui.resolveIcon(iconSource, paletteOverride)
    if iconSource == nil then
        return { id = 0, palette = nil }
    end
    
    local resolvedId = 0
    local resolvedPalette = paletteOverride

    if type(iconSource) == "number" then
        resolvedId = math.floor(iconSource)
    elseif type(iconSource) == "table" then
        if type(iconSource.icon) == "table" then
            resolvedId = tonumber(iconSource.icon.id) or 0
            resolvedPalette = resolvedPalette or iconSource.icon.palette or iconSource.icon.iconPalette
        else
            resolvedId = tonumber(iconSource.icon or iconSource.id) or 0
            resolvedPalette = resolvedPalette or iconSource.iconPalette or iconSource.palette
        end
    end

    if resolvedPalette == "" then resolvedPalette = nil end
    return {
        id = resolvedId,
        palette = resolvedPalette
    }
end

local function resolveIconPalette(paletteId)
    if not paletteId then return nil end
    if cachedPalettes[paletteId] then return cachedPalettes[paletteId] end
    
    local loader = require("data.loader")
    local palettes = (loader and loader.iconPalettes) or {}
    local entry = palettes[paletteId]
    if not entry or not entry.colors then return nil end
    
    local colors = {}
    for i = 1, 4 do
        table.insert(colors, parseHexColor(entry.colors[i]))
    end
    cachedPalettes[paletteId] = colors
    return colors
end

local function resolveIconKeyProfile(iconId)
    local loader = require("data.loader")
    local profiles = (loader and loader.iconKeyProfiles) or {}
    local defaultProf = profiles["default"] or {
        targetHue = 0.0,
        hueTolerance = 0.08,
        minimumSaturation = 0.25,
        minimumLightness = 0.10,
        maximumLightness = 0.95
    }
    local customProf = profiles[tostring(iconId)]
    if not customProf then return defaultProf end
    
    return {
        targetHue = customProf.targetHue or defaultProf.targetHue,
        hueTolerance = customProf.hueTolerance or defaultProf.hueTolerance,
        minimumSaturation = customProf.minimumSaturation or defaultProf.minimumSaturation,
        minimumLightness = customProf.minimumLightness or defaultProf.minimumLightness,
        maximumLightness = customProf.maximumLightness or defaultProf.maximumLightness,
    }
end

-- Exposed so the resolution rules can be tested without a draw: everything
-- below this point needs a graphics context, everything above is pure data.
ui.resolveIconPalette = resolveIconPalette
ui.resolveIconKeyProfile = resolveIconKeyProfile

-- Centralized icon renderer
function ui.drawIcon(iconSource, x, y, options)
    if not iconset then return end
    options = options or {}
    local icon = ui.resolveIcon(iconSource, options.palette)
    if not icon or icon.id <= 0 then return end
    
    local quad = resolveIconQuad(icon.id)
    if not quad then return end
    
    local scale = options.scale or 1.0
    local drawColor = options.color or { 1, 1, 1, 1 }
    if options.disabled then
        drawColor = { drawColor[1] * 0.5, drawColor[2] * 0.5, drawColor[3] * 0.5, (drawColor[4] or 1) * 0.5 }
    end
    
    love.graphics.push("all")
    
    -- Drop shadow pass
    if options.shadow then
        love.graphics.setColor(0, 0, 0, 0.8)
        love.graphics.draw(iconset, quad, x + scale, y + scale, 0, scale, scale)
    end
    
    -- Palette shader pass
    local shaderActive = false
    if icon.palette then
        initIconShader()
        local paletteData = resolveIconPalette(icon.palette)
        local profileData = resolveIconKeyProfile(icon.id)
        if paletteData and discreteHslPaletteShader then
            shaderActive = true
            love.graphics.setShader(discreteHslPaletteShader)
            discreteHslPaletteShader:send("u_palette", unpack(paletteData))
            discreteHslPaletteShader:send("u_targetHue", profileData.targetHue or 0.0)
            discreteHslPaletteShader:send("u_hueTolerance", profileData.hueTolerance or 0.08)
            discreteHslPaletteShader:send("u_minimumSaturation", profileData.minimumSaturation or 0.25)
            discreteHslPaletteShader:send("u_minimumLightness", profileData.minimumLightness or 0.10)
            discreteHslPaletteShader:send("u_maximumLightness", profileData.maximumLightness or 0.95)
        end
    end
    
    love.graphics.setColor(drawColor[1], drawColor[2], drawColor[3], drawColor[4] or 1)
    love.graphics.draw(iconset, quad, x, y, 0, scale, scale)
    
    if shaderActive then
        love.graphics.setShader()
    end
    
    love.graphics.pop()
end

-- Draws "[icon] text" as one unit
function ui.drawIconText(iconSource, text, x, y, color, options)
    local icon = ui.resolveIcon(iconSource)
    local textX = x
    if iconSource ~= nil then
        if icon.id > 0 then
            local iconY = y + math.floor((ui.lineHeight - iconSize) / 2) - 1
            ui.drawIcon(iconSource, textX + ui.toPx(0.25), iconY, options)
        end
        textX = textX + ui.toPx(0.25) + iconSize + ui.toPx(0.25)
    end
    ui.drawString(text, textX, y, color)
    return textX + ui.measureText(text)
end

-- Draw icons from system/iconset.png with uniform scale factor wrapper
function ui.drawIconScaled(iconSource, x, y, scale, options)
    options = options or {}
    options.scale = scale or 1.0
    return ui.drawIcon(iconSource, x, y, options)
end

function ui.loadFont(name, size)
    size = size or 8
    local path = name and name ~= "Lucida" and ("assets/fonts/" .. name .. ".ttf")
    local ok, font
    if path and love.filesystem.getInfo(path) then
        ok, font = pcall(love.graphics.newFont, path, size, "mono")
    end
    if not ok or not font then
        ok, font = pcall(love.graphics.newFont, size, "mono")
    end
    if not ok or not font then
        ok, font = pcall(love.graphics.newFont, size)
    end
    if ok and font then
        font:setFilter("nearest", "nearest")
        return font
    end
    return nil
end

-- Set font helper. "Lucida" (and any name with no matching .ttf) means the
-- LÖVE built-in default font; any other name is looked up generically at
-- assets/fonts/<name>.ttf so new fonts only need a file dropped in, no code
-- change here.
--
-- "mono" hinting forces 1-bit (no grayscale antialiasing) glyph rasterization
-- — without it, TrueType fonts render with soft AA edges that read as a
-- blurry smear at the tiny 6-12px sizes this UI uses; only PressStart2P and
-- Silkscreen happened to look crisp before because their design docs bake
-- pixel alignment in at specific sizes. "mono" makes every font crisp at
-- every size, matching those two.
function ui.setFont(name, size)
    size = size or ui.fontSize or 8
    local loaded = ui.loadFont(name, size)
    if loaded then
        mainFont = loaded
        ui.fontSize = size
        -- UI geometry stays on the fixed 8px grid even when a font needs a
        -- larger nominal size to reach the intended visual size. Without this,
        -- LÖVE advances wrapped text using the font's native height while list
        -- rows continue to advance by ui.lineHeight.
        local nativeHeight = mainFont:getHeight()
        if nativeHeight > 0 then
            mainFont:setLineHeight(ui.lineHeight / nativeHeight)
        end
        love.graphics.setFont(mainFont)
    end
end

function ui.loadPopupFont(name, size)
    popupFont = ui.loadFont(name, size)
end

function ui.getPopupFont()
    return popupFont
end

function ui.getPopupNumberFont()
    return popupNumberFont or popupFont
end

function ui.getPopupTextFont()
    return popupTextFont or popupFont
end

-- Measure rendered width of text in the active UI font (monospace).
-- Pre-wraps text to hard line breaks at the given pixel limit using the
-- active font's own wrap logic (Font:getWrap), so a typewriter reveal can
-- expose it character by character without printf re-wrapping mid-word --
-- wrap points are decided ONCE for the full text and never move.
function ui.wrapText(text, limit, font)
    local targetFont = font or mainFont
    if not targetFont or not text then return text or "" end
    -- Inline \c[N] colour codes are parsed OUT before printf ever measures the
    -- string, so wrapping the raw text overestimates every word carrying one
    -- and breaks lines printf would not have broken -- that mismatch is what
    -- let pre-wrapped dialogue still re-flow mid-reveal. Only coloured text
    -- needs the manual pass; plain text keeps Font:getWrap, so every existing
    -- wrap point stays byte-identical.
    if not string.find(text, "\\c%[") then
        local _, lines = targetFont:getWrap(text, limit)
        return table.concat(lines, "\n")
    end
    if not limit or limit <= 0 then return text end
    local spaceW = targetFont:getWidth(" ")
    local out = {}
    local body = text:sub(-1) == "\n" and text or (text .. "\n")
    for rawLine in body:gmatch("(.-)\r?\n") do
        local line, lineW
        for word in rawLine:gmatch("%S+") do
            local w = targetFont:getWidth((word:gsub("\\c%[%d+%]", "")))
            if not line then
                line, lineW = word, w
            elseif lineW + spaceW + w <= limit then
                line, lineW = line .. " " .. word, lineW + spaceW + w
            else
                out[#out + 1] = line
                line, lineW = word, w
            end
        end
        out[#out + 1] = line or ""
    end
    return table.concat(out, "\n")
end

-- One RPG-style character reveal shared by dialogue, battle logs, and
-- authored cinematic captions.
function ui.revealedCount(text, elapsed)
    text = tostring(text or "")
    local delay = (config.ui and config.ui.textRevealDelay) or 0
    if delay <= 0 then return #text end
    return math.min(#text, math.floor((elapsed or 0) / delay))
end

function ui.utf8Prefix(text, byteCount)
    if byteCount >= #text then return text end
    local nextByte = text:byte(byteCount + 1)
    while byteCount > 0 and nextByte and nextByte >= 0x80 and nextByte < 0xC0 do
        byteCount = byteCount - 1
        nextByte = text:byte(byteCount + 1)
    end
    return text:sub(1, byteCount)
end

-- Engine-level pre-calculated text reveal.
-- Wrap points are decided ONCE against the FULL text, so no word can migrate
-- to the next line as later characters appear. `options.limit`/`options.width`
-- supplies the wrap width; omit it for text that is already hard-wrapped.
-- Callers that draw with printf must pass the SAME limit printf gets, or the
-- pre-wrap is meaningless.
--
-- This returns left-aligned-safe text only. Centred and right-aligned reveals
-- must NOT go through printf at all -- printf re-derives each line's origin
-- from the width of what is currently visible, so the line slides as it types.
-- Use ui.revealedLines for those; padding with spaces cannot fix it, because
-- the padding counts toward printf's own wrap limit and pushes the line over.
function ui.revealedText(text, elapsed, options)
    text = tostring(text or "")
    options = options or {}
    local limit = options.limit or options.width
    local fullWrapped = (limit and limit > 0)
        and ui.wrapText(text, limit, options.font) or text
    return ui.utf8Prefix(fullWrapped, ui.revealedCount(fullWrapped, elapsed))
end

-- Pre-calculated reveal LAYOUT: the companion to ui.revealedText for text that
-- is centred or right-aligned, where position must be fixed before the first
-- character shows.
--
-- Every line's x origin is measured from that line's FINAL, fully-revealed
-- width, then handed back alongside only the characters visible so far. Draw
-- each entry with love.graphics.print at its own `x` (never printf, which
-- would re-wrap and re-centre against the partial string) and the block is
-- pinned in place for the whole animation.
--
-- Returns: array of { text = visible prefix, x = fixed offset, full = final
-- line } and, second, whether the reveal has finished.
function ui.revealedLines(text, elapsed, options)
    text = tostring(text or "")
    options = options or {}
    local font = options.font or mainFont
    local width = options.limit or options.width
    local align = options.align or "left"

    local fullWrapped = (width and width > 0)
        and ui.wrapText(text, width, font) or text
    local revCount = ui.revealedCount(fullWrapped, elapsed)
    local visible = ui.utf8Prefix(fullWrapped, revCount)

    local function split(s)
        local lines = {}
        local body = s:sub(-1) == "\n" and s or (s .. "\n")
        for line in body:gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
        return lines
    end

    local fullLines = split(fullWrapped)
    local visibleLines = split(visible)

    local out = {}
    for i, full in ipairs(fullLines) do
        local shown = visibleLines[i]
        if shown == nil then break end
        local x = 0
        if font and width then
            local fullW = font:getWidth((full:gsub("\\c%[%d+%]", "")))
            if align == "center" then x = (width - fullW) / 2
            elseif align == "right" then x = width - fullW end
        end
        out[#out + 1] = { text = shown, x = x, full = full }
    end
    return out, revCount >= #fullWrapped
end

function ui.measureText(text)
    if mainFont then return mainFont:getWidth(text) end
    return #tostring(text) * (ui.fontSize or 8)
end

-- Longest prefix of `text` that fits in `maxWidth` pixels. Silent truncation,
-- no ellipsis -- the convention party status cells already used, now measured
-- against the real font instead of assuming ~6px per character. Multibyte
-- safe: the cut never lands inside a UTF-8 codepoint, since printf hard-errors
-- on malformed UTF-8 and item names carry curly quotes.
function ui.fitText(text, maxWidth)
    text = tostring(text or "")
    if maxWidth == nil or maxWidth <= 0 then return "" end
    if ui.measureText(text) <= maxWidth then return text end
    local n = #text
    while n > 0 do
        local byte = text:byte(n + 1)
        while n > 0 and byte and byte >= 0x80 and byte < 0xC0 do
            n = n - 1
            byte = text:byte(n + 1)
        end
        local candidate = text:sub(1, n)
        if ui.measureText(candidate) <= maxWidth then return candidate end
        n = n - 1
    end
    return ""
end

return ui
