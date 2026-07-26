local targeting = require("engine.targeting")

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

    -- Global / No-target checks
    if item.target == "none" or (item.effects and #item.effects > 0 and not target) then
        for _, eff in ipairs(item.effects or {}) do
            if eff.type == "mp_heal" and session then
                local maxMp = session.maxMp or 999
                if (session.mp or 0) >= maxMp then
                    return false, "MP is already full"
                end
            elseif eff.type == "max_mp_plus" and session then
                local sys = (session.loader and session.loader.system
                    and session.loader.system.summoner) or {}
                if (session.maxMp or 0) >= (sys.maxMpCap or 9999) then
                    return false, "Maximum MP is already at its limit"
                end
            elseif eff.type == "recruit_egg" and session then
                local partyFull = (#(session.party or {}) >= 4)
                local reserveFull = (#(session.reserve or {}) >= 16)
                if partyFull and reserveFull then
                    return false, "Party and reserve are full"
                end
            end
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

    -- Resource check
    if skill.mpCost and actor then
        local actorMp = actor.mp or 0
        if actorMp < skill.mpCost then
            return false, "Not enough MP"
        end
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
    end

    return true, "OK"
end

return usability
