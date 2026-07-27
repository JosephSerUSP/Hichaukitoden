-- Sandboxed formula evaluation per SPEC S5 (docs/archive/plans/overhaul-3).
-- Formulas are Lua expressions over a documented, read-only context plus a
-- small whitelist of math helpers. Every exposed token is documented in
-- data/engine.json -> formulaHelp; keep the two in sync.
local traits = require("engine.traits")

local formula = {}

-- Whitelisted helpers. Deterministic under math.randomseed — the golden
-- harness depends on it — so never reseed here.
local HELPERS = {
    random = math.random,
    floor = math.floor,
    ceil = math.ceil,
    abs = math.abs,
    min = math.min,
    max = math.max,
    round = function(x) return math.floor(x + 0.5) end,
    clamp = function(x, lo, hi) return math.max(lo, math.min(hi, x)) end,
    -- Formats quantity for display: "x04" with leading zero dark gray (palette
    -- index 7) only on the leading zero; the x and actual digit stay normal.
    formatQty = function(qty)
        qty = math.floor(tonumber(qty) or 0)
        if qty <= 0 then return "x\\c[7]00\\c[0]" end
        if qty < 10 then
            return "x\\c[7]0\\c[0]" .. tostring(qty)
        else
            return "x" .. tostring(qty)
        end
    end,
    -- Formats a quantity NUMBER (no "x" prefix) with a dark-gray leading zero
    -- when <10, e.g. "01", "15". Used for the "qty×price" shop format.
    formatQtyNum = function(qty)
        qty = math.floor(tonumber(qty) or 0)
        if qty < 10 then
            return "\\c[7]0\\c[0]" .. tostring(qty)
        else
            return tostring(qty)
        end
    end,
    -- Formats price with leading zeros padded to the width of the shop's
    -- maxPrice (20 × most expensive item cost, set as v.maxPrice by openShop).
    -- Leading zeros are dark gray (palette index 7); the G is yellow (palette 6).
    formatPrice = function(cost, maxPrice)
        cost = math.floor(tonumber(cost) or 0)
        maxPrice = math.floor(tonumber(maxPrice) or cost or 0)
        local maxDigits = #tostring(maxPrice)
        local priceStr = tostring(cost)
        local zeros = maxDigits - #priceStr
        if zeros > 0 then
            return "\\c[7]" .. string.rep("0", zeros) .. "\\c[0]" .. priceStr .. " \\c[6]G\\c[0]"
        else
            return priceStr .. " \\c[6]G\\c[0]"
        end
    end,
}

-- One warning per distinct expression, so a bad formula in a data file
-- doesn't flood the console every battle round.
local warned = {}
local function warnOnce(expr, err)
    if not warned[expr] then
        warned[expr] = true
        print("[formula] error in '" .. tostring(expr) .. "': " .. tostring(err))
    end
end

-- Read-only battler view: the only fields formulas may see.
function formula.battlerView(battler, session)
    if not battler then return nil end
    return {
        name = battler.name or "",
        level = battler.level or 1,
        hp = battler.hp or 0,
        maxHp = traits.getParam(battler, "maxHp", session) or 1,
        atk = traits.getParam(battler, "atk", session) or 10,
        def = traits.getParam(battler, "def", session) or 10,
        mat = traits.getParam(battler, "mat", session) or 10,
        mdf = traits.getParam(battler, "mdf", session) or 10,
        mpd = traits.getParam(battler, "mpd", session) or 1,
        asp = traits.getParam(battler, "asp", session) or 10,
        -- Front/back row (Summoner rework §4): engine state only for now;
        -- exposed so formulas/conditions can read it ("front" until a
        -- battle assigns rows by slot).
        row = battler.row or "front",
        meta = battler.meta or {},
        -- Creature history, readable from data so a scene can show "3rd
        -- expedition, 11 battles" without engine changes (engine/session.lua
        -- Battler.new; counted by the RECORD_HISTORY command).
        history = battler.history or {},
        -- Generic trait access: `a.trait.GOLD_DIGGER`, `ally.trait.MOVE_HEAL`,
        -- ... resolves to traits.getRate for ANY registered code, so a new
        -- trait becomes usable from data (flows, scene hooks, item/skill
        -- formulas) with no new Lua. Replaces the pattern of hand-adding one
        -- field per trait (which is how FLEE_CHANCE_BONUS ended up hardcoded
        -- in groupView while ten other codes stayed unreachable and dead).
        -- Lazy via __index: computing all ~21 codes per view build would run
        -- getActiveObjects once per code on every formula evaluation.
        trait = setmetatable({}, {
            __index = function(_, code)
                return traits.getRate(battler, code, session)
            end
        })
    }
end

function formula.itemView(item)
    if not item then return nil end
    return {
        id = item.id,
        name = item.name or "",
        meta = item.meta or {}
    }
end

-- Aggregate view over a list of battlers (party or enemies).
function formula.groupView(list, session)
    list = list or {}
    local count, alive, totalLevel, totalMaxHp = 0, 0, 0, 0
    local totalMpd = 0
    local living = {}
    -- Use numeric for loop (1 to 4 for party, #list for others) instead of
    -- ipairs, so sparse arrays (e.g. party[1] removed, leaving a nil gap)
    -- still count every non-nil member. ipairs stops at the first nil, which
    -- would report party.count = 0 when only slot 2+ are occupied — breaking
    -- any "party.count > 0" gate and the whole party-selection flow.
    local limit = session and session.party == list and 4 or #list
    for i = 1, limit do
        local b = list[i]
        if b then
            count = count + 1
            totalLevel = totalLevel + (b.level or 1)
            totalMaxHp = totalMaxHp + (traits.getParam(b, "maxHp", session) or 1)
            if not (b.isDead and b:isDead()) and (b.hp or 0) > 0 then
                alive = alive + 1
                totalMpd = totalMpd + (traits.getParam(b, "mpd", session) or 0)
                table.insert(living, b)
            end
        end
    end
    return {
        size = count,
        count = count,
        aliveCount = alive,
        avgLevel = count > 0 and totalLevel / count or 0,
        totalLevel = totalLevel,
        totalMaxHp = totalMaxHp,
        -- Combined MPD of the LIVING members: the expedition's cost per step,
        -- and the figure Strain scales. Living only, and deliberately so -- a
        -- creature that dies stops costing the Summoner anything, which is the
        -- grim arithmetic the design is built on. One shared query so the
        -- traversal cost, the battle Strain and any UI preview cannot disagree
        -- about what the party costs.
        mpd = totalMpd,
        -- Group trait access: `party.trait.FLEE_CHANCE_BONUS` sums a code across
        -- LIVING members (the flee roll's long-standing rule). Generic for the
        -- same reason as battlerView.trait: the old hand-rolled `fleeBonus`
        -- field was the ONLY trait a formula could reach, so the other codes
        -- stayed unreachable from data -- and several of them stayed dead.
        trait = setmetatable({}, {
            __index = function(_, code)
                local sum = 0
                for _, b in ipairs(living) do
                    sum = sum + traits.getRate(b, code, session)
                end
                return sum
            end
        }),
    }
end

function formula.sessionView(session)
    if not session then return nil end
    return {
        gold = session.gold or 0,
        mp = session.mp or 0,
        maxMp = session.maxMp or 0,
        expBank = session.expBank or 0,
        developerMode = session.developerMode == true,
        -- `session.currentFloor` and `session.floor` were never set by anything,
        -- so this token silently read 1 everywhere for as long as it existed --
        -- including in a trap authored as `4 + session.floor`, which therefore
        -- dealt a flat 5 on every floor. The depth the party is actually at is
        -- `dungeonFloor`, maintained by exploration.loadMap.
        floor = session.dungeonFloor or 0,
        -- Display name of the current map (menu FLOOR readout).
        mapTitle = (session.currentMapData and session.currentMapData.title) or "Town",
        mapSafe = (session.currentMapData and session.currentMapData.safe) and true or false,
        encounterRate = (session.currentMapData and session.currentMapData.encounterRate)
            or (session.loader and session.loader.system and session.loader.system.combat
                and session.loader.system.combat.encounterChance)
            or 0.10,
        -- Distinct non-empty inventory stacks — lets scene hooks bound an
        -- inventory-list cursor (session.itemCount) without SCRIPT.
        itemCount = (function()
            local tab = (env and env.v and tonumber(env.v.tab)) or 1
            local loader = session.loader
            local n = 0
            for itemId, qty in pairs(session.inventory or {}) do
                if qty > 0 then
                    if tab == 1 or not loader then
                        n = n + 1
                    else
                        local item = loader.getItem(itemId)
                        if item then
                            local matches = false
                            if tab == 1 then matches = true
                            elseif tab == 2 then matches = (item.type == "consumable")
                            elseif tab == 3 then matches = (item.type == "equipment")
                            elseif tab == 4 then matches = (item.type == "quest" or item.type == "junk")
                            else matches = true end
                            if matches then n = n + 1 end
                        end
                    end
                end
            end
            return n
        end)(),
        -- Matching-gear stacks per equip slot (1=Weapon 2=Armor
        -- 3=Accessory) — lets the status scene's equip picker bound its
        -- cursor: the 'equipment' list has equipCount[slot] + 1 rows
        -- (the extra row is [ UNEQUIP ]).
        equipCount = (function()
            local counts = { 0, 0, 0 }
            local slotOf = { Weapon = 1, Armor = 2, Accessory = 3 }
            local loader = session.loader
            for itemId, qty in pairs(session.inventory or {}) do
                if qty > 0 and loader then
                    local item = loader.getItem(itemId)
                    local s = item and item.type == "equipment" and slotOf[item.equipType]
                    if s then counts[s] = counts[s] + 1 end
                end
            end
            return counts
        end)(),
        -- Per-member skill/passive counts (1-indexed by party slot) — lets
        -- the status scene bound its skill/passive inspector cursors
        -- (skillIdx/passiveIdx) the same way itemCount/equipCount bound
        -- theirs, instead of a SCRIPT walking session.party by hand.
        skillCount = (function()
            local counts = {}
            for i, m in ipairs(session.party or {}) do
                counts[i] = (m.actorData and m.actorData.skills and #m.actorData.skills) or 0
            end
            return counts
        end)(),
        passiveCount = (function()
            local counts = {}
            for i, m in ipairs(session.party or {}) do
                counts[i] = (m.actorData and m.actorData.passives and #m.actorData.passives) or 0
            end
            return counts
        end)(),
    }
end

-- Assemble an evaluation context. opts fields (all optional): a, b, target,
-- enemy, ally (battlers), party, enemies (battler lists), session, battle
-- ({ round = n }), v (flow-locals table). session is also used to resolve
-- params through traits and to pull the combat config table.
function formula.makeContext(opts, session)
    opts = opts or {}
    session = session or opts.session
    local ctx = {}
    for _, key in ipairs({ "a", "b", "target", "enemy", "ally" }) do
        if opts[key] then ctx[key] = formula.battlerView(opts[key], session) end
    end
    if opts.party then ctx.party = formula.groupView(opts.party, session) end
    if opts.enemies then ctx.enemies = formula.groupView(opts.enemies, session) end
    if session then
        ctx.session = formula.sessionView(session)
        local sys = session.loader and session.loader.system
        ctx.combat = sys and sys.combat or nil
    end
    ctx.battle = opts.battle
    ctx.v = opts.v
    if opts.ingredient1 then ctx.ingredient1 = formula.itemView(opts.ingredient1) end
    if opts.ingredient2 then ctx.ingredient2 = formula.itemView(opts.ingredient2) end
    return ctx
end

-- Evaluate exprString against ctx. Returns value, nil on success and
-- 0, err on failure (fallback 0 per SPEC S5; the error is logged once).
function formula.eval(exprString, ctx)
    if not exprString or exprString == "" then return 0, "empty formula" end
    if type(exprString) == "number" then return exprString, nil end
    ctx = ctx or {}

    -- Fresh env per call: helpers first, context on top. No _G access —
    -- unknown names read as nil and fail the expression rather than escape.
    local env = {}
    for k, fn in pairs(HELPERS) do env[k] = fn end
    for k, val in pairs(ctx) do env[k] = val end

    local chunk, err = load("return " .. exprString, "formula:" .. exprString, "t", env)
    if not chunk then
        warnOnce(exprString, err)
        return 0, err
    end
    local ok, result = pcall(chunk)
    if not ok then
        warnOnce(exprString, result)
        return 0, result
    end
    local rt = type(result)
    if rt ~= "number" and rt ~= "boolean" and rt ~= "string" then
        local msg = "formula did not return a number, boolean or string"
        warnOnce(exprString, msg)
        return 0, msg
    end
    return result, nil
end

return formula
