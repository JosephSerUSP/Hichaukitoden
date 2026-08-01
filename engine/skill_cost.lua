-- Skill costs: Charges + Overcast (magic), Cooldown/Warmup/Condition
-- (physical). See docs/design/skill-costs.md.
--
-- One module because both families answer the SAME question the battle menu
-- asks -- "is this row selectable, and if not, why" -- and that question is
-- asked from three places (the player's submenu, Battle:getAIAction, the
-- status scene). `usability.canUseSkill` is the public predicate; everything
-- here is the machinery behind it. Splitting magic and physical into two
-- modules would mean two places to keep the answer consistent.
--
-- No skill costs MP. MP is the Summoner's shared expedition pool (SPEC S1.11);
-- Overcast is the ONE path from a skill to it, and it is deliberately steep.

local formula = require("engine.formula")
local conditions = require("engine.conditions")

local skill_cost = {}

-- ---------------------------------------------------------------------
-- Charges (magic)
-- ---------------------------------------------------------------------

--- Maximum charges for `skill` in the hands of `battler`.
--
-- Authored as a formula against the caster, so a promoted caster gets more
-- castings without the skill row changing. It reads BASE mdf (`b.base.mdf`),
-- never final: equipment must not be able to buy charges, and a PARAM_RATE
-- debuff must not be able to shrink a creature's maximum while it holds spent
-- charges. See docs/design/skill-costs.md S5.
--
-- A literal 0 is preserved (an Overcast-only skill -- a pool that exists and is
-- permanently empty, e.g. a dragon's Breath). Everything else floors at 1,
-- because a formula that rounds to nothing would silently make the skill
-- uncastable in a way no author intended.
--
-- Returns nil when the skill declares no `charges` key at all: not a magic
-- skill, no pool, nothing to spend.
function skill_cost.maxCharges(skill, battler, session)
    if not skill or skill.charges == nil then return nil end

    if type(skill.charges) == "number" then
        if skill.charges <= 0 then return 0 end
        return math.max(1, math.floor(skill.charges))
    end

    local env = { b = formula.battlerView(battler, session),
                  a = formula.battlerView(battler, session) }
    local value = tonumber(formula.eval(skill.charges, env)) or 0
    if value <= 0 then return 0 end
    return math.max(1, math.floor(value))
end

--- Current charges. Missing key = full, so a newly summoned, promoted or
--- loaded-from-an-old-save creature starts topped up rather than empty.
function skill_cost.getCharges(battler, skillId, skill, session)
    local max = skill_cost.maxCharges(skill, battler, session)
    if max == nil then return nil, nil end
    local stored = battler and battler.charges and battler.charges[skillId]
    if stored == nil then return max, max end
    return math.max(0, math.min(stored, max)), max
end

--- Can this actor pay for one casting, and how?
-- Returns "charge", "overcast", or nil plus a reason.
--
-- Overcast is offered ONLY at zero charges: it is never a cheaper alternative
-- to spending a charge, so there is no optimization for the player to think
-- about. Enemies never Overcast -- they have no Summoner and no MP pool, so an
-- enemy out of charges is out of that spell, which is the intended pressure
-- release for a long fight.
function skill_cost.payment(skill, battler, session, isEnemy)
    local current = select(1, skill_cost.getCharges(battler, skill and skill.id, skill, session))
    if current == nil then return "free" end
    if current > 0 then return "charge" end

    local mp = skill.overcast and skill.overcast.mp
    if not mp then return nil, "Out of charges" end
    if isEnemy then return nil, "Out of charges" end
    if (session and session.mp or 0) < mp then
        return nil, "Not enough MP to Overcast"
    end
    return "overcast"
end

--- Spends the cost decided by `payment`. Called from the ONE place a skill
--- actually resolves, so the charge path and the Overcast path cannot drift.
function skill_cost.spend(skill, battler, session, isEnemy)
    local how = skill_cost.payment(skill, battler, session, isEnemy)
    if how == "charge" then
        local current, max = skill_cost.getCharges(battler, skill.id, skill, session)
        battler.charges = battler.charges or {}
        battler.charges[skill.id] = math.max(0, current - 1)
        return "charge"
    elseif how == "overcast" then
        session.mp = math.max(0, (session.mp or 0) - (skill.overcast.mp or 0))
        return "overcast"
    end
    return how
end

--- Full refill for one battler: Rest. Clearing the table (rather than writing
--- each skill to its max) means the "missing key = full" rule above does the
--- work, and a creature that learns a skill later is already full of it.
function skill_cost.restAll(battler)
    if battler then battler.charges = nil end
end

--- Partial restore (the item/food channel). `skillId` nil = every skill the
--- creature knows; `amount` "all" = that skill back to full.
-- Returns the number of charges actually restored, so a caller can refuse to
-- consume an item that would do nothing.
function skill_cost.restore(battler, session, loader, skillId, amount)
    if not battler then return 0 end
    local restored = 0
    for _, id in ipairs(battler.skills or {}) do
        if skillId == nil or id == skillId then
            local skill = loader and loader.getSkill and loader.getSkill(id)
            local current, max = skill_cost.getCharges(battler, id, skill, session)
            -- A skill with no pool, or an Overcast-only skill (max 0), has
            -- nothing to restore and must not soak up the item's effect.
            if current and max and max > 0 and current < max then
                local grant = (amount == "all") and max or (tonumber(amount) or 0)
                local new = math.min(max, current + grant)
                battler.charges = battler.charges or {}
                battler.charges[id] = new
                restored = restored + (new - current)
            end
        end
    end
    return restored
end

-- ---------------------------------------------------------------------
-- Availability gates (physical)
-- ---------------------------------------------------------------------
--
-- Cooldown and warmup counters are BATTLE-scoped: they live in
-- `battler.skillTimers` and are cleared when a battle starts, the way states
-- are backed up and restored around a round. Charges answer "how much is left
-- of the day" and belong in the save; these answer "what can I do this turn"
-- and do not. Different lifetimes, different homes.

local function timers(battler)
    battler.skillTimers = battler.skillTimers or { cooldown = {}, warmup = {} }
    return battler.skillTimers
end

--- Battle start: clear cooldowns, and arm warmups so a skill with
--- `warmup: 2` is unavailable for the first two rounds of THIS battle.
function skill_cost.beginBattle(battler, loader)
    battler.skillTimers = { cooldown = {}, warmup = {} }
    for _, id in ipairs(battler.skills or {}) do
        local skill = loader and loader.getSkill and loader.getSkill(id)
        if skill and (skill.warmup or 0) > 0 then
            battler.skillTimers.warmup[id] = skill.warmup
        end
    end
end

--- Battle end: drop the counters entirely. A cooldown never follows a creature
--- out of the fight it was spent in.
function skill_cost.endBattle(battler)
    if battler then battler.skillTimers = nil end
end

--- One round elapsed. Ticked from the `battle.round_end` flow via the
--- TICK_SKILL_TIMERS command, so the tick is authored data rather than another
--- hardcoded branch in battle.lua.
function skill_cost.tick(battler)
    local t = timers(battler)
    for id, turnsLeft in pairs(t.cooldown) do
        local left = turnsLeft - 1
        t.cooldown[id] = (left > 0) and left or nil
    end
    for id, turnsLeft in pairs(t.warmup) do
        local left = turnsLeft - 1
        t.warmup[id] = (left > 0) and left or nil
    end
end

function skill_cost.startCooldown(skill, battler)
    if not skill or not (skill.cooldown and skill.cooldown > 0) then return end
    timers(battler).cooldown[skill.id] = skill.cooldown
end

function skill_cost.cooldownLeft(skill, battler)
    if not battler or not battler.skillTimers then return 0 end
    return battler.skillTimers.cooldown[skill and skill.id] or 0
end

function skill_cost.warmupLeft(skill, battler)
    if not battler or not battler.skillTimers then return 0 end
    return battler.skillTimers.warmup[skill and skill.id] or 0
end

--- Authored condition: one of the prefixed forms engine/conditions.lua owns
--- (flag:, hasItem:, gold:, questStatus:, state:), else a formula against the
--- actor. The shared module exists precisely so a new gate does not grow a
--- private parser that drifts from the interpreter's IF.
function skill_cost.conditionMet(skill, battler, session)
    if not skill or not skill.condition then return true end
    local matched, result = conditions.evalPrefixed(skill.condition, session, battler)
    if matched then return result and true or false end
    local env = { a = formula.battlerView(battler, session),
                  b = formula.battlerView(battler, session) }
    local value = formula.eval(skill.condition, env)
    return (value ~= nil and value ~= false and value ~= 0)
end

-- ---------------------------------------------------------------------
-- The one predicate
-- ---------------------------------------------------------------------

--- Why (if at all) `skill` is unavailable to `battler` right now.
-- Returns nil when usable, else a short player-facing reason. The reason
-- matters: a known skill is never hidden from the menu, it is shown greyed
-- with this text, because a row that vanishes looks like a bug.
function skill_cost.blockedReason(skill, battler, session, isEnemy)
    if not skill or not battler then return nil end

    local warm = skill_cost.warmupLeft(skill, battler)
    if warm > 0 then
        return "Ready in " .. warm .. (warm == 1 and " round" or " rounds")
    end

    local cool = skill_cost.cooldownLeft(skill, battler)
    if cool > 0 then
        return "Cooling down (" .. cool .. ")"
    end

    if not skill_cost.conditionMet(skill, battler, session) then
        -- conditionText is REQUIRED alongside condition (G1 enforces it):
        -- a formula cannot produce readable text, and an unexplained grey row
        -- is a bug report waiting to happen.
        return skill.conditionText or "Unavailable"
    end

    local how, reason = skill_cost.payment(skill, battler, session, isEnemy)
    if not how then return reason or "Unavailable" end

    return nil
end

return skill_cost
