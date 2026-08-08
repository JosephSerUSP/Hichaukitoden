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

-- ---------------------------------------------------------------------
-- HP cost (mostly physical)
-- ---------------------------------------------------------------------

--- What `skill` costs its user in HP. A flat number or a formula against the
--- user, so "a tenth of your max HP" scales with the creature.
---
--- HP is the one cost paid from a resource the player is ALREADY spending
--- defensively, which is what makes it interesting on a physical skill: the
--- price is measured in survivability, not in supply. It stacks with the other
--- gates rather than replacing them -- a skill may cost HP and have a cooldown.
function skill_cost.hpCost(skill, battler, session)
    if not skill or skill.hpCost == nil then return 0 end
    if type(skill.hpCost) == "number" then return math.max(0, math.floor(skill.hpCost)) end
    local view = formula.battlerView(battler, session)
    return math.max(0, math.floor(tonumber(formula.eval(skill.hpCost, { a = view, b = view })) or 0))
end

--- A skill may never be the thing that kills its user: paying must leave at
--- least 1 HP. Suicide would also hand the player a way to dodge permadeath's
--- consequences by choosing the moment, which the design does not want.
function skill_cost.canPayHp(skill, battler, session)
    local cost = skill_cost.hpCost(skill, battler, session)
    if cost <= 0 then return true end
    return (battler.hp or 0) > cost
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
    -- HP is charged alongside whatever the magic path decides, not instead of
    -- it: the two are independent costs, and a skill may carry both.
    local hp = skill_cost.hpCost(skill, battler, session)
    if hp > 0 then
        battler.hp = math.max(1, (battler.hp or 1) - hp)
    end

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
    battler.skillTimers = battler.skillTimers or {
        cooldown = {}, cooldownFresh = {}, warmup = {}
    }
    -- Saves never carry battle timers, but tests/debug callers can hand us an
    -- older timer shape. Normalize it here so the arming marker is harmless to
    -- anything created before this rule existed.
    battler.skillTimers.cooldown = battler.skillTimers.cooldown or {}
    battler.skillTimers.cooldownFresh = battler.skillTimers.cooldownFresh or {}
    battler.skillTimers.warmup = battler.skillTimers.warmup or {}
    return battler.skillTimers
end

--- Battle start: clear cooldowns, and arm warmups so a skill with
--- `warmup: 2` is unavailable for the first two rounds of THIS battle.
function skill_cost.beginBattle(battler, loader)
    battler.skillTimers = { cooldown = {}, cooldownFresh = {}, warmup = {} }
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
--
-- A cooldown armed during THIS round ignores this first round-end tick. The
-- action that started it happened inside the round that is now closing; no
-- subsequent round has elapsed yet. Without this marker cooldown:1 is armed
-- and immediately deleted by the same round_end, making it indistinguishable
-- from no cooldown at all (Darting Peck was the visible case).
function skill_cost.tick(battler)
    local t = timers(battler)
    for id, turnsLeft in pairs(t.cooldown) do
        if t.cooldownFresh[id] then
            t.cooldownFresh[id] = nil
        else
            local left = turnsLeft - 1
            t.cooldown[id] = (left > 0) and left or nil
        end
    end
    for id, turnsLeft in pairs(t.warmup) do
        local left = turnsLeft - 1
        t.warmup[id] = (left > 0) and left or nil
    end
end

function skill_cost.startCooldown(skill, battler)
    if not skill or not (skill.cooldown and skill.cooldown > 0) then return end
    local t = timers(battler)
    t.cooldown[skill.id] = skill.cooldown
    t.cooldownFresh[skill.id] = true
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

    if not skill_cost.canPayHp(skill, battler, session) then
        return "Not enough HP"
    end

    local how, reason = skill_cost.payment(skill, battler, session, isEnemy)
    if not how then return reason or "Unavailable" end

    return nil
end

--- What a skill's cost LOOKS like, as coloured segments, for any surface that
--- lists skills (the battle console, the status page).
---
--- Built here rather than in the scene script because the cost display and the
--- cost rules must not be able to disagree: a row that shows "3/6" and a
--- predicate that says "out of charges" would be a bug the player sees before
--- anyone else. Each segment is { text, color }, where color names a key in
--- ui.costColors -- the engine says WHICH resource, presentation owns the tone.
---
--- Charges show as the REMAINING count alone, not "remaining/max": the battle
--- console's skill column is ~76px wide, and "8/8" cost enough of it to
--- truncate "Wind Blade" into "Wind Blad". Remaining-only also reads the way
--- the resource actually behaves -- a magazine count -- and the maximum is
--- already on the status page, where there is room for it.
---
--- Overcast replaces the count once the pool is empty, because that IS the
--- cost at that point.
---
--- `verbose` is the roomier reading for the status page, where the pane is
--- 20.5 tiles instead of 15 and the player is planning rather than acting:
--- charges show as remaining/max, and an Overcast price is shown ALONGSIDE
--- them rather than only once the pool runs dry -- out of battle, knowing what
--- the spell will cost you when it does run dry is the useful part.
function skill_cost.displayCost(skill, battler, session, isEnemy, verbose)
    local segments = {}
    if not skill or not battler then return segments end

    local hp = skill_cost.hpCost(skill, battler, session)
    if hp > 0 then
        table.insert(segments, { text = tostring(hp) .. "HP", color = "hp" })
    end

    local current, max = skill_cost.getCharges(battler, skill.id, skill, session)
    local overcastMp = skill.overcast and skill.overcast.mp
    if current ~= nil then
        if verbose then
            -- An Overcast-only skill (max 0) has no pool worth printing --
            -- "0/0" says nothing. Its price is the MP segment below.
            if max and max > 0 then
                table.insert(segments, {
                    text = tostring(current) .. "/" .. tostring(max), color = "charges" })
            end
            if overcastMp and not isEnemy then
                table.insert(segments, { text = tostring(overcastMp) .. "MP", color = "mp" })
            end
        elseif current > 0 then
            table.insert(segments, { text = tostring(current), color = "charges" })
        elseif overcastMp and not isEnemy then
            table.insert(segments, { text = tostring(overcastMp) .. "MP", color = "mp" })
        elseif max and max > 0 then
            -- Spent, with no Overcast to fall back on. Show the empty pool
            -- rather than nothing, so the row explains itself.
            table.insert(segments, { text = "0", color = "charges" })
        end
    end

    -- Cooldown/warmup are availability costs measured in battle turns rather
    -- than resources. Put the active timer at the far right of the cost column
    -- so a blocked skill explains itself at a glance ("1T", "2T", ...), even
    -- while its selected row keeps the normal cursor colour. The renderer
    -- already greys cost segments for blocked rows.
    local warm = skill_cost.warmupLeft(skill, battler)
    local cool = skill_cost.cooldownLeft(skill, battler)
    local turns = warm > 0 and warm or cool
    if turns > 0 then
        table.insert(segments, { text = tostring(turns) .. "T", color = "charges" })
    end

    return segments
end

return skill_cost