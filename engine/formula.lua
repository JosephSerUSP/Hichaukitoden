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
        asp = traits.getParam(battler, "asp", session) or 10,
        meta = battler.meta or {}
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
        expBank = session.expBank or 0,
        floor = session.currentFloor or session.floor or 1,
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
            local n = 0
            for _, qty in pairs(session.inventory or {}) do
                if qty > 0 then n = n + 1 end
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
    }
end

-- Assemble an evaluation context. opts fields (all optional): a, b, target,
-- enemy, ally (battlers), party, enemies (battler lists), session, battle
-- ({ round = n }), v (flow-locals table). session is also used to resolve
-- params through traits and to pull the combat config table.

local function tokenize(expr)
    local tokens = {}
    local pos = 1
    local len = #expr
    while pos <= len do
        local c = expr:sub(pos, pos)
        if c:match("%s") then
            pos = pos + 1
        elseif c:match("[%a_]") then
            local start = pos
            while pos <= len and expr:sub(pos, pos):match("[%w_]") do
                pos = pos + 1
            end
            local word = expr:sub(start, pos - 1)
            if word == "and" or word == "or" or word == "not" then
                table.insert(tokens, {type = "OP", value = word})
            elseif word == "true" then
                table.insert(tokens, {type = "BOOL", value = true})
            elseif word == "false" then
                table.insert(tokens, {type = "BOOL", value = false})
            else
                table.insert(tokens, {type = "ID", value = word})
            end
        elseif c:match("%d") or (c == "." and expr:sub(pos+1, pos+1):match("%d")) then
            local start = pos
            while pos <= len and expr:sub(pos, pos):match("[%w_%.]") do
                pos = pos + 1
            end
            table.insert(tokens, {type = "NUM", value = tonumber(expr:sub(start, pos - 1))})
        elseif c == "'" or c == '"' then
            local quote = c
            pos = pos + 1
            local start = pos
            while pos <= len and expr:sub(pos, pos) ~= quote do
                if expr:sub(pos, pos) == "\\" then pos = pos + 1 end
                pos = pos + 1
            end
            table.insert(tokens, {type = "STR", value = expr:sub(start, pos - 1)})
            pos = pos + 1
        else
            local two = expr:sub(pos, pos+1)
            if two == "==" or two == "~=" or two == "<=" or two == ">=" or two == ".." then
                table.insert(tokens, {type = "OP", value = two})
                pos = pos + 2
            else
                table.insert(tokens, {type = "OP", value = c})
                pos = pos + 1
            end
        end
    end
    table.insert(tokens, {type = "EOF", value = ""})
    return tokens
end

local function parseAST(tokens)
    local pos = 1
    local function peek() return tokens[pos] end
    local function consume(type, value)
        local t = peek()
        if type and t.type ~= type then return nil end
        if value and t.value ~= value then return nil end
        pos = pos + 1
        return t
    end
    local function consume_any()
        local t = peek()
        pos = pos + 1
        return t
    end

    local expr

    local function primary()
        local node
        local t = peek()
        if t.type == "NUM" or t.type == "STR" or t.type == "BOOL" then
            consume_any()
            node = {type = "LITERAL", value = t.value}
        elseif t.type == "ID" then
            consume_any()
            node = {type = "VAR", name = t.value}
        elseif consume("OP", "(") then
            node = expr()
            if not consume("OP", ")") then error("Expected ')'") end
        elseif consume("OP", "-") then
            node = {type = "UNARY", op = "-", right = primary()}
            return node
        elseif consume("OP", "not") then
            node = {type = "UNARY", op = "not", right = primary()}
            return node
        elseif consume("OP", "#") then
            node = {type = "UNARY", op = "#", right = primary()}
            return node
        else
            error("Unexpected token: " .. tostring(t.value))
        end

        while true do
            if consume("OP", ".") then
                local prop = consume("ID")
                if not prop then error("Expected property name after '.'") end
                node = {type = "INDEX", base = node, prop = prop.value}
            elseif consume("OP", "[") then
                local idx = expr()
                if not consume("OP", "]") then error("Expected ']'") end
                node = {type = "INDEX_EXPR", base = node, index = idx}
            elseif consume("OP", "(") then
                local args = {}
                if peek().value ~= ")" then
                    table.insert(args, expr())
                    while consume("OP", ",") do
                        table.insert(args, expr())
                    end
                end
                if not consume("OP", ")") then error("Expected ')' after arguments") end
                node = {type = "CALL", func = node, args = args}
            else
                break
            end
        end
        return node
    end

    local function exponential()
        local node = primary()
        if peek().value == "^" then
            local op = consume_any().value
            node = {type = "BINARY", op = op, left = node, right = exponential()}
        end
        return node
    end

    local function multiplicative()
        local node = exponential()
        while peek().value == "*" or peek().value == "/" or peek().value == "%" do
            local op = consume_any().value
            node = {type = "BINARY", op = op, left = node, right = exponential()}
        end
        return node
    end

    local function additive()
        local node = multiplicative()
        while peek().value == "+" or peek().value == "-" do
            local op = consume_any().value
            node = {type = "BINARY", op = op, left = node, right = multiplicative()}
        end
        return node
    end

    local function concatenation()
        local node = additive()
        if peek().value == ".." then
            local op = consume_any().value
            node = {type = "BINARY", op = op, left = node, right = concatenation()}
        end
        return node
    end

    local function relational()
        local node = concatenation()
        while peek().value == "<" or peek().value == ">" or peek().value == "<=" or peek().value == ">=" or peek().value == "==" or peek().value == "~=" do
            local op = consume_any().value
            node = {type = "BINARY", op = op, left = node, right = concatenation()}
        end
        return node
    end

    local function logical_and()
        local node = relational()
        while peek().value == "and" do
            consume_any()
            node = {type = "LOGICAL", op = "and", left = node, right = relational()}
        end
        return node
    end

    local function logical_or()
        local node = logical_and()
        while peek().value == "or" do
            consume_any()
            node = {type = "LOGICAL", op = "or", left = node, right = logical_and()}
        end
        return node
    end

    expr = logical_or

    local ast = expr()
    if peek().type ~= "EOF" then
        error("Unexpected trailing token: " .. tostring(peek().value))
    end
    return ast
end

local function evaluateAST(node, env)
    if node.type == "LITERAL" then
        return node.value
    elseif node.type == "VAR" then
        return env[node.name]
    elseif node.type == "INDEX" then
        local base = evaluateAST(node.base, env)
        if type(base) ~= "table" and type(base) ~= "userdata" then return nil end
        return base[node.prop]
    elseif node.type == "INDEX_EXPR" then
        local base = evaluateAST(node.base, env)
        local idx = evaluateAST(node.index, env)
        if type(base) ~= "table" and type(base) ~= "userdata" then return nil end
        return base[idx]
    elseif node.type == "CALL" then
        local fn = evaluateAST(node.func, env)
        if type(fn) ~= "function" then error("Attempt to call a non-function") end
        local args = {}
        for i, argNode in ipairs(node.args) do
            args[i] = evaluateAST(argNode, env)
        end
        return fn(unpack(args))
    elseif node.type == "UNARY" then
        local right = evaluateAST(node.right, env)
        if node.op == "-" then return -right
        elseif node.op == "not" then return not right
        elseif node.op == "#" then return #right end
    elseif node.type == "BINARY" then
        local left = evaluateAST(node.left, env)
        local right = evaluateAST(node.right, env)
        if node.op == "+" then return left + right
        elseif node.op == "-" then return left - right
        elseif node.op == "*" then return left * right
        elseif node.op == "/" then return left / right
        elseif node.op == "%" then return left % right
        elseif node.op == "^" then return left ^ right
        elseif node.op == ".." then return tostring(left) .. tostring(right)
        elseif node.op == "==" then return left == right
        elseif node.op == "~=" then return left ~= right
        elseif node.op == "<" then return left < right
        elseif node.op == "<=" then return left <= right
        elseif node.op == ">" then return left > right
        elseif node.op == ">=" then return left >= right end
    elseif node.type == "LOGICAL" then
        local left = evaluateAST(node.left, env)
        if node.op == "and" then
            return left and evaluateAST(node.right, env)
        elseif node.op == "or" then
            return left or evaluateAST(node.right, env)
        end
    end
end

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

    local tokens, ast
    local ok, parseErr = pcall(function()
        tokens = tokenize(exprString)
        ast = parseAST(tokens)
    end)
    if not ok or not ast then
        warnOnce(exprString, parseErr or "parse error")
        return 0, parseErr or "parse error"
    end

    local ok, result = pcall(function()
        return evaluateAST(ast, env)
    end)
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
