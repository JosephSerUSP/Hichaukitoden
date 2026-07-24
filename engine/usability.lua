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

    -- Target state validation if target provided
    if target then
        local spec = item.target or item.targetScope or "ally"
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
