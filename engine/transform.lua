-- Changing a creature's form without changing the creature.
--
-- Promotion, Egg hatching, Homunculus metamorphosis and the reversible Kappa
-- curse are ONE operation with different ways of choosing the destination.
-- All four must preserve the same things -- accumulated growth, the seed,
-- permanent item gains, learned skills, name, level, history -- and all four
-- swap the same things: form-defined MPD, capacities, affinities, innate
-- skills and passives.
--
-- Written as one primitive because four bespoke copies would drift, and
-- because "preserves history" is the rule with teeth: it is what the seeded
-- growth model exists to make possible.
local transform = {}

local growth = require("engine.growth")

-- Deterministic destination for a Homunculus: the eligible species whose
-- authored level-1 profile is closest to this creature's PERMANENT parameter
-- profile. Deterministic because the design shows the player its destination
-- before it happens -- a random result would make that preview a lie.
--
-- Ties break on actor id, so the answer never depends on table order.
function transform.classify(session, battler, eligibleIds)
    local loader = session.loader
    local best, bestScore
    local mine = {}
    for _, p in ipairs(growth.PARAMS) do
        mine[p] = (battler.growth and battler.growth[p] or 0)
            + (battler.paramPlus and battler.paramPlus[p] or 0)
    end
    for _, id in ipairs(eligibleIds or {}) do
        local ad = loader.getActor(id)
        if ad then
            local score = 0
            for _, p in ipairs(growth.PARAMS) do
                local theirs = (ad.baseParams or {})[p] or 0
                local diff = (mine[p] or 0) - theirs
                score = score + diff * diff
            end
            if bestScore == nil or score < bestScore
                or (score == bestScore and tostring(id) < tostring(best)) then
                best, bestScore = id, score
            end
        end
    end
    return best
end

-- Which outcome an Egg-like creature is destined for. Provenance is stored on
-- the instance when it is created, so the answer is fixed from the moment the
-- Egg exists rather than rolled at the moment it hatches -- a save cannot be
-- reloaded to fish for a better result.
function transform.hatchOutcome(battler, actorData)
    local table_ = (actorData or {}).hatchOutcomes
    if not table_ then return nil end
    local key = battler.provenance
    if key and table_[key] then return table_[key] end
    return table_.default
end

-- Swap `battler` onto `actorData`, keeping everything that makes it the same
-- creature. Returns the new battler.
--
-- opts.bonus       fixed one-time gains folded into the permanent record
-- opts.reversible  remember the current form so it can be restored later
-- opts.clearOrigin drop any remembered form (a reversion, or a promotion that
--                  settles the creature permanently)
function transform.into(session, battler, actorData, opts)
    opts = opts or {}
    local sessionMod = require("engine.session")

    local newB = sessionMod.Battler.new(actorData, battler.level, battler.growthSeed)
    newB.name = battler.name
    newB.exp = battler.exp
    newB.states = battler.states or {}
    newB.equipment = battler.equipment or { nil, nil, nil }
    newB.paramPlus = battler.paramPlus or newB.paramPlus
    newB.wardCharges = battler.wardCharges
    newB.history = battler.history or newB.history
    newB.provenance = battler.provenance
    newB.favoriteFood = battler.favoriteFood
    newB.favoriteFoodFound = battler.favoriteFoodFound

    -- THE rule: never recalculate. Battler.new just accumulated the
    -- DESTINATION form's budgets over every level already lived, which would
    -- rewrite this creature's past as though it had always been the new
    -- species. Only future levels may use the new budgets.
    newB.growthSeed = battler.growthSeed or newB.growthSeed
    newB.growth = battler.growth or newB.growth

    if opts.bonus then
        newB.growth = newB.growth or {}
        for _, p in ipairs(growth.PARAMS) do
            local gain = tonumber(opts.bonus[p])
            if gain then newB.growth[p] = (newB.growth[p] or 0) + gain end
        end
    end

    -- Reversion bookkeeping. A cursed creature remembers what it was and the
    -- level it must reach to change back; a natively recruited Kappa has no
    -- remembered form and so never reverts, which is what separates the two.
    if opts.reversible then
        newB.originForm = battler.actorData and battler.actorData.id
        newB.originAtLevel = battler.level
    elseif opts.clearOrigin then
        newB.originForm = nil
        newB.originAtLevel = nil
    else
        newB.originForm = battler.originForm
        newB.originAtLevel = battler.originAtLevel
    end

    -- Learned skills belong to the creature, not the species: anything the old
    -- form knew that is not innate to either form would otherwise vanish.
    local innate, known = {}, {}
    for _, sk in ipairs((battler.actorData and battler.actorData.skills) or {}) do innate[sk] = true end
    for _, sk in ipairs(newB.skills or {}) do known[sk] = true end
    for _, sk in ipairs(battler.skills or {}) do
        if not innate[sk] and not known[sk] then
            table.insert(newB.skills, sk)
            known[sk] = true
        end
    end

    -- HP last: Max HP is not known until the growth record and bonus are in
    -- place, and clamping early caps the creature at its OLD maximum.
    local maxHp = newB:getMaxHp(session)
    newB.hp = (battler.hp or 0) > 0 and math.min(maxHp, battler.hp) or maxHp
    return newB
end

return transform
