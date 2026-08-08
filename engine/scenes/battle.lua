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
--   v.skillSelect        boolean, spell/skill submenu active
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
local battle_view = require("presentation.battle_view")
local compareIds = require("engine.inventory").compareIds
local progress = require("engine.progress")

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
    for i = 1, config.MAX_PARTY_SIZE do
        local c = sess().party[i]
        if c and not c:isDead() and not (c.isRestricted and c:isRestricted()) then
            -- A creature under FORCE_ACTION is never asked. buildTurnQueue
            -- would override its choice anyway, and presenting a menu whose
            -- result is discarded is the worst of both: the player believes
            -- they decided something. This is presentation of the rule, not a
            -- second copy of it -- battle.lua stays authoritative, which is
            -- why an enemy is compelled without the scene being involved.
            if not battleSystem.forcedSkill(c, sess()) then
                table.insert(living, { type = "monster", actor = c, index = i })
            end
        end
    end
    v.livingMembers = living
    v.activeMemberIdx = 1
    v.collectedActions = {}
    -- Nobody left to command -- every living creature is compelled. Go straight
    -- to confirmation, or the round could never be submitted: the jump to the
    -- confirm phase normally happens when the last member commits, and with an
    -- empty list nobody ever does.
    v.confirmPhase = (#living == 0)
end

-------------------------------------------------------------------------------
-- Triggers a battle from the current map's encounter table
-------------------------------------------------------------------------------
-- Set by the host (main.lua) to be told how a battle ended, so an event that
-- started one can resume at its onVictory/onDefeat branch. A battle the player
-- walked into has no listener and simply returns to the map, which is why this
-- is a hook rather than a branch in here: the scene does not know, and must not
-- know, whether an event is waiting on it.
battle.onResolved = nil

local function resolved(outcome)
    battle_view.clear()
    if battle.onResolved then battle.onResolved(outcome) end
end

-- `troopId` names a troop to fight; without one the map's encounter table is
-- rolled. Both paths go through the same battle_start phase, so a scripted
-- fight and a wandering one are built the same way and both get their troop's
-- battle events -- the scripted case used to bypass the phase entirely.
--
-- Called unconditionally: battle.battle_start is a required phase (G1 fails
-- without it). The Lua duplicate that used to sit behind a flow.has check --
-- its own weighted roll over the map's encounter table, its own battler
-- construction -- was removed on 26.07.2026 with the other S4 fallbacks.
function battle.triggerBattle(troopId)
    local enemyList, troopData
    for _, ev in ipairs(flow.run("battle.battle_start",
        { session = sess(), troopId = troopId })) do
        if ev.type == "spawn_enemies" then
            enemyList = ev.enemies
            troopData = ev.troop
        end
    end
    if not enemyList or #enemyList == 0 then return end

    battle_view.clear()
    -- CRITICAL: goto_scene must come FIRST — it creates a fresh scene state (v = {}).
    -- Setting state variables before goto_scene would write to the OLD scene and lose them.
    scene_host.goto_scene("battle", { session = sess(), loader = ldr(), party = sess().party })

    -- Now populate the fresh scene state
    local v = battle.getState()
    v.battle = battleSystem.Battle.new(sess(), enemyList)
    -- The troop rides on the Battle so its events can be found at every phase
    -- without the scene passing it down each time.
    v.battle.troop = troopData
    v.combatLog = { ldr().getTerm("battle.encounter", "A hostile group blocks your path!") }
    v.eventsQueue = {}
    v.eventQueueIndex = 1
    v.combatState = "input"
    v.selectedIndex = 1
    v.skillSelect = false
    v.escaped = false

    battle.rebuildLivingMembers()
    renderer.initBattleAnims(enemyList)
end

-------------------------------------------------------------------------------
-- Test battle (used by command-line test-battle mode)
-------------------------------------------------------------------------------
function battle.triggerTestBattle()
    battle_view.clear()
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
    v.skillSelect = false

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
-- Resolve authoritative combat once; presentation owns its own earlier frame
-------------------------------------------------------------------------------
function battle.resolveRound()
    local v = battle.getState()
    local actBattle = v.battle
    if not actBattle then return {} end

    -- #179: capture only what presentation needs BEFORE the engine advances.
    -- Battle:resolveRound then commits the real Battle/Battler/GameSession graph
    -- exactly once. Nothing below rewinds HP, states, MP, party membership or
    -- any future semantic field merely to make an animation land later.
    battle_view.beginRound(sess(), actBattle)
    return actBattle:resolveRound(v.collectedActions)
end

-------------------------------------------------------------------------------
-- Advances the combat log by one event and formats it
-------------------------------------------------------------------------------
local function processEvent(ev)
    local v = battle.getState()
    local popupX, popupY = battle.getTargetCoords(ev.target)
    local desc = ""
    local function visualTarget(target)
        return battle_view.target(target)
    end
    local function isEnemy(target)
        if not (v.battle and target) then return false end
        for _, enemy in ipairs(v.battle.enemies or {}) do
            if enemy == target then return true end
        end
        return false
    end

    if ev.type == "text" then
        battle_view.applyEvent(ev)
        desc = ev.text
        if ev.animation then
            animation_player.play(ev.animation, visualTarget(ev.itemTarget or ev.target))
        end
    elseif ev.type == "action" then
        battle_view.applyEvent(ev)
        desc = ldr().formatTerm("battle.uses_skill", "{0} uses {1} on {2}!", ev.actor.name, ev.skill.name, ev.target.name)
        animation_player.play("system.action_flash", visualTarget(ev.actor))
    elseif ev.type == "play_anim" then
        local target = ev.on or ev.target or (v.battle and v.battle.enemies[1])
        if target then
            animation_player.play(ev.animId, visualTarget(target))
        end
    elseif ev.type == "damage" then
        local target = visualTarget(ev.target)
        animation_player.onComplete(target, function()
            local fmt = conf("battle_screen", "popup", {}).damageFormat or "-{0}"
            local text = fmt:gsub("{0}", tostring(ev.value))
            local color = conf("battle_screen", "popup", {}).damageColor or {1, 0.2, 0.2, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            battle_view.applyEvent(ev)
            if isEnemy(ev.target) then
                animation_player.play("system.damage_flash", target)
            else
                renderer.triggerSmallDamage(target)
            end
        end)
    elseif ev.type == "heal" then
        local target = visualTarget(ev.target)
        animation_player.onComplete(target, function()
            local fmt = conf("battle_screen", "popup", {}).healFormat or "+{0}"
            local text = fmt:gsub("{0}", tostring(ev.value))
            local color = conf("battle_screen", "popup", {}).healColor or {0.2, 1, 0.2, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            battle_view.applyEvent(ev)
        end)
    elseif ev.type == "hp_clamp" or ev.type == "max_hp_change" then
        -- Capacity changes are already resolved facts. The projection catches
        -- up without producing damage/death feedback or touching the battler.
        battle_view.applyEvent(ev)
    elseif ev.type == "death" then
        local target = visualTarget(ev.target)
        animation_player.onComplete(target, function()
            local fmt = conf("battle_screen", "popup", {}).deadFormat or "DEAD"
            local color = conf("battle_screen", "popup", {}).deadColor or {0.6, 0.6, 0.6, 1}
            renderer.addDamagePopup(fmt, popupX, popupY, color)
            battle_view.applyEvent(ev)
            if isEnemy(ev.target) then
                -- Keep renderer's deadEnemyFlags keyed to the same projected
                -- identity it draws; otherwise the death animation finishes
                -- and the enemy becomes visible again.
                for idx, enemy in ipairs(v.battle.enemies or {}) do
                    if enemy == ev.target then
                        renderer.triggerDeathAnim(idx)
                        break
                    end
                end
            end
        end)
    elseif ev.type == "state_add" then
        local target = visualTarget(ev.target)
        animation_player.onComplete(target, function()
            local fmt = conf("battle_screen", "popup", {}).stateFormat or "{0}"
            local text = fmt:gsub("{0}", ev.state:upper())
            local color = conf("battle_screen", "popup", {}).stateColor or {0.8, 0.4, 1.0, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            battle_view.applyEvent(ev)
        end)
    elseif ev.type == "state_remove" then
        local target = visualTarget(ev.target)
        animation_player.onComplete(target, function()
            battle_view.applyEvent(ev)
        end)
    elseif ev.type == "mp_drain" or ev.type == "overcast" or ev.type == "kill_mp_restore" then
        battle_view.applyEvent(ev)
    elseif ev.type == "victory" then
        desc = ldr().getTerm("battle.victory_full", "Victory! All hostile forces vanquished.")
    elseif ev.type == "defeat" then
        desc = ldr().getTerm("battle.defeat_full", "Defeat! The party has fallen in battle...")
    elseif ev.type == "flee_success" then
        desc = ldr().getTerm("battle.flee_success", "Escaped successfully!")
        v.escaped = true
    elseif ev.type == "wave" then
        -- Emergency wave is already authoritative when resolveRound returns.
        -- BattleView intentionally keeps the old party visible until this beat,
        -- then advances only its projected slot membership as the card-flip
        -- animation lands. No session.party/reserve writes occur here.
        local STAGGER = 0.15
        local pending = ev.pending or {}
        if pending[1] then
            animation_player.play("system.wave", visualTarget(pending[1].battler))
        end
        for i, p in ipairs(pending) do
            local delayMs = (i - 1) * STAGGER * 1000
            local incoming = visualTarget(p.battler)
            if p.outgoing then
                local outgoing = visualTarget(p.outgoing)
                animation_player.play("system.swap_out", outgoing, delayMs)
                animation_player.onComplete(outgoing, function()
                    battle_view.applyWaveEntry(p)
                    animation_player.play("system.swap_in", incoming)
                end)
            else
                battle_view.applyWaveEntry(p)
                animation_player.play("system.swap_in", incoming, delayMs)
            end
        end
    elseif ev.type == "reap" then
        -- REAP_FALLEN has already removed the creature from authoritative
        -- party state. Keep its projected card alive until the fade finishes,
        -- then converge that one visual slot to the engine's resolved roster.
        local target = visualTarget(ev.target)
        animation_player.play("system.reap", target)
        desc = ldr().formatTerm("battle.reaped", "{0} has passed away.", ev.target.name)
        animation_player.onComplete(target, function()
            battle_view.applyReap(ev)
        end)
    end

    return desc
end

function battle.advanceLog()
    local v = battle.getState()
    if v.eventQueueIndex <= #(v.eventsQueue or {}) then
        local ev = v.eventsQueue[v.eventQueueIndex]
        v.eventQueueIndex = v.eventQueueIndex + 1

        local desc = processEvent(ev)

        if ev.type == "wait" then
            v.waitTimer = (ev.duration or 0) / 1000
            return
        end

        if desc ~= "" then
            local log = v.combatLog or {}
            table.insert(log, desc)
            v.combatLog = log

            -- Process all subsequent skipped events immediately
            while v.eventQueueIndex <= #(v.eventsQueue or {}) do
                local nextEv = v.eventsQueue[v.eventQueueIndex]
                if nextEv.type == "damage" or nextEv.type == "heal" or nextEv.type == "hp_clamp" or
                   nextEv.type == "max_hp_change" or nextEv.type == "death" or
                   nextEv.type == "state_add" or nextEv.type == "state_remove" or nextEv.type == "mp_drain" or
                   nextEv.type == "overcast" or nextEv.type == "kill_mp_restore" or
                   nextEv.type == "play_anim" then
                    v.eventQueueIndex = v.eventQueueIndex + 1
                    processEvent(nextEv)
                elseif nextEv.type == "wait" then
                    v.eventQueueIndex = v.eventQueueIndex + 1
                    processEvent(nextEv)
                    v.waitTimer = (nextEv.duration or 0) / 1000
                    break
                else
                    break
                end
            end
        else
            return battle.advanceLog()
        end
    end
end

-------------------------------------------------------------------------------
-- Enters target selection mode for choose-mode specs, or commits immediately
-------------------------------------------------------------------------------
function battle.startTargetSelection(pendingAction)
    local v = battle.getState()
    local memberInfo = (v.livingMembers or {})[v.activeMemberIdx or 1]
    if not memberInfo then return end

    local spec = "enemy"
    if pendingAction.type == "skill" then
        local sk = ldr().getSkill(pendingAction.id)
        spec = sk and sk.target or "enemy"
    elseif pendingAction.type == "item" then
        local itemId = pendingAction.id
        if not itemId then
            local items = {}
            for id, qty in pairs(sess().inventory or {}) do
                if qty > 0 then table.insert(items, id) end
            end
            table.sort(items, compareIds)
            itemId = items[pendingAction.itemIndex]
        end
        local item = itemId and ldr().getItem(itemId)
        spec = item and item.target or "ally"
    end

    local targeting = require("engine.targeting")
    local expanded = targeting.expand(spec)

    if expanded.mode == "choose" then
        v.targetSelect = true
        v.targetIndex = 1
        v.pendingAction = pendingAction
        v.pendingAction.targetSpec = spec
        v.prevSelectedIndex = v.selectedIndex
        v.selectedIndex = 1
    else
        -- Random-mode specs: the real pick happens at round resolution —
        -- resolve()'s random branch ignores the committed target and rolls
        -- fresh (battle.lua:resolveRound passes it as chosenTarget, which
        -- only choose-mode honors). What we commit here is a provisional
        -- placeholder that keeps the turn in the queue, chosen via
        -- getCandidates so the spec's side AND state filters are honored
        -- (the old hand-roll assumed side=="enemy"/alive and fell back to
        -- self for every other spec, bypassing the resolver entirely).
        -- getCandidates consumes no battle RNG — T2's rule that the
        -- selection path must never perturb AI rolls holds.
        local candidates = targeting.getCandidates(memberInfo.actor, spec, v.battle)
        local target = candidates[1] or memberInfo.actor
        battle.commitAction(memberInfo.index, {
            type = pendingAction.type,
            id = pendingAction.id,
            itemIndex = pendingAction.itemIndex,
            target = target
        })
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
    v.skillSelect = false
    v.itemSelect = false

    if v.activeMemberIdx > #(v.livingMembers or {}) then
        v.confirmPhase = true
        v.selectedIndex = 1
    end
end

-------------------------------------------------------------------------------
-- Submits the queued round after final confirmation
-------------------------------------------------------------------------------
function battle.submitRound()
    local v = battle.getState()
    v.confirmPhase = false
    v.escaped = false
    v.eventsQueue = battle.resolveRound()
    v.eventQueueIndex = 1
    v.combatLog = {}
    battle.advanceLog()
    v.combatState = "log"
end

-------------------------------------------------------------------------------
-- Undoes the last committed action
-------------------------------------------------------------------------------
function battle.undoAction()
    local v = battle.getState()
    if v.confirmPhase then
        v.confirmPhase = false
        v.activeMemberIdx = #(v.livingMembers or {})
        v.selectedIndex = 1
        return true
    end

    if not v.activeMemberIdx or v.activeMemberIdx <= 1 then return false end

    v.activeMemberIdx = v.activeMemberIdx - 1
    
    local memberInfo = (v.livingMembers or {})[v.activeMemberIdx]
    if not memberInfo then return false end
    
    local memberIndex = memberInfo.index
    local prevAction = v.collectedActions and v.collectedActions[memberIndex]
    if v.collectedActions then
        v.collectedActions[memberIndex] = nil
    end

    v.skillSelect = false
    v.itemSelect = false
    if prevAction then
        -- Put the cursor back on the row the undone action came from. These
        -- were hardcoded 1..5, which is wrong the moment a creature has its
        -- own command set: row 5 is Flee for a Pixie and does not exist for an
        -- Egg. Find the command in THIS creature's list instead.
        local cmds = require("engine.battle").commandsFor(memberInfo.actor, ldr())
        local wanted
        for _, cmd in ipairs(cmds) do
            local act = cmd.action
            if act and act.type == prevAction.type
                and (act.id == nil or act.id == prevAction.id) then
                -- A command that commits this exact action (Defend, Flee, Wait).
                wanted = cmd.id
                break
            elseif cmd.resolve == "target" and act and act.type == prevAction.type then
                wanted = cmd.id
                break
            end
        end
        if not wanted then
            -- Anything chosen through a submenu returns to the submenu's row.
            if prevAction.type == "skill" then wanted = "skill"
            elseif prevAction.type == "item" then wanted = "item" end
        end
        v.selectedIndex = 1
        for i, cmd in ipairs(cmds) do
            if cmd.id == wanted then v.selectedIndex = i break end
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
            -- Drain complete. Anyone who gained a level gets read one at a
            -- time before the battle actually ends; with nobody to report,
            -- this is the same immediate dismissal it always was.
            if #(v.levelUps or {}) > 0 then
                v.levelUpIndex = 1
                progress.publish(v, v.levelUps, 1)
                v.combatState = "levelup"
            else
                scene_host.goto_scene("map")
                resolved("victory")
            end
        end
        return true
    end

    -- The level-up report: one creature per confirm press, in party order.
    -- Everything shown is authored (data/scenes.json windows + engine.json
    -- windowLayout) over the vars progress.publish sets; the scene only moves
    -- the cursor through the list.
    if v.combatState == "levelup" then
        local nextIndex = (v.levelUpIndex or 1) + 1
        if nextIndex <= #(v.levelUps or {}) then
            v.levelUpIndex = nextIndex
            progress.publish(v, v.levelUps, nextIndex)
        else
            scene_host.goto_scene("map")
            resolved("victory")
        end
        return true
    end

    if v.combatState ~= "log"
        or v.eventQueueIndex <= #(v.eventsQueue or {}) then return false end

    -- #179: animations gate only PRESENTATION progression now. Domain truth is
    -- already fully resolved before the first log event is shown, so victory,
    -- REAP_FALLEN and other engine rules no longer depend on a presentation
    -- callback having performed a delayed HP/death mutation.
    if animation_player.isAnythingPlaying() then return false end

    -- Reap ("{name} has passed away") messages queued below drain through
    -- the normal log pipeline first; once they're read, come back here to
    -- finish whatever the flow was building toward.
    if v.pendingAfterReap then
        local nextState = v.pendingAfterReap
        v.pendingAfterReap = nil
        if nextState == "victory" then
            battle_view.clear()
            v.combatState = "victory"
        elseif nextState == "escaped" then
            scene_host.goto_scene("map")
            resolved("escaped")
        end
        return true
    end

    -- Queues flowEvents' reap entries onto the log and switches combatState
    -- back to "log" so the player reads each one individually before
    -- nextState fires (see the pendingAfterReap branch above). Returns true
    -- when there were any (caller should stop and let the log run).
    local function queueReapEvents(flowEvents, nextState)
        local reaped = {}
        for _, ev in ipairs(flowEvents) do
            if ev.type == "reap" then
                table.insert(reaped, ev)
            else
                -- Ward saves and other already-resolved facts may accompany
                -- reaps in the same end-of-battle flow. Advance their visual
                -- projection now; ignoring them would leave a saved creature
                -- looking dead until BattleView is discarded.
                battle_view.applyEvent(ev)
            end
        end
        if #reaped == 0 then return false end
        v.eventsQueue = v.eventsQueue or {}
        local startIdx = #v.eventsQueue + 1
        for _, ev in ipairs(reaped) do table.insert(v.eventsQueue, ev) end
        v.eventQueueIndex = startIdx
        v.pendingAfterReap = nextState
        v.combatState = "log"
        battle.advanceLog()
        return true
    end

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
        -- Slot-keyed snapshot for the level-up report (engine/progress.lua).
        -- Taken here rather than inside the flow because the report is a diff
        -- across the WHOLE grant, not per GRANT_XP command.
        local growthBefore = progress.snapshot(s)
        -- battle.victory is a validator-required phase (no legacy fallback);
        -- it also runs the REAP_FALLEN permadeath sweep.
        local flowEvents = flow.run("battle.victory", { session = s, battle = b, party = s.party, enemies = b.enemies })
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
        v.levelUps = progress.levelUps(s, growthBefore)
        v.levelUpIndex = 0
        progress.publish(v, v.levelUps, 0)
        if not queueReapEvents(flowEvents, "victory") then
            battle_view.clear()
            v.combatState = "victory"
        end
    elseif b:isDefeat() then
        -- E9: defeat routes to the data-authored Game Over scene. The session
        -- reset happens there (RESET_SESSION on the player's choice), not as
        -- a side effect of losing. No REAP_FALLEN here: RESET_SESSION wipes
        -- the whole session, so permadeath bookkeeping would be moot.
        local toGameOver = false
        local targetScene = "game_over"
        for _, ev in ipairs(flow.run("battle.defeat", { session = sess(), battle = b })) do
            if ev.type == "scene_change" and ev.kind == "defeat" then
                toGameOver = true
                if ev.scene then targetScene = ev.scene end
            end
        end
        if toGameOver then
            battle_view.clear()
            -- Staged defeat sequence: background fades to fully black -> a
            -- dramatic pause -> a second fade covers the party dock and
            -- monsters -> THEN hand off to game_over. The persistent dock
            -- remains in place so the destination owns its one close
            -- animation. battle.update drives the stages.
            v.defeatTargetScene = targetScene
            v.defeatTimer = 0
            v.defeatStage = 0
            v.defeatBgFade = 0
            v.defeatFinalFade = 0
            v.combatState = "defeat_sequence"
        end
    elseif v.escaped then
        -- battle.escaped is a validator-required phase; it also runs the
        -- REAP_FALLEN permadeath sweep before returning to the map.
        local toMap = false
        local flowEvents = flow.run("battle.escaped", { session = sess(), battle = b })
        for _, ev in ipairs(flowEvents) do
            if ev.type == "scene_change" and ev.kind == "map" then toMap = true end
        end
        if not queueReapEvents(flowEvents, "escaped") and toMap then
            scene_host.goto_scene("map")
            resolved("escaped")
        end
    else
        battle_view.clear()
        battle.rebuildLivingMembers()
        v.combatState = "input"
        v.selectedIndex = 1
        v.skillSelect = false
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

-------------------------------------------------------------------------------
-- Auto-advance the combat log in love.update
-------------------------------------------------------------------------------
local autoAdvanceTimer = 0

-- Quadratic ease-out (matches presentation/animation_player.lua's track
-- easing so this hand-rolled sequence reads consistently with the rest of
-- the animation system): fast start, slow settle.
local function easeOut(t)
    t = math.max(0, math.min(1, t))
    return 1 - (1 - t) * (1 - t)
end

-- Defeat sequence stage durations (seconds): background fades to fully black,
-- THEN a dramatic pause, THEN a second fade sweeps the party dock and monsters
-- to full black. The game-over scene closes the persistent dock afterward.
local DEFEAT_STAGE0_DUR = 0.6  -- background fade to 100%
local DEFEAT_STAGE1_DUR = 0.7  -- dramatic pause, held black background
local DEFEAT_STAGE2_DUR = 0.6  -- final fade to full black

function battle.update(dt)
    battle_view.update(dt)
    local v = battle.getState()
    if not v or not v.battle then
        autoAdvanceTimer = 0
        return
    end

    if v.combatState == "defeat_sequence" then
        v.defeatTimer = (v.defeatTimer or 0) + dt
        local t = v.defeatTimer
        local S0, S1, S2 = DEFEAT_STAGE0_DUR, DEFEAT_STAGE1_DUR, DEFEAT_STAGE2_DUR
        if t < S0 then
            -- Background fades to fully black.
            v.defeatStage = 0
            v.defeatBgFade = easeOut(t / S0)
            v.defeatFinalFade = 0
        elseif t < S0 + S1 then
            -- Dramatic pause: everything holds (background already black,
            -- windows/monsters still visible on top of it).
            v.defeatStage = 1
            v.defeatBgFade = 1
            v.defeatFinalFade = 0
        elseif t < S0 + S1 + S2 then
            -- The final fade covers the party dock and monsters together.
            v.defeatStage = 2
            v.defeatBgFade = 1
            v.defeatFinalFade = easeOut((t - S0 - S1) / S2)
        else
            v.defeatBgFade = 1
            v.defeatFinalFade = 1
            if v.defeatTargetScene then
                local target = v.defeatTargetScene
                v.defeatTargetScene = nil
                battle_view.clear()
                scene_host.goto_scene(target, { session = sess(), loader = ldr(), party = sess().party })
            end
        end
        return
    end

    if v.combatState == "log" then
        local isRevealing = renderer.isBattleLogRevealing(v.combatLog)
        local isAnimPlaying = animation_player.isAnythingPlaying()

        if v.waitTimer and v.waitTimer > 0 then
            if not isRevealing and not isAnimPlaying then
                v.waitTimer = v.waitTimer - dt
                if v.waitTimer <= 0 then
                    v.waitTimer = 0
                    battle.advanceLog()
                end
            end
            autoAdvanceTimer = 0
            return
        end

        if v.eventQueueIndex <= #(v.eventsQueue or {}) then
            local isAnimPlaying = animation_player.isAnythingPlaying()

            if not isRevealing and not isAnimPlaying then
                autoAdvanceTimer = autoAdvanceTimer + dt
                local delay = conf("battle_screen", "autoAdvanceDelay", 1.2)
                if autoAdvanceTimer >= delay then
                    autoAdvanceTimer = 0
                    battle.advanceLog()
                end
            else
                autoAdvanceTimer = 0
            end
        else
            local isRevealing = renderer.isBattleLogRevealing(v.combatLog)
            local isAnimPlaying = animation_player.isAnythingPlaying()

            if not isRevealing and not isAnimPlaying then
                local b = v.battle
                if not b:isVictory() and not b:isDefeat() and not v.escaped then
                    autoAdvanceTimer = autoAdvanceTimer + dt
                    local delay = conf("battle_screen", "autoAdvanceDelay", 1.2)
                    if autoAdvanceTimer >= delay then
                        autoAdvanceTimer = 0
                        battle_view.clear()
                        battle.rebuildLivingMembers()
                        v.combatState = "input"
                        v.selectedIndex = 1
                        v.skillSelect = false
                    end
                else
                    autoAdvanceTimer = 0
                end
            else
                autoAdvanceTimer = 0
            end
        end
    else
        autoAdvanceTimer = 0
    end
end

return battle
