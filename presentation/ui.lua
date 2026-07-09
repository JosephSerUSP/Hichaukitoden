local config = require("engine.config")
local json = require("data.json")
local engineData
if love.filesystem.getInfo("data/engine.json") then
    engineData = json.decode(love.filesystem.read("data/engine.json"))
end

local ui = {}






local iconset
local iconSize = 12
local windowskin
local mainFont

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
        if startIdx > currentPos then
            table.insert(chunks, currentActiveColor)
            table.insert(chunks, string.sub(result, currentPos, startIdx - 1))
        end
        local colIdx = tonumber(code) + 1 -- 1-indexed in lua
        if palette[colIdx] then
            currentActiveColor = palette[colIdx]
        else
            currentActiveColor = defaultColor
        end
        currentPos = endIdx + 1
    end
    return chunks
end

function ui.setFont(fontName)
    local success, loadedFont
    local path
    local size = 8
    
    if fontName == "Silkscreen" then
        path = "assets/fonts/Silkscreen.ttf"
    elseif fontName == "PressStart2P" then
        path = "assets/fonts/PressStart2P.ttf"
    elseif fontName == "Silver" then
        path = "assets/fonts/Silver.ttf"
        size = 14 -- Silver natural scale
    else
        path = "C:/Windows/Fonts/lucon.ttf"
    end
    
    success, loadedFont = pcall(function()
        return love.graphics.newFont(path, size, "mono")
    end)
    
    if not (success and loadedFont) then
        loadedFont = love.graphics.newFont(8, "mono")
    end
    
    mainFont = loadedFont
    mainFont:setFilter("nearest", "nearest")
    mainFont:setLineHeight(1.0)
    love.graphics.setFont(mainFont)
    ui.activeFont = fontName
end

function ui.init()
    if love.filesystem.getInfo("assets/system/iconset.png") then
        iconset = love.graphics.newImage("assets/system/iconset.png")
        iconset:setFilter("nearest", "nearest")
    end
    
    if love.filesystem.getInfo("assets/system/PRINCESSTHEKING.png") then
        windowskin = love.graphics.newImage("assets/system/PRINCESSTHEKING.png")
        windowskin:setFilter("nearest", "nearest")
    end
    
    -- Load active font from system config
    local fontName = config.ui and config.ui.activeFont or "Lucida"
    
    ui.setFont(fontName)
end

-- Exposed layout constants (use these instead of hardcoded numbers)
ui.fontSize   = 8
ui.tileSize   = 8    -- SNES-style 8x8 tile size grid
ui.lineHeight = ui.tileSize   -- exactly equal to tileHeight (8px)
ui.screenWidthTiles = 32   -- 256 / 8
ui.screenHeightTiles = 30   -- 240 / 8

-- Utility to convert tile coordinate to pixels
function ui.toPx(tiles)
    return tiles * ui.tileSize
end

-- Draw RPG Maker 2003 styled windowskin panel
-- Layout specifications:
-- First 32x32: seamlessly tiling background
-- Next 32x32 (x=32..64, y=0..32): 8px borders
function ui.drawPanel(x, y, w, h, title)
    love.graphics.push("all")
    
    if windowskin then
        local wsW, wsH = windowskin:getDimensions()
        
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
                love.graphics.draw(windowskin, tileQuad, bx, by)
            end
        end
        love.graphics.setScissor(sx, sy, sw, sh) -- restore scissor
        
        -- 2. Draw 8px Edges (tiled/stretched)
        local edgeW = w - 16
        local edgeH = h - 16
        
        -- Top side edge (x=40, y=0, w=16, h=8)
        local topQuad = love.graphics.newQuad(40, 0, 16, 8, wsW, wsH)
        love.graphics.draw(windowskin, topQuad, x + 8, y, 0, edgeW / 16, 1)
        
        -- Bottom side edge (x=40, y=24, w=16, h=8)
        local botQuad = love.graphics.newQuad(40, 24, 16, 8, wsW, wsH)
        love.graphics.draw(windowskin, botQuad, x + 8, y + h - 8, 0, edgeW / 16, 1)
        
        -- Left side edge (x=32, y=8, w=8, h=16)
        local leftQuad = love.graphics.newQuad(32, 8, 8, 16, wsW, wsH)
        love.graphics.draw(windowskin, leftQuad, x, y + 8, 0, 1, edgeH / 16)
        
        -- Right side edge (x=56, y=8, w=8, h=16)
        local rightQuad = love.graphics.newQuad(56, 8, 8, 16, wsW, wsH)
        love.graphics.draw(windowskin, rightQuad, x + w - 8, y + 8, 0, 1, edgeH / 16)
        
        -- 3. Draw 8px Corners
        local tlQuad = love.graphics.newQuad(32, 0, 8, 8, wsW, wsH)
        local trQuad = love.graphics.newQuad(56, 0, 8, 8, wsW, wsH)
        local blQuad = love.graphics.newQuad(32, 24, 8, 8, wsW, wsH)
        local brQuad = love.graphics.newQuad(56, 24, 8, 8, wsW, wsH)
        
        love.graphics.draw(windowskin, tlQuad, x, y)
        love.graphics.draw(windowskin, trQuad, x + w - 8, y)
        love.graphics.draw(windowskin, blQuad, x, y + h - 8)
        love.graphics.draw(windowskin, brQuad, x + w - 8, y + h - 8)
    else
        -- Fallback
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.rectangle("fill", x + 2, y + 2, w, h, 2, 2)
        love.graphics.setColor(15/255, 20/255, 35/255, 0.95)
        love.graphics.rectangle("fill", x, y, w, h, 2, 2)
        love.graphics.setColor(120/255, 120/255, 140/255, 0.8)
        love.graphics.rectangle("line", x + 2, y + 2, w - 4, h - 4)
    end
    
    -- Draw title header if specified
    if title then
        local headerSpacing = (engineData and engineData.windowLayout and engineData.windowLayout.headerSpacing) or 0
        love.graphics.setColor(1, 1, 0.7, 1)
        ui.drawString(title, x + 12, y + 6 + headerSpacing)
    end
    
    love.graphics.pop()
end

-- Draw text with drop shadow (crisp monochrome)
function ui.drawString(text, x, y, color, alignment, limit, eventName)
    local r, g, b, a = love.graphics.getColor()
    local currentFont = love.graphics.getFont()
    
    color = color or {1, 1, 1, 1}
    alignment = alignment or "left"
    limit = limit or 256
    
    -- Set active font explicitly to ensure properties apply
    if mainFont then love.graphics.setFont(mainFont) end
    
    local parsedText = text or ""
    if eventName and eventName ~= "" then
        parsedText = string.gsub(parsedText, "\\eventName", string.gsub(eventName, "%%", "%%%%"))
    else
        parsedText = string.gsub(parsedText, "\\eventName", "")
    end

    if alignment == "right" then
        local padding = (engineData and engineData.windowLayout and engineData.windowLayout.rightPaddingTileOffset) or 1
        limit = limit - (padding * ui.tileSize)
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
function ui.drawBar(x, y, w, h, current, maxVal, color1, color2)
    local r_old, g_old, b_old, a_old = love.graphics.getColor()
    
    love.graphics.setColor(0.1, 0.1, 0.1, 1)
    love.graphics.rectangle("fill", x, y, w, h)
    
    local pct = math.max(0, math.min(1, current / maxVal))
    local fillW = math.floor((w - 2) * pct)
    
    if fillW > 0 then
        for i = 0, h - 3 do
            local factor = i / (h - 2)
            local r = color1[1] * (1 - factor) + color2[1] * factor
            local g = color1[2] * (1 - factor) + color2[2] * factor
            local b = color1[3] * (1 - factor) + color2[3] * factor
            love.graphics.setColor(r, g, b, 1)
            love.graphics.rectangle("fill", x + 1, y + 1 + i, fillW, 1)
        end
    end
    
    love.graphics.setColor(0.4, 0.4, 0.4, 1)
    love.graphics.rectangle("line", x, y, w, h)
    
    love.graphics.setColor(r_old, g_old, b_old, a_old)
end

-- Draw icons from system/iconset.png
function ui.drawIcon(iconId, x, y)
    if not iconset or not iconId or iconId <= 0 then return end
    
    local col = (iconId - 1) % 10
    local row = math.floor((iconId - 1) / 10)
    local quad = love.graphics.newQuad(col * iconSize, row * iconSize, iconSize, iconSize, iconset:getDimensions())
    
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.draw(iconset, quad, x + 1, y + 1)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(iconset, quad, x, y)
    love.graphics.pop()
end

return ui
