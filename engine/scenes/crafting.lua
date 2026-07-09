local ui = require("presentation.ui")
local session = require("engine.session")
local traits = require("engine.traits")
local formula = require("engine.formula")
local interpreter = require("engine.interpreter")

local crafting = {}

-- Window definitions registered with scene_host for the crafting kind
local windowDefs = {
    discipline_panel = { type = "list", title = "Select Discipline:" },
    crafter_panel = { type = "list", title = "Select Crafter:" },
    ingredient_panel = { type = "panel", title = "Select Ingredients:" },
    inventory_list = { type = "list", title = "Inventory", icon = true },
    detail_panel = { type = "panel", title = "Item Info" },
    confirm_panel = { type = "confirm", title = "Confirm Crafting" },
    roulette_panel = { type = "roulette", title = "Crafting..." },
}

function crafting.registerKindWindows(host)
    -- Register window definitions so scene_host knows the crafting scene's windows
    -- This is called from scene_host.push() when a crafting scene is entered.
    if host and host.register then
        host.register("crafting", windowDefs)
    end
end

-- Scene-state key map (mirrors what hooks set in ctx.v):
--   v.state                    1=discipline, 2=crafter, 3=ingredients, 4=confirm, 5=roulette, 6=result
--   v.selectedDisciplineIdx    current discipline list cursor
--   v.selectedCrafterIdx       current crafter list cursor
--   v.selectedIngredient1Idx   inventory cursor for ingredient slot 1
--   v.selectedIngredient2Idx   inventory cursor for ingredient slot 2
--   v.cursorSlot               1 or 2 (which ingredient slot is active)
--   v.confirmOptionIdx         1=Craft, 2=Back
--   v.i1_item_id               resolved item id for slot 1 (0 = none)
--   v.i2_item_id               resolved item id for slot 2 (0 = none)
--   v.crafterIdx               party index of selected crafter
--   v.yieldScore               calculated yield score
--   v.yieldAnomalyScore        anomaly-boosted score
--   v.isAnomaly                true when anomaly triggered
--   v.rouletteStep             roulette animation step counter
--   v.rouletteDelay            current roulette delay

-- Cached inventory list (rebuilt on state 3 entry via CALC_CRAFT_YIELD)
local inventoryItems = {}

-- ---------------------------------------------------------------------------
-- Helpers that work against session / loader (no module-level state)
-- ---------------------------------------------------------------------------

local function getSceneConfig(ctx)
    local loader = ctx and ctx.loader
    if not loader and activeSession then loader = activeSession.loader end
    local scenes = loader and loader.scenes or {}
    local craftScene = scenes[1]
    return craftScene and craftScene.config or {}
end

local function getDiscipline(ctx)
    local config = getSceneConfig(ctx)
    local v = ctx and ctx.v or {}
    local disciplines = config.disciplines or {}
    return disciplines[v.selectedDisciplineIdx or 1]
end

local function getBattlerStat(battler, statName, sess)
    if statName == "level" then return battler.level end
    return traits.getParam(battler, statName, sess)
end

local function refreshInventoryList(disc, session)
    inventoryItems = {}
    if not session then return end

    for itemId, qty in pairs(session.inventory) do
        if qty > 0 then
            local item = session.loader.getItem(itemId)
            if item then
                table.insert(inventoryItems, { item = item, qty = qty })
            end
        end
    end

    -- Sort inventory to prioritize items of this discipline's craftKind
    local discKind = disc and disc.kind or ""
    table.sort(inventoryItems, function(a, b)
        local aKind = a.item.meta and a.item.meta.craftKind or ""
        local bKind = b.item.meta and b.item.meta.craftKind or ""
        if aKind == discKind and bKind ~= discKind then return true
        elseif aKind ~= discKind and bKind == discKind then return false
        else return a.item.id < b.item.id end
    end)
end

-- ---------------------------------------------------------------------------
-- calcCraftYield(ctx) — called by CALC_CRAFT_YIELD handler in interpreter.lua
--
-- 1. Builds / refreshes the inventory list
-- 2. Resolves ingredient selections into item IDs
-- 3. Calculates yield / penalty / anomaly
-- 4. Determines outcome tier and builds the roulette pool
-- 5. Sets all results into ctx.v
-- ---------------------------------------------------------------------------
function crafting.calcCraftYield(ctx)
    if not ctx or not ctx.session then return end
    local v = ctx.v
    local session = ctx.session
    local loader = session.loader
    local config = getSceneConfig(ctx)

    -- 1. Resolve the craft scenario
    local disc = config.disciplines and config.disciplines[v.selectedDisciplineIdx or 1]
    if not disc then return end

    -- Refresh inventory list
    refreshInventoryList(disc, session)

    -- Track inventory count for modulo wrapping in up/down hooks
    v.invCount = #inventoryItems

    -- Track party count for crafter list wrapping (replaces hardcoded % 4)
    v.partyCount = ctx.party and #ctx.party or (session.party and #session.party or 4)

    -- 2. Resolve ingredient item IDs from cursor positions
    local function resolveItem(idx)
        local entry = inventoryItems[idx]
        return entry and entry.item or nil
    end

    local i1 = resolveItem(v.selectedIngredient1Idx)
    local i2 = resolveItem(v.selectedIngredient2Idx)

    if i1 then v.i1_item_id = i1.id else v.i1_item_id = 0 end
    if i2 then v.i2_item_id = i2.id else v.i2_item_id = 0 end

    -- If both slots aren't filled, no yield calculation yet
    if v.i1_item_id == 0 or v.i2_item_id == 0 then
        v.yieldScore = 0
        v.yieldAnomalyScore = 0
        v.isAnomaly = false
        return
    end

    -- 3. Get crafter
    local crafter = session.party[v.crafterIdx or 1]
    if not crafter then return end

    -- 4. Calculate yield
    local S = getBattlerStat(crafter, disc.stat, session)

    local mockCtx = {
        i1 = formula.itemView(i1),
        i2 = formula.itemView(i2),
        ingredient1 = formula.itemView(i1),
        ingredient2 = formula.itemView(i2),
        crafter = crafter,
        alpha = config.alpha or 0.5,
        S = S,
    }

    local _, Y = pcall(formula.eval, config.yieldFormula or "0", mockCtx)
    Y = math.floor(tonumber(Y) or 0)

    local _, penalty = pcall(formula.eval, config.penaltyFormula or "0", mockCtx)
    penalty = math.floor(tonumber(penalty) or 0)

    local Y_final = math.max(0, Y - penalty)

    local _, anomalyMult = pcall(formula.eval, config.anomalyFormula or "1.0", mockCtx)
    anomalyMult = tonumber(anomalyMult) or 1.0
    local isCrit = (anomalyMult > 1.0)

    local Y_anomaly = math.floor(Y_final * anomalyMult)

    -- 5. Determine outcome tier
    local brackets = config.brackets or {}
    local tier = 0
    local tierName = "Junk"
    for _, br in ipairs(brackets) do
        if Y_final <= br.max then
            tier = br.tier
            tierName = br.name
            break
        end
    end
    -- If no bracket matched, use the last one
    if tier == 0 and Y_final > 0 then
        local lastBr = brackets[#brackets]
        if lastBr and Y_final > lastBr.max then
            tier = lastBr.tier
            tierName = lastBr.name
        end
    end

    -- 6. Build outcome pool
    local finalScore = isCrit and Y_anomaly or Y_final
    local outcomeTier = 0
    for _, br in ipairs(brackets) do
        if finalScore <= br.max then
            outcomeTier = br.tier
            break
        end
    end
    if outcomeTier == 0 and finalScore > 0 then
        local lastBr = brackets[#brackets]
        if lastBr then outcomeTier = lastBr.tier end
    end

    local pool = {}
    for _, item in ipairs(loader.items or {}) do
        if item.meta and item.meta.craftKind == disc.kind and item.meta.tier == outcomeTier then
            table.insert(pool, item)
        end
    end
    -- Fallback to junk
    if #pool == 0 then
        for _, item in ipairs(loader.items or {}) do
            if item.meta and item.meta.craftKind == disc.kind and item.meta.tier == 0 then
                table.insert(pool, item)
            end
        end
    end

    -- 7. Store results in ctx.v
    v.yieldScore = Y_final
    v.yieldAnomalyScore = Y_anomaly
    v.penaltyValue = penalty
    v.isAnomaly = isCrit
    v.outcomeTier = outcomeTier
    v.outcomeTierName = tierName
    v.i1Name = i1 and i1.name or ""
    v.i2Name = i2 and i2.name or ""
    v.crafterName = crafter and crafter.actorData.name or ""
    v.elementConflict = (i1 and i2 and i1.meta and i2.meta
        and i1.meta.craftElement and i2.meta.craftElement
        and i1.meta.craftElement ~= "" and i2.meta.craftElement ~= ""
        and i1.meta.craftElement ~= i2.meta.craftElement)

    -- Roulette pool, published as v.pool for the "v:pool" list source
    v.poolTargetIdx = v.poolTargetIdx or 0
    if #pool > 0 then
        v.poolSize = #pool
        -- On first entry (target not yet picked), randomize target
        if v.poolTargetIdx == 0 then
            v.poolTargetIdx = math.random(#pool)
        end
        v.poolCurrentIdx = math.random(#pool)
        local targetItem = pool[v.poolTargetIdx]
        v.resultItemId = targetItem and targetItem.id or 0
        v.resultItemName = targetItem and targetItem.name or ""
        v.pool = {}
        for _, pitem in ipairs(pool) do
            table.insert(v.pool, { name = pitem.name or "", icon = pitem.icon or 0 })
        end
    else
        v.poolSize = 0
        v.poolCurrentIdx = 0
        v.resultItemId = 0
        v.resultItemName = ""
        v.pool = {}
    end

    -- 8. Roulette completion logic (state 5 only)
    if v.state == 5 then
        local timing = config.timing or {}
        local steps = timing.steps or 200
        v.rouletteStep = (v.rouletteStep or 0) + 1

        if v.rouletteStep >= steps then
            -- Consume ingredients and grant result
            local i1Item = session.loader.getItem(v.i1_item_id or 0)
            local i2Item = session.loader.getItem(v.i2_item_id or 0)
            local resultItem = pool[v.poolTargetIdx or 1]

            if i1Item and session:hasItem(i1Item.id, 1) then
                session:addItem(i1Item.id, -1)
            end
            if i2Item and session:hasItem(i2Item.id, 1) then
                session:addItem(i2Item.id, -1)
            end
            if resultItem then
                session:addItem(resultItem.id, 1)
            end

            -- Emit text event
            table.insert(ctx.events or {}, {
                type = "text",
                text = "Crafted " .. (v.resultItemName or "") .. "!"
            })

            v.state = 6
            v.rouletteStep = 0
        else
            -- Animate: compute next delay
            local delay = v.rouletteDelay or timing.initialDelay or 0.05
            v.rouletteDelay = math.min(
                delay * (timing.delayMult or 1.25),
                timing.maxDelay or 10
            )
        end
    end
end

-- ---------------------------------------------------------------------------
-- Legacy drawing (superseded by the generic window renderer; the crafting
-- scene opts in with "draw": "windows" in scenes.json). Kept callable until
-- D13 phase 2 deletes this module; main.lua no longer routes here.
-- ---------------------------------------------------------------------------
function drawCraftingScene()
    local stateObj = require("engine.scene_host").getCurrentState()
    local v = stateObj and stateObj.v or {}

    local config = getSceneConfig()
    local term = config.terms or {}

    -- Title Header
    ui.drawPanel(0, 0, ui.toPx(32), ui.toPx(3.5), term.title or "Item Creation")

    local sv = v.state or 1

    if sv == 1 then -- Select Discipline
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(12), ui.toPx(20.5), term.selectDiscipline or "Select Discipline:")
        local disciplines = config.disciplines or {}
        local selIdx = v.selectedDisciplineIdx or 1
        for i, d in ipairs(disciplines) do
            local isSel = (i == selIdx)
            local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = isSel and ">" or " "
            ui.drawString(prefix .. d.label, ui.toPx(0.5), ui.toPx(5.5) + (i - 1) * ui.lineHeight, color)
        end
        -- Details panel
        local activeDisc = disciplines[selIdx]
        if activeDisc then
            ui.drawPanel(ui.toPx(12), ui.toPx(3.5), ui.toPx(20), ui.toPx(20.5), "Details")
            ui.drawString("Governing Stat: " .. string.upper(activeDisc.stat), ui.toPx(12.5), ui.toPx(5.5), {1, 0.9, 0.3, 1})
            ui.drawString(activeDisc.description or "", ui.toPx(12.5), ui.toPx(7.5), {1, 1, 1, 1}, "left", ui.toPx(19))
        end

    elseif sv == 2 then -- Select Crafter
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(12), ui.toPx(20.5), term.selectCrafter or "Select Crafter:")
        local party = activeSession and activeSession.party or {}
        local selIdx = v.selectedCrafterIdx or 1
        for i, member in ipairs(party) do
            local isSel = (i == selIdx)
            local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
            local prefix = isSel and ">" or " "
            ui.drawString(prefix .. member.actorData.name, ui.toPx(0.5), ui.toPx(5.5) + (i - 1) * ui.lineHeight, color)
        end
        -- Crafter stats panel
        local activeMember = activeSession and activeSession.party[selIdx]
        if activeMember then
            local disc = getDiscipline()
            local S = getBattlerStat(activeMember, disc and disc.stat or "atk", activeSession)
            ui.drawPanel(ui.toPx(12), ui.toPx(3.5), ui.toPx(20), ui.toPx(20.5), "Crafter Stats")
            if activeMember.actorData.spriteKey then
                local imgPath = "assets/portraits/" .. activeMember.actorData.spriteKey .. ".png"
                if love.filesystem.getInfo(imgPath) then
                    local img = love.graphics.newImage(imgPath)
                    img:setFilter("nearest", "nearest")
                    love.graphics.draw(img, ui.toPx(13), ui.toPx(5.5), 0, 1, 1)
                end
            end
            ui.drawString(activeMember.actorData.name, ui.toPx(20), ui.toPx(5.5), {1, 1, 0.5, 1})
            ui.drawString("Level: " .. activeMember.level, ui.toPx(20), ui.toPx(7.5))
            ui.drawString(string.upper(disc and disc.stat or "ATK") .. ": " .. S, ui.toPx(20), ui.toPx(9.5), {1, 0.9, 0.3, 1})
        end

    elseif sv == 3 then -- Select Ingredients
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(32), ui.toPx(5), term.selectIngredients or "Select Ingredients:")
        local cursorSlot = v.cursorSlot or 1
        local i1Id = v.i1_item_id or 0
        local i2Id = v.i2_item_id or 0
        local i1Name = (i1Id > 0) and (v.i1Name or "") or "--- [Empty] ---"
        local i2Name = (i2Id > 0) and (v.i2Name or "") or "--- [Empty] ---"
        local colorI1 = (cursorSlot == 1) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local colorI2 = (cursorSlot == 2) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        ui.drawString("Slot 1: " .. i1Name, ui.toPx(1), ui.toPx(5.5), colorI1)
        ui.drawString("Slot 2: " .. i2Name, ui.toPx(16), ui.toPx(5.5), colorI2)

        ui.drawPanel(0, ui.toPx(8.5), ui.toPx(20), ui.toPx(15.5), "Inventory")
        local disc = getDiscipline()
        local scrollIdx = (cursorSlot == 1) and (v.selectedIngredient1Idx or 1) or (v.selectedIngredient2Idx or 1)

        if #inventoryItems == 0 then
            ui.drawString("No items in inventory.", ui.toPx(1), ui.toPx(10), {0.6, 0.6, 0.6, 1})
        else
            local startOffset = math.max(1, scrollIdx - 3)
            local endOffset = math.min(#inventoryItems, startOffset + 5)
            for i = startOffset, endOffset do
                local entry = inventoryItems[i]
                local isSel = (i == scrollIdx)
                local color = isSel and {1, 1, 0.5, 1} or {1, 1, 1, 1}
                local matchColor = color
                if entry.item.meta and entry.item.meta.craftKind == (disc and disc.kind or "") then
                    if not isSel then matchColor = {0.6, 1, 0.6, 1} end
                end
                ui.drawString((isSel and ">" or " "), ui.toPx(0.5), ui.toPx(10.5) + (i - startOffset) * ui.lineHeight, color)
                ui.drawIcon(entry.item.icon or 0, ui.toPx(1.5), ui.toPx(10.5) + (i - startOffset) * ui.lineHeight - 2)
                ui.drawString(entry.item.name .. " (x" .. entry.qty .. ")", ui.toPx(3.5), ui.toPx(10.5) + (i - startOffset) * ui.lineHeight, matchColor)
            end
        end
        -- Item details
        local selectedEntry = inventoryItems[scrollIdx]
        if selectedEntry then
            ui.drawPanel(ui.toPx(20), ui.toPx(8.5), ui.toPx(12), ui.toPx(15.5), "Item Info")
            local item = selectedEntry.item
            ui.drawString(item.name, ui.toPx(20.5), ui.toPx(10.5), {1, 1, 0.5, 1})
            if item.meta then
                if item.meta.tier then ui.drawString("Tier: " .. item.meta.tier, ui.toPx(20.5), ui.toPx(12.5)) end
                if item.meta.potency then ui.drawString("Potency: " .. item.meta.potency, ui.toPx(20.5), ui.toPx(14.5), {1, 0.9, 0.3, 1}) end
                if item.meta.craftElement then ui.drawString("Element: " .. item.meta.craftElement, ui.toPx(20.5), ui.toPx(16.5)) end
            else
                ui.drawString("No meta parameters.", ui.toPx(20.5), ui.toPx(12.5), {0.6, 0.6, 0.6, 1})
            end
        end

    elseif sv == 4 then -- Confirm Craft
        ui.drawPanel(0, ui.toPx(3.5), ui.toPx(32), ui.toPx(20.5), "Confirm Crafting")
        ui.drawString("Crafter: " .. (v.crafterName or ""), ui.toPx(2), ui.toPx(5.5), {1, 1, 0.5, 1})
        ui.drawString("Ingredient 1: " .. (v.i1Name or ""), ui.toPx(2), ui.toPx(7.5))
        ui.drawString("Ingredient 2: " .. (v.i2Name or ""), ui.toPx(2), ui.toPx(9.5))
        local score = v.yieldScore or 0
        ui.drawString(term.yieldText:gsub("{0}", tostring(score)), ui.toPx(2), ui.toPx(12.5), {1, 0.9, 0.3, 1})
        ui.drawString("Expected Tier: " .. (v.outcomeTierName or "Junk"), ui.toPx(2), ui.toPx(14.5))
        if v.elementConflict then
            ui.drawString("WARNING: Element conflict!", ui.toPx(2), ui.toPx(16.5), {1, 0.3, 0.3, 1})
        end
        local confirmIdx = v.confirmOptionIdx or 1
        local colC = (confirmIdx == 1) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        local colB = (confirmIdx == 2) and {1, 1, 0.5, 1} or {1, 1, 1, 1}
        ui.drawString((confirmIdx == 1 and "> Craft" or "  Craft"), ui.toPx(6), ui.toPx(19.5), colC)
        ui.drawString((confirmIdx == 2 and "> Back" or "  Back"), ui.toPx(18), ui.toPx(19.5), colB)

    elseif sv == 5 then -- Roulette Animation
        ui.drawPanel(ui.toPx(4), ui.toPx(7), ui.toPx(24), ui.toPx(10), "Crafting...")
        local poolSize = v.poolSize or 0
        local currentIdx = v.poolCurrentIdx or 1
        if poolSize > 0 and currentIdx >= 1 and currentIdx <= poolSize then
            local icon = v["poolIcon" .. currentIdx] or 0
            local name = v["poolName" .. currentIdx] or ""
            love.graphics.setColor(1, 1, 0.5, 0.5 + 0.5 * math.sin(love.timer.getTime() * 15))
            love.graphics.rectangle("line", ui.toPx(14.5) - 4, ui.toPx(10) - 4, 20, 20)
            love.graphics.setColor(1, 1, 1, 1)
            ui.drawIcon(icon, ui.toPx(15), ui.toPx(10.5))
            ui.drawString(name, ui.toPx(4), ui.toPx(13.5), {1, 1, 0.5, 1}, "center", ui.toPx(24))
        end

    elseif sv == 6 then -- Result Screen
        ui.drawPanel(ui.toPx(4), ui.toPx(6), ui.toPx(24), ui.toPx(12), "Crafting Success!")
        local resultName = v.resultItemName or ""
        if resultName ~= "" then
            ui.drawString(term.resultText:gsub("{0}", resultName), ui.toPx(4), ui.toPx(11.5), {1, 1, 0.5, 1}, "center", ui.toPx(24))
        end
        if v.isAnomaly then
            ui.drawString(term.anomalyText or "CRITICAL ANOMALY!", ui.toPx(4), ui.toPx(15.5), {1, 0.3, 0.3, 1}, "center", ui.toPx(24))
        end
    end
end

-- Legacy fallback stubs (called only when hooks are absent)
-- All logic now lives in hooks; these remain as no-ops for safety.
function initCraftingScene() end
function updateCraftingScene(dt) end
function keypressedCraftingScene(key) end

return crafting
