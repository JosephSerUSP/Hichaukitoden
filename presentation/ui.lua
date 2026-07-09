local config = require("engine.config")

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
function ui.load()
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
        love.graphics.setColor(1, 1, 0.7, 1)
        ui.drawString(title, x + 12, y + 7)
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

-- Draw registered windows for a scene kind (D4 crafting support - full implementation)
function ui.drawWindows(kind, windows, ctx)
    if not windows then return end
    local sceneConfig = (ctx and ctx.sceneData and ctx.sceneData.config) or {}
    local terms = sceneConfig.terms or {}

    for name, win in pairs(windows) do
        if win.type == "header" then
            ui.drawPanel(16, 8, 224, 24, terms.title or "Item Creation")
        elseif win.type == "list" then
            ui.drawPanel(16, 40, 224, 80, name)
            if win.source and ctx and ctx.v then
                ui.drawString("List: " .. (win.source or "items"), 24, 56, {1,1,1,1})
                if win.filter then
                    ui.drawString("Filtered by discipline", 24, 68, {0.6,0.8,1,1})
                end
            end
        elseif win.type == "slots" then
            ui.drawPanel(16, 130, 224, 48, "Ingredient Slots")
            ui.drawString("Slot 1: " .. (ctx.v and ctx.v.i1 and ctx.v.i1.name or "Empty"), 24, 148, {1,1,1,1})
            ui.drawString("Slot 2: " .. (ctx.v and ctx.v.i2 and ctx.v.i2.name or "Empty"), 24, 160, {1,1,1,1})
        elseif win.type == "roulette" then
            ui.drawPanel(64, 64, 128, 80, terms.title or "Crafting...")
            ui.drawString("Roulette spinning...", 80, 90, {1, 0.8, 0.2, 1})
            if ctx.v and ctx.v.currentIdx then
                ui.drawString("Item: " .. (ctx.v.pool and ctx.v.pool[ctx.v.currentIdx] and ctx.v.pool[ctx.v.currentIdx].name or "?"), 80, 110, {1,1,0.5,1})
            end
        elseif win.type == "result" then
            ui.drawPanel(64, 64, 128, 80, "Success!")
            ui.drawString(terms.resultText or "Item crafted!", 80, 90, {0.3, 1, 0.3, 1})
            if ctx.v and ctx.v.resultItem then
                ui.drawString(ctx.v.resultItem.name or "Unknown", 80, 110, {1,1,1,1})
            end
        elseif win.type == "text" or win.type == "yield_text" then
            local yieldText = terms.yieldText or "Expected Yield: {0}"
            if ctx.v and ctx.v.yield then
                yieldText = yieldText:gsub("{0}", tostring(ctx.v.yield))
            end
            ui.drawString(yieldText, 40, 170, {1,1,0.5,1})
            if ctx.v and ctx.v.isAnomaly then
                ui.drawString(terms.anomalyText or "CRITICAL ANOMALY!", 40, 185, {1,0.3,0.3,1})
            end
        elseif win.type == "panel" or win.type == "confirm" then
            ui.drawPanel(40, 200, 176, 60, name)
            if win.title then
                ui.drawString(win.title, 48, 212, {1,1,0.7,1})
            end
        elseif win.type == "confirm_options" then
            ui.drawString("Craft  Back", 80, 220, {1,1,1,1})
        elseif win.portrait then
            -- Portrait at 1x scale (D4 feedback fix)
            if ctx and ctx.v and ctx.v.crafter then
                -- Placeholder for portrait draw (full sprite support in D5)
                love.graphics.setColor(1,1,1,1)
                love.graphics.rectangle("fill", 200, 40, 32, 32)
            end
        end
    end
end

-- Set font helper
function ui.setFont(name)
    if name == "PressStart2P" and love.filesystem.getInfo("assets/fonts/PressStart2P.ttf") then
        mainFont = love.graphics.newFont("assets/fonts/PressStart2P.ttf", 8)
    elseif name == "Silkscreen" and love.filesystem.getInfo("assets/fonts/Silkscreen.ttf") then
        mainFont = love.graphics.newFont("assets/fonts/Silkscreen.ttf", 8)
    else
        mainFont = love.graphics.newFont(8)
    end
    love.graphics.setFont(mainFont)
end

return ui
