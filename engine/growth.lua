-- Seeded, budget-first creature growth (docs/design/creature-parameters.md).
--
-- Growth is ADDITIVE, PERMANENT, SEEDED PER INSTANCE and intentionally uneven.
-- It is not recalculated from species and current level, which is what the
-- engine used to do: `base * (1 + rate * multiplier * (level-1)^exponent)`, a
-- smooth curve every creature of a species shared exactly. Two Pixies at level
-- 12 were the same Pixie, and there was nothing for a promotion to preserve --
-- change the species and every past level silently re-derived.
--
-- Each form authors budgets for three bands (levels 2-10, 11-20, 21-30). An
-- instance's seed divides each budget into uneven packets, so a creature has a
-- HISTORY: a Pixie with a +60 HP budget for levels 21-30 might receive
-- +3, +4, +2, +3, +16, +4, +3, +17, +4, +4 -- every level raises HP, but two
-- are memorable spurts.
--
-- Determinism matters twice over. A creature generated directly at level 20
-- replays the same history it would have lived through, and reloading a save
-- can never reroll a level-up. So this uses its own LCG rather than
-- math.random: touching the global stream would both make growth depend on
-- when it happened to be computed and shift every battle roll after it.
local growth = {}

-- Park-Miller. Small, deterministic, and entirely ours -- see above for why it
-- must not be math.random.
local function lcg(seed)
    local s = math.floor(seed) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

-- The parameters that receive level growth. mpd/mxa/mxp are form-defined and
-- never grow (creature-parameters.md), which is why they are absent.
growth.PARAMS = { "maxHp", "atk", "def", "mat", "mdf" }

local DEFAULT_BANDS = {
    { from = 2,  to = 10 },
    { from = 11, to = 20 },
    { from = 21, to = 30 },
}

-- Splits `budget` across `count` levels: never below `minEach`, uneven, and
-- summing to exactly the budget. Two levels are picked as spurts and weighted
-- heavily, which is what turns a curve into a story the player can notice.
--
-- The leftover from flooring is handed out by largest fractional part rather
-- than to the first levels, so the unevenness comes from the seed and not from
-- an artefact of the rounding.
local function split(budget, count, minEach, rand)
    local out = {}
    if count <= 0 then return out end

    budget = math.max(budget, minEach * count)
    local remaining = budget - minEach * count
    for i = 1, count do out[i] = minEach end

    local weights, total = {}, 0
    for i = 1, count do
        weights[i] = 0.5 + rand()
        total = total + weights[i]
    end
    if count >= 4 then
        for _ = 1, 2 do
            local pick = 1 + math.floor(rand() * count)
            if pick > count then pick = count end
            total = total + weights[pick] * 4
            weights[pick] = weights[pick] * 5
        end
    end

    local assigned, fracs = 0, {}
    for i = 1, count do
        local exact = remaining * (weights[i] / total)
        local whole = math.floor(exact)
        out[i] = out[i] + whole
        assigned = assigned + whole
        fracs[i] = { i = i, f = exact - whole }
    end
    table.sort(fracs, function(x, y)
        if x.f ~= y.f then return x.f > y.f end
        return x.i < y.i
    end)
    local leftover = remaining - assigned
    for k = 1, leftover do
        local pick = fracs[((k - 1) % count) + 1]
        out[pick.i] = out[pick.i] + 1
    end
    return out
end

-- The band an actor authors for `level`, or nil when the level is past
-- everything authored (growth simply stops rather than extrapolating).
local function bandFor(actorData, level)
    local bands = (actorData and actorData.growthBands) or DEFAULT_BANDS
    for idx, band in ipairs(bands) do
        if level >= (band.from or 0) and level <= (band.to or 0) then
            return band, idx
        end
    end
    return nil
end

-- Every packet for one band, as packets[levelOffset][param]. Computed whole
-- because the split has to see the band's level count; callers want one level.
local function bandPackets(actorData, band, bandIndex, seed)
    local count = (band.to or 0) - (band.from or 0) + 1
    if count <= 0 then return {} end

    local packets = {}
    for i = 1, count do packets[i] = {} end

    for pIdx, param in ipairs(growth.PARAMS) do
        local budget = math.floor(tonumber(band[param]) or 0)
        -- Every stat is seeded on its own stream, so two stats in one band do
        -- not share a spurt level and the packets stay independent.
        local rand = lcg(seed + bandIndex * 7919 + pIdx * 104729)

        -- Narrow per-instance variation on the authored budget (about +-5%),
        -- so an instance can be lucky in one statistic without receiving a
        -- materially larger total.
        if budget > 0 then
            budget = math.max(1, math.floor(budget * (0.95 + rand() * 0.10) + 0.5))
        end

        -- HP rises at EVERY level: a level-up that shows no change reads as a
        -- bug even when other stats moved. Other stats may sit out a level.
        local minEach = (param == "maxHp") and 1 or 0
        local parts = split(budget, count, minEach, rand)
        for i = 1, count do packets[i][param] = parts[i] end
    end

    return packets
end

-- The gains for reaching `level` (so level 1 grants nothing -- base params ARE
-- level 1). Deterministic in (actorData, seed, level).
function growth.packetFor(actorData, seed, level)
    if level <= 1 then return {} end
    local band, bandIndex = bandFor(actorData, level)
    if not band then return {} end
    local packets = bandPackets(actorData, band, bandIndex, seed or 0)
    return packets[level - (band.from or 0) + 1] or {}
end

-- Total accumulated growth from level 2 up to `level`. This is the replay the
-- design calls for: a creature generated directly at level 20 lives the same
-- history as one that walked there, and a reload cannot reroll a level-up.
function growth.accumulate(actorData, seed, level)
    local total = {}
    for _, param in ipairs(growth.PARAMS) do total[param] = 0 end
    for l = 2, (level or 1) do
        local packet = growth.packetFor(actorData, seed, l)
        for _, param in ipairs(growth.PARAMS) do
            total[param] = total[param] + (packet[param] or 0)
        end
    end
    return total
end

-- A stable seed for a battler that was never given one. Catalog Units author
-- this explicitly as `defaultGrowthSeed`: resource identity is an opaque handle
-- and changing its spelling must never reroll growth. Persistent creatures get
-- a real per-instance seed when recruited, which is what makes two Pixies
-- different.
--
-- Tiny ad-hoc Battler tables used by focused tests/tools are not authored Units
-- and may omit the field. They receive one neutral deterministic seed rather
-- than deriving mechanics from an arbitrary `id` string. G1 requires the field
-- on every real catalog Unit.
function growth.defaultSeed(actorData)
    local seed = actorData and actorData.defaultGrowthSeed
    if seed == nil then return 1 end
    if type(seed) ~= "number" or seed ~= math.floor(seed)
        or seed <= 0 or seed >= 2147483647 then
        error("Unit '" .. tostring(actorData and actorData.id)
            .. "' has invalid defaultGrowthSeed " .. tostring(seed))
    end
    return seed
end

return growth
