local ui = require("presentation.ui")
local session = require("engine.session")
local traits = require("engine.traits")
local formula = require("engine.formula")
local interpreter = require("engine.interpreter")
local scene_host = require("engine.scene_host")

local crafting = {}

-- Scene States
-- 1 = select_discipline
-- 2 = select_crafter
-- 3 = select_ingredients (two slots: first selects i1, then i2)
-- 4 = confirm_craft
-- 5 = roulette
-- 6 = result

local function v() return scene_host.getCurrentState().v end

local function getDiscipline()
    local scenesData = activeSession and activeSession.loader and activeSession.loader.scenes or {}
    local craftScene = scenesData[1]
    local config = craftScene and craftScene.config or {}
    local disciplines = config.disciplines or {}
    return disciplines[v().selectedDisciplineIdx or 1]
end

local function getSceneConfig()
    local scenesData = activeSession and activeSession.loader and activeSession.loader.scenes or {}
    local craftScene = scenesData[1]
    return craftScene and craftScene.config or {}
end

local function refreshInventoryList(disc)
    local items = {}
    if not activeSession then return items end
    
    for itemId, qty in pairs(activeSession.inventory) do
        if qty > 0 then
            local item = activeSession.loader.getItem(itemId)
            if item then
                table.insert(items, { item = item, qty = qty })
            end
        end
    end
    
    -- Sort inventory to prioritize items of this discipline's craftKind
    table.sort(items, function(a, b)
        local aKind = a.item.meta and a.item.meta.craftKind or ""
        local bKind = b.item.meta and b.item.meta.craftKind or ""
        local discKind = disc and disc.kind or ""
        
        if aKind == discKind and bKind ~= discKind then
            return true
        elseif aKind ~= discKind and bKind == discKind then
            return false
        else
            return a.item.id < b.item.id
        end
    end)
    return items
end

function initCraftingScene()
    local disc = getDiscipline()
    v().inventoryItems = refreshInventoryList(disc)
end

local function getBattlerStat(battler, statName)
    if statName == "level" then
        return battler.level
    end
    return traits.getParam(battler, statName, activeSession)
end

local function calculateYield()
    if not v().i1_item or not v().i2_item or not v().crafter_battler then return 0, 0, 0, false end
    
    local config = getSceneConfig()
    local disc = getDiscipline()
    
    local S = getBattlerStat(v().crafter_battler, disc.stat)
    
    local mockCtx = {
        i1 = formula.itemView(v().i1_item),
        i2 = formula.itemView(v().i2_item),
        crafter = v().crafter_battler,
        alpha = config.alpha or 0.5,
        S = S
    }
    
    local _, Y = pcall(formula.eval, config.yieldFormula or "0", mockCtx)
    Y = math.floor(tonumber(Y) or 0)
    
    local _, penalty = pcall(formula.eval, config.penaltyFormula or "0", mockCtx)
    penalty = math.floor(tonumber(penalty) or 0)
    
    local Y_final = math.max(0, Y - penalty)
    
    -- Check for anomaly
    local _, anomalyMult = pcall(formula.eval, config.anomalyFormula or "1.0", mockCtx)
    anomalyMult = tonumber(anomalyMult) or 1.0
    local isCrit = (anomalyMult > 1.0)
    
    local Y_anomaly = math.floor(Y_final * anomalyMult)
    
    return Y_final, Y_anomaly, penalty, isCrit
end

local function getOutcomeTier(score)
    local config = getSceneConfig()
    local brackets = config.brackets or {}
    
    for _, br in ipairs(brackets) do
        if score <= br.max then
            return br.tier, br.name
        end
    end
    
    local lastBr = brackets[#brackets]
    return lastBr and lastBr.tier or 0, lastBr and lastBr.name or "Junk"
end

local function getOutcomePool(tier, disc)
    local pool = {}
    for _, item in ipairs(activeSession.loader.items or {}) do
        if item.meta and item.meta.craftKind == disc.kind and item.meta.tier == tier then
            table.insert(pool, item)
        end
    end
    
    -- Fallback to junk if pool empty
    if #pool == 0 then
        for _, item in ipairs(activeSession.loader.items or {}) do
            if item.meta and item.meta.craftKind == disc.kind and item.meta.tier == 0 then
                table.insert(pool, item)
            end
        end
    end
    return pool
end

function updateCraftingScene(dt)
    if v().state == 5 then -- Roulette animation
        v().rouletteTimer = (v().rouletteTimer or 0) + dt
        if v().rouletteTimer >= (v().rouletteDelay or 0) then
            v().rouletteTimer = 0
            v().rouletteStep = (v().rouletteStep or 0) + 1
            
            local config = getSceneConfig()
            local timing = config.timing or {}
            
            if v().rouletteStep >= (timing.steps or 12) then
                -- Settle on target result (already assigned in handleEvalPool)
            else
                -- decel delay
                v().rouletteDelay = math.min(timing.maxDelay or 0.4, (v().rouletteDelay or 0.05) * (timing.delayMult or 1.25))
                if v().roulettePool and #v().roulettePool > 0 then
                    v().rouletteCurrentIdx = math.random(#v().roulettePool)
                end
            end
        end
    end
end

function drawCraftingScene()
    local config = getSceneConfig()
    local term = config.terms or {}
    
    -- Title Header
    ui.drawPanel(0, 0, ui.toPx(32), ui.toPx(3.5), term.title or "Item Creation")
    
    if state == 1 then -- Select Discipline
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(12), ui.toPx(20.5), term.selectDiscipline or "Select Discipline:")
        local disciplines = config.disciplines or {}
        for i, d in ipairs(disciplines) do
            local isSel = (i == selectedDisciplineIdx)
            local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = isSel and ">" or " "
            ui.drawString(prefix .. d.label, ui.toPx(0.5), ui.toPx(5.5) + (i - 1) * ui.lineHeight, color)
        end
        
        -- Details panel
        local activeDisc = disciplines[v().selectedDisciplineIdx or 1]
        if activeDisc then
            ui.drawPanel(ui.toPx(12), ui.toPx(3.5), ui.toPx(20), ui.toPx(20.5), "Details")
            ui.drawString("Governing Stat: " .. string.upper(activeDisc.stat), ui.toPx(12.5), ui.toPx(5.5), {1, 0.9, 0.3, 1})
            ui.drawString(activeDisc.description or "", ui.toPx(12.5), ui.toPx(7.5), {1, 1, 1, 1}, "left", ui.toPx(19))
        end
        
    elseif v().state == 2 then -- Select Crafter
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(12), ui.toPx(20.5), term.selectCrafter or "Select Crafter:")
        for i, member in ipairs(activeSession.party) do
            local isSel = (i == v().selectedCrafterIdx)
            local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = isSel and ">" or " "
            ui.drawString(prefix .. member.actorData.name, ui.toPx(0.5), ui.toPx(5.5) + (i - 1) * ui.lineHeight, color)
        end
        
        -- Crafter stats panel
        local activeMember = activeSession.party[v().selectedCrafterIdx or 1]
        if activeMember then
            ui.drawPanel(ui.toPx(12), ui.toPx(3.5), ui.toPx(20), ui.toPx(20.5), "Crafter Stats")
            
            -- Draw Portrait
            if activeMember.actorData.spriteKey then
                local imgPath = "assets/portraits/" .. activeMember.actorData.spriteKey .. ".png"
                if love.filesystem.getInfo(imgPath) then
                    local img = love.graphics.newImage(imgPath)
                    img:setFilter("nearest", "nearest")
                    love.graphics.draw(img, ui.toPx(13), ui.toPx(5.5), 0, 1, 1)
                end
            end
            
            local disc = getDiscipline()
            local S = getBattlerStat(activeMember, disc.stat)
            
            ui.drawString(activeMember.actorData.name, ui.toPx(20), ui.toPx(5.5), {1, 1, 0.5, 1})
            ui.drawString("Level: " .. activeMember.level, ui.toPx(20), ui.toPx(7.5))
            
            -- Show governing stat prominently
            ui.drawString(string.upper(disc.stat) .. ": " .. S, ui.toPx(20), ui.toPx(9.5), {1, 0.9, 0.3, 1})
        end
        
    elseif state == 3 then -- Select Ingredients
        -- Slots panel at the top
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(32), ui.toPx(5), term.selectIngredients or "Select Ingredients:")
        
        local colorI1 = (cursorIngredientSlot == 1) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local nameI1 = i1_item and i1_item.name or "--- [Empty] ---"
        ui.drawString("Slot 1: " .. nameI1, ui.toPx(1), ui.toPx(5.5), colorI1)
        
        local colorI2 = (cursorIngredientSlot == 2) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local nameI2 = i2_item and i2_item.name or "--- [Empty] ---"
        ui.drawString("Slot 2: " .. nameI2, ui.toPx(16), ui.toPx(5.5), colorI2)
        
        -- Inventory list below
        ui.drawPanel(0, ui.toPx(8.5), ui.toPx(20), ui.toPx(15.5), "Inventory")
        
        local disc = getDiscipline()
        local scrollIdx = (cursorIngredientSlot == 1) and selectedIngredient1Idx or selectedIngredient2Idx
        
        if #inventoryItems == 0 then
            ui.drawString("No items in inventory.", ui.toPx(1), ui.toPx(10), {0.6, 0.6, 0.6, 1})
        else
            -- Render list of items
            local startOffset = math.max(1, scrollIdx - 3)
            local endOffset = math.min(#inventoryItems, startOffset + 5)
            
            for i = startOffset, endOffset do
                local entry = inventoryItems[i]
                local isSel = (i == scrollIdx)
                local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                local prefix = isSel and ">" or " "
                
                -- Highlight if matches discipline's craftKind
                local matchColor = color
                if entry.item.meta and entry.item.meta.craftKind == disc.kind then
                    if not isSel then matchColor = {0.6, 1, 0.6, 1} end
                end
                
                local name = entry.item.name .. " x" .. entry.qty
                ui.drawString(prefix, ui.toPx(0.5), ui.toPx(10.5) + (i - startOffset) * ui.lineHeight, color)
                ui.drawIcon(entry.item.icon or 0, ui.toPx(1.5), ui.toPx(10.5) + (i - startOffset) * ui.lineHeight - 2)
                ui.drawString(entry.item.name .. " (x" .. entry.qty .. ")", ui.toPx(3.5), ui.toPx(10.5) + (i - startOffset) * ui.lineHeight, matchColor)
            end
        end
        
        -- Details of selected item on the right
        local selectedEntry = inventoryItems[scrollIdx]
        if selectedEntry then
            ui.drawPanel(ui.toPx(20), ui.toPx(8.5), ui.toPx(12), ui.toPx(15.5), "Item Info")
            local item = selectedEntry.item
            ui.drawString(item.name, ui.toPx(20.5), ui.toPx(10.5), {1, 1, 0.5, 1})
            
            if item.meta then
                if item.meta.tier then
                    ui.drawString("Tier: " .. item.meta.tier, ui.toPx(20.5), ui.toPx(12.5))
                end
                if item.meta.potency then
                    ui.drawString("Potency: " .. item.meta.potency, ui.toPx(20.5), ui.toPx(14.5), {1, 0.9, 0.3, 1})
                end
                if item.meta.craftElement then
                    ui.drawString("Element: " .. item.meta.craftElement, ui.toPx(20.5), ui.toPx(16.5))
                end
            else
                ui.drawString("No meta parameters.", ui.toPx(20.5), ui.toPx(12.5), {0.6, 0.6, 0.6, 1})
            end
        end
        
    elseif state == 4 then -- Confirm Craft
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(32), ui.toPx(20.5), "Confirm Crafting")
        
        -- Crafter
        ui.drawString("Crafter: " .. crafter_battler.actorData.name, ui.toPx(2), ui.toPx(5.5), {1, 1, 0.5, 1})
        
        -- Ingredients
        ui.drawString("Ingredient 1: " .. i1_item.name, ui.toPx(2), ui.toPx(7.5))
        ui.drawString("Ingredient 2: " .. i2_item.name, ui.toPx(2), ui.toPx(9.5))
        
        -- Yield calculations
        local score, score_anomaly, penalty, isCrit = calculateYield()
        local tier, tier_name = getOutcomeTier(score)
        
        ui.drawString(term.yieldText:gsub("{0}", score), ui.toPx(2), ui.toPx(12.5), {1, 0.9, 0.3, 1})
        ui.drawString("Expected Tier: " .. tier_name .. " (Tier " .. tier .. ")", ui.toPx(2), ui.toPx(14.5))
        
        -- Check element conflicts
        if i1_item.meta and i2_item.meta then
            local el1 = i1_item.meta.craftElement or ""
            local el2 = i2_item.meta.craftElement or ""
            if el1 ~= el2 and el1 ~= "" and el2 ~= "" then
                ui.drawString("WARNING: Element conflict (" .. el1 .. " vs " .. el2 .. ")!", ui.toPx(2), ui.toPx(16.5), {1, 0.3, 0.3, 1})
            end
        end
        
        -- Option prompt at the bottom
        local craftSel = (confirmOptionIdx == 1) and "> Craft" or "  Craft"
        local backSel = (confirmOptionIdx == 2) and "> Back" or "  Back"
        
        local colorCraft = (confirmOptionIdx == 1) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local colorBack = (confirmOptionIdx == 2) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        
        ui.drawString(craftSel, ui.toPx(6), ui.toPx(19.5), colorCraft)
        ui.drawString(backSel, ui.toPx(18), ui.toPx(19.5), colorBack)
        
    elseif state == 5 then -- Roulette Animation
        ui.drawPanel(ui.toPx(4), ui.toPx(7), ui.toPx(24), ui.toPx(10), "Crafting...")
        
        local activeItem = roulettePool[rouletteCurrentIdx]
        if activeItem then
            -- Draw background pulsing border
            love.graphics.setColor(1, 1, 0.5, 0.5 + 0.5 * math.sin(love.timer.getTime() * 15))
            love.graphics.rectangle("line", ui.toPx(14.5) - 4, ui.toPx(10) - 4, 20, 20)
            love.graphics.setColor(1, 1, 1, 1)
            
            ui.drawIcon(activeItem.icon or 0, ui.toPx(15), ui.toPx(10.5))
            ui.drawString(activeItem.name, ui.toPx(4), ui.toPx(13.5), {1, 1, 0.5, 1}, "center", ui.toPx(24))
        end
        
    elseif state == 6 then -- Result Screen
        ui.drawPanel(ui.toPx(4), ui.toPx(6), ui.toPx(24), ui.toPx(12), "Crafting Success!")
        
        if resultItem then
            ui.drawIcon(resultItem.icon or 0, ui.toPx(15), ui.toPx(8.5))
            ui.drawString(term.resultText:gsub("{0}", resultItem.name), ui.toPx(4), ui.toPx(11.5), {1, 1, 0.5, 1}, "center", ui.toPx(24))
            ui.drawString(resultItem.description or "", ui.toPx(5), ui.toPx(13.5), {0.8, 0.8, 0.8, 1}, "center", ui.toPx(22))
        end
        
        if v().isAnomaly then
            ui.drawString(term.anomalyText or "CRITICAL ANOMALY!", ui.toPx(4), ui.toPx(15.5), {1, 0.3, 0.3, 1}, "center", ui.toPx(24))
        end
    end
end

function crafting.handleSelectCrafter(ctx)
    v().crafter_battler = activeSession.party[v().selectedCrafterIdx or 1]
    local disc = getDiscipline()
    v().inventoryItems = refreshInventoryList(disc)
end

function crafting.handleReset(ctx)
    v().state = 1
    v().i1_item = nil
    v().i2_item = nil
    local disc = getDiscipline()
    v().inventoryItems = refreshInventoryList(disc)
end

function crafting.handleSelectIngredient(ctx)
    local items = v().inventoryItems or {}
    if #items == 0 then return end

    local scrollIdx = (v().cursorIngredientSlot == 1) and v().selectedIngredient1Idx or v().selectedIngredient2Idx
    local selectedEntry = items[scrollIdx]

    if v().cursorIngredientSlot == 1 then
        v().i1_item = selectedEntry.item
        v().cursorIngredientSlot = 2
    else
        v().i2_item = selectedEntry.item

        if not v().i1_item then
            v().cursorIngredientSlot = 1
        else
            if v().i1_item.id == v().i2_item.id and selectedEntry.qty < 2 then
                v().i2_item = nil
            else
                v().state = 4
                v().confirmOptionIdx = 1
            end
        end
    end
end

function crafting.handleEvalPool(ctx)
    local score, score_anomaly, penalty, isCrit = calculateYield()
    v().isAnomaly = isCrit
    local finalScore = v().isAnomaly and score_anomaly or score

    local outcome_tier, tier_name = getOutcomeTier(finalScore)
    local disc = getDiscipline()

    v().roulettePool = getOutcomePool(outcome_tier, disc)
    v().rouletteTargetIdx = math.random(#v().roulettePool)
    v().resultItem = v().roulettePool[v().rouletteTargetIdx]

    local config = getSceneConfig()
    local timing = config.timing or {}
    v().rouletteTimer = 0
    v().rouletteDelay = timing.initialDelay or 0.05
    v().rouletteStep = 0
    v().rouletteCurrentIdx = math.random(#v().roulettePool)
end

function crafting.handleGiveResult(ctx)
    if not v().i1_item or not v().i2_item or not v().resultItem then return end

    local cmds = {
        { cmd = "TAKE_ITEM", item = v().i1_item.id, count = 1 },
        { cmd = "TAKE_ITEM", item = v().i2_item.id, count = 1 },
        { cmd = "GIVE_ITEM_ID", item = v().resultItem.id, count = 1 },
        { cmd = "EMIT_TEXT", fallback = "Crafted " .. v().resultItem.name .. "!" }
    }

    local cCtx = { session = activeSession, loader = activeSession.loader, party = activeSession.party }
    local interpreter = require("engine.interpreter")
    interpreter.runImmediate(cmds, cCtx)
end

function keypressedCraftingScene(key)
    local config = getSceneConfig()
    
    if v().state == 1 then
        local disciplines = config.disciplines or {}
        if key == "up" or key == "w" then
            v().selectedDisciplineIdx = (v().selectedDisciplineIdx - 2) % #disciplines + 1
        elseif key == "down" or key == "s" then
            v().selectedDisciplineIdx = v().selectedDisciplineIdx % #disciplines + 1
        end
        
    elseif v().state == 2 then
        if key == "up" or key == "w" then
            v().selectedCrafterIdx = (v().selectedCrafterIdx - 2) % #activeSession.party + 1
        elseif key == "down" or key == "s" then
            v().selectedCrafterIdx = v().selectedCrafterIdx % #activeSession.party + 1
        end
        
    elseif v().state == 3 then
        local items = v().inventoryItems or {}
        if key == "left" or key == "a" or key == "right" or key == "d" then
            v().cursorIngredientSlot = (v().cursorIngredientSlot == 1) and 2 or 1
        elseif key == "up" or key == "w" then
            if #items > 0 then
                if v().cursorIngredientSlot == 1 then
                    v().selectedIngredient1Idx = (v().selectedIngredient1Idx - 2) % #items + 1
                else
                    v().selectedIngredient2Idx = (v().selectedIngredient2Idx - 2) % #items + 1
                end
            end
        elseif key == "down" or key == "s" then
            if #items > 0 then
                if v().cursorIngredientSlot == 1 then
                    v().selectedIngredient1Idx = v().selectedIngredient1Idx % #items + 1
                else
                    v().selectedIngredient2Idx = v().selectedIngredient2Idx % #items + 1
                end
            end
        end
        
    elseif v().state == 4 then
        if key == "left" or key == "a" or key == "right" or key == "d" then
            v().confirmOptionIdx = (v().confirmOptionIdx == 1) and 2 or 1
        end
    end
end

return crafting
