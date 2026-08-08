local targeting = require("engine.targeting")
local skill_cost = require("engine.skill_cost")
local config = require("engine.config")

local usability = {}

--- Checks if an item can be used in the given context and optional target.
-- @param item table Item object definition from loader
-- @param target table|nil Target battler object (optional)
-- @param context table|nil Context containing session, isField, battle, etc.
-- @return boolean usable, string reason
function usability.canUseItem(item, target, context)
    if not item then return false, "No item" end
    context = context or {}

    local isBattle = (context.battle ~= nil) or (context.isBattle == true)
    local isField = not isBattle

    -- Type check
    local itemType = item.type or "consumable"
    if itemType ~= "consumable" then
        return false, "Not consumable"
    end

    -- Scope check
    local scope = item.scope or "always"
    if scope == "none" then
        return false, "Cannot be used"
    elseif scope == "field" and isBattle then
        return false, "Cannot be used in battle"
    elseif scope == "battle" and isField then
        return false, "Cannot be used in field"
    end

    local session = context.session
    if item.meta and item.meta.dungeonOnly
        and (not session or not session.currentMapData or session.currentMapData.safe == true) then
        return false, "Can only be used in the dungeon"
    end

    -- Global / No-target checks
    if item.target == "none" or item.target == "party"
        or (item.effects and #item.effects > 0 and not target) then
        local canAffect = false
        local unavailableReason = "No effect"
        for _, eff in ipairs(item.effects or {}) do
            if eff.type == "mp_heal" and session then
                local maxMp = session.maxMp or 999
                if (session.mp or 0) < maxMp then canAffect = true
                else unavailableReason = "MP is already full" end
            elseif eff.type == "max_mp_plus" and session then
                local sys = (session.loader and session.loader.system
                    and session.loader.system.summoner) or {}
                if (session.maxMp or 0) < (sys.maxMpCap or 9999) then canAffect = true
                else unavailableReason = "Maximum MP is already at its limit" end
            elseif eff.type == "recruit_egg" and session then
                local formation = require("engine.formation")
                local partyFull = (#formation.denseMembers(session.party) >= config.MAX_PARTY_SIZE)
                local reserveFull = (#formation.denseMembers(session.reserve) >= config.MAX_RESERVE_SIZE)
                if not (partyFull and reserveFull) then canAffect = true
                else unavailableReason = "Party and reserve are full" end
            elseif (eff.type == "hp" or eff.type == "hp_heal") and session then
                for slot = 1, config.MAX_PARTY_SIZE do
                    local member = session.party and session.party[slot]
                    if member and not member:isDead() and member.hp < member:getMaxHp(session) then
                        canAffect = true
                        break
                    end
                end
            else
                canAffect = true
            end
        end
        if item.effects and #item.effects > 0 and not canAffect then
            return false, unavailableReason
        end
    end

    -- Target state validation if target provided
    if target then
        local spec = item.target or "ally"
        if spec ~= "none" then
            local exp = targeting.expand(spec)

            local isDead = target.isDead and target:isDead()
            if exp.state == "alive" and isDead then
                return false, "Target is dead"
            elseif exp.state == "dead" and not isDead then
                return false, "Target is not dead"
            end

            -- Check if healing HP on target that already has full HP
            if exp.state ~= "dead" and item.effects then
                local hasHpHeal = false
                for _, eff in ipairs(item.effects) do
                    if eff.type == "hp" or eff.type == "hp_heal" then
                        hasHpHeal = true
                        break
                    end
                end
                if hasHpHeal then
                    local maxHp = target.getMaxHp and target:getMaxHp(context.session) or target.maxHp or 999
                    if (target.hp or 0) >= maxHp then
                        return false, "HP is already full"
                    end
                end

                -- Skillbooks: refuse a creature that already knows the skill, so
                -- the item can't be consumed for nothing (same guard shape as the
                -- full-HP check above; effects.lua also fails soft if it slips by).
                -- Charge restoratives: refuse a creature whose charges are
                -- already full, in the same shape as the full-HP guard above.
                -- A Mana Nut must not be consumable for nothing, and "full"
                -- has to mean the same thing here as it does at Rest -- so it
                -- is skill_cost that answers, not a second copy of the rule.
                for _, eff in ipairs(item.effects) do
                    if eff.type == "restore_charges" then
                        local skill_cost = require("engine.skill_cost")
                        local anyRoom = false
                        for _, id in ipairs(target.skills or {}) do
                            if eff.skill == nil or eff.skill == id then
                                local sk = context.session and context.session.loader
                                    and context.session.loader.getSkill(id)
                                local cur, max = skill_cost.getCharges(target, id, sk, context.session)
                                if cur and max and max > 0 and cur < max then
                                    anyRoom = true
                                    break
                                end
                            end
                        end
                        if not anyRoom then
                            return false, "Charges are already full"
                        end
                    end
                end

                for _, eff in ipairs(item.effects) do
                    if eff.type == "learn_skill" then
                        local skillId = eff.skill or eff.value
                        for _, known in ipairs(target.skills or {}) do
                            if known == skillId then
                                return false, "Already knows that skill"
                            end
                        end
                    end
                end
            end
        end
    end

    return true, "OK"
end

--- Checks if a skill can be used by an actor on an optional target.
-- @param skill table Skill object definition
-- @param actor table Battler using the skill
-- @param target table|nil Target battler (optional)
-- @param context table|nil Context containing session, battle, etc.
-- @return boolean usable, string reason
function usability.canUseSkill(skill, actor, target, context)
    if not skill then return false, "No skill" end
    context = context or {}

    -- Skills historically only existed inside battle, so an unspecified
    -- context continues to mean battle. Field callers opt in explicitly with
    -- isField=true. This keeps headless tests and AI callers from becoming
    -- field calls merely because they do not carry a Battle object.
    local isField = context.isField == true
    local isBattle = not isField
    if context.battle ~= nil or context.isBattle == true then
        isBattle, isField = true, false
    end

    -- Skills author the same occasion vocabulary items use: `battle`, `field`,
    -- `always`, `none`. Missing or unknown scope is invalid rather than inferred
    -- from charges/effect shape, so editing mechanics cannot silently change
    -- where a skill is usable.
    local scope = skill.scope
    if scope ~= "battle" and scope ~= "field" and scope ~= "always" and scope ~= "none" then
        return false, "Invalid use scope"
    end
    if scope == "none" then
        return false, "Cannot be used"
    elseif scope == "field" and isBattle then
        return false, "Cannot be used in battle"
    elseif scope == "battle" and isField then
        return false, "Cannot be used in field"
    end

    -- Cost and availability: charges/Overcast for magic, warmup/cooldown/
    -- condition for physical. skill_cost owns the whole answer so that the
    -- player's menu, Battle:getAIAction and the status scene cannot disagree
    -- about whether a row is selectable -- one rule binds both sides, the same
    -- way FORCE_ACTION does (SPEC S1.12).
    --
    -- No skill costs MP any more. The only path from a skill to the Summoner's
    -- pool is Overcast, decided inside skill_cost.payment.
    if actor then
        local session = context.session
            or (context.battle and context.battle.session)
        local isEnemy = context.isEnemy
        if isEnemy == nil and context.battle and context.battle.enemies then
            for _, e in ipairs(context.battle.enemies) do
                if e == actor then isEnemy = true break end
            end
        end
        local blocked = skill_cost.blockedReason(skill, actor, session, isEnemy)
        if blocked then return false, blocked end
    end

    -- Target validation if target provided
    if target then
        local spec = skill.target or "enemy-any"
        local exp = targeting.expand(spec)

        local isDead = target.isDead and target:isDead()
        if exp.state == "alive" and isDead then
            return false, "Target is dead"
        elseif exp.state == "dead" and not isDead then
            return false, "Target is not dead"
        end

        -- A single-target restorative skill should not spend a persistent
        -- charge to heal zero HP. Party-wide actions handle this at the caller
        -- by checking whether at least one legal target can benefit.
        if exp.state ~= "dead" and exp.shape == "single" then
            local hasHpHeal = false
            for _, eff in ipairs(skill.effects or {}) do
                if eff.type == "hp" or eff.type == "hp_heal" then
                    hasHpHeal = true
                    break
                end
            end
            if hasHpHeal then
                local session = context.session
                    or (context.battle and context.battle.session)
                local maxHp = target.getMaxHp and target:getMaxHp(session) or target.maxHp or 999
                if (target.hp or 0) >= maxHp then
                    return false, "HP is already full"
                end
            end
        end
    end

    return true, "OK"
end

return usability
