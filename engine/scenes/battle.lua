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
    v.skillSelect = false
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
    -- Emergency wave (Summoner rework §3): back up party/reserve SLOT
    -- membership too, same idea as the hp/mp backups above — a same-round
    -- swap must not silently show in the party grid before its "wave"
    -- event is actually revealed in the log. The real writes are replayed
    -- by processEvent's "wave" handler, timed to the swap animation.
    local partyBackup = {}
    for i = 1, 4 do partyBackup[i] = sess().party[i] end
    local reserveBackup = {}
    for k, b in pairs(sess().reserve or {}) do reserveBackup[k] = b end

    local events = actBattle:resolveRound(v.collectedActions)

    -- Restore backup states immediately so the UI can apply changes step-by-step
    for b, bk in pairs(backups) do
        b.hp = bk.hp
        b.states = bk.states
    end
    sess().mp = mpBackup
    for i = 1, 4 do sess().party[i] = partyBackup[i] end
    sess().reserve = reserveBackup

    return events
end

-------------------------------------------------------------------------------
-- Advances the combat log by one event and formats it
-------------------------------------------------------------------------------
local function processEvent(ev)
    local v = battle.getState()
    local popupX, popupY = battle.getTargetCoords(ev.target)
    local desc = ""

    if ev.type == "text" then
        desc = ev.text
        if ev.animation then
            animation_player.play(ev.animation, ev.itemTarget or ev.target)
        end
    elseif ev.type == "action" then
        desc = ldr().formatTerm("battle.uses_skill", "{0} uses {1} on {2}!", ev.actor.name, ev.skill.name, ev.target.name)
        animation_player.play("system.action_flash", ev.actor)
        if ev.animation then
            animation_player.play(ev.animation, ev.target, 500)
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
        animation_player.onComplete(ev.target, function()
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
                if not isEnemy then
                    renderer.triggerSmallDamage(ev.target)
                end
            end
        end)
    elseif ev.type == "heal" then
        animation_player.onComplete(ev.target, function()
            local fmt = conf("battle_screen", "popup", {}).healFormat or "+{0}"
            local text = fmt:gsub("{0}", tostring(ev.value))
            local color = conf("battle_screen", "popup", {}).healColor or {0.2, 1, 0.2, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            ev.target.hp = math.min(ev.target:getMaxHp(sess()), ev.target.hp + ev.value)
        end)
    elseif ev.type == "death" then
        animation_player.onComplete(ev.target, function()
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
        end)
    elseif ev.type == "state_add" then
        animation_player.onComplete(ev.target, function()
            local fmt = conf("battle_screen", "popup", {}).stateFormat or "{0}"
            local text = fmt:gsub("{0}", ev.state:upper())
            local color = conf("battle_screen", "popup", {}).stateColor or {0.8, 0.4, 1.0, 1}
            renderer.addDamagePopup(text, popupX, popupY, color)
            ev.target:addState(ev.state)
        end)
    elseif ev.type == "state_remove" then
        animation_player.onComplete(ev.target, function()
            ev.target:removeState(ev.state)
        end)
    elseif ev.type == "mp_drain" then
        sess().mp = math.max(0, sess().mp - ev.value)
    elseif ev.type == "victory" then
        desc = ldr().getTerm("battle.victory_full", "Victory! All hostile forces vanquished.")
    elseif ev.type == "defeat" then
        desc = ldr().getTerm("battle.defeat_full", "Defeat! The party has fallen in battle...")
    elseif ev.type == "flee_success" then
        desc = ldr().getTerm("battle.flee_success", "Escaped successfully!")
        v.escaped = true
    elseif ev.type == "wave" then
        -- Emergency wave (Summoner rework §3): the swap stands in for a
        -- game over, so it needs to read as a distinct, understandable
        -- beat, not a buried log line or a silent instant substitution.
        -- resolveRound's wrapper reverted session.party/reserve to their
        -- pre-round state (see battle.resolveRound), so at this exact
        -- moment — when the log actually reveals the event, not when the
        -- engine originally resolved it — the party grid still shows the
        -- OLD (dead) occupants. Each slot gets its own staggered flip:
        -- the outgoing spirit shrinks (system.swap_out), and only once
        -- THAT finishes does the real slot write land and the incoming
        -- spirit grow in (system.swap_in) — a per-slot "card flip", not a
        -- screen-wide pop. An amber screen-flash marks the whole beat.
        local STAGGER = 0.15
        local pending = ev.pending or {}
        if pending[1] then animation_player.play("system.wave", pending[1].battler) end
        for i, p in ipairs(pending) do
            local delayMs = (i - 1) * STAGGER * 1000
            if p.outgoing then
                animation_player.play("system.swap_out", p.outgoing, delayMs)
                animation_player.onComplete(p.outgoing, function()
                    sess().party[p.slot] = p.battler
                    sess().reserve[p.reserveKey] = nil
                    animation_player.play("system.swap_in", p.battler)
                end)
            else
                -- Empty slot (reserve ran shorter than the wipe) — nothing
                -- to shrink out, just place the incoming spirit and grow
                -- it in on the same stagger as the others.
                sess().party[p.slot] = p.battler
                sess().reserve[p.reserveKey] = nil
                animation_player.play("system.swap_in", p.battler, delayMs)
            end
        end
    elseif ev.type == "reap" then
        -- Permadeath (Summoner rework §3): one animation + one dedicated
        -- log line per fallen spirit, individually, like "action"/"death".
        -- The actual party[slot] removal is deferred until the animation
        -- finishes (onComplete), so the spirit visibly fades in the party
        -- grid instead of vanishing the instant the log line appears.
        animation_player.play("system.reap", ev.target)
        desc = ldr().formatTerm("battle.reaped", "{0} has passed away.", ev.target.name)
        animation_player.onComplete(ev.target, function()
            if ev.slot then sess().party[ev.slot] = nil end
            sess():autoFieldIfEmpty()
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

        if desc ~= "" then
            local log = v.combatLog or {}
            table.insert(log, desc)
            v.combatLog = log

            -- Process all subsequent skipped events immediately
            while v.eventQueueIndex <= #(v.eventsQueue or {}) do
                local nextEv = v.eventsQueue[v.eventQueueIndex]
                if nextEv.type == "damage" or nextEv.type == "heal" or nextEv.type == "death" or 
                   nextEv.type == "state_add" or nextEv.type == "state_remove" or nextEv.type == "mp_drain" then
                    v.eventQueueIndex = v.eventQueueIndex + 1
                    processEvent(nextEv)
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
        local items = {}
        for itemId, qty in pairs(sess().inventory or {}) do
            if qty > 0 then table.insert(items, itemId) end
        end
        table.sort(items)
        local itemId = items[pendingAction.itemIndex]
        local item = itemId and ldr().getItem(itemId)
        spec = item and (item.target or item.targetScope) or "ally"
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

    v.skillSelect = false
    v.itemSelect = false
    if prevAction then
        if prevAction.type == "attack" then
            v.selectedIndex = 1
        elseif prevAction.type == "skill" then
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

    -- Bug fix (owner report, 17.07.2026): a lethal hit's damage/death
    -- mutation is deferred to animation_player.onComplete, gated behind
    -- that event's own animation (e.g. a delayed skill-cast effect on the
    -- target can run 1-2s past when its log LINE finishes revealing).
    -- battle.update's auto-advance already refuses to proceed while
    -- anything is still playing, but a player-pressed SPACE reaches this
    -- function directly and has no such guard — so victory/defeat could
    -- fire, and battle.victory's REAP_FALLEN could check isDead() on a
    -- battler, BEFORE that battler's own lethal-hit callback had actually
    -- landed: hp/dead-state still read pre-death, REAP_FALLEN misses it,
    -- and the deferred callback finally applies moments later with
    -- nothing left to process it — a party member stuck permanently
    -- "dead" (hp/tint eventually update) but never reaped. Matching
    -- battle.update's own gate here closes the race at its only other
    -- entry point.
    if animation_player.isAnythingPlaying() then return false end

    -- Reap ("{name} has passed away") messages queued below drain through
    -- the normal log pipeline first; once they're read, come back here to
    -- finish whatever the flow was building toward.
    if v.pendingAfterReap then
        local nextState = v.pendingAfterReap
        v.pendingAfterReap = nil
        if nextState == "victory" then
            v.combatState = "victory"
        elseif nextState == "escaped" then
            scene_host.goto_scene("map")
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
            if ev.type == "reap" then table.insert(reaped, ev) end
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
        if not queueReapEvents(flowEvents, "victory") then
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
            -- Staged defeat sequence (owner feedback, 17.07.2026): background
            -- fades to fully black -> a dramatic pause -> party window
            -- slides out downward -> immediately (no pause) a second fade
            -- covers everything else (monsters included) to full black ->
            -- THEN hand off to game_over. battle.update drives the stages.
            v.defeatTargetScene = targetScene
            v.defeatTimer = 0
            v.defeatStage = 0
            v.defeatBgFade = 0
            v.defeatFinalFade = 0
            v.defeatSlideT = 0
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
        end
    else
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

-- Defeat sequence stage durations (seconds), owner-directed 17.07.2026:
-- background fades to fully black, THEN a dramatic pause, THEN the party
-- window slides out (no pause before this), THEN immediately (no pause)
-- a second fade sweeps everything else (monsters included) to full black.
local DEFEAT_STAGE0_DUR = 0.6  -- background fade to 100%
local DEFEAT_STAGE1_DUR = 0.7  -- dramatic pause, held black background
local DEFEAT_STAGE2_DUR = 0.45 -- party window slide-out
local DEFEAT_STAGE3_DUR = 0.6  -- final fade to full black (monsters)

function battle.update(dt)
    local v = battle.getState()
    if not v or not v.battle then
        autoAdvanceTimer = 0
        return
    end

    if v.combatState == "defeat_sequence" then
        v.defeatTimer = (v.defeatTimer or 0) + dt
        local t = v.defeatTimer
        local S0, S1, S2, S3 = DEFEAT_STAGE0_DUR, DEFEAT_STAGE1_DUR, DEFEAT_STAGE2_DUR, DEFEAT_STAGE3_DUR
        if t < S0 then
            -- Background fades to fully black.
            v.defeatStage = 0
            v.defeatBgFade = easeOut(t / S0)
            v.defeatFinalFade = 0
            v.defeatSlideT = 0
        elseif t < S0 + S1 then
            -- Dramatic pause: everything holds (background already black,
            -- windows/monsters still visible on top of it).
            v.defeatStage = 1
            v.defeatBgFade = 1
            v.defeatFinalFade = 0
            v.defeatSlideT = 0
        elseif t < S0 + S1 + S2 then
            -- Party window slides straight down and off-screen.
            v.defeatStage = 2
            v.defeatBgFade = 1
            v.defeatFinalFade = 0
            v.defeatSlideT = easeOut((t - S0 - S1) / S2)
        elseif t < S0 + S1 + S2 + S3 then
            -- No pause after the slide: a second fade immediately sweeps
            -- over everything else (the monsters) to full black.
            v.defeatStage = 3
            v.defeatBgFade = 1
            v.defeatFinalFade = easeOut((t - S0 - S1 - S2) / S3)
            v.defeatSlideT = 1
        else
            v.defeatBgFade = 1
            v.defeatFinalFade = 1
            v.defeatSlideT = 1
            if v.defeatTargetScene then
                local target = v.defeatTargetScene
                v.defeatTargetScene = nil
                scene_host.goto_scene(target, { session = sess(), loader = ldr(), party = sess().party })
            end
        end
        return
    end

    if v.combatState == "log" then
        if v.eventQueueIndex <= #(v.eventsQueue or {}) then
            local isRevealing = renderer.isBattleLogRevealing(v.combatLog)
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
