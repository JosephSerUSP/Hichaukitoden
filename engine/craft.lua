local traits = require("engine.traits")

-- Item Creation: signatures, ideation and resolution.
--
-- See docs/game design/itemCreation.md for the design and why. In short:
--
--   * FORM is categorical and comes from the crafter. A cook cannot forge a
--     sword -- not because a threshold forbids it, but because cooking is the
--     act of making food. So there is no single craft space; there is one per
--     discipline, each small and dense.
--   * ELEMENT is a colour space. Red > Green > Blue > Red is a cycle, so those
--     three sit 120 degrees apart on a hue plane; White <-> Black is a true
--     opposition, so it is one signed value axis; non-elemental is the origin.
--   * SIGNATURES ARE READ, not authored. An item's element comes from its
--     traits, effects and name; its intensity from its price. Only discipline
--     membership and an intensity grade are ever hand-written, because those
--     are judgements no property encodes.
--
-- Every tunable lives in data/engine.json (craftRules, craftElementSources,
-- craftLexicon, disciplineDefaults, intensityGrades).
local craft = {}

local HUE_ORDER = { "Red", "Green", "Blue" }
local HUE_DEG = { Red = 90, Green = 210, Blue = 330 }
local HCOS, HSIN = {}, {}
for i, e in ipairs(HUE_ORDER) do
    HCOS[i] = math.cos(HUE_DEG[e] * math.pi / 180)
    HSIN[i] = math.sin(HUE_DEG[e] * math.pi / 180)
end

local DEFAULTS = {
    crafterPull = 0.30, alpha = 0.50, intensityWeight = 0.70,
    scatter = 0.24, scatterFalloff = 1.2,
    reachBase = 14.0, reachPerStat = 14.0, beyondReachCost = 0.12,
    foreignIngredientWorth = 0.20, statDivisor = 20.0,
    intensityScale = 40.0, crafterIntensityScale = 10.0,
    coherenceRange = 1.2,
}

local function rules(loader)
    local r = (loader.engine and loader.engine.craftRules) or {}
    return setmetatable(r, { __index = DEFAULTS })
end

-- Signature cache. Loader tables are shared and immutable (AGENTS.md), so the
-- derived signature is never written back onto the item; it is held here and
-- dropped wholesale when the loader changes.
local cache, cacheLoader = {}, nil
local function cacheFor(loader)
    if cacheLoader ~= loader then cache, cacheLoader = {}, loader end
    return cache
end
function craft.reset() cache, cacheLoader = {}, nil end

-- ---------------------------------------------------------------- element --

-- Weight map -> a point in the colour space. Normalised by total weight, so
-- what survives is the MIX: two Reds and one Red point the same direction.
function craft.elemVec(w)
    local hx, hy, tot = 0, 0, 0
    for i = 1, 3 do
        local v = w[HUE_ORDER[i]] or 0
        hx = hx + v * HCOS[i]
        hy = hy + v * HSIN[i]
    end
    for _, v in pairs(w) do tot = tot + math.abs(v) end
    if tot <= 0 then return 0, 0, 0 end
    return hx / tot, hy / tot, ((w.White or 0) - (w.Black or 0)) / tot
end

local function addW(dst, src, k)
    if not src then return end
    for e, v in pairs(src) do dst[e] = (dst[e] or 0) + v * k end
end

-- "Philosopher's" must reach the lexicon entry "philosopher".
local function lexScan(text, dst, weight, lexicon)
    if not text or weight <= 0 then return end
    for word in tostring(text):lower():gmatch("[%a']+") do
        local w = word:gsub("'s$", ""):gsub("'", "")
        local el = lexicon[w]
        if el then dst[el] = (dst[el] or 0) + weight end
    end
end

-- ------------------------------------------------------------ membership --

-- Which disciplines can PRODUCE this item. Authored membership wins; otherwise
-- the default from what the item plainly is. Ingredients are ungated, so this
-- never restricts what an item may be used to MAKE.
function craft.disciplinesOf(item, loader)
    local meta = item.meta or {}
    if type(meta.disciplines) == "table" and #meta.disciplines > 0 then
        return meta.disciplines
    end
    local d = (loader.engine and loader.engine.disciplineDefaults) or {}
    local kind = item.equipType and (d.byEquipType or {})[item.equipType]
    if not kind then
        for _, ef in ipairs(item.effects or {}) do
            kind = (d.byEffect or {})[ef.type]
            if kind then break end
        end
    end
    if not kind then kind = (d.byType or {})[item.type] end
    return kind and { kind } or {}
end

-- ------------------------------------------------------------- signature --

function craft.signature(item, loader)
    if not item then return nil end
    local c = cacheFor(loader)
    if c[item.id] then return c[item.id] end

    local src = (loader.engine and loader.engine.craftElementSources) or {}
    local lexicon = (loader.engine and loader.engine.craftLexicon) or {}
    local el = {}

    for _, t in ipairs(item.traits or {}) do
        if t.code == "ELEMENT_CHANGE" and t.dataId then
            if loader.elements and loader.elements[t.dataId] then
                addW(el, { [t.dataId] = 1 }, src.elementChangeWeight or 3.0)
            end
        elseif t.code == "PARAM_PLUS" and t.dataId then
            addW(el, (src.params or {})[t.dataId], src.paramWeight or 0.7)
        else
            addW(el, (src.traits or {})[t.code], 1)
        end
    end

    for _, ef in ipairs(item.effects or {}) do
        addW(el, (src.effects or {})[ef.type], 1)
        if ef.param then addW(el, (src.params or {})[ef.param], src.paramWeight or 0.7) end
    end

    lexScan(item.name, el, src.nameWeight or 2.0, lexicon)
    lexScan(item.description, el, src.descriptionWeight or 0.5, lexicon)

    -- Intensity from price: the game's own hand-tuned statement of worth, and
    -- every item has one. Log-scaled so 1g..9999g spreads across the range.
    local intensity = 10 * math.log((item.cost or 0) + 1, 10)
    local grade = (item.meta or {}).intensityGrade
    if grade then
        for _, g in ipairs((loader.engine and loader.engine.intensityGrades) or {}) do
            if g.grade == grade then intensity = intensity * (g.mult or 1) break end
        end
    end

    local hx, hy, val = craft.elemVec(el)
    local disciplines = craft.disciplinesOf(item, loader)
    local set = {}
    for _, d in ipairs(disciplines) do set[d] = true end

    local sig = {
        el = el, hx = hx, hy = hy, val = val, intensity = intensity,
        disciplines = disciplines, produces = set,
    }
    c[item.id] = sig
    return sig
end

-- Items the given discipline can produce. `meta.craftable = false` opts an item
-- out entirely (quest and key items), because signatures are derived and every
-- item would otherwise acquire one.
function craft.pool(kind, loader)
    local out = {}
    for _, item in ipairs(loader.items or {}) do
        if (item.meta or {}).craftable ~= false then
            local sig = craft.signature(item, loader)
            if sig.produces[kind] then table.insert(out, item) end
        end
    end
    return out
end

-- Whether an item may be SELECTED as an ingredient. Independent of
-- `craft.pool` above, which answers whether an item may be PRODUCED: monster
-- remains are ingredients that are never output (`craftable: false` alone),
-- while a promotion key is neither, and only the second exclusion can say so.
-- One shared reading so the scene's list, the validator and the editor cannot
-- drift apart on what is selectable.
function craft.isIngredient(item)
    return item ~= nil and (item.meta or {}).craftIngredient ~= false
end

-- -------------------------------------------------------------- blending --

-- The stronger element asserts itself in a mixture instead of meeting at the
-- midpoint. Reuses the battle affinity table: one relationship, two systems.
-- The skill layer's rates are the right analogue -- one element overcoming
-- another is exactly what happens in the pot.
local function dominanceFactor(a, b, loader)
    local ta, tb = 0, 0
    for _, v in pairs(a) do ta = ta + v end
    for _, v in pairs(b) do tb = tb + v end
    if ta <= 0 or tb <= 0 then return 1 end

    local er = (loader.engine and loader.engine.elementRules) or {}
    local strong = 1 + (er.skillStrongBonus or 0.5)
    local weak = er.skillWeakMultiplier or 0.65
    local f = 1
    for e, av in pairs(a) do
        local data = loader.elements and loader.elements[e]
        if data then
            for g, bv in pairs(b) do
                local prod = (av / ta) * (bv / tb)
                for _, s in ipairs(data.strongAgainst or {}) do
                    if s == g then f = f + prod * (strong - 1) end
                end
                for _, w in ipairs(data.weakAgainst or {}) do
                    if w == g then f = f - prod * (1 - weak) end
                end
            end
        end
    end
    return math.max(0.1, f)
end

-- --------------------------------------------------------------- crafter --

-- INNATE elements only. Never traits.getElements: crafting identity is what a
-- creature IS, not what it is wearing, or a bag of ELEMENT_CHANGE trinkets
-- would collapse the whole crafter roster into one.
function craft.crafterVec(crafter)
    local w = {}
    for _, e in ipairs((crafter.actorData and crafter.actorData.elements) or {}) do
        w[e] = (w[e] or 0) + 1
    end
    local hx, hy, val = craft.elemVec(w)
    return hx, hy, val
end

function craft.crafterStat(crafter, session)
    local loader = session.loader
    local kind = crafter.actorData and crafter.actorData.discipline
    local stat = "atk"
    for _, d in ipairs((loader.engine and loader.engine.disciplines) or {}) do
        if d.kind == kind then stat = d.stat or stat break end
    end
    local raw = (stat == "level") and (crafter.level or 1)
                 or traits.getParam(crafter, stat, session)
    return (raw or 0) / rules(loader).statDivisor
end

-- How far into its own discipline a crafter can reach. A falloff, not a wall:
-- see craft.distance. CRAFT_YIELD_RATE extends it, so a passive can make a
-- creature a better crafter without touching a battle stat.
function craft.reach(crafter, session)
    local r = rules(session.loader)
    local rate = 1 + (traits.getRate(crafter, "CRAFT_YIELD_RATE", session) or 0)
    return (r.reachBase + r.reachPerStat * craft.crafterStat(crafter, session)) * rate
end

-- --------------------------------------------------------------- ideation --

-- rng: a function returning [0,1). The scene seeds it from the attempt's stored
-- seed so a reload reproduces an outcome while a fresh attempt rolls anew.
local function gauss(rng)
    return (rng() + rng() + rng() - 1.5) * 1.4
end

function craft.ideate(itemA, itemB, crafter, session, rng)
    local loader = session.loader
    local r = rules(loader)
    local a = craft.signature(itemA, loader)
    local b = craft.signature(itemB, loader)
    local kind = crafter.actorData and crafter.actorData.discipline

    local fa = dominanceFactor(a.el, b.el, loader)
    local fb = dominanceFactor(b.el, a.el, loader)
    local blend = {}
    addW(blend, a.el, fa)
    addW(blend, b.el, fb)
    local hx, hy, val = craft.elemVec(blend)

    -- The crafter is the third vertex: two ingredients only define a line.
    local k = r.crafterPull
    local cx, cy, cv = craft.crafterVec(crafter)
    hx = hx * (1 - k) + cx * k
    hy = hy * (1 - k) + cy * k
    val = val * (1 - k) + cv * k

    -- Foreign ingredients steer but do not empower: an ingredient this craft has
    -- no use for still tints the mix, but contributes little of its worth. Iron
    -- in a stockpot tints the stew and yields slop.
    local f = r.foreignIngredientWorth
    local wa = a.produces[kind] and 1 or f
    local wb = b.produces[kind] and 1 or f
    local stat = craft.crafterStat(crafter, session)
    local intensity = (a.intensity * wa + b.intensity * wb) / 2
                    + r.alpha * stat * r.crafterIntensityScale

    -- Precision is scatter, and it shrinks as the discipline stat grows. This
    -- is the whole of the "barely reached it" effect -- there is no anomaly.
    if rng then
        local sigma = r.scatter / (1 + r.scatterFalloff * stat)
        hx = hx + gauss(rng) * sigma
        hy = hy + gauss(rng) * sigma
        val = val + gauss(rng) * sigma
        intensity = intensity + gauss(rng) * sigma * (r.intensityScale * 0.65)
    end

    return { hx = hx, hy = hy, val = val, intensity = intensity,
             kind = kind, nativeA = a.produces[kind] or false,
             nativeB = b.produces[kind] or false }
end

-- ------------------------------------------------------------- resolution --

function craft.distance(point, item, reach, loader)
    local r = rules(loader)
    local sig = craft.signature(item, loader)
    local dx, dy = point.hx - sig.hx, point.hy - sig.hy
    local dv = point.val - sig.val
    local over = sig.intensity - reach
    return math.sqrt(dx * dx + dy * dy + dv * dv)
         + r.intensityWeight * math.abs(point.intensity - sig.intensity) / r.intensityScale
         + (over > 0 and over * r.beyondReachCost or 0)
end

-- Ranked neighbourhood, nearest first. The scene shows this as the reel, which
-- is how the player reads coherence without ever seeing a number.
function craft.resolve(point, crafter, session)
    local loader = session.loader
    local reach = craft.reach(crafter, session)
    local ranked = {}
    for _, item in ipairs(craft.pool(point.kind, loader)) do
        table.insert(ranked, { item = item, distance = craft.distance(point, item, reach, loader) })
    end
    table.sort(ranked, function(x, y)
        if x.distance == y.distance then return x.item.id < y.item.id end
        return x.distance < y.distance
    end)
    return ranked
end

-- 1 = dead on, 0 = nowhere near. Drives the crafter's reaction line; the bands
-- and their wording live in the scene, not here.
function craft.coherence(distance, loader)
    local range = rules(loader).coherenceRange
    local c = 1 - (distance / range)
    if c < 0 then return 0 elseif c > 1 then return 1 end
    return c
end

return craft
