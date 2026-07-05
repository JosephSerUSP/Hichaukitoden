local loader = require("data.loader")
local session = require("engine.session")
local exploration = require("engine.exploration")
local battleSystem = require("engine.battle")
local director = require("engine.director")
local renderer = require("presentation.renderer")
local traits = require("engine.traits")
local viewport_3d = require("presentation.viewport_3d")

-- Game resolution dimensions
local gameWidth, gameHeight = 256, 240
local canvas
local scale, scaleX, scaleY = 1, 1, 1

-- Global Session and State Router
local activeSession
local currentScene = "title"
local isTestBattle = false
local triggerTestBattle

-- Scene States Cache
local townSelectedIdx = 1

-- Battle State
local activeBattle
local battleCombatLog = {}
local battleCombatState = "input" -- "input" or "log"
local battleSelectedIndex = 1
local battleSpellSelect = false
local battleEventsQueue = {}
local battleEventQueueIndex = 1

-- Dialogue State
local activeWalker
local dialogueSelectIdx = 1

-- Shop State
local activeShopId = ""
local shopItems = {}
local shopSelectedIdx = 1

-- Menu State
local previousSceneBeforeMenu = "town"
local menuSelectedIdx = 1
local menuActiveCol = 1 -- 1 = Left menu column, 2 = Right panel details
local menuSubScene = "main"
local menuSelectedSubIdx = 1
local selectedItemIdToUse = nil
local selectedCreatureIndex = 1
local selectedSlotIndex = 1
statusInspectMode = false
statusInspectIdx = 1

local inputCooldown = 0

-- Interactive Battle Input variables
local battleLivingMembers = {}
local battleActiveMemberIndex = 1
local battleCollectedActions = {}

local server = require("engine.server")

function love.load(arg)
    print("--------------------------------------------------")
    print("HICHAUKITODEN GAME LOADED (WITH INPUT COOLDOWN FIX)")
    print("--------------------------------------------------")
    
    -- Check for test battle CLI argument
    if arg then
        for _, val in ipairs(arg) do
            if val == "test-battle" then
                isTestBattle = true
            end
        end
    end
    
    love.graphics.setDefaultFilter("nearest", "nearest")
    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    love.resize(love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Initialize database loader
    loader.init()
    
    -- Initialize activeSession
    activeSession = session.GameSession.new(loader)
    activeSession:initializeStartingParty()
    
    -- Initialize renderer graphics
    renderer.init(activeSession)
    
    -- Initialize 3D viewport textures
    viewport_3d.init()
    
    -- Start developer server
    server.start()
    
    -- If in test battle mode, launch immediately into battle
    if isTestBattle then
        triggerTestBattle()
    end
end

function love.update(dt)
    renderer.update(dt)
    server.update(dt)
    if activeSession and activeSession.transitionTimer and activeSession.transitionTimer > 0 then
        activeSession.transitionTimer = activeSession.transitionTimer - dt
    end
    
    if inputCooldown > 0 then
        inputCooldown = inputCooldown - dt
    end
    
    -- Exiting scene transition (slide-out animation)
    if renderer.closing then
        renderer.closingTimer = renderer.closingTimer - dt
        if renderer.closingTimer <= 0 then
            renderer.closing = false
            currentScene = renderer.closingTargetScene
            if renderer.closingTargetSubScene ~= "" then
                menuSubScene = renderer.closingTargetSubScene
            end
            renderer.resetMenuTimer()
            inputCooldown = 0.30
        end
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1) -- reset color at start of frame
    
    if currentScene == "title" then
        renderer.drawTitle()
    elseif currentScene == "town" then
        renderer.drawTown(townSelectedIdx)
    elseif currentScene == "map" then
        renderer.drawMap()
    elseif currentScene == "dialogue" then
        renderer.drawDialogue(activeWalker, dialogueSelectIdx)
    elseif currentScene == "battle" then
        renderer.drawBattle(activeBattle, battleCombatLog, battleCombatState, battleSelectedIndex, battleSpellSelect, battleLivingMembers, battleActiveMemberIndex)
    elseif currentScene == "shop" then
        renderer.drawShop(activeShopId, shopSelectedIdx, shopItems)
    elseif currentScene == "menu" then
        if previousSceneBeforeMenu == "town" then
            renderer.drawTown(townSelectedIdx)
        else
            renderer.drawMap()
        end
        if menuSubScene == "use_target" then
            renderer.drawTargetSelector(menuSelectedSubIdx, activeSession)
        elseif menuSubScene == "equip_passive" then
            renderer.drawEquipMenu(activeSession.party[selectedCreatureIndex], menuSelectedSubIdx, activeSession)
        elseif menuSubScene == "select_passive" then
            local slotType = (selectedSlotIndex == 1) and "Weapon" or (selectedSlotIndex == 2 and "Armor" or "Accessory")
            renderer.drawSelectEquipMenu(menuSelectedSubIdx, activeSession, slotType, activeSession.party[selectedCreatureIndex], selectedSlotIndex)
        else
            renderer.drawMainMenu(menuSelectedIdx, menuActiveCol, menuSelectedSubIdx, activeSession, menuSubScene)
        end
    end
    
    if server.isActive() then
        love.graphics.setColor(0.1, 0.4, 0.8, 0.8)
        love.graphics.rectangle("fill", 216, 2, 38, 9)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("DEV ON", 219, 3)
    end
    
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1) -- reset color before drawing canvas to prevent dark tinting leak
    love.graphics.draw(canvas, scaleX, scaleY, 0, scale, scale)
end

local handleDialogueAction -- forward declaration

local function isSafeMap()
    if activeSession and activeSession.currentMapData then
        return activeSession.currentMapData.safe == true
    end
    return true
end

local function openShop(shopId)
    activeShopId = shopId
    shopItems = {}
    shopSelectedIdx = 1
    
    local shopData = loader.shops[shopId]
    if shopData and shopData.items then
        for _, shopItem in ipairs(shopData.items) do
            local allowed = true
            if shopItem.condition then
                local cond = shopItem.condition
                if cond:match("^level:(%d+)") then
                    local lvl = tonumber(cond:match("^level:(%d+)"))
                    allowed = (activeSession.summoner.level >= lvl)
                elseif cond:match("^flag:(.+)") then
                    local flag = cond:match("^flag:(.+)")
                    allowed = (activeSession.flags[flag] == true)
                elseif cond:match("^gold:(%d+)") then
                    local gold = tonumber(cond:match("^gold:(%d+)"))
                    allowed = (activeSession.gold >= gold)
                end
            end
            
            if allowed then
                local itemData = loader.getItem(shopItem.id)
                if itemData then
                    table.insert(shopItems, itemData)
                end
            end
        end
    end
    currentScene = "shop"
end

handleDialogueAction = function()
    local node = activeWalker:getCurrentNode()
    if not node then return end
    
    if node.type == "ACTION" then
        if node.action == "OPEN_SHOP" then
            openShop(node.shopId)
        elseif node.action == "OFFER_QUEST" then
            activeSession.flags["quest:" .. node.questId .. ":active"] = true
            activeWalker:goToNode(node.acceptNode or node.next)
            handleDialogueAction()
        elseif node.action == "COMPLETE_QUEST" then
            activeSession.flags["quest:" .. node.questId .. ":active"] = nil
            activeSession.flags["quest:" .. node.questId .. ":completed"] = true
            if node.takeItem then
                activeSession:addItem(node.takeItem, -1)
            end
            activeWalker:goToNode(node.completeNode or node.next)
            handleDialogueAction()
        elseif node.action == "DESCEND_FLOOR" then
            activeSession.dungeonFloor = activeSession.dungeonFloor + 1
            if activeSession.dungeonFloor > 5 then
                activeSession.dungeonFloor = 5
            end
            exploration.loadMap(activeSession, activeSession.dungeonFloor + 1)
            currentScene = "map"
        elseif node.action == "START_BATTLE" then
            triggerBattle()
        elseif node.action == "GIVE_ITEM_ACTION" then
            local loot = "hp_tonic"
            if activeSession.currentMapData.treasures and #activeSession.currentMapData.treasures > 0 then
                loot = activeSession.currentMapData.treasures[math.random(#activeSession.currentMapData.treasures)]
            end
            local item = loader.getItem(loot)
            activeSession:addItem(loot, 1)
            
            node.type = "TEXT"
            node.content = "Found a " .. (item and item.name or loot) .. "!"
            node.action = nil
        elseif node.action == "CALL_COMMON_EVENT_ACTION" then
            local ce = loader.commonEvents and loader.commonEvents[tostring(node.commonEventId)]
            if ce and ce.commands then
                local nextNodeName = node.next
                -- Build and inject sub-nodes into current walker graph dynamically
                local timeStr = tostring(os.clock()):gsub("%.", "_")
                local firstCeNode = "ce_" .. node.commonEventId .. "_" .. timeStr .. "_1"
                for idx, ceCmd in ipairs(ce.commands) do
                    local nodeId = "ce_" .. node.commonEventId .. "_" .. timeStr .. "_" .. idx
                    local nextId = (idx < #ce.commands) and ("ce_" .. node.commonEventId .. "_" .. timeStr .. "_" .. (idx + 1)) or nextNodeName
                    
                    if ceCmd.type == "TEXT" then
                        activeWalker.graph.nodes[nodeId] = {
                            type = "TEXT",
                            content = ceCmd.text,
                            next = nextId
                        }
                    elseif ceCmd.type == "RECOVER_PARTY" then
                        activeWalker.graph.nodes[nodeId] = {
                            type = "ACTION",
                            action = "RECOVER_PARTY_ACTION",
                            next = nextId
                        }
                    elseif ceCmd.type == "DESCEND" then
                        activeWalker.graph.nodes[nodeId] = {
                            type = "TEXT",
                            content = "You descend deeper into the chasm...",
                            next = "ce_descend_" .. timeStr .. "_" .. idx
                        }
                        activeWalker.graph.nodes["ce_descend_" .. timeStr .. "_" .. idx] = {
                            type = "ACTION",
                            action = "DESCEND_FLOOR",
                            next = nil
                        }
                    elseif ceCmd.type == "BATTLE" then
                        activeWalker.graph.nodes[nodeId] = {
                            type = "ACTION",
                            action = "START_BATTLE",
                            next = nil
                        }
                    elseif ceCmd.type == "GIVE_ITEM" then
                        activeWalker.graph.nodes[nodeId] = {
                            type = "ACTION",
                            action = "GIVE_ITEM_ACTION",
                            next = nextId
                        }
                    elseif ceCmd.type == "CALL_COMMON_EVENT" then
                        activeWalker.graph.nodes[nodeId] = {
                            type = "ACTION",
                            action = "CALL_COMMON_EVENT_ACTION",
                            commonEventId = ceCmd.commonEventId,
                            next = nextId
                        }
                    end
                end
                
                activeWalker:goToNode(firstCeNode)
                handleDialogueAction()
            else
                activeWalker:advance()
                handleDialogueAction()
            end
        elseif node.action == "RECOVER_PARTY_ACTION" then
            activeSession.mp = activeSession.maxMp
            for _, c in ipairs(activeSession.party) do
                c.hp = c:getMaxHp(activeSession)
                c:removeState("dead")
            end
            activeSession.summoner.hp = activeSession.summoner:getMaxHp(activeSession)
            activeSession.summoner:removeState("dead")
            
            node.type = "TEXT"
            node.content = "Your party has been fully recovered!"
            node.action = nil
        else
            activeWalker:advance()
            handleDialogueAction()
        end
    end
end

-- Translates JSON command lists to dynamic conversation graphs
local function runEventCommands(eventTitle, commands)
    if not commands or #commands == 0 then return end
    
    local nodes = {}
    local startNode = "node_1"
    
    for i, cmd in ipairs(commands) do
        local nodeName = "node_" .. i
        local nextNode = (i < #commands) and ("node_" .. (i + 1)) or nil
        
        if cmd.type == "TEXT" then
            nodes[nodeName] = {
                type = "TEXT",
                content = cmd.text,
                next = nextNode
            }
        elseif cmd.type == "CHOICE" then
            local options = {}
            for _, opt in ipairs(cmd.options) do
                table.insert(options, {
                    label = opt.label,
                    script = opt.script
                })
            end
            nodes[nodeName] = {
                type = "CHOICE",
                options = options,
                next = nextNode
            }
        elseif cmd.type == "RECOVER_PARTY" then
            activeSession.mp = activeSession.maxMp
            for _, c in ipairs(activeSession.party) do
                c.hp = c:getMaxHp(activeSession)
                c:removeState("dead")
            end
            activeSession.summoner.hp = activeSession.summoner:getMaxHp(activeSession)
            activeSession.summoner:removeState("dead")
            
            nodes[nodeName] = {
                type = "TEXT",
                content = "Your party has been fully recovered!",
                next = nextNode
            }
        elseif cmd.type == "DESCEND" then
            nodes[nodeName] = {
                type = "TEXT",
                content = "You descend deeper into the chasm...",
                next = "descend_action"
            }
            nodes["descend_action"] = {
                type = "ACTION",
                action = "DESCEND_FLOOR",
                next = nil
            }
        elseif cmd.type == "BATTLE" then
            nodes[nodeName] = {
                type = "ACTION",
                action = "START_BATTLE",
                next = nil
            }
        elseif cmd.type == "GIVE_ITEM" then
            nodes[nodeName] = {
                type = "ACTION",
                action = "GIVE_ITEM_ACTION",
                next = nextNode
            }
        elseif cmd.type == "CALL_COMMON_EVENT" then
            nodes[nodeName] = {
                type = "ACTION",
                action = "CALL_COMMON_EVENT_ACTION",
                commonEventId = cmd.commonEventId,
                next = nextNode
            }
        end
    end
    
    local graph = {
        initialNode = startNode,
        name = eventTitle,
        nodes = nodes
    }
    
    activeWalker = director.GraphWalker.new(activeSession, graph)
    activeWalker.eventName = eventTitle
    currentScene = "dialogue"
    handleDialogueAction()
end

local function checkStepEvents()
    local px, py = activeSession.playerX - 1, activeSession.playerY - 1
    if activeSession.currentMapData.events then
        for _, ev in ipairs(activeSession.currentMapData.events) do
            if ev.x == px and ev.y == py and ev.trigger == "step" then
                local commands = nil
                if ev.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = ev.script
                end
                
                if commands then
                    runEventCommands(ev.name or "Event", commands)
                    return true
                end
            end
        end
    end
    return false
end

-- Triggers a conversation graph
local function triggerDialogue(graphName)
    local walker = director.startConversation(activeSession, graphName)
    if walker then
        activeWalker = walker
        dialogueSelectIdx = 1
        currentScene = "dialogue"
        handleDialogueAction()
    end
end

local function triggerBattle()
    local mapData = activeSession.currentMapData
    local possibleEnemies = mapData.encounters
    if not possibleEnemies or #possibleEnemies == 0 then return end
    
    local enemyList = {}
    local numEnemies = math.random(1, 3)
    
    for i = 1, numEnemies do
        local totalWeight = 0
        for _, enemyOpt in ipairs(possibleEnemies) do
            totalWeight = totalWeight + enemyOpt.weight
        end
        local roll = math.random(totalWeight)
        local sum = 0
        local enemyId = possibleEnemies[1].id
        for _, enemyOpt in ipairs(possibleEnemies) do
            sum = sum + enemyOpt.weight
            if roll <= sum then
                enemyId = enemyOpt.id
                break
            end
        end
        
        local enemyData = loader.getActor(enemyId)
        if enemyData then
            local enemyBattler = session.Battler.new(enemyData, enemyData.level or activeSession.dungeonFloor)
            enemyBattler.hp = enemyBattler:getMaxHp(activeSession)
            table.insert(enemyList, enemyBattler)
        end
    end
    
    activeBattle = battleSystem.Battle.new(activeSession, enemyList)
    battleCombatLog = { "A hostile group blocks your path!" }
    battleEventsQueue = {}
    battleEventQueueIndex = 1
    battleCombatState = "input"
    battleSelectedIndex = 1
    battleSpellSelect = false
    
    battleLivingMembers = {}
    table.insert(battleLivingMembers, { type = "summoner", actor = activeSession.summoner, index = 1 })
    for i = 1, 4 do
        local c = activeSession.party[i]
        if c and not c:isDead() then
            table.insert(battleLivingMembers, { type = "monster", actor = c, index = i + 1 })
        end
    end
    battleActiveMemberIndex = 1
    battleCollectedActions = {}
    
    currentScene = "battle"
    renderer.initBattleAnims(enemyList)
end

triggerTestBattle = function()
    -- Initialize session if not initialized
    if not activeSession then
        activeSession = session.GameSession.new(loader)
        activeSession:initializeStartingParty()
    end
    
    -- Spawn mock enemies (use database entries if they exist, otherwise fall back to generic dummy data)
    local enemyList = {}
    local gData = loader.getActor("goblin") or { id = "enemy_1", name = "Test Target A", level = 1 }
    local b1 = session.Battler.new(gData, 1)
    b1.hp = b1:getMaxHp(activeSession)
    table.insert(enemyList, b1)
    
    local pData = loader.getActor("pixie") or { id = "enemy_2", name = "Test Target B", level = 1 }
    local b2 = session.Battler.new(pData, 1)
    b2.hp = b2:getMaxHp(activeSession)
    table.insert(enemyList, b2)
    
    activeBattle = battleSystem.Battle.new(activeSession, enemyList)
    battleCombatLog = { "--- BATTLE SCREEN TEST MODE ---", "Press SPACE or P to spawn damage popups!" }
    battleEventsQueue = {}
    battleEventQueueIndex = 1
    battleCombatState = "input"
    battleSelectedIndex = 1
    battleSpellSelect = false
    
    battleLivingMembers = {}
    table.insert(battleLivingMembers, { type = "summoner", actor = activeSession.summoner, index = 1 })
    for i = 1, 4 do
        local c = activeSession.party[i]
        if c and not c:isDead() then
            table.insert(battleLivingMembers, { type = "monster", actor = c, index = i + 1 })
        end
    end
    battleActiveMemberIndex = 1
    battleCollectedActions = {}
    
    currentScene = "battle"
    renderer.initBattleAnims(enemyList)
end

-- Map a battler to screen coordinates on the battle scene
local function getTargetCoords(target)
    if activeBattle then
        for idx, enemy in ipairs(activeBattle.enemies) do
            if enemy == target then
                local spacing = 220 / #activeBattle.enemies
                local ex = 18 + (idx - 1) * spacing
                return ex + 28, 60 -- Centered over the 56x56 enemy sprite
            end
        end
        
        local gridCoords = {
            { x = 130 + 27, y = 146 + 10 },
            { x = 192 + 27, y = 146 + 10 },
            { x = 130 + 27, y = 185 + 10 },
            { x = 192 + 27, y = 185 + 10 }
        }
        for idx, c in ipairs(activeSession.party) do
            if c == target then
                local slot = gridCoords[idx]
                if slot then return slot.x, slot.y end
            end
        end
        if target == activeSession.summoner then
            return 50, 196 + 10
        end
    end
    return 128, 70
end

-- Resolves combat rounds with dynamic state backup/restore for sequential action rendering
local function resolveBattleRound()
    local backups = {}
    for _, b in ipairs(activeBattle:getAllActiveBattlers()) do
        local stateCopy = {}
        for _, st in ipairs(b.states) do
            table.insert(stateCopy, { id = st.id, duration = st.duration, maxDuration = st.maxDuration })
        end
        backups[b] = {
            hp = b.hp,
            states = stateCopy
        }
    end
    local mpBackup = activeSession.mp

    local events = activeBattle:resolveRound(battleCollectedActions)

    -- Restore backup states immediately so the UI can apply changes step-by-step
    for b, bk in pairs(backups) do
        b.hp = bk.hp
        b.states = bk.states
    end
    activeSession.mp = mpBackup

    return events
end

-- Advances the combat logs queue by one event and formats it
local function advanceBattleLog()
    if battleEventQueueIndex <= #battleEventsQueue then
        local ev = battleEventsQueue[battleEventQueueIndex]
        battleEventQueueIndex = battleEventQueueIndex + 1
        
        local desc = ""
        local popupX, popupY = getTargetCoords(ev.target)
        
        if ev.type == "text" then
            desc = ev.text
        elseif ev.type == "action" then
            desc = ev.actor.name .. " uses " .. ev.skill.name .. " on " .. ev.target.name .. "!"
            if activeBattle then
                for idx, enemy in ipairs(activeBattle.enemies) do
                    if enemy == ev.actor then
                        renderer.triggerActionFlash(idx, "action")
                        break
                    end
                end
            end
        elseif ev.type == "damage" then
            desc = "- " .. ev.target.name .. " takes " .. ev.value .. " damage."
            renderer.addDamagePopup("-" .. ev.value, popupX, popupY, {1, 0.2, 0.2})
            -- Apply damage sequentially
            ev.target.hp = math.max(0, ev.target.hp - ev.value)
            if activeBattle then
                for idx, enemy in ipairs(activeBattle.enemies) do
                    if enemy == ev.target then
                        renderer.triggerActionFlash(idx, "damage")
                        break
                    end
                end
            end
        elseif ev.type == "heal" then
            desc = "- " .. ev.target.name .. " recovers " .. ev.value .. " HP."
            renderer.addDamagePopup("+" .. ev.value, popupX, popupY, {0.2, 1, 0.2})
            -- Apply heal sequentially
            ev.target.hp = math.min(ev.target:getMaxHp(activeSession), ev.target.hp + ev.value)
        elseif ev.type == "death" then
            desc = "! " .. ev.target.name .. " has fallen!"
            renderer.addDamagePopup("DEAD", popupX, popupY, {0.6, 0.6, 0.6})
            -- Apply death state sequentially
            ev.target:addState("dead")
            ev.target.hp = 0
            -- Trigger death animation if enemy
            if activeBattle then
                for idx, enemy in ipairs(activeBattle.enemies) do
                    if enemy == ev.target then
                        renderer.triggerDeathAnim(idx)
                        break
                    end
                end
            end
        elseif ev.type == "state_add" then
            desc = "- " .. ev.target.name .. " got " .. ev.state:upper() .. " status."
            renderer.addDamagePopup(ev.state:upper(), popupX, popupY, {0.8, 0.4, 1.0})
            -- Apply state add sequentially
            ev.target:addState(ev.state)
        elseif ev.type == "state_remove" then
            desc = "- " .. ev.target.name .. "'s " .. ev.state:upper() .. " wore off."
            -- Apply state removal sequentially
            ev.target:removeState(ev.state)
        elseif ev.type == "mp_drain" then
            desc = "- " .. ev.actor.name .. " consumes " .. ev.value .. " MP."
            -- Apply MP drain sequentially
            activeSession.mp = math.max(0, activeSession.mp - ev.value)
        elseif ev.type == "victory" then
            desc = "Victory! All hostile forces vanquished."
        elseif ev.type == "defeat" then
            desc = "Defeat! The party has fallen in battle..."
        elseif ev.type == "flee_success" then
            desc = "Escaped successfully!"
        end
        
        if desc ~= "" then
            table.insert(battleCombatLog, desc)
        else
            advanceBattleLog() -- skip empty and try next
        end
    end
end

-- Action handling for key presses
local function handleKeyPressed(key)
    if renderer.closing then return end
    if key == "escape" then
        if currentScene == "title" then
            love.event.quit()
        elseif currentScene == "town" or currentScene == "map" then
            -- Open Main Menu instead of exiting!
            previousSceneBeforeMenu = currentScene
            menuSelectedIdx = 1
            menuSubScene = "main"
            renderer.resetMenuTimer()
            currentScene = "menu"
            return
        elseif currentScene == "menu" then
            if menuSubScene == "use_target" then
                menuSubScene = "main"
                menuActiveCol = 2
            elseif menuActiveCol == 2 then
                menuActiveCol = 1
                menuSelectedSubIdx = 1
            else
                renderer.startClosing("menu", previousSceneBeforeMenu)
            end
            return
        elseif currentScene == "dialogue" then
            currentScene = "map"
            return
        end
    end
    
    if currentScene == "title" then
        if key == "return" or key == "space" then
            -- Initialize session if not exists
            if not activeSession then
                activeSession = session.GameSession.new(loader)
                activeSession:initializeStartingParty()
            end
            exploration.loadMap(activeSession, 1) -- Load Town Map (mapIdx = 1)
            currentScene = "map"
        end
        
    elseif currentScene == "town" then
        if key == "up" or key == "w" then
            townSelectedIdx = (townSelectedIdx - 2) % 4 + 1
        elseif key == "down" or key == "s" then
            townSelectedIdx = townSelectedIdx % 4 + 1
        elseif key == "return" or key == "space" then
            if townSelectedIdx == 1 then
                activeSession.dungeonFloor = 1
                exploration.loadMap(activeSession, 2)
                currentScene = "map"
            elseif townSelectedIdx == 2 then
                triggerDialogue("npc_weapon_shop")
            elseif townSelectedIdx == 3 then
                triggerDialogue("npc_alicia")
            elseif townSelectedIdx == 4 then
                activeSession.mp = activeSession.maxMp
                for _, actor in ipairs(activeSession.party) do
                    actor.hp = actor:getMaxHp(activeSession)
                    actor:removeState("dead")
                end
                activeSession.summoner.hp = activeSession.summoner:getMaxHp(activeSession)
                activeSession.summoner:removeState("dead")
                triggerDialogue("npc_drunkard")
            end
        end
        
    elseif currentScene == "map" then
        local moved = false
        if key == "up" or key == "w" then
            moved = exploration.moveForward(activeSession)
            if moved then
                activeSession.transitionTimer = 0.15
                activeSession.transitionDir = "forward"
            end
        elseif key == "down" or key == "s" then
            moved = exploration.moveBackward(activeSession)
            if moved then
                activeSession.transitionTimer = 0.15
                activeSession.transitionDir = "backward"
            end
        elseif key == "left" or key == "a" then
            exploration.turnLeft(activeSession)
            activeSession.transitionTimer = 0.15
            activeSession.transitionDir = "turn_left"
        elseif key == "right" or key == "d" then
            exploration.turnRight(activeSession)
            activeSession.transitionTimer = 0.15
            activeSession.transitionDir = "turn_right"
        elseif key == "q" then
            moved = exploration.strafeLeft(activeSession)
            if moved then
                activeSession.transitionTimer = 0.15
                activeSession.transitionDir = "strafe_left"
            end
        elseif key == "e" then
            moved = exploration.strafeRight(activeSession)
            if moved then
                activeSession.transitionTimer = 0.15
                activeSession.transitionDir = "strafe_right"
            end
        elseif key == "space" or key == "return" then
            local frontTile, tx, ty = exploration.getFrontTile(activeSession)
            
            -- Check for coordinate-based events from the map's JSON array
            local eventObj = nil
            if activeSession.currentMapData.events then
                for _, ev in ipairs(activeSession.currentMapData.events) do
                    if ev.x == tx - 1 and ev.y == ty - 1 then
                        eventObj = ev
                        break
                    end
                end
            end
            
            if eventObj and (eventObj.trigger == nil or eventObj.trigger == "interact") then
                local commands = nil
                if eventObj.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(eventObj.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = eventObj.script
                end
                
                if commands then
                    runEventCommands(eventObj.name or "Event", commands)
                end
            end
        end
        
        if moved then
            local triggered = checkStepEvents()
            if not triggered and not isSafeMap() then
                if math.random() < 0.10 then
                    triggerBattle()
                end
            end
        end
        
    elseif currentScene == "dialogue" then
        local node = activeWalker:getCurrentNode()
        if node then
            if node.type == "TEXT" then
                if key == "space" or key == "return" then
                    activeWalker:advance()
                    dialogueSelectIdx = 1
                    handleDialogueAction()
                    if not activeWalker:getCurrentNode() then
                        currentScene = "map"
                    end
                end
            elseif node.type == "CHOICE" then
                if key == "up" or key == "w" then
                    dialogueSelectIdx = (dialogueSelectIdx - 2) % #node.options + 1
                elseif key == "down" or key == "s" then
                    dialogueSelectIdx = dialogueSelectIdx % #node.options + 1
                elseif key == "space" or key == "return" then
                    activeWalker:selectChoice(dialogueSelectIdx)
                    dialogueSelectIdx = 1
                    handleDialogueAction()
                    if not activeWalker:getCurrentNode() then
                        currentScene = "map"
                    end
                end
            end
        end
        
    elseif currentScene == "menu" then
        if menuSubScene == "main" then
            if key == "up" or key == "w" then
                menuSelectedIdx = (menuSelectedIdx - 2) % 4 + 1
            elseif key == "down" or key == "s" then
                menuSelectedIdx = menuSelectedIdx % 4 + 1
            elseif key == "space" or key == "return" then
                if menuSelectedIdx == 1 then -- ITEMS
                    menuSubScene = "items_list"
                    menuSelectedSubIdx = 1
                elseif menuSelectedIdx == 2 or menuSelectedIdx == 3 then -- STATUS or EQUIP
                    menuSubScene = "party_select"
                    menuSelectedSubIdx = 1
                elseif menuSelectedIdx == 4 then -- EXIT
                    menuSubScene = "exit_confirm"
                    menuSelectedSubIdx = 2 -- Default to NO
                end
            end
            
        elseif menuSubScene == "party_select" then
            -- 2x2 grid navigation inputs for selecting creatures in the party
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 3) % 4 + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = (menuSelectedSubIdx + 1) % 4 + 1
            elseif key == "left" or key == "a" then
                if menuSelectedSubIdx == 2 then menuSelectedSubIdx = 1
                elseif menuSelectedSubIdx == 4 then menuSelectedSubIdx = 3
                end
            elseif key == "right" or key == "d" then
                if menuSelectedSubIdx == 1 then menuSelectedSubIdx = 2
                elseif menuSelectedSubIdx == 3 then menuSelectedSubIdx = 4
                end
            elseif key == "escape" then
                menuSubScene = "main"
                menuSelectedSubIdx = 1
            elseif key == "space" or key == "return" then
                if activeSession.party[menuSelectedSubIdx] then
                    selectedCreatureIndex = menuSelectedSubIdx
                    if menuSelectedIdx == 2 then
                        menuSubScene = "status_detail"
                        statusInspectMode = false
                        statusInspectIdx = 1
                    else
                        menuSubScene = "equip_passive"
                        menuSelectedSubIdx = 1
                    end
                end
            end
            
        elseif menuSubScene == "items_list" then
            local items = {}
            for itemId, qty in pairs(activeSession.inventory) do
                local item = loader.getItem(itemId)
                if item then table.insert(items, { item = item, qty = qty }) end
            end
            
            if key == "up" or key == "w" then
                if #items > 0 then
                    menuSelectedSubIdx = (menuSelectedSubIdx - 2) % #items + 1
                end
            elseif key == "down" or key == "s" then
                if #items > 0 then
                    menuSelectedSubIdx = menuSelectedSubIdx % #items + 1
                end
            elseif key == "escape" then
                renderer.startClosing("items_list", "menu", "main")
            elseif key == "space" or key == "return" then
                local selectedEntry = items[menuSelectedSubIdx]
                if selectedEntry then
                    selectedItemIdToUse = selectedEntry.item.id
                    if selectedItemIdToUse == "elixir_of_insight" then
                        -- Instantly use on the whole party
                        for _, c in ipairs(activeSession.party) do
                            c:gainExp(15, activeSession)
                        end
                        activeSession:addItem("elixir_of_insight", -1)
                        selectedItemIdToUse = nil
                    else
                        menuSubScene = "use_target"
                        menuSelectedSubIdx = 1
                    end
                end
            end
            
        elseif menuSubScene == "use_target" then
            -- 2x2 grid navigation inputs for item target selection
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 3) % 4 + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = (menuSelectedSubIdx + 1) % 4 + 1
            elseif key == "left" or key == "a" then
                if menuSelectedSubIdx == 2 then menuSelectedSubIdx = 1
                elseif menuSelectedSubIdx == 4 then menuSelectedSubIdx = 3
                end
            elseif key == "right" or key == "d" then
                if menuSelectedSubIdx == 1 then menuSelectedSubIdx = 2
                elseif menuSelectedSubIdx == 3 then menuSelectedSubIdx = 4
                end
            elseif key == "escape" then
                menuSubScene = "items_list"
                menuSelectedSubIdx = 1
                selectedItemIdToUse = nil
            elseif key == "space" or key == "return" then
                local target = activeSession.party[menuSelectedSubIdx]
                if target and selectedItemIdToUse then
                    if selectedItemIdToUse == "hp_tonic" then
                        target.hp = target:getMaxHp(activeSession)
                        activeSession:addItem("hp_tonic", -1)
                    elseif selectedItemIdToUse == "sigil_ink" then
                        target.paramPlus.maxHp = target.paramPlus.maxHp + 2
                        target.hp = math.min(target:getMaxHp(activeSession), target.hp + 2)
                        activeSession:addItem("sigil_ink", -1)
                    elseif selectedItemIdToUse == "whispered_lessons" then
                        target:gainExp(6, activeSession)
                        activeSession:addItem("whispered_lessons", -1)
                    end
                    menuSubScene = "items_list"
                    menuSelectedSubIdx = 1
                    selectedItemIdToUse = nil
                end
            end
            
        elseif menuSubScene == "equip_passive" then
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 2) % 3 + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = menuSelectedSubIdx % 3 + 1
            elseif key == "escape" then
                renderer.startClosing("equip_passive", "menu", "party_select")
            elseif key == "space" or key == "return" then
                selectedSlotIndex = menuSelectedSubIdx
                menuSubScene = "select_passive"
                menuSelectedSubIdx = 1
            end
            
        elseif menuSubScene == "select_passive" then
            local slotType = (selectedSlotIndex == 1) and "Weapon" or (selectedSlotIndex == 2 and "Armor" or "Accessory")
            local list = {}
            table.insert(list, { id = "empty", name = "[ UNEQUIP ]", description = "Unequip current gear." })
            for itemId, qty in pairs(activeSession.inventory) do
                local item = loader.getItem(itemId)
                if item and item.type == "equipment" and item.equipType == slotType then
                    table.insert(list, item)
                end
            end
            
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 2) % #list + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = menuSelectedSubIdx % #list + 1
            elseif key == "escape" then
                renderer.startClosing("select_passive", "menu", "equip_passive")
            elseif key == "space" or key == "return" then
                local choice = list[menuSelectedSubIdx]
                local targetCreature = activeSession.party[selectedCreatureIndex]
                if targetCreature and choice then
                    local prevItem = targetCreature.equipment[selectedSlotIndex]
                    if choice.id == "empty" then
                        if prevItem then
                            activeSession:addItem(prevItem.id, 1)
                        end
                        targetCreature.equipment[selectedSlotIndex] = nil
                    else
                        if prevItem then
                            activeSession:addItem(prevItem.id, 1)
                        end
                        targetCreature.equipment[selectedSlotIndex] = choice
                        activeSession:addItem(choice.id, -1)
                    end
                end
                menuSubScene = "equip_passive"
                menuSelectedSubIdx = selectedSlotIndex
            end
            
        elseif menuSubScene == "status_detail" then
            local c = activeSession.party[selectedCreatureIndex]
            local numPassives = c and #(c.actorData.passives or {}) or 0
            local numSkills = c and #(c.actorData.skills or {}) or 0
            local totalTraits = numPassives + numSkills
            
            if statusInspectMode then
                if key == "escape" or key == "space" or key == "return" then
                    statusInspectMode = false
                elseif key == "up" or key == "w" then
                    if totalTraits > 0 then
                        statusInspectIdx = (statusInspectIdx - 2) % totalTraits + 1
                    end
                elseif key == "down" or key == "s" then
                    if totalTraits > 0 then
                        statusInspectIdx = statusInspectIdx % totalTraits + 1
                    end
                end
            else
                if key == "escape" then
                    renderer.startClosing("status_detail", "menu", "party_select")
                elseif key == "space" or key == "return" or key == "tab" then
                    if totalTraits > 0 then
                        statusInspectMode = true
                        statusInspectIdx = 1
                    end
                elseif key == "left" or key == "a" or key == "up" or key == "w" then
                    local nextIdx = selectedCreatureIndex
                    repeat
                        nextIdx = (nextIdx - 2) % 4 + 1
                    until activeSession.party[nextIdx] or nextIdx == selectedCreatureIndex
                    selectedCreatureIndex = nextIdx
                elseif key == "right" or key == "d" or key == "down" or key == "s" then
                    local nextIdx = selectedCreatureIndex
                    repeat
                        nextIdx = nextIdx % 4 + 1
                    until activeSession.party[nextIdx] or nextIdx == selectedCreatureIndex
                    selectedCreatureIndex = nextIdx
                end
            end
            
        elseif menuSubScene == "exit_confirm" then
            if key == "up" or key == "w" or key == "down" or key == "s" then
                menuSelectedSubIdx = menuSelectedSubIdx == 1 and 2 or 1
            elseif key == "escape" then
                menuSubScene = "main"
                menuSelectedSubIdx = 1
            elseif key == "space" or key == "return" then
                if menuSelectedSubIdx == 1 then
                    love.event.quit()
                else
                    menuSubScene = "main"
                    menuSelectedSubIdx = 1
                end
            end
        end
        
    elseif currentScene == "battle" then
        if battleCombatState == "input" then
            local memberInfo = battleLivingMembers[battleActiveMemberIndex]
            if not memberInfo then
                battleCombatState = "log"
                return
            end
            
            local isSummoner = (memberInfo.type == "summoner")
            
            if battleSpellSelect then
                -- Get skills/spells list
                local options = {}
                if isSummoner then
                    options = { {id = "soothingMote", mp = 5}, {id = "divineFavor", mp = 8}, {id = "holySmite", mp = 15} }
                else
                    for _, skId in ipairs(memberInfo.actor.skills or {}) do
                        local sk = loader.getSkill(skId)
                        if sk then table.insert(options, sk) end
                    end
                end
                
                if key == "up" or key == "w" then
                    if #options > 0 then
                        battleSelectedIndex = (battleSelectedIndex - 2) % #options + 1
                    end
                elseif key == "down" or key == "s" then
                    if #options > 0 then
                        battleSelectedIndex = battleSelectedIndex % #options + 1
                    end
                elseif key == "escape" then
                    battleSpellSelect = false
                    battleSelectedIndex = 2 -- Back to Spell/Skill option
                elseif key == "space" or key == "return" then
                    local choice = options[battleSelectedIndex]
                    if choice then
                        local allowed = true
                        if isSummoner then
                            allowed = (activeSession.mp >= choice.mp)
                        end
                        
                        if allowed then
                            local spell = loader.getSkill(choice.id)
                            local target = activeSession.summoner
                            if spell and (spell.target == "enemy-any" or spell.target == "enemy") then
                                -- Target first living enemy
                                for _, e in ipairs(activeBattle.enemies) do
                                    if not e:isDead() then target = e break end
                                end
                            else
                                -- Heal target lowest HP ally
                                local lowestHp = 9999
                                for _, c in ipairs(activeSession.party) do
                                    if not c:isDead() and c.hp < lowestHp then
                                        lowestHp = c.hp
                                        target = c
                                    end
                                end
                            end
                            
                            battleCollectedActions[memberInfo.index] = {
                                type = isSummoner and "spell" or "skill",
                                id = choice.id,
                                target = target
                            }
                            
                            -- Move to next member
                            battleActiveMemberIndex = battleActiveMemberIndex + 1
                            battleSelectedIndex = 1
                            battleSpellSelect = false
                            
                            -- If all actions collected, resolve round!
                            if battleActiveMemberIndex > #battleLivingMembers then
                                local events = resolveBattleRound()
                                battleEventsQueue = events
                                battleEventQueueIndex = 1
                                battleCombatLog = {}
                                advanceBattleLog()
                                battleCombatState = "log"
                            end
                        else
                            -- Not enough MP error popup/log
                            battleEventsQueue = { { type = "text", text = "Not enough MP!" } }
                            battleEventQueueIndex = 1
                            battleCombatLog = {}
                            advanceBattleLog()
                            battleCombatState = "log"
                        end
                    end
                end
            else
                -- Main commands: Attack (1), Spell/Skill (2), Item/Defend (3), Flee (4)
                if key == "up" or key == "w" then
                    battleSelectedIndex = (battleSelectedIndex - 2) % 4 + 1
                elseif key == "down" or key == "s" then
                    battleSelectedIndex = battleSelectedIndex % 4 + 1
                elseif key == "space" or key == "return" then
                    if battleSelectedIndex == 1 then
                        -- Attack
                        local target = activeBattle.enemies[1]
                        for _, e in ipairs(activeBattle.enemies) do
                            if not e:isDead() then target = e break end
                        end
                        
                        battleCollectedActions[memberInfo.index] = {
                            type = "attack",
                            target = target
                        }
                        
                        battleActiveMemberIndex = battleActiveMemberIndex + 1
                        battleSelectedIndex = 1
                        
                        if battleActiveMemberIndex > #battleLivingMembers then
                            local events = resolveBattleRound()
                            battleEventsQueue = events
                            battleEventQueueIndex = 1
                            battleCombatLog = {}
                            advanceBattleLog()
                            battleCombatState = "log"
                        end
                    elseif battleSelectedIndex == 2 then
                        -- Spell/Skill selection submenu
                        battleSpellSelect = true
                        battleSelectedIndex = 1
                    elseif battleSelectedIndex == 3 then
                        -- Item (Summoner) or Defend (Monster)
                        if isSummoner then
                            if activeSession:hasItem("hp_tonic", 1) then
                                local target = activeSession.summoner
                                local lowestHp = 9999
                                for _, c in ipairs(activeSession.party) do
                                    if not c:isDead() and c.hp < lowestHp then
                                        lowestHp = c.hp
                                        target = c
                                    end
                                end
                                
                                battleCollectedActions[memberInfo.index] = {
                                    type = "item",
                                    id = "hp_tonic",
                                    target = target
                                }
                                
                                battleActiveMemberIndex = battleActiveMemberIndex + 1
                                battleSelectedIndex = 1
                                
                                if battleActiveMemberIndex > #battleLivingMembers then
                                    local events = resolveBattleRound()
                                    battleEventsQueue = events
                                    battleEventQueueIndex = 1
                                    battleCombatLog = {}
                                    advanceBattleLog()
                                    battleCombatState = "log"
                                end
                            else
                                battleEventsQueue = { { type = "text", text = "No HP Tonics left!" } }
                                battleEventQueueIndex = 1
                                battleCombatLog = {}
                                advanceBattleLog()
                                battleCombatState = "log"
                            end
                        else
                            -- Monster Defend action
                            battleCollectedActions[memberInfo.index] = {
                                type = "defend"
                            }
                            battleActiveMemberIndex = battleActiveMemberIndex + 1
                            battleSelectedIndex = 1
                            
                            if battleActiveMemberIndex > #battleLivingMembers then
                                local events = resolveBattleRound()
                                battleEventsQueue = events
                                battleEventQueueIndex = 1
                                battleCombatLog = {}
                                advanceBattleLog()
                                battleCombatState = "log"
                            end
                        end
                    elseif battleSelectedIndex == 4 then
                        -- Flee
                        battleCollectedActions[memberInfo.index] = {
                            type = "flee"
                        }
                        battleActiveMemberIndex = battleActiveMemberIndex + 1
                        battleSelectedIndex = 1
                        
                        if battleActiveMemberIndex > #battleLivingMembers then
                            local events = resolveBattleRound()
                            battleEventsQueue = events
                            battleEventQueueIndex = 1
                            battleCombatLog = {}
                            advanceBattleLog()
                            battleCombatState = "log"
                        end
                    end
                end
            end
            
        elseif battleCombatState == "log" then
            if key == "space" or key == "return" then
                if battleEventQueueIndex <= #battleEventsQueue then
                    advanceBattleLog()
                else
                    if activeBattle:isVictory() then
                        local goldGain = math.random(10, 30)
                        activeSession.gold = activeSession.gold + goldGain
                        
                        -- Apply passive mending / trick heal if present on survivors
                        for _, c in ipairs(activeSession.party) do
                            if not c:isDead() then
                                c:gainExp(5, activeSession)
                                local regenVal = traits.getRate(c, "POST_BATTLE_HEAL", activeSession)
                                if regenVal > 0 then
                                    c.hp = math.min(c:getMaxHp(activeSession), c.hp + regenVal)
                                end
                            end
                        end
                        
                        currentScene = "map"
                    elseif activeBattle:isDefeat() then
                        currentScene = "title"
                        activeSession = session.GameSession.new(loader)
                        activeSession:initializeStartingParty()
                        renderer.init(activeSession)
                    else
                        local escaped = false
                        for _, line in ipairs(battleCombatLog) do
                            if line == "Escaped successfully!" then escaped = true break end
                        end
                        if escaped then
                            currentScene = "map"
                        else
                            -- Rebuild living members list for the next round
                            battleLivingMembers = {}
                            table.insert(battleLivingMembers, { type = "summoner", actor = activeSession.summoner, index = 1 })
                            for i = 1, 4 do
                                local c = activeSession.party[i]
                                if c and not c:isDead() then
                                    table.insert(battleLivingMembers, { type = "monster", actor = c, index = i + 1 })
                                end
                            end
                            
                            battleActiveMemberIndex = 1
                            battleCollectedActions = {}
                            battleCombatState = "input"
                            battleSelectedIndex = 1
                            battleSpellSelect = false
                        end
                    end
                end
            end
        end
    elseif currentScene == "shop" then
        if key == "up" or key == "w" then
            if #shopItems > 0 then
                shopSelectedIdx = (shopSelectedIdx - 2) % #shopItems + 1
            end
        elseif key == "down" or key == "s" then
            if #shopItems > 0 then
                shopSelectedIdx = shopSelectedIdx % #shopItems + 1
            end
        elseif key == "escape" then
            renderer.startClosing("shop", "map")
        elseif key == "space" or key == "return" then
            local selectedItem = shopItems[shopSelectedIdx]
            if selectedItem then
                if activeSession.gold >= selectedItem.cost then
                    activeSession.gold = activeSession.gold - selectedItem.cost
                    activeSession:addItem(selectedItem.id, 1)
                end
            end
        end
    end
end

function love.keypressed(key, scancode, isrepeat)
    local repeat_event = isrepeat or (type(scancode) == "boolean" and scancode)
    if repeat_event then return end
    
    -- If in test battle mode, only handle popup triggers and ignore/block other inputs
    if isTestBattle then
        if key == "space" or key == "p" then
            if activeBattle and activeSession then
                -- Collect potential targets
                local targets = {}
                for _, e in ipairs(activeBattle.enemies) do
                    table.insert(targets, e)
                end
                for _, c in ipairs(activeSession.party) do
                    table.insert(targets, c)
                end
                table.insert(targets, activeSession.summoner)
                
                if #targets > 0 then
                    local target = targets[math.random(#targets)]
                    local isHeal = math.random() < 0.25
                    local txt = isHeal and ("+" .. math.random(5, 20)) or ("-" .. math.random(5, 30))
                    if math.random() < 0.1 then txt = "CRITICAL!" end
                    
                    local x, y = getTargetCoords(target)
                    if x and y then
                        local col = isHeal and {0.2, 1, 0.2} or {1, 0.2, 0.2}
                        renderer.addDamagePopup(txt, x, y, col)
                    end
                end
            end
        end
        return -- Block all other keys from progressing state/crashing
    end
    
    if inputCooldown > 0 then return end
    if key == "f9" then
        if server.isActive() then
            server.stop()
            print("Developer server stopped.")
        else
            server.start()
        end
        return
    end
    
    local oldScene = currentScene
    local oldSub = menuSubScene
    
    handleKeyPressed(key)
    
    local function isMajorSubSceneTransition(oldSub, newSub)
        if oldSub == newSub then return false end
        if (oldSub == "main" and newSub == "party_select") or (oldSub == "party_select" and newSub == "main") then
            return false
        end
        if (oldSub == "items_list" and newSub == "use_target") or (oldSub == "use_target" and newSub == "items_list") then
            return false
        end
        return true
    end

    if currentScene ~= oldScene or (currentScene == "menu" and isMajorSubSceneTransition(oldSub, menuSubScene)) then
        if not renderer.closing then
            renderer.resetMenuTimer()
        end
    end
end

function love.resize(w, h)
    scale = math.min(w / gameWidth, h / gameHeight)
    scale = math.max(1, math.floor(scale))
    scaleX = math.floor((w - gameWidth * scale) / 2)
    scaleY = math.floor((h - gameHeight * scale) / 2)
end
