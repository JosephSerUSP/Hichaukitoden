local effects = require("engine.effects")
local traits = require("engine.traits")
local config = require("engine.config")

local battle = {}

local Battle = {}
Battle.__index = Battle

function Battle.new(session, enemies)
    local self = setmetatable({}, Battle)
    self.session = session
    self.enemies = enemies
    self.allies = session:getActiveParty() -- Note: includes summoner at index 5
    self.round = 1
    self.log = {}
    return self
end

-- Generate enemy actions using basic AI
function Battle:getAIAction(enemy)
    -- Filter out dead/incapacitated
    if enemy:isDead() then return nil end
    
    local skills = enemy.skills
    if #skills == 0 then return nil end
    
    -- Pick a random skill
    local skillId = skills[math.random(#skills)]
    local skill = self.session.loader.getSkill(skillId) or self.session.loader.getSkill("attack")
    
    -- Select target
    local target
    if skill.target == "enemy" or skill.target == "enemy-any" then
        -- Attack a random ally creature.
        -- Summoner is only targetable if all active creatures are dead!
        local livingAllies = {}
        for i = 1, 4 do
            local ally = self.allies[i]
            if ally and not ally:isDead() then
                table.insert(livingAllies, ally)
            end
        end
        
        if #livingAllies > 0 then
            target = livingAllies[math.random(#livingAllies)]
        else
            -- Target the summoner if no creatures are left
            target = self.session.summoner
        end
    elseif skill.target == "self" then
        target = enemy
    else
        -- Default to random enemy
        local livingAllies = {}
        for _, ally in ipairs(self.allies) do
            if not ally:isDead() then
                table.insert(livingAllies, ally)
            end
        end
        target = livingAllies[math.random(#livingAllies)]
    end
    
    return {
        actor = enemy,
        skill = skill,
        target = target
    }
end

-- Resolve one round of battle
-- summonerAction can be: { type = "spell", id = "cure", target = ... }, { type = "item", id = "hp_tonic", target = ... }, { type = "flee" }, { type = "formation" } or nil
function Battle:resolveRound(summonerAction)
    local roundEvents = {}
    
    -- 1. Execute Summoner's action first (Instant!)
    local sumAct = summonerAction and summonerAction[1]
    if sumAct then
        if sumAct.type == "spell" then
            local spell = self.session.loader.getSkill(sumAct.id)
            if spell and self.session.mp >= (spell.mpCost or 0) then
                self.session.mp = self.session.mp - (spell.mpCost or 0)
                table.insert(roundEvents, {
                    type = "text",
                    text = "Alex casts " .. spell.name .. "!"
                })
                for _, eff in ipairs(spell.effects or {}) do
                    local evs = effects.apply(eff, self.session.summoner, sumAct.target, self.session)
                    for _, ev in ipairs(evs) do
                        table.insert(roundEvents, ev)
                    end
                end
            end
        elseif sumAct.type == "item" then
            if self.session:hasItem(sumAct.id, 1) then
                self.session:addItem(sumAct.id, -1)
                local item = self.session.loader.getItem(sumAct.id)
                table.insert(roundEvents, {
                    type = "text",
                    text = "Alex uses " .. item.name .. "!"
                })
                for _, eff in ipairs(item.effects or {}) do
                    local evs = effects.apply(eff, self.session.summoner, sumAct.target, self.session)
                    for _, ev in ipairs(evs) do
                        table.insert(roundEvents, ev)
                    end
                end
            end
        elseif sumAct.type == "flee" then
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
                table.insert(roundEvents, { type = "text", text = "Failed to escape!" })
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
            -- Retrieve the player-chosen action for this slot (i + 1)
            local chosenAct = summonerAction and summonerAction[i + 1]
            local skill
            local target
            
            if chosenAct then
                if chosenAct.type == "spell" or chosenAct.type == "skill" then
                    skill = self.session.loader.getSkill(chosenAct.id) or self.session.loader.getSkill("attack")
                    target = chosenAct.target
                elseif chosenAct.type == "defend" then
                    -- Defend grants temporary defense increase or just logs defend
                    skill = { name = "Defend", speed = 50, effects = { { code = "STATE_ADD", value = "defending", dataId = "defending" } } }
                    target = ally
                else
                    skill = self.session.loader.getSkill("attack")
                    target = chosenAct.target
                end
            else
                skill = self.session.loader.getSkill("attack")
                -- Target first living enemy
                for _, enemy in ipairs(self.enemies) do
                    if not enemy:isDead() then target = enemy break end
                end
            end
            
            if target then
                local baseSpeed = (config.combat and config.combat.baseSpeed or 10) + ally.level * (config.combat and config.combat.speedPerLevel or 0.5)
                local actSpeed = skill.speed or 0
                local totalSpeed = baseSpeed + actSpeed
                table.insert(queue, {
                    actor = ally,
                    skill = skill,
                    target = target,
                    speed = totalSpeed
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
    for _, turn in ipairs(queue) do
        if not turn.actor:isDead() and not turn.target:isDead() then
            table.insert(roundEvents, {
                type = "action",
                actor = turn.actor,
                skill = turn.skill,
                target = turn.target
            })
            
            for _, eff in ipairs(turn.skill.effects or {}) do
                local evs = effects.apply(eff, turn.actor, turn.target, self.session)
                for _, ev in ipairs(evs) do
                    table.insert(roundEvents, ev)
                end
            end
            
            -- Check for victory/defeat mid-turn
            if self:isVictory() then
                table.insert(roundEvents, { type = "victory" })
                break
            elseif self:isDefeat() then
                table.insert(roundEvents, { type = "defeat" })
                break
            end
        end
    end
    
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
    
    -- MP drain at round end for each active monster
    if not self.session.currentMapData.safe then
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
                        text = ally.name .. " suffers from MP exhaustion!"
                    })
                end
            end
        end
    end
    
    self.round = self.round + 1
    return roundEvents
end

function Battle:isVictory()
    for _, enemy in ipairs(self.enemies) do
        if not enemy:isDead() then return false end
    end
    return true
end

function Battle:isDefeat()
    -- If the summoner is dead or all active creatures are dead
    if self.session.summoner:isDead() then return true end
    
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
    table.insert(list, self.session.summoner)
    for _, enemy in ipairs(self.enemies) do
        table.insert(list, enemy)
    end
    return list
end

battle.Battle = Battle

return battle
