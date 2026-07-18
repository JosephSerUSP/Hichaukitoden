local effects = require("engine.effects")
local traits = require("engine.traits")
local config = require("engine.config")
local flow = require("engine.flow")

local battle = {}

-- The basic attack every battler falls back to (combat.attackSkillId)
local function getAttackSkill(session)
    local id = config.combat and config.combat.attackSkillId or "attack"
    return session.loader.getSkill(id) or session.loader.getSkill("attack")
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

    for i = 1, 4 do
        if session.party[i] then
            table.insert(self.fallen, session.party[i])
            session.party[i] = nil
        end
    end
    local deployed = session:fillEmptySlotsFromReserve()
    self.allies = session:getActiveParty()

    -- `deployed` rides on the event so the presentation layer can flash
    -- the incoming spirits (system.wave) and name them — the swap needs
    -- to read as a distinct, attention-grabbing beat, not a buried log
    -- line, since it's standing in for a game over.
    local names = {}
    for _, b in ipairs(deployed) do table.insert(names, b.name or "?") end
    table.insert(roundEvents, { type = "wave", deployed = deployed })
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
function Battle:resolveRound(collectedActions)
    local roundEvents = {}

    -- 1. Flee: if any creature chose it this round, resolve immediately
    -- (before the speed-ordered queue runs) and skip the rest of the round.
    local fleeing = false
    for i = 1, 4 do
        local act = collectedActions and collectedActions[i]
        if act and act.type == "flee" then fleeing = true break end
    end
    if fleeing then
        if flow.has("battle.flee_attempt") then
            local flowEvents = flow.run("battle.flee_attempt", {
                session = self.session,
                battle = self,
            })
            local escaped = false
            for _, ev in ipairs(flowEvents) do
                table.insert(roundEvents, ev)
                if ev.type == "flee_success" then escaped = true end
            end
            if escaped then return roundEvents end
        else
            -- Legacy block: runs only when the phase is removed from
            -- flows.json (SPEC S4 fallback rule)
            local roll = math.random()
            local baseFlee = config.combat and config.combat.baseFleeChance or 0.4
            -- Add flee bonus from coward/fleeChanceBonus passive
            for _, ally in ipairs(self.allies) do
                if not ally:isDead() then
                    baseFlee = baseFlee + traits.getRate(ally, "FLEE_CHANCE_BONUS", self.session)
                end
            end

            if roll < baseFlee then
                table.insert(roundEvents, { type = "flee_success" })
                return roundEvents
            else
                table.insert(roundEvents, { type = "text", text = self.session.loader.getTerm("battle.flee_fail", "Failed to escape!") })
                -- Lose some gold as penalty
                local goldLossMin = config.combat and config.combat.goldLossOnFleeMin or 5
                local goldLossMax = config.combat and config.combat.goldLossOnFleeMax or 15
                local goldLoss = math.random(goldLossMin, goldLossMax)
                self.session.gold = math.max(0, self.session.gold - goldLoss)
            end
        end
    end

    -- Check if combat ends immediately
    if self:isVictory() then
        table.insert(roundEvents, { type = "victory" })
        return roundEvents
    end

    -- 2. Build the turn queue for all creatures
    local queue = {}

    -- Ally creatures
    for i = 1, 4 do
        local ally = self.allies[i]
        if ally and not ally:isDead() then
            local chosenAct = collectedActions and collectedActions[i]
            local skill
            local target
            local itemAct = nil

            if chosenAct then
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
    
    -- 3. Execute actions in speed order
    local targeting = require("engine.targeting")
    for _, turn in ipairs(queue) do
        local targetDead = false
        if turn.target and turn.target.isDead and turn.target:isDead() then
            local spec = turn.item and (turn.item.target or turn.item.targetScope or "ally") or turn.skill.target
            local expanded = targeting.expand(spec)
            if expanded.state ~= "dead" and expanded.state ~= "any" then
                targetDead = true
            end
        end

        if not turn.actor:isDead() and not targetDead then
            if turn.item then
                -- F7: apply the used item's effects and consume it. This
                -- spends the creature's turn exactly like a skill would.
                local evs = self:applyItem(turn.item, turn.actor, turn.target)
                for _, ev in ipairs(evs) do
                    table.insert(roundEvents, ev)
                end
            else
                local targets = targeting.resolve(turn.actor, turn.skill.target, self, turn.target, turn.skill)
                
                table.insert(roundEvents, {
                    type = "action",
                    actor = turn.actor,
                    skill = turn.skill,
                    target = turn.target or (targets[1] or turn.actor),
                    animation = turn.skill and turn.skill.animation or nil,
                })
                
                for _, tgt in ipairs(targets) do
                    for _, eff in ipairs(turn.skill.effects or {}) do
                        local evs = effects.apply(eff, turn.actor, tgt, self.session, { element = turn.skill.element })
                        for _, ev in ipairs(evs) do
                            table.insert(roundEvents, ev)
                        end
                    end
                end
            end
            
            -- Check for victory/defeat mid-turn. A wipe with reserves left
            -- deploys the emergency wave instead of ending the battle; the
            -- round continues (remaining enemy turns whose targets fell are
            -- skipped by the target-dead check above).
            if self:isVictory() then
                table.insert(roundEvents, { type = "victory" })
                break
            elseif self:isDefeat() and not self:tryDeployWave(roundEvents) then
                table.insert(roundEvents, { type = "defeat" })
                break
            end
        end
    end
    
    -- Skip round-end ticks if the battle outcome is already decided
    if self:isVictory() or self:isDefeat() then
        return roundEvents
    end
    
    if flow.has("battle.round_end") then
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
        return roundEvents
    end

    -- Legacy block: runs only when the phase is removed from flows.json
    -- (SPEC S4 fallback rule)
    -- Apply end of turn effects (poison, regen, status decay)
    for _, battler in ipairs(self:getAllActiveBattlers()) do
        if not battler:isDead() then
            -- Regeneration
            for _, state in ipairs(battler.states) do
                if state.id == "regen" then
                    local maxHp = traits.getParam(battler, "maxHp", self.session)
                    local heal = math.floor(maxHp * (config.combat and config.combat.regenRate or 0.1))
                    battler.hp = math.min(maxHp, battler.hp + heal)
                    table.insert(roundEvents, {
                        type = "heal",
                        target = battler,
                        value = heal
                    })
                elseif state.id == "poison" then
                    local dmg = math.floor(traits.getParam(battler, "maxHp", self.session) * (config.combat and config.combat.poisonRate or 0.1))
                    battler.hp = math.max(0, battler.hp - dmg)
                    table.insert(roundEvents, {
                        type = "damage",
                        target = battler,
                        value = dmg
                    })
                    if battler.hp <= 0 then
                        battler:addState("dead")
                        table.insert(roundEvents, {
                            type = "death",
                            target = battler
                        })
                    end
                end
            end
            
            -- Decay turn counts
            for i = #battler.states, 1, -1 do
                local state = battler.states[i]
                if state.duration and state.duration ~= 9999 then
                    state.duration = state.duration - 1
                    if state.duration <= 0 then
                        table.remove(battler.states, i)
                        table.insert(roundEvents, {
                            type = "state_remove",
                            target = battler,
                            state = state.id
                        })
                    end
                end
            end
        end
    end
    
    -- MP drain at round end for each active monster (no drain on safe maps
    -- or when no map is loaded, e.g. test battles)
    local mapData = self.session.currentMapData
    if not (mapData and mapData.safe) then
        for i = 1, 4 do
            local ally = self.allies[i]
            if ally and not ally:isDead() then
                local drain = traits.getParam(ally, "mpd", self.session)
                self.session.mp = math.max(0, self.session.mp - drain)
                table.insert(roundEvents, {
                    type = "mp_drain",
                    value = drain,
                    actor = ally
                })
            end
        end
        if self.session.mp <= 0 then
            -- Party takes progressive damage at 0 MP
            for i = 1, 4 do
                local ally = self.allies[i]
                if ally and not ally:isDead() then
                    local exhaustDmg = config.combat and config.combat.mpExhaustionDamage or 1
                    ally.hp = math.max(1, ally.hp - exhaustDmg)
                    table.insert(roundEvents, {
                        type = "damage",
                        target = ally,
                        value = exhaustDmg
                    })
                    table.insert(roundEvents, {
                        type = "text",
                        text = self.session.loader.formatTerm("battle.mp_exhaustion", "{0} suffers from MP exhaustion!", ally.name)
                    })
                end
            end
        end
    end
    
    -- Round-end ticks (poison) can wipe the party too
    if self:isDefeat() and not self:tryDeployWave(roundEvents) then
        table.insert(roundEvents, { type = "defeat" })
    end
    self.round = self.round + 1
    return roundEvents
end

function Battle:applyItem(action, actor, target)
    local events = {}
    local session = self.session
    local loader = session.loader

    -- Resolve the item by its 1-based index into the id-sorted non-empty
    -- inventory — the SAME ordering api.items()/USE_ITEM use, so the index
    -- committed from the battle command menu maps here correctly.
    local stacks = {}
    for itemId, qty in pairs(session.inventory or {}) do
        if qty > 0 then table.insert(stacks, itemId) end
    end
    table.sort(stacks)
    local item = stacks[action.itemIndex] and loader.getItem(stacks[action.itemIndex])
    if not item then return events end

    table.insert(events, {
        type = "text",
        text = loader.formatTerm("battle.uses_item", "{0} uses {1}!", actor.name, item.name or "?"),
        animation = item.animation,
        itemTarget = target,
    })

    local targeting = require("engine.targeting")
    local targets = targeting.resolve(actor, item.target or item.targetScope or "ally", self, target, item)
    for _, tgt in ipairs(targets) do
        for _, eff in ipairs(item.effects or {}) do
            for _, ev in ipairs(effects.apply(eff, tgt, tgt, session)) do
                table.insert(events, ev)
            end
        end
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
    for i = 1, 4 do
        if self.allies[i] and not self.allies[i]:isDead() then
            monstersAlive = true
            break
        end
    end
    return not monstersAlive
end

function Battle:getAllActiveBattlers()
    local list = {}
    for i = 1, 4 do
        if self.allies[i] then table.insert(list, self.allies[i]) end
    end
    for _, enemy in ipairs(self.enemies) do
        table.insert(list, enemy)
    end
    return list
end

battle.Battle = Battle

return battle
