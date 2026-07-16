-- Battle scene module (D10)
--
-- The scene-module pattern (D4/D10):
--   - registerKindWindows(host) for window definitions
--   - getState() helper reading from scene_host state
--   - Exported functions called by main.lua thin wrappers
--
-- Scene state variables (in scene_host.getCurrentState().v):
--   v.battle             activeBattle (Battle object)
--   v.combatLog          combat log list
--   v.combatState        "input" or "log"
--   v.selectedIndex      command cursor position
--   v.spellSelect        boolean, spell/skill submenu active
--   v.eventsQueue        battle events queue from resolveRound
--   v.eventQueueIndex    current position in events queue
--   v.escaped            boolean, true when flee succeeded
--   v.livingMembers      list of living battlers for input
--   v.activeMemberIdx    which member is currently selecting action
--   v.collectedActions   actions table collected this round

local scene_host = require("engine.scene_host")
local battleSystem = require("engine.battle")
local flow = require("engine.flow")
local traits = require("engine.traits")
local renderer = require("presentation.renderer")
local session = require("engine.session")
local config = require("engine.config")
local loader = require("data.loader")
local animation_player = require("presentation.animation_player")

local battle = {}

-- Window definitions registered with scene_host for the battle kind
local windowDefs = {
    battle_log_window = { type = "log", title = "Combat Log" },
    battle_command_window = { type = "command", title = "Commands" },
    battle_status_window = { type = "status", title = "Battle Status" },
    battle_victory_window = { type = "victory", title = "Victory" },
}

function battle.registerKindWindows(host)
    if host and host.register then
        host.register("battle", windowDefs)
    end
end

-- Read battle state from the current scene's v table
function battle.getState()
    local state = scene_host.getCurrentState()
    return state and state.v or {}
end

-- Config accessor with fallback
local function conf(group, key, default)
    local g = config[group]
    if g and g[key] ~= nil then return g[key] end
    return default
end

-- The active session from global (set by main.lua)
local function sess()
    return _G.activeSession
end

-- The loader from global
local function ldr()
    return loader
end

-------------------------------------------------------------------------------
-- Rebuilds the list of party members that still get to act this round
-------------------------------------------------------------------------------
function battle.rebuildLivingMembers()
    -- overhaul-6 F1: the summoner is not a battle participant; living
    -- members are the active party creatures only, indexed 1-4 to match
    -- Battle:resolveRound's collectedActions slots directly (no +1 offset).
    local v = battle.getState()
    local living = {}
    for i = 1, 4 do
        local c = sess().party[i]
        if c and not c:isDead() then
            table.insert(living, { type = "monster", actor = c, index = i })
        end
    end
    v.livingMembers = living
    v.activeMemberIdx = 1
    v.collectedActions = {}
end

-------------------------------------------------------------------------------
-- Triggers a battle from the current map's encounter table
-------------------------------------------------------------------------------
function battle.triggerBattle()
    local mapData = sess().currentMapData
    local possibleEnemies = mapData and mapData.encounters
    if not possibleEnemies or #possibleEnemies == 0 then return end

    local enemyList = {}
    if flow.has("battle.battle_start") then
        for _, ev in ipairs(flow.run("battle.battle_start", { session = sess() })) do
            if ev.type == "spawn_enemies" then enemyList = ev.enemies end
        end
        if #enemyList == 0 then return end
    else
        local numEnemies = math.random(conf("combat", "minEnemies", 1), conf("combat", "maxEnemies", 3))
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
                if roll <= sum then enemyId = enemyOpt.id; break end
            end
            local enemyData = ldr().getActor(enemyId)
            if enemyData then
                local enemyBattler = session.Battler.new(enemyData, enemyData.level or sess().dungeonFloor)
                enemyBattler.hp = enemyBattler:getMaxHp(sess())
                table.insert(enemyList, enemyBattler)
            end
        end
    end

    -- CRITICAL: goto_scene must come FIRST — it creates a fresh scene state (v = {}).
    -- Setting state variables before goto_scene would write to the OLD scene and lose them.
    scene_host.goto_scene("battle", { session = sess(), loader = ldr(), party = sess().party })

    -- Now populate the fresh scene state
    local v = battle.getState()
    v.battle = battleSystem.Battle.new(sess(), enemyList)
    v.combatLog = { ldr().getTerm("battle.encounter", "A hostile group blocks your path!") }
    v.eventsQueue = {}
    v.eventQueueIndex = 1
    v.combatState = "input"
    v.selectedIndex = 1
    v.spellSelect = false
    v.escaped = false

    battle.rebuildLivingMembers()
    renderer.initBattleAnims(enemyList)
end

-------------------------------------------------------------------------------
-- Test battle (used by command-line test-battle mode)
-------------------------------------------------------------------------------
function battle.triggerTestBattle()
    local enemyList = {}
    local gData = ldr().getActor(1) or { id = "enemy_1", name = "Test Target A", level = 1 }
    local b1 = session.Battler.new(gData, 1)
    b1.hp = b1:getMaxHp(sess())
    table.insert(enemyList, b1)

    local pData = ldr().getActor(2) or { id = "enemy_2", name = "Test Target B", level = 1 }
    local b2 = session.Battler.new(pData, 1)
    b2.hp = b2:getMaxHp(sess())
    table.insert(enemyList, b2)

    scene_host.goto_scene("battle", { session = sess(), loader = ldr(), party = sess().party })

    local v = battle.getState()
    v.battle = battleSystem.Battle.new(sess(), enemyList)
    v.combatLog = { "--- BATTLE SCREEN TEST MODE ---", "Press SPACE or P to spawn damage popups!" }
    v.eventsQueue = {}
    v.eventQueueIndex = 1
    v.combatState = "input"
    v.selectedIndex = 1
    v.spellSelect = false

    battle.rebuildLivingMembers()
    renderer.initBattleAnims(enemyList)
end

-------------------------------------------------------------------------------
-- Map a battler to screen coordinates on the battle scene
-------------------------------------------------------------------------------
function battle.getTargetCoords(target)
    local v = battle.getState()
    return renderer.getBattlerCoords(v.battle, sess(), target)
end

-------------------------------------------------------------------------------
-- Resolves combat rounds with dynamic state backup/restore
-------------------------------------------------------------------------------
function battle.resolveRound()
    local v = battle.getState()
    local actBattle = v.battle
    if not actBattle then return {} end

    local backups = {}
    for _, b in ipairs(actBattle:getAllActiveBattlers()) do
        local stateCopy = {}
        for _, st in ipairs(b.states) do
            table.insert(stateCopy, { id = st.id, duration = st.duration, maxDuration = st.maxDuration })
        end
        backups[b] = {
            hp = b.hp,
            states = stateCopy
        }
    end
    local mpBackup = sess().mp

    local events = actBattle:resolveRound(v.collectedActions)

    -- Restore backup states immediately so the UI can apply changes step-by-step
    for b, bk in pairs(backups) do
        b.hp = bk.hp
        b.states = bk.states
    end
    sess().mp = mpBackup

    return events
end

-------------------------------------------------------------------------------
-- Advances the combat log by one event and formats it
-------------------------------------------------------------------------------
function battle.advanceLog()
    local v = battle.getState()
    if v.eventQueueIndex <= #(v.eventsQueue or {}) then
        local ev = v.eventsQueue[v.eventQueueIndex]
        v.eventQueueIndex = v.eventQueueIndex + 1

        local desc = ""
        local popupX, popupY = battle.getTargetCoords(ev.target)

        if ev.type == "text" then
            desc = ev.text
            if ev.animation then
                animation_player.play(ev.animation, ev.itemTarget or ev.target)
            end
        elseif ev.type == "action" then
            desc = ldr().formatTerm("battle.uses_skill", "{0} uses {1} on {2}!", ev.actor.name, ev.skill.name, ev.target.name)
            if ev.animation then
                animation_player.play(ev.animation, ev.target)
            end
            if v.battle then
                for idx, enemy in ipairs(v.battle.enemies) do
                    if enemy == ev.actor then
                        renderer.triggerActionFlash(idx, "action")
                        break
                    end
                end
            end
        elseif ev.type == "damage" then
            desc = ldr().formatTerm("battle.takes_damage", "- {0} takes {1} damage.", ev.target.name, ev.value)
            local fmt = conf("battle_screen", "popup", {}).damageFormat or "-{0}"
            local text = fmt:gsub("{0}", tostring(ev.value))
            local color = conf("battle_screen", "popup", {}).damageColor or {1, 0.2, 0.2, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            ev.target.hp = math.max(0, ev.target.hp - ev.value)
            if v.battle then
                local isEnemy = false
                for idx, enemy in ipairs(v.battle.enemies) do
                    if enemy == ev.target then
                        renderer.triggerActionFlash(idx, "damage")
                        isEnemy = true
                        break
                    end
                end
                -- E8: party smallBattlers flash/shake too (overhaul-6 F1:
                -- the summoner is never a damage target in battle anymore)
                if not isEnemy then
                    renderer.triggerSmallDamage(ev.target)
                end
            end
        elseif ev.type == "heal" then
            desc = ldr().formatTerm("battle.recovers_hp", "- {0} recovers {1} HP.", ev.target.name, ev.value)
            local fmt = conf("battle_screen", "popup", {}).healFormat or "+{0}"
            local text = fmt:gsub("{0}", tostring(ev.value))
            local color = conf("battle_screen", "popup", {}).healColor or {0.2, 1, 0.2, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            ev.target.hp = math.min(ev.target:getMaxHp(sess()), ev.target.hp + ev.value)
        elseif ev.type == "death" then
            desc = ldr().formatTerm("battle.has_fallen", "! {0} has fallen!", ev.target.name)
            local fmt = conf("battle_screen", "popup", {}).deadFormat or "DEAD"
            local color = conf("battle_screen", "popup", {}).deadColor or {0.6, 0.6, 0.6, 1}
            renderer.addDamagePopup(fmt, popupX, popupY, color)
            ev.target:addState("dead")
            ev.target.hp = 0
            if v.battle then
                for idx, enemy in ipairs(v.battle.enemies) do
                    if enemy == ev.target then
                        renderer.triggerDeathAnim(idx)
                        break
                    end
                end
            end
        elseif ev.type == "state_add" then
            desc = ldr().formatTerm("battle.got_status", "- {0} got {1} status.", ev.target.name, ev.state:upper())
            local fmt = conf("battle_screen", "popup", {}).stateFormat or "{0}"
            local text = fmt:gsub("{0}", ev.state:upper())
            local color = conf("battle_screen", "popup", {}).stateColor or {0.8, 0.4, 1.0, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            ev.target:addState(ev.state)
        elseif ev.type == "state_remove" then
            desc = ldr().formatTerm("battle.status_wore_off", "- {0}'s {1} wore off.", ev.target.name, ev.state:upper())
            ev.target:removeState(ev.state)
        elseif ev.type == "mp_drain" then
            desc = ldr().formatTerm("battle.consumes_mp", "- {0} consumes {1} MP.", ev.actor.name, ev.value)
            sess().mp = math.max(0, sess().mp - ev.value)
        elseif ev.type == "victory" then
            desc = ldr().getTerm("battle.victory_full", "Victory! All hostile forces vanquished.")
        elseif ev.type == "defeat" then
            desc = ldr().getTerm("battle.defeat_full", "Defeat! The party has fallen in battle...")
        elseif ev.type == "flee_success" then
            desc = ldr().getTerm("battle.flee_success", "Escaped successfully!")
            v.escaped = true
        end

        if desc ~= "" then
            local log = v.combatLog or {}
            table.insert(log, desc)
            v.combatLog = log
        else
            battle.advanceLog() -- skip empty and try next
        end
    end
end

-------------------------------------------------------------------------------
-- Records the chosen action for the active member; resolves the round once all have acted
-------------------------------------------------------------------------------
function battle.commitAction(memberIndex, action)
    local v = battle.getState()
    if not v.collectedActions then v.collectedActions = {} end
    v.collectedActions[memberIndex] = action
    v.activeMemberIdx = (v.activeMemberIdx or 1) + 1
    v.selectedIndex = 1
    v.spellSelect = false
    v.itemSelect = false

    if v.activeMemberIdx > #(v.livingMembers or {}) then
        v.escaped = false
        v.eventsQueue = battle.resolveRound()
        v.eventQueueIndex = 1
        v.combatLog = {}
        battle.advanceLog()
        v.combatState = "log"
    end
end

-------------------------------------------------------------------------------
-- Undoes the last committed action
-------------------------------------------------------------------------------
function battle.undoAction()
    local v = battle.getState()
    if not v.activeMemberIdx or v.activeMemberIdx <= 1 then return false end

    v.activeMemberIdx = v.activeMemberIdx - 1
    
    local memberInfo = (v.livingMembers or {})[v.activeMemberIdx]
    if not memberInfo then return false end
    
    local memberIndex = memberInfo.index
    local prevAction = v.collectedActions and v.collectedActions[memberIndex]
    if v.collectedActions then
        v.collectedActions[memberIndex] = nil
    end

    v.spellSelect = false
    v.itemSelect = false
    if prevAction then
        if prevAction.type == "attack" then
            v.selectedIndex = 1
        elseif prevAction.type == "skill" or prevAction.type == "spell" then
            v.selectedIndex = 2
        elseif prevAction.type == "defend" then
            v.selectedIndex = 3
        elseif prevAction.type == "item" then
            v.selectedIndex = 4
        elseif prevAction.type == "flee" then
            v.selectedIndex = 5
        else
            v.selectedIndex = 1
        end
    else
        v.selectedIndex = 1
    end
    return true
end


-------------------------------------------------------------------------------
-- NOTE: command-selection input ("handleInput") and log advancement
-- ("handleLogInput") are NOT defined here. They live as scene-local named
-- scripts in data/scenes.json (battle scene → scripts), run via
-- SCRIPT { ref = ... } from the battle hooks. The Lua copies that used to
-- sit here were dead code left behind by that conversion and had already
-- diverged from the authoritative script versions — do not re-add them.
-- What remains in this module is the state machinery those scripts call
-- through the interpreter's api.battle bridge (commitAction, advanceLog,
-- showMessage, handleTransition).
-------------------------------------------------------------------------------
-- Handles battle completion: victory, defeat, escape, or the next round
-------------------------------------------------------------------------------
function battle.handleTransition(action)
    local v = battle.getState()
    local b = v.battle
    if action ~= "select" or not b then return false end

    -- B.9: the victory window is showing
    if v.combatState == "victory" then
        if v.victoryStage == 0 then
            -- Press ENTER starts the drain animation
            v.victoryStage = 1
        elseif renderer.getVictoryStage() == 2 then
            -- Drain complete, dismiss
            scene_host.goto_scene("map")
        end
        return true
    end

    if v.combatState ~= "log"
        or v.eventQueueIndex <= #(v.eventsQueue or {}) then return false end

    if b:isVictory() then
        -- B.9: grant rewards, then show the dedicated victory window instead
        -- of leaving immediately. Rewards are diffed around the flow run so
        -- the window can report them without new engine event types.
        local s = sess()
        local goldBefore = s.gold
        local before = {}
        for _, c in ipairs(s.party) do
            before[c] = { level = c.level, exp = c.exp }
        end
        if flow.has("battle.victory") then
            flow.run("battle.victory", { session = s, battle = b, party = s.party, enemies = b.enemies })
        else
            local goldGain = math.random(conf("combat", "victoryGoldMin", 10), conf("combat", "victoryGoldMax", 30))
            s.gold = s.gold + goldGain
            for _, c in ipairs(s.party) do
                if not c:isDead() then
                    c:gainExp(conf("combat", "victoryExp", 5), sess())
                    local regenVal = traits.getRate(c, "POST_BATTLE_HEAL", sess())
                    if regenVal > 0 then c.hp = math.min(c:getMaxHp(sess()), c.hp + regenVal) end
                end
            end
        end
        -- Structured reward data for the window: gold delta, the battle's
        -- base EXP grant, and per-member before/after level+exp so the
        -- renderer can animate each EXP gauge (rollover handled there).
        local members = {}
        for _, c in ipairs(s.party) do
            local snap = before[c]
            if snap then
                table.insert(members, {
                    name = c.name or (c.actorData and c.actorData.name) or "?",
                    fromLevel = snap.level, fromExp = snap.exp,
                    toLevel = c.level, toExp = c.exp,
                })
            end
        end
        v.victory = {
            gold = s.gold - goldBefore,
            exp = conf("combat", "victoryExp", 5),
            expPerLevel = conf("growth", "expPerLevel", 15),
            members = members,
        }
        v.victoryStage = 0
        v.combatState = "victory"
    elseif b:isDefeat() then
        -- E9: defeat routes to the data-authored Game Over scene. The session
        -- reset happens there (RESET_SESSION on the player's choice), not as
        -- a side effect of losing.
        local toGameOver = true
        local targetScene = "game_over"
        if flow.has("battle.defeat") then
            toGameOver = false
            for _, ev in ipairs(flow.run("battle.defeat", { session = sess(), battle = b })) do
                if ev.type == "scene_change" and ev.kind == "defeat" then
                    toGameOver = true
                    if ev.scene then targetScene = ev.scene end
                end
            end
        end
        if toGameOver then
            scene_host.goto_scene(targetScene, { session = sess(), loader = ldr(), party = sess().party })
        end
    elseif v.escaped then
        local toMap = true
        if flow.has("battle.escaped") then
            toMap = false
            for _, ev in ipairs(flow.run("battle.escaped", { session = sess(), battle = b })) do
                if ev.type == "scene_change" and ev.kind == "map" then toMap = true end
            end
        end
        if toMap then scene_host.goto_scene("map") end
    else
        battle.rebuildLivingMembers()
        v.combatState = "input"
        v.selectedIndex = 1
        v.spellSelect = false
    end
    return true
end

-------------------------------------------------------------------------------
-- Interrupts input to show a one-line battle message
-------------------------------------------------------------------------------
function battle.showMessage(text)
    local v = battle.getState()
    v.eventsQueue = { { type = "text", text = text } }
    v.eventQueueIndex = 1
    v.combatLog = {}
    battle.advanceLog()
    v.combatState = "log"
end

return battle
