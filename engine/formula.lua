-- Sandboxed formula evaluation per SPEC S5 (docs/plans/overhaul-3).
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
    }
end

-- Aggregate view over a list of battlers (party or enemies).
function formula.groupView(list, session)
    list = list or {}
    local count, alive, totalLevel, totalMaxHp, fleeBonus = 0, 0, 0, 0, 0
    for _, b in ipairs(list) do
        count = count + 1
        totalLevel = totalLevel + (b.level or 1)
        totalMaxHp = totalMaxHp + (traits.getParam(b, "maxHp", session) or 1)
        if not (b.isDead and b:isDead()) and (b.hp or 0) > 0 then
            alive = alive + 1
            -- Living members only, matching the legacy flee roll in battle.lua
            fleeBonus = fleeBonus + traits.getRate(b, "FLEE_CHANCE_BONUS", session)
        end
    end
    return {
        size = count,
        count = count,
        aliveCount = alive,
        avgLevel = count > 0 and totalLevel / count or 0,
        totalLevel = totalLevel,
        totalMaxHp = totalMaxHp,
        fleeBonus = fleeBonus,
    }
end

function formula.sessionView(session)
    if not session then return nil end
    return {
        gold = session.gold or 0,
        mp = session.mp or 0,
        maxMp = session.maxMp or 0,
        floor = session.currentFloor or session.floor or 1,
        mapSafe = (session.currentMapData and session.currentMapData.safe) and true or false,
        encounterRate = (session.currentMapData and session.currentMapData.encounterRate)
            or (session.loader and session.loader.system and session.loader.system.combat
                and session.loader.system.combat.encounterChance)
            or 0.10,
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
