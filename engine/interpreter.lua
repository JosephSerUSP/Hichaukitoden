-- Unified command interpreter per SPEC S1/S2/S3/S6 (docs/plans/overhaul-3).
-- One command language for map/common events (interactive mode) and engine
-- phases (immediate mode). Command semantics live here; the registry that
-- drives the editor and validator lives in data/engine.json -> commands.
--
-- Interactive ctx (interpreter.compile / runInteractive):
--   session       GameSession
--   loader        data loader
--   recoverParty  callback: full party recovery (main.lua owns the rule)
--
-- Immediate ctx (runImmediate / flow.run):
--   session   GameSession (required)
--   loader    data loader (defaults to session.loader)
--   battle    Battle instance or nil (provides allies/enemies/round)
--   party     battler list (defaults to battle.allies or session.party)
--   enemies   battler list (defaults to battle.enemies)
--   a, b, target, enemy, ally   battler refs for formulas/battlerRefs
--   v         flow-local variable table (created if absent)
--
-- Every command may carry an optional `comment` string field; it is ignored
-- here and by the validator (SPEC S3).
local traits = require("engine.traits")
local effects = require("engine.effects")
local formulaEngine = require("engine.formula")
local config = require("engine.config")

local interpreter = {}

-- The nine ids interpreter.compile knows how to turn into dialogue nodes.
-- Anything else is a registry command executed via runImmediate (task A4b);
-- in map/common data the legacy nine are stored under `type`, newer commands
-- under `cmd` (the editor's cmdFieldName rule mirrors this table).
local INTERACTIVE_COMPILE_IDS = {
    TEXT = true, CHOICE = true, CONDITIONAL_BRANCH = true, RECOVER_PARTY = true,
    TELEPORT = true, BATTLE = true, GIVE_ITEM = true, CALL_COMMON_EVENT = true,
    COMMENT = true,
}

local function cmdId(cmd)
    return cmd.cmd or cmd.type
end

------------------------------------------------------------------
-- Interactive mode: command list -> GraphWalker node graph
------------------------------------------------------------------

-- Compiles a flat "commands" list (as authored in the editor) into GraphWalker
-- nodes, chaining them together and rejoining at tailNodeId at the end.
-- Moved verbatim from main.lua (task A4); behavior must stay pixel-identical
-- for the legacy interactive commands. ctx carries loader and the
-- recoverParty callback formerly reached as main.lua upvalues. Returns the
-- id of the first node generated (or tailNodeId if commands is empty).
--
-- Task A4b: any command that is NOT one of the legacy interactive ids
-- compiles into a RUN_IMMEDIATE action node instead. Contiguous runs of
-- such commands share ONE node (so SET_VAR -> IF chains keep their ctx.v
-- flow-locals), and the host (main.lua handleDialogueAction) executes the
-- run through interpreter.runImmediate, rendering any emitted text events
-- as dialogue. This is what makes registry commands with map/common
-- contexts actually work in map/common events (SPEC S1).
function interpreter.compile(nodes, commands, prefix, tailNodeId, ctx)
    if not commands or #commands == 0 then return tailNodeId end
    local loader = ctx.loader

    local firstId = nil
    local skipUntil = 0
    for i, cmd in ipairs(commands) do
        if i > skipUntil then
        local nodeId = prefix .. "_" .. i
        firstId = firstId or nodeId
        local nextId = (i < #commands) and (prefix .. "_" .. (i + 1)) or tailNodeId

        if not INTERACTIVE_COMPILE_IDS[cmdId(cmd)] then
            -- Task A4b: collect the contiguous run of non-interactive
            -- commands into ONE node so ctx.v flow-locals survive across the
            -- run (SET_VAR -> IF chains). COMMENTs inside the run are
            -- swallowed too — they are no-ops in runImmediate, and splitting
            -- the run on them would silently reset v.
            local run = { cmd }
            local j = i
            while j < #commands do
                local nid = cmdId(commands[j + 1])
                if nid == "COMMENT" or not INTERACTIVE_COMPILE_IDS[nid] then
                    j = j + 1
                    table.insert(run, commands[j])
                else
                    break
                end
            end
            skipUntil = j
            local runNext = (j < #commands) and (prefix .. "_" .. (j + 1)) or tailNodeId
            nodes[nodeId] = { type = "ACTION", action = "RUN_IMMEDIATE", commands = run, next = runNext }
        elseif cmd.type == "TEXT" then
            nodes[nodeId] = { type = "TEXT", content = cmd.text, speaker = cmd.speaker, next = nextId }
        elseif cmd.type == "CHOICE" then
            local options = {}
            for oi, opt in ipairs(cmd.options or {}) do
                -- Older data files used "script" for option sub-commands
                local optFirst = interpreter.compile(nodes, opt.commands or opt.script, nodeId .. "_opt" .. oi, nextId, ctx)
                table.insert(options, {
                    label = opt.label,
                    setFlag = opt.setFlag,
                    target = optFirst or nextId
                })
            end
            nodes[nodeId] = { type = "CHOICE", options = options }
        elseif cmd.type == "CONDITIONAL_BRANCH" then
            local trueFirst = interpreter.compile(nodes, cmd.commands, nodeId .. "_then", nextId, ctx)
            local falseFirst = interpreter.compile(nodes, cmd.elseCommands, nodeId .. "_else", nextId, ctx)
            nodes[nodeId] = {
                type = "ROUTER",
                condition = cmd.condition,
                trueNode = trueFirst or nextId,
                falseNode = falseFirst or nextId
            }
        elseif cmd.type == "RECOVER_PARTY" then
            ctx.recoverParty()
            nodes[nodeId] = { type = "TEXT", content = loader.getTerm("events.recover_party", "Your party has been fully recovered!"), next = nextId }
        elseif cmd.type == "TELEPORT" then
            local teleportId = nodeId .. "_teleport"
            nodes[nodeId] = { type = "TEXT", content = loader.getTerm("events.teleport", "You are whisked away..."), next = teleportId }
            nodes[teleportId] = { type = "ACTION", action = "TELEPORT" }
        elseif cmd.type == "BATTLE" then
            nodes[nodeId] = { type = "ACTION", action = "START_BATTLE" }
        elseif cmd.type == "GIVE_ITEM" then
            nodes[nodeId] = { type = "ACTION", action = "GIVE_ITEM_ACTION", next = nextId }
        elseif cmd.type == "CALL_COMMON_EVENT" then
            nodes[nodeId] = { type = "ACTION", action = "CALL_COMMON_EVENT_ACTION", commonEventId = cmd.commonEventId, next = nextId }
        elseif cmdId(cmd) == "COMMENT" then
            -- Documentation only (SPEC S3): compiles to nothing. Keep the
            -- chain intact by letting the previous node's nextId point past
            -- it — easiest is an empty ROUTER-less passthrough node.
            -- (cmdId: flows-style data stores COMMENT under `cmd`, editor
            -- map/common data under `type`; both must stay inert here.)
            nodes[nodeId] = { type = "ROUTER", condition = "", trueNode = nextId, falseNode = nextId }
        end
        end
    end
    return firstId
end

-- Builds a dialogue graph for a command list. The caller owns walker
-- creation and scene switching (that is presentation glue, not semantics).
function interpreter.buildGraph(eventTitle, commands, ctx)
    if not commands or #commands == 0 then return nil end
    local nodes = {}
    local startNode = interpreter.compile(nodes, commands, "node", nil, ctx)
    return {
        initialNode = startNode,
        name = eventTitle,
        nodes = nodes
    }
end

------------------------------------------------------------------
-- Immediate mode: synchronous execution for engine phases
------------------------------------------------------------------

local INTERACTIVE_IDS = {
    TEXT = true, CHOICE = true, RECOVER_PARTY = true, TELEPORT = true,
    BATTLE = true, GIVE_ITEM = true, CALL_COMMON_EVENT = true,
}

local handlers = {}

local function evalFormula(expr, ctx)
    if type(expr) == "number" then return expr end
    local fctx = formulaEngine.makeContext({
        a = ctx.a, b = ctx.b, target = ctx.target, enemy = ctx.enemy, ally = ctx.ally,
        party = ctx.party, enemies = ctx.enemies,
        battle = ctx.battle and { round = ctx.battle.round } or nil,
        v = ctx.v,
        -- Crafting scene context: ingredients and crafter stats
        ingredient1 = ctx.ingredient1,
        ingredient2 = ctx.ingredient2,
        crafter = ctx.crafter,
        alpha = ctx.alpha,
        S = ctx.S,
    }, ctx.session)
    -- FOR_EACH loop variables (arbitrary names via `as`) shadow the fixed refs
    for name, battler in pairs(ctx.refs or {}) do
        fctx[name] = formulaEngine.battlerView(battler, ctx.session)
    end
    local val, err = formulaEngine.eval(expr, fctx)
    if err then
        table.insert(ctx.events, { type = "text", text = "[flow] formula error: " .. tostring(err) })
    end
    return val
end

-- battlerRef resolution: a loop variable name set by FOR_EACH, one of the
-- context refs (a/b/target/enemy/ally), or "summoner".
local function resolveRef(ref, ctx)
    if type(ref) == "table" then return ref end
    if not ref then return ctx.target or ctx.a end
    if ref == "summoner" then return ctx.session.summoner end
    return (ctx.refs and ctx.refs[ref]) or ctx[ref]
end

local function emitAll(ctx, events)
    for _, ev in ipairs(events or {}) do
        table.insert(ctx.events, ev)
    end
end

handlers.COMMENT = function() end

-- Scene-only bridge for the battle's legacy input semantics.  The scene hook
-- selects the input phase; the helper owns the actual command decisions.
handlers.BATTLE_INPUT = function(cmd, ctx)
    ctx.hookHandled = true
    require("engine.scenes.battle").handleInput(cmd.action)
end

handlers.BATTLE_LOG = function(cmd, ctx)
    ctx.hookHandled = require("engine.scenes.battle").handleLogInput(cmd.action)
    ctx.hookFallback = not ctx.hookHandled
end

handlers.BATTLE_TRANSITION = function(cmd, ctx)
    ctx.hookHandled = require("engine.scenes.battle").handleTransition(cmd.action)
    ctx.hookFallback = not ctx.hookHandled
end

handlers.SET_VAR = function(cmd, ctx)
    ctx.v[cmd.name] = evalFormula(cmd.value, ctx)
end

handlers.SET_FLAG = function(cmd, ctx)
    -- Same flag table conditions read (flag:<name>); false clears the flag
    -- so "flag not set" and "flag == false" stay indistinguishable.
    ctx.session.flags[cmd.flag] = cmd.value and true or nil
end

handlers.IF = function(cmd, ctx)
    local branch
    if cmd.condition and cmd.condition:match("^flag:") then
        -- CONDITIONAL_BRANCH's string conditions stay valid alongside (S2)
        branch = ctx.session.flags[cmd.condition:match("^flag:(.+)")] == true
    elseif cmd.condition and cmd.condition:match("^hasItem:") then
        branch = ctx.session:hasItem(tonumber(cmd.condition:match("^hasItem:(.+)")), 1)
    else
        local val = evalFormula(cmd.condition, ctx)
        if type(val) == "boolean" then
            branch = val
        else
            branch = (val ~= 0 and val ~= nil) and val == val -- NaN-safe truthiness
        end
    end
    interpreter.execList(branch and cmd["then"] or cmd["else"], ctx)
end

local function scopeList(scope, ctx)
    local base
    if scope == "slot_allies" then
        -- Battle slots 1-4 only, matching the legacy `for i = 1, 4` loops in
        -- engine/battle.lua: with a full party this excludes the summoner
        -- (index 5 of battle.allies); with fewer creatures it includes them.
        local allies = ctx.party or (ctx.battle and ctx.battle.allies) or ctx.session.party or {}
        local slots = {}
        for i = 1, 4 do
            if allies[i] and not allies[i]:isDead() then table.insert(slots, allies[i]) end
        end
        return slots
    elseif scope == "party" or scope == "allies" or scope == "living_allies" then
        base = ctx.party or (ctx.battle and ctx.battle.allies) or ctx.session.party or {}
    else
        base = ctx.enemies or (ctx.battle and ctx.battle.enemies) or {}
    end
    if scope == "living_allies" or scope == "living_enemies" then
        local living = {}
        for _, b in ipairs(base) do
            if b and not (b.isDead and b:isDead()) then table.insert(living, b) end
        end
        return living
    end
    return base
end

handlers.FOR_EACH = function(cmd, ctx)
    local list = scopeList(cmd.scope, ctx)
    local varName = cmd.as or "it"
    ctx.refs = ctx.refs or {}
    local prev = ctx.refs[varName]
    for _, battler in ipairs(list) do
        if battler then
            ctx.refs[varName] = battler
            interpreter.execList(cmd["do"], ctx)
        end
    end
    ctx.refs[varName] = prev
end

handlers.GAIN_GOLD = function(cmd, ctx)
    local amount = math.floor(evalFormula(cmd.amount, ctx))
    ctx.session.gold = math.max(0, (ctx.session.gold or 0) + amount)
end

handlers.GRANT_XP = function(cmd, ctx)
    local target = resolveRef(cmd.target, ctx)
    if not target then return end
    local amount = math.floor(evalFormula(cmd.amount, ctx))
    target:gainExp(amount, ctx.session)
end

-- DAMAGE/HEAL route through effects.apply so death/log events stay
-- consistent with skills and items (S2). The evaluated amount is passed as a
-- literal formula; effects.apply then applies DEF reduction for damage
-- exactly as a skill would.
handlers.DAMAGE = function(cmd, ctx)
    local target = resolveRef(cmd.target, ctx)
    if not target then return end
    local amount = evalFormula(cmd.amount, ctx)
    if cmd.pierce then
        -- Raw damage: no DEF reduction, no element scaling, and minHp floors
        -- the target's HP without killing. Exists to reproduce legacy blocks
        -- like MP-exhaustion damage (hp = max(1, hp - n)) exactly.
        local dmg = math.floor(amount)
        target.hp = math.max(cmd.minHp or 0, target.hp - dmg)
        table.insert(ctx.events, { type = "damage", target = target, value = dmg })
        if target.hp <= 0 then
            target:addState("dead")
            table.insert(ctx.events, { type = "death", target = target })
        end
        return
    end
    local source = ctx.a or target
    emitAll(ctx, effects.apply({ type = "hp_damage", formula = tostring(amount) }, source, target, ctx.session))
end

handlers.HEAL = function(cmd, ctx)
    local target = resolveRef(cmd.target, ctx)
    if not target then return end
    -- E11: absorbed TRAIT_HEAL. With a trait code the heal amount is the
    -- target's rate for that trait, applied silently (no heal event) and
    -- skipping dead targets and zero rates — exact former TRAIT_HEAL
    -- semantics, so the golden victory flow stays byte-identical.
    if cmd.trait then
        if target:isDead() then return end
        local rate = traits.getRate(target, cmd.trait, ctx.session)
        if rate > 0 then
            target.hp = math.min(traits.getParam(target, "maxHp", ctx.session), target.hp + rate)
        end
        return
    end
    local amount = evalFormula(cmd.amount, ctx)
    local source = ctx.a or target
    emitAll(ctx, effects.apply({ type = "hp_heal", formula = tostring(amount) }, source, target, ctx.session))
end

handlers.ADD_STATE = function(cmd, ctx)
    local target = resolveRef(cmd.target, ctx)
    if not target then return end
    emitAll(ctx, effects.apply({ type = "add_status", status = cmd.state, duration = cmd.duration }, target, target, ctx.session))
end

handlers.REMOVE_STATE = function(cmd, ctx)
    local target = resolveRef(cmd.target, ctx)
    if not target then return end
    emitAll(ctx, effects.apply({ type = "remove_status", status = cmd.state }, target, target, ctx.session))
end

handlers.CHANGE_MP = function(cmd, ctx)
    local amount = math.floor(evalFormula(cmd.amount, ctx))
    if amount < 0 then
        local drain = math.abs(amount)
        ctx.session.mp = math.max(0, ctx.session.mp - drain)
        table.insert(ctx.events, { type = "mp_drain", value = drain, actor = (cmd.actor and resolveRef(cmd.actor, ctx)) or ctx.a })
    else
        ctx.session.mp = math.min(ctx.session.maxMp or (ctx.session.mp + amount), ctx.session.mp + amount)
    end
end

handlers.DRAIN_MP = function(cmd, ctx)
    local amount = math.floor(evalFormula(cmd.amount, ctx))
    ctx.session.mp = math.max(0, ctx.session.mp - amount)
    table.insert(ctx.events, { type = "mp_drain", value = amount, actor = (cmd.actor and resolveRef(cmd.actor, ctx)) or ctx.a })
end

handlers.RESTORE_MP = function(cmd, ctx)
    local amount = math.floor(evalFormula(cmd.amount, ctx))
    ctx.session.mp = math.min(ctx.session.maxMp or (ctx.session.mp + amount), ctx.session.mp + amount)
end

-- The regen/poison/duration-decay block as one command (S2). Mirrors the
-- legacy block in engine/battle.lua resolveRound; A5b deletes that copy.
handlers.STATE_TICKS = function(cmd, ctx)
    local battlers = {}
    for _, b in ipairs(ctx.party or {}) do table.insert(battlers, b) end
    for _, b in ipairs(ctx.enemies or {}) do table.insert(battlers, b) end
    for _, battler in ipairs(battlers) do
        if battler and not battler:isDead() then
            for _, state in ipairs(battler.states) do
                if state.id == "regen" then
                    local maxHp = traits.getParam(battler, "maxHp", ctx.session)
                    local heal = math.floor(maxHp * (config.combat and config.combat.regenRate or 0.1))
                    battler.hp = math.min(maxHp, battler.hp + heal)
                    table.insert(ctx.events, { type = "heal", target = battler, value = heal })
                elseif state.id == "poison" then
                    local dmg = math.floor(traits.getParam(battler, "maxHp", ctx.session) * (config.combat and config.combat.poisonRate or 0.1))
                    battler.hp = math.max(0, battler.hp - dmg)
                    table.insert(ctx.events, { type = "damage", target = battler, value = dmg })
                    if battler.hp <= 0 then
                        battler:addState("dead")
                        table.insert(ctx.events, { type = "death", target = battler })
                    end
                end
            end
            for i = #battler.states, 1, -1 do
                local state = battler.states[i]
                if state.duration and state.duration ~= 9999 then
                    state.duration = state.duration - 1
                    if state.duration <= 0 then
                        table.remove(battler.states, i)
                        table.insert(ctx.events, { type = "state_remove", target = battler, state = state.id })
                    end
                end
            end
        end
    end
end

handlers.EMIT_TEXT = function(cmd, ctx)
    local loader = ctx.loader or ctx.session.loader
    local args = {}
    for _, argExpr in ipairs(cmd.args or {}) do
        table.insert(args, tostring(evalFormula(argExpr, ctx)))
    end
    local text
    if cmd.term then
        text = loader.formatTerm(cmd.term, cmd.fallback or cmd.term, unpack(args))
    else
        text = cmd.fallback or ""
    end
    table.insert(ctx.events, { type = "text", text = text })
end

handlers.CHANGE_ITEM = function(cmd, ctx)
    local count = cmd.count or 1
    if cmd.item == "random" then
        local loot = "1"
        local mapData = ctx.session.currentMapData
        if mapData and mapData.treasures and #mapData.treasures > 0 then
            loot = mapData.treasures[math.random(#mapData.treasures)]
        end
        if count < 0 then
            if ctx.session:hasItem(loot, 1) then ctx.session:addItem(loot, count) end
        else
            ctx.session:addItem(loot, count)
        end
    else
        if count < 0 then
            if ctx.session:hasItem(cmd.item, 1) then ctx.session:addItem(cmd.item, count) end
        else
            ctx.session:addItem(cmd.item, count)
        end
    end
end

handlers.TAKE_ITEM = function(cmd, ctx)
    -- Fails soft (S2): removing more than owned just clears the stack.
    if ctx.session:hasItem(cmd.item, 1) then
        ctx.session:addItem(cmd.item, -(cmd.count or 1))
    end
end

handlers.GIVE_ITEM_ID = function(cmd, ctx)
    ctx.session:addItem(cmd.item, cmd.count or 1)
end

-- Rolls the encounter chance; on success emits an `encounter` event the map
-- host consumes to start a battle. One math.random() call, like the legacy
-- step-handler roll.
handlers.ROLL_ENCOUNTER = function(cmd, ctx)
    local chance = evalFormula(cmd.chance, ctx)
    if math.random() < chance then
        table.insert(ctx.events, { type = "encounter" })
    end
end

-- Builds the enemy group from the current map's weighted encounter table and
-- emits it as a `spawn_enemies` event; the host constructs the Battle. RNG
-- sequence matches legacy triggerBattle: one count roll (via the count
-- formula), then one weighted roll per enemy.
handlers.SPAWN_ENEMIES = function(cmd, ctx)
    local sessionMod = require("engine.session")
    local mapData = ctx.session.currentMapData
    local possibleEnemies = mapData and mapData.encounters
    if not possibleEnemies or #possibleEnemies == 0 then return end

    local count = math.floor(evalFormula(cmd.count, ctx))
    local enemyList = {}
    for _ = 1, count do
        local totalWeight = 0
        for _, enemyOpt in ipairs(possibleEnemies) do
            totalWeight = totalWeight + enemyOpt.weight
        end
        local roll = math.random(totalWeight)
        local sum = 0
        local enemyId = possibleEnemies[1].id
        for _, enemyOpt in ipairs(possibleEnemies) do
            sum = sum + enemyOpt.weight
            if roll <= sum then
                enemyId = enemyOpt.id
                break
            end
        end

        local enemyData = (ctx.loader or ctx.session.loader).getActor(enemyId)
        if enemyData then
            local enemyBattler = sessionMod.Battler.new(enemyData, enemyData.level or ctx.session.dungeonFloor)
            enemyBattler.hp = enemyBattler:getMaxHp(ctx.session)
            table.insert(enemyList, enemyBattler)
        end
    end
    table.insert(ctx.events, { type = "spawn_enemies", enemies = enemyList })
end

-- Emits a raw event of the given type (e.g. flee_success), optionally with
-- value/state fields, so flows can signal the host battle loop.
handlers.EMIT_EVENT = function(cmd, ctx)
    local ev = { type = cmd.event }
    if cmd.value ~= nil then ev.value = evalFormula(cmd.value, ctx) end
    if cmd.state ~= nil then ev.state = cmd.state end
    if cmd.target ~= nil then ev.target = resolveRef(cmd.target, ctx) end
    table.insert(ctx.events, ev)
end



handlers.OPEN_WINDOW = function(cmd, ctx)
    table.insert(ctx.events, { type = "open_window", windowId = cmd.windowId })
end

handlers.CLOSE_WINDOW = function(cmd, ctx)
    table.insert(ctx.events, { type = "close_window", windowId = cmd.windowId })
end

handlers.SET_LIST = function(cmd, ctx)
    table.insert(ctx.events, {
        type = "set_list", windowId = cmd.windowId, listId = cmd.listId,
        -- Optional row template/formulas consumed by the window renderer.
        format = cmd.format, priority = cmd.priority, highlight = cmd.highlight,
    })
end

handlers.SET_TEXT = function(cmd, ctx)
    -- Optional terms.json lookup (E9): "term" names the entry, "text" is the
    -- fallback — same contract as EMIT_TEXT.
    local text = cmd.text
    if cmd.term then
        local loader = ctx.loader or (ctx.session and ctx.session.loader)
        if loader and loader.getTerm then
            text = loader.getTerm(cmd.term, cmd.text or cmd.term)
        end
    end
    table.insert(ctx.events, { type = "set_text", windowId = cmd.windowId, text = text })
end

handlers.SET_CURSOR = function(cmd, ctx)
    local idx = evalFormula(cmd.index, ctx)
    table.insert(ctx.events, {
        type = "set_cursor", windowId = cmd.windowId, index = idx,
        -- Raw formula kept so the renderer can bind the cursor to live
        -- scene variables instead of the value at hook time.
        indexFormula = type(cmd.index) == "string" and cmd.index or nil,
    })
end

handlers.FOCUS_WINDOW = function(cmd, ctx)
    table.insert(ctx.events, { type = "focus_window", windowId = cmd.windowId })
end

handlers.PLAY_ANIM = function(cmd, ctx)
    table.insert(ctx.events, { type = "play_anim", animId = cmd.animId })
end

handlers.WAIT = function(cmd, ctx)
    table.insert(ctx.events, { type = "wait", duration = cmd.duration or 0 })
end

-- E10: load a map by index (title New Game, future warps). Same call the
-- legacy title key handler made (exploration.loadMap).
handlers.LOAD_MAP = function(cmd, ctx)
    local exploration = require("engine.exploration")
    exploration.loadMap(ctx.session, tonumber(evalFormula(cmd.mapId, ctx)) or 1)
end

-- E10: quit the game (title Exit). No-op outside a LOVE runtime.
handlers.QUIT_GAME = function(cmd, ctx)
    if love and love.event then love.event.quit() end
end

-- E9: rebuild the global session from scratch (data-authored game over →
-- "Return to Title"). Generic on purpose: any scene hook can start a fresh
-- run. The renderer is re-pointed because it caches the session reference.
handlers.RESET_SESSION = function(cmd, ctx)
    local sessionModule = require("engine.session")
    local fresh = sessionModule.GameSession.new(ctx.loader or (ctx.session and ctx.session.loader))
    fresh:initializeStartingParty()
    _G.activeSession = fresh
    ctx.session = fresh
    local ok, renderer = pcall(require, "presentation.renderer")
    if ok and renderer and renderer.init then renderer.init(fresh) end
end

handlers.SCENE_EVENT = function(cmd, ctx)
    -- The interpreter never switches scenes itself (S2); main.lua consumes
    -- this event and performs the transition.
    table.insert(ctx.events, { type = "scene_change", kind = cmd.kind, scene = cmd.scene })
end

------------------------------------------------------------------
-- SCRIPT (SPEC S6): sandboxed Lua escape hatch
------------------------------------------------------------------

-- Copy a stdlib table so scripts cannot mutate the real one for the engine.
local function copyTable(src)
    local t = {}
    for k, fn in pairs(src) do t[k] = fn end
    return t
end

local function buildScriptApi(ctx)
    local session = ctx.session
    local api = {}
    function api.damage(target, n)
        emitAll(ctx, effects.apply({ type = "hp_damage", formula = tostring(n) }, ctx.a or target, target, session))
    end
    function api.heal(target, n)
        emitAll(ctx, effects.apply({ type = "hp_heal", formula = tostring(n) }, ctx.a or target, target, session))
    end
    function api.giveItem(id, n) session:addItem(id, n or 1) end
    function api.takeItem(id, n)
        if session:hasItem(id, 1) then session:addItem(id, -(n or 1)) end
    end
    function api.gainGold(n) session.gold = math.max(0, session.gold + math.floor(n or 0)) end
    function api.grantXp(target, n) if target then target:gainExp(math.floor(n or 0), session) end end
    function api.addState(target, id, dur)
        emitAll(ctx, effects.apply({ type = "add_status", status = id, duration = dur }, target, target, session))
    end
    function api.removeState(target, id)
        emitAll(ctx, effects.apply({ type = "remove_status", status = id }, target, target, session))
    end
    function api.setFlag(flag, val) session.flags[flag] = val and true or nil end
    function api.emit(event) table.insert(ctx.events, event) end
    -- Generic read helpers (D13): formula evaluation and data queries, so
    -- extra scenes can compute in SCRIPT without bespoke engine commands.
    function api.eval(expr, env)
        local ok, val = pcall(formulaEngine.eval, tostring(expr or ""), env or {})
        if ok then return val end
        return nil
    end
    function api.items()
        local loader = ctx.loader or session.loader
        local list = {}
        for itemId, qty in pairs(session.inventory or {}) do
            if qty > 0 then
                local item = loader.getItem(itemId)
                if item then
                    table.insert(list, { id = item.id, name = item.name or "", icon = item.icon or 0, qty = qty, meta = item.meta or {} })
                end
            end
        end
        table.sort(list, function(a, b) return a.id < b.id end)
        return list
    end
    function api.allItems()
        local loader = ctx.loader or session.loader
        local list = {}
        for _, item in ipairs(loader.items or {}) do
            table.insert(list, { id = item.id, name = item.name or "", icon = item.icon or 0, meta = item.meta or {} })
        end
        return list
    end
    function api.party(i)
        local out = {}
        for idx, m in ipairs(ctx.party or session.party or {}) do
            local view = formulaEngine.battlerView(m, session) or {}
            view.index = idx
            table.insert(out, view)
        end
        if i ~= nil then return out[i] end
        return out
    end
    return api
end

handlers.SCRIPT = function(cmd, ctx)
    local session = ctx.session
    local loader = ctx.loader or session.loader
    local scripting = loader.engine and loader.engine.scripting or {}

    -- Live handles for the script's ctx: battlers are real (mutation goes
    -- through api anyway for events), session is a read-only view unless
    -- allowRawAccess opts in below.
    local scriptCtx = {
        session = formulaEngine.sessionView(session),
        battle = ctx.battle and { round = ctx.battle.round } or nil,
        actor = ctx.a,
        target = ctx.target or ctx.b,
        v = ctx.v,
        -- Scene hooks expose the scene's config as read-only-by-convention
        -- data (D13); nil outside scene contexts.
        config = ctx.scene and ctx.scene.config or nil,
    }

    local env = {
        ctx = scriptCtx,
        api = buildScriptApi(ctx),
        math = copyTable(math),
        string = copyTable(string),
        table = copyTable(table),
        random = math.random,
        pairs = pairs,
        ipairs = ipairs,
        tostring = tostring,
        tonumber = tonumber,
        select = select,
        unpack = unpack,
        print = print,
    }
    -- Explicitly absent: io, os, love, require, raw loader/session (S6).
    if scripting.allowRawAccess == true then
        scriptCtx.rawSession = session
        scriptCtx.rawLoader = loader
    end

    -- `ref` resolves a scene-local named script (scenes.json → scene.scripts),
    -- so hooks can share one script body across call sites (D13).
    local code = cmd.code
    if cmd.ref ~= nil then
        local scripts = ctx.scene and ctx.scene.scripts or {}
        code = scripts[cmd.ref]
        if type(code) ~= "string" then
            error("SCRIPT ref '" .. tostring(cmd.ref) .. "' not found in scene scripts", 0)
        end
    end

    local chunk, err = load(code or "", "SCRIPT", "t", env)
    if not chunk then
        error("SCRIPT compile error: " .. tostring(err), 0)
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        error("SCRIPT runtime error: " .. tostring(runErr), 0)
    end
end

------------------------------------------------------------------
-- Execution entry points
------------------------------------------------------------------

function interpreter.execList(commands, ctx)
    for _, cmd in ipairs(commands or {}) do
        local id = cmdId(cmd)
        if INTERACTIVE_IDS[id] then
            error("interactive command '" .. tostring(id) .. "' is invalid in immediate mode", 0)
        end
        local handler = handlers[id]
        if not handler then
            error("unknown command '" .. tostring(id) .. "'", 0)
        end
        handler(cmd, ctx)
    end
end

-- Synchronous execution for engine phases. Returns the event stream the
-- battle log/renderer already consumes. Interactive commands are an error.
function interpreter.runImmediate(commands, ctx)
    ctx = ctx or {}
    assert(ctx.session, "runImmediate requires ctx.session")
    ctx.loader = ctx.loader or ctx.session.loader
    ctx.events = ctx.events or {}
    ctx.v = ctx.v or {}
    if ctx.battle then
        ctx.party = ctx.party or ctx.battle.allies
        ctx.enemies = ctx.enemies or ctx.battle.enemies
    end
    interpreter.execList(commands, ctx)
    return ctx.events
end

-- Player-paced execution: compiles to a dialogue graph the existing
-- GraphWalker/renderer path consumes. Returns the graph (nil when there is
-- nothing to run); the caller creates the walker and switches scenes.
function interpreter.runInteractive(commands, ctx)
    return interpreter.buildGraph(ctx.eventTitle or "Event", commands, ctx)
end

interpreter.INTERACTIVE_IDS = INTERACTIVE_IDS

-- Exposed so the validator can prove every command registered in engine.json
-- is actually implemented: a command counts as implemented if it has an
-- immediate-mode handler OR is one of the ids interpreter.compile turns into
-- dialogue nodes. Registering a command with no handler puts a silent no-op
-- in the editor's command palette — exactly the dead/unimplemented content
-- the validator exists to catch.
interpreter.INTERACTIVE_COMPILE_IDS = INTERACTIVE_COMPILE_IDS

function interpreter.isImplemented(id)
    return handlers[id] ~= nil or INTERACTIVE_COMPILE_IDS[id] == true
end

return interpreter
