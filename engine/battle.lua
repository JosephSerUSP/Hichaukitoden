local effects = require("engine.effects")
local traits = require("engine.traits")
local config = require("engine.config")
local flow = require("engine.flow")
local interpreter = require("engine.interpreter")
local compareIds = require("engine.inventory").compareIds

local battle = {}

-- The basic attack every battler falls back to (combat.attackSkillId)
local function getAttackSkill(session)
    local id = config.combat and config.combat.attackSkillId or "attack"
    return session.loader.getSkill(id) or session.loader.getSkill("attack")
end

-- The skill a battler is compelled to use this round, or nil. Checked where the
-- queue is built rather than in the command menu and again in the AI, so one
-- rule binds both sides: a berserk enemy and a berserk party creature are
-- compelled by the same code, and neither battle.lua nor the battle scene
-- carries a branch that knows what "berserk" means.
local function forcedSkill(battler, session)
    for _, found in ipairs(traits.findAllSources(battler, "FORCE_ACTION", session)) do
        local skill = session.loader.getSkill(found.trait.dataId)
        if skill then return skill end
    end
    return nil
end
battle.forcedSkill = forcedSkill

-- Which commands a battler may choose from this round.
--
-- The console used to draw a fixed five-entry list and dispatch on the row
-- number, so every creature could do everything and "1" meant Attack forever.
-- The list is now data: engine.json `battleCommands` declares what a command is
-- and how it resolves, an actor's `battleCommands` says which of them it has,
-- and `defaultBattleCommands` covers the ordinary creature that authors none.
-- An Egg authoring `["wait"]` is the whole of "an Egg can only wait".
--
-- Registry order is menu order, so the set an actor authors is displayed in the
-- registry's sequence rather than the order they happened to list it in.
function battle.commandsFor(battler, loader)
    local registry = (loader.engine and loader.engine.battleCommands) or {}
    local allowed = battler and battler.actorData and battler.actorData.battleCommands
        or (loader.engine and loader.engine.defaultBattleCommands)
        or {}
    local wanted = {}
    for _, id in ipairs(allowed) do wanted[id] = true end
    local out = {}
    for _, cmd in ipairs(registry) do
        if wanted[cmd.id] then table.insert(out, cmd) end
    end
    return out
end

local Battle = {}
Battle.__index = Battle

function Battle.new(session, enemies)
    local self = setmetatable({}, Battle)
    self.session = session
    self.enemies = enemies
    self.allies = session:getActiveParty() -- the 4 active creatures; no summoner (overhaul-6 F1)
    self.round = 1
    self.log = {}
    -- Wave casualties awaiting the battle-end REAP_FALLEN sweep (Summoner
    -- rework §3): spirits replaced by an emergency reserve wave leave the
    -- party immediately but only convert to banked EXP when the battle ends.
    self.fallen = {}
    -- Front/back row state (Summoner rework §4): engine-accessible only for
    -- now — no combat math consumes it. Default by fielded slot: 1-2 front,
    -- 3-4 back. Spirits keep an explicitly assigned row across battles.
    for i, ally in ipairs(self.allies) do
        ally.row = ally.row or ((i <= 2) and "front" or "back")
    end
    return self
end

-- Emergency wave (Summoner rework §3): when the whole fielded party is
-- down and reserve spirits exist, the reserve wave deploys automatically
-- and free of MP cost via the shared session:fillEmptySlotsFromReserve
-- (also used by the general auto-field rule). The fallen move to
-- self.fallen for the battle-end REAP_FALLEN sweep; the deployed spirits
-- were never queued this round, so the party forfeits the turn by
-- construction. Returns true when a wave deployed (defeat is averted),
-- false when the reserve is empty (party left untouched).
function Battle:tryDeployWave(roundEvents)
    local session = self.session
    local hasReserve = false
    for _, b in pairs(session.reserve or {}) do
        if b then hasReserve = true break end
    end
    if not hasReserve then return false end

    local outgoingBySlot = {}
    for i = 1, config.MAX_PARTY_SIZE do
        if session.party[i] then
            outgoingBySlot[i] = session.party[i]
            table.insert(self.fallen, session.party[i])
            session.party[i] = nil
        end
    end
    local deployed = session:fillEmptySlotsFromReserve()
    for _, d in ipairs(deployed) do
        d.outgoing = outgoingBySlot[d.slot]
    end
    self.allies = session:getActiveParty()

    -- `deployed` rides on the event ({battler, slot, reserveKey, outgoing}
    -- per entry) so the presentation layer can play the swap as a proper
    -- per-slot flip (outgoing shrinks, incoming grows), staggered, timed
    -- to when the log actually reveals this event rather than the instant
    -- resolveRound ran — see engine/scenes/battle.lua's resolveRound
    -- (party/reserve backup+restore) and processEvent's "wave" handler.
    local names = {}
    for _, d in ipairs(deployed) do table.insert(names, d.battler.name or "?") end
    table.insert(roundEvents, { type = "wave", pending = deployed })
    table.insert(roundEvents, {
        type = "text",
        text = session.loader.formatTerm("battle.reserve_wave",
            "The party has fallen! The reserves rush in -- {0} will not act this round.",
            table.concat(names, ", "))
    })
    return true
end

-- Generate enemy actions using basic AI
function Battle:getAIAction(enemy)
    -- Filter out dead/incapacitated
    if enemy:isDead() then return nil end

    -- A compelled enemy picks nothing, so this returns BEFORE the skill roll
    -- below. That ordering is deliberate: choosing then discarding would still
    -- consume battle RNG and shift every later roll in the round.
    local compelled = forcedSkill(enemy, self.session)
    if compelled then
        local targeting = require("engine.targeting")
        local target = targeting.resolve(enemy, compelled.target, self, nil, compelled)[1]
        if not target then return nil end
        return { actor = enemy, skill = compelled, target = target }
    end

    local skills = enemy.skills
    if #skills == 0 then return nil end

    -- Pick a random skill, re-rolling up to 3x if it's a heal and nobody on
    -- this side is wounded. Shipped in violation of SPEC S9's original "no
    -- AI targeting intelligence" line; owner-sanctioned retroactively
    -- 17.07.2026 (see the S9 amendment). The extra math.random calls are
    -- baked into the T1 golden battle.log — removing this breaks G2.
    local skillId = skills[math.random(#skills)]
    local skill = self.session.loader.getSkill(skillId) or getAttackSkill(self.session)
    
    local retries = 3
    while retries > 0 do
        local isHealSkill = false
        for _, eff in ipairs(skill.effects or {}) do
            if eff.type == "hp_heal" or eff.type == "hp" then
                isHealSkill = true
                break
            end
        end
        if isHealSkill then
            local anyWounded = false
            for _, e in ipairs(self.enemies) do
                if not e:isDead() and e.hp < e:getMaxHp(self.session) then
                    anyWounded = true
                    break
                end
            end
            if not anyWounded then
                skillId = skills[math.random(#skills)]
                skill = self.session.loader.getSkill(skillId) or getAttackSkill(self.session)
                retries = retries - 1
            else
                break
            end
        else
            break
        end
    end
    
    -- Select target using the unified targeting module
    local targeting = require("engine.targeting")
    local targets = targeting.resolve(enemy, skill.target, self, nil, skill)
    local target = targets[1]
    if not target then return nil end

    return {
        actor = enemy,
        skill = skill,
        target = target
    }
end

-- Resolve one round of battle
-- collectedActions: 1-indexed by ally slot (1-4), each entry either nil or
-- { type = "skill", id = ..., target = ... }, { type = "defend" },
-- { type = "attack", target = ... }, or { type = "flee" }.
-- (Summoner rework: no "spell" type — summoner spells are removed; the
-- Summoner has no battle verbs of their own.)
-- (overhaul-6 F1: the summoner no longer has an instant "acts first" slot;
-- Flee is now any active creature's action -- the first one committed for
-- the round triggers the party's flee attempt, same odds/penalty as before.)

-- Whether the battle is already over before a single turn is taken.
--
-- This used to also scan the committed actions for `act.type == "flee"` and
-- resolve the escape here, before the queue was built -- one battle verb
-- resolving somewhere no other verb did. Escaping is an ordinary effect now
-- (effects.lua `escape`), so it costs a turn and runs in speed order like
-- everything else, and an escape item is expressible without this function
-- learning what an item is.
function Battle:checkImmediateEnd(roundEvents)
    if self:isVictory() then
        table.insert(roundEvents, { type = "victory" })
        return true
    end

    return false
end

function Battle:buildTurnQueue(collectedActions)
    -- 2. Build the turn queue for all creatures
    local queue = {}

    -- Ally creatures
    for i = 1, config.MAX_PARTY_SIZE do
        local ally = self.allies[i]
        if ally and not ally:isDead() then
            local chosenAct = collectedActions and collectedActions[i]
            local skill
            local target
            local itemAct = nil

            local compelled = forcedSkill(ally, self.session)
            if compelled then
                -- Whatever was chosen is discarded, including an item: a
                -- creature that cannot control itself cannot rummage in a bag.
                skill = compelled
                local targeting = require("engine.targeting")
                target = targeting.resolve(ally, compelled.target, self)[1]
            elseif chosenAct then
                if chosenAct.type == "skill" then
                    skill = self.session.loader.getSkill(chosenAct.id) or getAttackSkill(self.session)
                    target = chosenAct.target
                elseif chosenAct.type == "defend" then
                    -- Defend is a data-defined skill (combat.defendSkillId) so its
                    -- speed/effects are editable like any other skill
                    local defendId = config.combat and config.combat.defendSkillId or "defend"
                    skill = self.session.loader.getSkill(defendId)
                        or { name = "Defend", speed = 50, effects = {} }
                    target = ally
                elseif chosenAct.type == "item" then
                    -- F7: Item joins the creature's command list. The item is
                    -- resolved in the execution loop via applyItem; it spends
                    -- this creature's turn like any other action.
                    itemAct = chosenAct
                    target = chosenAct.target
                else
                    skill = getAttackSkill(self.session)
                    target = chosenAct.target
                end
            else
                skill = getAttackSkill(self.session)
                local targeting = require("engine.targeting")
                local targets = targeting.resolve(ally, skill.target, self)
                target = targets[1]
            end
            
            if target then
                local baseSpeed = (config.combat and config.combat.baseSpeed or 10) + ally.level * (config.combat and config.combat.speedPerLevel or 0.5)
                local actSpeed = skill and (skill.speed or 0) or (config.combat and config.combat.battleItemSpeed or 50)
                local totalSpeed = baseSpeed + actSpeed
                table.insert(queue, {
                    actor = ally,
                    skill = skill,
                    target = target,
                    speed = totalSpeed,
                    item = itemAct,
                })
            end
        end
    end
    
    -- Enemies
    for _, enemy in ipairs(self.enemies) do
        if not enemy:isDead() then
            local action = self:getAIAction(enemy)
            if action then
                local baseSpeed = (config.combat and config.combat.baseSpeed or 10) + enemy.level * (config.combat and config.combat.speedPerLevel or 0.5)
                local actSpeed = action.skill.speed or 0
                local totalSpeed = baseSpeed + actSpeed
                action.speed = totalSpeed
                table.insert(queue, action)
            end
        end
    end
    
    -- Sort queue by Speed descending
    table.sort(queue, function(a, b)
        return a.speed > b.speed
    end)

    self:applyFirstStrikes(queue)

    return queue
end

-- First strike (INITIATIVE) and its counter (REAR_GUARD), 24.07.2026.
-- A battler carrying INITIATIVE rolls its rate (0.25 = 25% for the `initiative`
-- passive) for the right to act before the whole speed order this round.
-- REAR_GUARD negates it: a side holding any REAR_GUARD stops the OPPOSING side
-- from first-striking at all. Symmetric by design -- the `rearGuard` passive is
-- described party-side ("negates enemy first strikes"), but creatures appear on
-- both sides of a battle, so the rule reads off traits rather than allegiance.
--
-- RNG discipline: the roll happens ONLY when an eligible carrier exists, so a
-- battle with no INITIATIVE in it consumes no randomness and the golden battle
-- log (G2) stays byte-identical.
function Battle:applyFirstStrikes(queue)
    local traits = require("engine.traits")
    local session = self.session

    local function guardOf(list)
        local sum = 0
        for _, b in ipairs(list or {}) do
            if b and not b:isDead() then
                sum = sum + traits.getRate(b, "REAR_GUARD", session)
            end
        end
        return sum
    end

    local allyIndex = {}
    for _, a in ipairs(self.allies or {}) do allyIndex[a] = true end
    local allyGuard, enemyGuard = guardOf(self.allies), guardOf(self.enemies)

    -- Collect eligible carriers first: no carrier means no roll at all.
    local eligible = {}
    for _, turn in ipairs(queue) do
        local rate = traits.getRate(turn.actor, "INITIATIVE", session)
        if rate > 0 then
            local blockedBy = allyIndex[turn.actor] and enemyGuard or allyGuard
            if blockedBy <= 0 then
                table.insert(eligible, { turn = turn, rate = rate })
            end
        end
    end
    if #eligible == 0 then return end

    local anyWon = false
    for _, cand in ipairs(eligible) do
        if math.random() < cand.rate then
            cand.turn.firstStrike = true
            anyWon = true
        end
    end
    if not anyWon then return end

    -- Stable partition: winners move ahead of everyone, each group keeping the
    -- speed order already established above.
    local front, back = {}, {}
    for _, turn in ipairs(queue) do
        table.insert(turn.firstStrike and front or back, turn)
    end
    for i = #queue, 1, -1 do queue[i] = nil end
    for _, turn in ipairs(front) do table.insert(queue, turn) end
    for _, turn in ipairs(back) do table.insert(queue, turn) end
end

function Battle:executeTurn(turn, roundEvents)
    if self:isVictory() or self:isDefeat() then
        return
    end

    local targeting = require("engine.targeting")
    local config = require("engine.config")
    
    local targetDead = false
    if turn.target and turn.target.isDead and turn.target:isDead() then
        local spec = turn.item and (turn.item.target or "ally") or (turn.skill and turn.skill.target)
        if spec then
            local expanded = targeting.expand(spec)
            if expanded.state ~= "dead" and expanded.state ~= "any" then
                targetDead = true
            end
        end
    end

    if targetDead then
        local autoRedirect = false
        if self.session and self.session.autoRedirect ~= nil then
            autoRedirect = self.session.autoRedirect
        elseif config.combat and config.combat.autoRedirect ~= nil then
            autoRedirect = config.combat.autoRedirect
        end

        if autoRedirect then
            local spec = turn.item and (turn.item.target or "ally") or (turn.skill and turn.skill.target)
            if spec then
                local newTargets = targeting.resolve(turn.actor, spec, self, nil, turn.item or turn.skill)
                if newTargets and #newTargets > 0 and not newTargets[1]:isDead() then
                    turn.target = newTargets[1]
                    targetDead = false
                end
            end
        end
    end

    if not turn.actor:isDead() then
        if targetDead then
            local loader = self.session and self.session.loader
            local msg = (loader and loader.formatTerm) and loader.formatTerm("battle.target_dead", "{0}'s target is already dead!", turn.actor.name) or (turn.actor.name .. "'s target is already dead!")
            table.insert(roundEvents, {
                type = "text",
                text = msg
            })
        elseif turn.item then
            -- F7: apply the used item's effects and consume it. This
            -- spends the creature's turn exactly like a skill would.
            local evs = self:applyItem(turn.item, turn.actor, turn.target)
            for _, ev in ipairs(evs) do
                table.insert(roundEvents, ev)
            end
        else
            local loader = self.session.loader
            local targets = targeting.resolve(turn.actor, turn.skill.target, self, turn.target, turn.skill)
            
            table.insert(roundEvents, {
                type = "action",
                actor = turn.actor,
                skill = turn.skill,
                target = turn.target or (targets[1] or turn.actor),
                animation = turn.skill and turn.skill.animation or nil,
            })
            
            local seq = nil
            if turn.skill.actionSequence then
                seq = loader.actionSequences[turn.skill.actionSequence]
            end
            local commands = (seq and seq.commands) or turn.skill.actionSequenceCommands
            if not commands then
                local defaultSeq = loader.actionSequences and loader.actionSequences["default"]
                commands = defaultSeq and defaultSeq.commands
            end
            if not commands then
                commands = { { cmd = "APPLY_EFFECT" } }
            end
            
            local seqCtx = {
                a = turn.actor,
                target = turn.target or (targets[1] or turn.actor),
                targets = targets,
                skill = turn.skill,
                battle = self,
                session = self.session,
                loader = loader,
                events = {},
                refs = {}
            }
            
            interpreter.runImmediate(commands, seqCtx)
            
            for _, ev in ipairs(seqCtx.events) do
                table.insert(roundEvents, ev)
            end
        end
        
        -- Check for victory/defeat mid-turn. A wipe with reserves left
        -- deploys the emergency wave instead of ending the battle; the
        -- round continues (remaining enemy turns whose targets fell are
        -- skipped by the target-dead check above).
        if self:isVictory() then
            table.insert(roundEvents, { type = "victory" })
        elseif self:isDefeat() and not self:tryDeployWave(roundEvents) then
            table.insert(roundEvents, { type = "defeat" })
        end
    end
end

function Battle:processRoundEnd(roundEvents)
    -- Skip round-end ticks if the battle outcome is already decided
    if self:isVictory() or self:isDefeat() then
        return
    end
    
    -- Called unconditionally: battle.round_end is a required phase (G1 fails
    -- without it), so there is nothing to fall back to. The Lua duplicate that
    -- used to sit below this was removed on 26.07.2026 -- it had already
    -- drifted, still branching on `state.id == "regen"` with rates from
    -- system.json after the live path became HRG-driven, which is precisely the
    -- failure "two paths for one behavior is the bug" names.
    local flowEvents = flow.run("battle.round_end", {
        session = self.session,
        battle = self,
    })
    for _, ev in ipairs(flowEvents) do
        table.insert(roundEvents, ev)
    end
    -- Round-end ticks (poison) can wipe the party too
    if self:isDefeat() and not self:tryDeployWave(roundEvents) then
        table.insert(roundEvents, { type = "defeat" })
    end
    self.round = self.round + 1
end


function Battle:resolveRound(collectedActions)
    local roundEvents = {}

    -- 1. Already decided before anyone acts
    if self:checkImmediateEnd(roundEvents) then
        return roundEvents
    end

    -- 2. Build queue
    local queue = self:buildTurnQueue(collectedActions)

    -- 3. Execute turns. A successful escape ends the battle where it lands, so
    -- creatures slower than the one that fled do not get a turn -- the party is
    -- already gone.
    local escaped = false
    for _, turn in ipairs(queue) do
        self:executeTurn(turn, roundEvents)
        for _, ev in ipairs(roundEvents) do
            if ev.type == "flee_success" then escaped = true break end
        end
        if escaped then break end
    end
    if escaped then return roundEvents end

    -- 4. End of round
    self:processRoundEnd(roundEvents)
    
    return roundEvents
end


function Battle:applyItem(action, actor, target)
    local events = {}
    local session = self.session
    local loader = session.loader

    local item = nil
    if action.id then
        item = loader.getItem(action.id)
    elseif action.itemIndex then
        local stacks = {}
        for itemId, qty in pairs(session.inventory or {}) do
            if qty > 0 then table.insert(stacks, itemId) end
        end
        table.sort(stacks, compareIds)
        item = stacks[action.itemIndex] and loader.getItem(stacks[action.itemIndex])
    end

    if not item then return events end

    -- Verify item is still in stock
    local curQty = (session.inventory and session.inventory[item.id]) or 0
    if curQty <= 0 then
        table.insert(events, {
            type = "text",
            text = loader.formatTerm("battle.no_items_left", "No {0} remaining!", item.name or "?"),
        })
        return events
    end

    table.insert(events, {
        type = "text",
        text = loader.formatTerm("battle.uses_item", "{0} uses {1}!", actor.name, item.name or "?"),
        animation = item.animation,
        itemTarget = target,
    })

    local targeting = require("engine.targeting")
    local targets = targeting.resolve(actor, item.target or "ally", self, target, item)
    
    local seq = nil
    if item.actionSequence then
        seq = loader.actionSequences[item.actionSequence]
    end
    local commands = (seq and seq.commands) or item.actionSequenceCommands
    if not commands then
        local defaultItemSeq = loader.actionSequences and loader.actionSequences["default_item"]
        commands = defaultItemSeq and defaultItemSeq.commands
    end
    if not commands then
        commands = { { cmd = "APPLY_EFFECT" } }
    end
    
    local seqCtx = {
        a = actor,
        target = target or (targets[1] or actor),
        targets = targets,
        item = item,
        battle = self,
        session = session,
        loader = loader,
        events = {},
        refs = {}
    }
    
    interpreter.runImmediate(commands, seqCtx)
    
    for _, ev in ipairs(seqCtx.events) do
        table.insert(events, ev)
    end

    -- Consume one. Persists: session.inventory is outside the per-round
    -- hp/state/mp backup/restore the scene host does around resolveRound.
    session:addItem(item.id, -1)
    return events
end

function Battle:isVictory()
    for _, enemy in ipairs(self.enemies) do
        if not enemy:isDead() then return false end
    end
    return true
end

function Battle:isDefeat()
    -- Defeat when all 4 active creatures are dead (the summoner is not a
    -- battle participant -- overhaul-6 F1).
    local monstersAlive = false
    for i = 1, config.MAX_PARTY_SIZE do
        if self.allies[i] and not self.allies[i]:isDead() then
            monstersAlive = true
            break
        end
    end
    return not monstersAlive
end

function Battle:getAllActiveBattlers()
    local list = {}
    for i = 1, config.MAX_PARTY_SIZE do
        if self.allies[i] then table.insert(list, self.allies[i]) end
    end
    for _, enemy in ipairs(self.enemies) do
        table.insert(list, enemy)
    end
    return list
end

battle.Battle = Battle

return battle
