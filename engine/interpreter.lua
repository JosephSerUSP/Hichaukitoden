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
local conditions = require("engine.conditions")

local interpreter = {}

-- The nine ids interpreter.compile knows how to turn into dialogue nodes.
-- Anything else is a registry command executed via runImmediate (task A4b);
-- in map/common data the legacy nine are stored under `type`, newer commands
-- under `cmd` (the editor's cmdFieldName rule mirrors this table).
local INTERACTIVE_COMPILE_IDS = {
    TEXT = true, CHOICE = true, CONDITIONAL_BRANCH = true, RECOVER_PARTY = true,
    TELEPORT = true, BATTLE = true, GIVE_ITEM = true, CALL_COMMON_EVENT = true,
    COMMENT = true, OPEN_SHOP = true, QUEST_OFFER = true, QUEST_COMPLETE = true,
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
                -- Optional per-option visibility gate (flag:/hasItem:/
                -- questStatus:), same grammar as CONDITIONAL_BRANCH; an
                -- option with an unmatched/false condition is left out of
                -- the compiled list entirely.
                local show = true
                if opt.condition then
                    local matched, result = conditions.evalPrefixed(opt.condition, ctx.session)
                    show = (not matched) or result
                end
                if show then
                    -- Older data files used "script" for option sub-commands
                    local optFirst = interpreter.compile(nodes, opt.commands or opt.script, nodeId .. "_opt" .. oi, nextId, ctx)
                    table.insert(options, {
                        label = opt.label,
                        setFlag = opt.setFlag,
                        target = optFirst or nextId
                    })
                end
            end
            nodes[nodeId] = { type = "CHOICE", options = options }
        elseif cmd.type == "OPEN_SHOP" then
            nodes[nodeId] = { type = "ACTION", action = "OPEN_SHOP", shopId = cmd.shopId, next = nextId }
        elseif cmd.type == "QUEST_OFFER" then
            nodes[nodeId] = { type = "ACTION", action = "OFFER_QUEST", questId = cmd.questId, next = nextId }
        elseif cmd.type == "QUEST_COMPLETE" then
            nodes[nodeId] = { type = "ACTION", action = "COMPLETE_QUEST", questId = cmd.questId, next = nextId }
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

-- Lets a scene hook opt OUT of handling a key for a particular branch, so
-- the legacy input still underneath it (map movement, dungeon interact)
-- runs instead. Needed because any existing hook key intercepts its key
-- unconditionally otherwise (scene_host.runHook has no other way to say
-- "I looked, but this press isn't mine").
handlers.FALLBACK = function(cmd, ctx)
    ctx.hookFallback = true
end


handlers.SET_VAR = function(cmd, ctx)
    -- E7 "Control Variables": optional multi-assignment form. Rows are
    -- evaluated IN ORDER, so later values can read earlier ones via v.
    -- When assignments is present the legacy name/value pair is ignored;
    -- the single {name, value} shape keeps working unchanged forever.
    if type(cmd.assignments) == "table" and #cmd.assignments > 0 then
        for _, a in ipairs(cmd.assignments) do
            if type(a) == "table" and a.name then
                ctx.v[a.name] = evalFormula(a.value, ctx)
            end
        end
        return
    end
    ctx.v[cmd.name] = evalFormula(cmd.value, ctx)
end

handlers.SET_FLAG = function(cmd, ctx)
    -- Same flag table conditions read (flag:<name>); false clears the flag
    -- so "flag not set" and "flag == false" stay indistinguishable.
    ctx.session.flags[cmd.flag] = cmd.value and true or nil
end

handlers.IF = function(cmd, ctx)
    local branch
    -- CONDITIONAL_BRANCH's "flag:"/"hasItem:" string conditions stay valid
    -- alongside formula conditions (S2); shared with director.lua's ROUTER.
    local matched, result = conditions.evalPrefixed(cmd.condition, ctx.session)
    if matched then
        branch = result
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

-- The regen/poison/duration-decay block as one command (S2). This is the
-- live implementation used by the battle.round_end flow. The matching block
-- in engine/battle.lua resolveRound is deliberately RETAINED as the SPEC S4
-- fallback (runs only if battle.round_end is removed from flows.json), not
-- deleted — keep the two in sync if this logic changes.
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

-- Field item use as data (items-scene promotion): applies an item's
-- data-defined effects through the same effects pipeline field and battle
-- use share, then consumes one. itemIndex is 1-based into the id-sorted
-- non-empty inventory — the SAME ordering the window renderer's
-- 'inventory' list source displays (keep them in sync). Items with
-- target 'party' hit every member; otherwise target is a party index.
handlers.USE_ITEM = function(cmd, ctx)
    local idx = tonumber(evalFormula(cmd.itemIndex, ctx)) or 1
    local stacks = {}
    for itemId, qty in pairs(ctx.session.inventory or {}) do
        if qty > 0 then table.insert(stacks, itemId) end
    end
    table.sort(stacks)
    local loader = ctx.loader or ctx.session.loader
    local item = stacks[idx] and loader.getItem(stacks[idx])
    if not item then return end
    -- targetScope is the old field name (see engine/battle.lua's same
    -- fallback); no item in data/items.json still uses it, kept only so a
    -- hand-authored item using the old name doesn't silently misbehave.
    if (item.target or item.targetScope) == "party" then
        for _, member in ipairs(ctx.session.party) do
            for _, eff in ipairs(item.effects or {}) do
                emitAll(ctx, effects.apply(eff, member, member, ctx.session))
            end
        end
    else
        local target = ctx.session.party[tonumber(evalFormula(cmd.target, ctx)) or 1]
        if not target then return end
        for _, eff in ipairs(item.effects or {}) do
            emitAll(ctx, effects.apply(eff, target, target, ctx.session))
        end
    end
    ctx.session:addItem(item.id, -1)
end

-- Equip flow as data (status-scene equip): slot is 1=Weapon, 2=Armor,
-- 3=Accessory. itemIndex is 1-based into the SAME ordering the window
-- renderer's 'equipment' list source displays: index 1 is always
-- [ UNEQUIP ], then the inventory's matching equipment id-ascending (keep
-- them in sync). Previous gear returns to the inventory, like the legacy
-- select_passive handler did.
handlers.EQUIP_ITEM = function(cmd, ctx)
    local slot = tonumber((evalFormula(cmd.slot, ctx))) or 1
    local slotType = ({ "Weapon", "Armor", "Accessory" })[slot]
    local member = ctx.session.party[tonumber((evalFormula(cmd.target, ctx))) or 1]
    if not slotType or not member then return end
    local idx = tonumber((evalFormula(cmd.itemIndex, ctx))) or 1
    local loader = ctx.loader or ctx.session.loader
    local prev = member.equipment[slot]
    if idx == 1 then
        if prev then ctx.session:addItem(prev.id, 1) end
        member.equipment[slot] = nil
        return
    end
    local matching = {}
    for itemId, qty in pairs(ctx.session.inventory or {}) do
        if qty > 0 then
            local item = loader.getItem(itemId)
            if item and item.type == "equipment" and item.equipType == slotType then
                table.insert(matching, item)
            end
        end
    end
    table.sort(matching, function(a, b) return a.id < b.id end)
    local item = matching[idx - 1]
    if not item then return end
    if prev then ctx.session:addItem(prev.id, 1) end
    member.equipment[slot] = item
    ctx.session:addItem(item.id, -1)
end

handlers.GIVE_ITEM_ID = function(cmd, ctx)
    ctx.session:addItem(cmd.item, cmd.count or 1)
end

-- Permadeath sweep (Summoner rework §3): every party spirit still dead at
-- battle end — plus emergency-wave casualties parked on battle.fallen — is
-- gone permanently and converts to banked EXP using the same yield rule as
-- ritual sacrifice (totalExp × summoner.sacrificeExpRate ×
-- (1 + SACRIFICE_EXP_RATE trait)). Runs from the battle.victory and
-- battle.escaped flows. EXP banking happens now (pure bookkeeping, nothing
-- to watch); the actual party[slot] removal does NOT happen here — it's
-- deferred to the presentation layer, one battler at a time, only once
-- that battler's system.reap animation finishes playing (see
-- engine/scenes/battle.lua processEvent's "reap" branch). Emits one `reap`
-- event per fallen spirit, carrying `slot` for battlers still fielded
-- (nil for wave casualties, already off-field) so the deferred removal
-- knows which party index to clear.
handlers.REAP_FALLEN = function(cmd, ctx)
    local session = ctx.session
    local fallen = {}
    for i = 1, 4 do
        local b = session.party[i]
        if b and b:isDead() then
            table.insert(fallen, { battler = b, slot = i })
        end
    end
    for _, b in ipairs((ctx.battle and ctx.battle.fallen) or {}) do
        table.insert(fallen, { battler = b, slot = nil })
    end
    if ctx.battle then ctx.battle.fallen = {} end

    local sys = session.loader and session.loader.system
    local rate = sys and sys.summoner and sys.summoner.sacrificeExpRate or 1.0
    for _, f in ipairs(fallen) do
        local b = f.battler
        local traitBonus = traits.getRate(b, "SACRIFICE_EXP_RATE", session)
        local exp = math.floor(b:totalExp() * rate * (1 + traitBonus))
        session.expBank = math.max(0, (session.expBank or 0) + exp)
        table.insert(ctx.events, { type = "reap", target = b, exp = exp, slot = f.slot })
    end
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
        -- Row widgets (vocabulary extension 11.07.2026): sprite names a row
        -- field holding a small-battler sheet key; gaugeValue/gaugeMax are
        -- row-scoped formulas drawn as a bar under each row.
        sprite = cmd.sprite,
        gaugeValue = cmd.gaugeValue, gaugeMax = cmd.gaugeMax,
        gaugeColor = cmd.gaugeColor, gaugeFill = cmd.gaugeFill,
        -- Equip vocabulary: slot/member are formulas the 'equipment' and
        -- 'equipSlots' list sources re-evaluate at draw time.
        slot = cmd.slot, member = cmd.member,
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
    local animId = cmd.animId
    if animId == "skill" then
        animId = ctx.skill and ctx.skill.animation
    elseif animId == "item" then
        animId = ctx.item and ctx.item.animation
    end
    if not animId then return end

    local onVal = cmd.on
    if onVal then
        -- Resolve targeting references (e.g. "a", "b", "target", "summoner", etc.)
        local targets = {}
        if onVal == "a" or onVal == "attacker" or onVal == "user" or onVal == "actor" then
            table.insert(targets, ctx.a)
        elseif onVal == "b" or onVal == "target" then
            if ctx.targets then
                for _, t in ipairs(ctx.targets) do
                    table.insert(targets, t)
                end
            elseif ctx.b then
                table.insert(targets, ctx.b)
            end
        else
            -- If it's a specific ref or fallback
            local ref = resolveRef(onVal, ctx)
            if ref then
                table.insert(targets, ref)
            end
        end
        
        -- Emit individual play_anim events for each target, or fallback
        if #targets > 0 then
            for _, t in ipairs(targets) do
                table.insert(ctx.events, { type = "play_anim", animId = animId, on = t })
            end
        else
            table.insert(ctx.events, { type = "play_anim", animId = animId })
        end
    else
        table.insert(ctx.events, { type = "play_anim", animId = animId })
    end
end

handlers.WAIT = function(cmd, ctx)
    table.insert(ctx.events, { type = "wait", duration = cmd.duration or 0 })
end

handlers.APPLY_EFFECT = function(cmd, ctx)
    local effects = require("engine.effects")
    local act = ctx.skill or ctx.item
    if not act then return end
    
    local isItem = (ctx.item ~= nil)
    local element = act.element
    
    for _, tgt in ipairs(ctx.targets or {}) do
        for _, eff in ipairs(act.effects or {}) do
            local user = isItem and tgt or ctx.a
            emitAll(ctx, effects.apply(eff, user, tgt, ctx.session, { element = element }))
        end
    end
end

handlers.QUEST_TAKE_REQUIREMENTS = function(cmd, ctx)
    local quest = ctx.quest
    if not quest then return end
    
    local hasAll = true
    local reqItems = (quest.requirements and quest.requirements.items) or {}
    
    for _, itemReq in ipairs(reqItems) do
        local itemId = tostring(itemReq.id)
        local qty = tonumber(itemReq.qty) or 1
        if not ctx.session:hasItem(itemId, qty) then
            hasAll = false
            break
        end
    end
    
    if not hasAll then
        table.insert(ctx.events, { type = "quest_requirements_failed", questId = ctx.questId })
        return
    end
    
    for _, itemReq in ipairs(reqItems) do
        if itemReq.consume ~= false then
            local itemId = tostring(itemReq.id)
            local qty = tonumber(itemReq.qty) or 1
            ctx.session:addItem(itemId, -qty)
        end
    end
end

handlers.QUEST_GRANT_REWARDS = function(cmd, ctx)
    local quest = ctx.quest
    if not quest then return end
    
    local rewards = quest.rewards or {}
    
    if rewards.gold and rewards.gold > 0 then
        ctx.session.gold = math.max(0, (ctx.session.gold or 0) + rewards.gold)
        table.insert(ctx.events, { type = "text", text = "Gained " .. tostring(rewards.gold) .. " gold." })
    end
    
    if rewards.xp and rewards.xp > 0 then
        for _, member in ipairs(ctx.session.party or {}) do
            member:gainExp(rewards.xp, ctx.session)
        end
        table.insert(ctx.events, { type = "text", text = "Party gained " .. tostring(rewards.xp) .. " XP." })
    end
    
    for _, itemRew in ipairs(rewards.items or {}) do
        local itemId = tostring(itemRew.id)
        local qty = tonumber(itemRew.qty) or 1
        ctx.session:addItem(itemId, qty)
        local loader = ctx.loader or ctx.session.loader
        local item = loader.getItem(itemId)
        local itemName = item and item.name or ("Item " .. itemId)
        table.insert(ctx.events, { type = "text", text = "Gained " .. itemName .. " x" .. tostring(qty) .. "." })
    end
    
    for _, flag in ipairs(rewards.flags or {}) do
        ctx.session.flags[flag] = true
    end
end

-- E10: load a map by index (title New Game, future warps). Same call the
-- legacy title key handler made (exploration.loadMap). Omitting mapId
-- defers to system.spawn.mapId, so "where New Game starts" is data-editable
-- without touching this command.
handlers.LOAD_MAP = function(cmd, ctx)
    local exploration = require("engine.exploration")
    local sys = ctx.session.loader and ctx.session.loader.system
    local spawnMapId = sys and sys.spawn and sys.spawn.mapId
    local mapId = cmd.mapId ~= nil and tonumber(evalFormula(cmd.mapId, ctx)) or spawnMapId or 1
    exploration.loadMap(ctx.session, mapId)
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
    -- The interpreter never switches scenes itself (S2); scene_host consumes
    -- this event and performs the transition. Optional `vars` (same
    -- {name, value} shape as SET_VAR assignments) are resolved NOW, against
    -- the PUSHING scene's v/session/party — the only point where that
    -- context is still live — then seeded into the pushed scene's v BEFORE
    -- its on_enter runs (scene_host.push), so the target scene's setup
    -- hooks can read them (e.g. the ritual scene's ritualMode/targetIndex).
    local vars = nil
    if type(cmd.vars) == "table" then
        vars = {}
        for _, a in ipairs(cmd.vars) do
            if type(a) == "table" and a.name then
                vars[a.name] = evalFormula(a.value, ctx)
            end
        end
    end
    table.insert(ctx.events, { type = "scene_change", kind = cmd.kind, scene = cmd.scene, vars = vars })
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
    function api.hasItem(id, n) return session:hasItem(id, n or 1) end
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
        local src = ctx.party or session.party or {}
        if i ~= nil then
            -- Slot-indexed access: return the occupant of slot i (1..4) or nil.
            -- Resolves by explicit index (not ipairs) so a sparse party array
            -- (a gap left by a removed creature) still maps correctly -- without
            -- this, an occupied slot past a gap reads as empty and the Reserve
            -- menu could offer Summon into it, silently overwriting the creature.
            local m = src[i]
            if m then
                local view = formulaEngine.battlerView(m, session) or {}
                view.index = i
                view.actorData = m.actorData or {}
                return view
            end
            return nil
        end
        local out = {}
        for idx, m in ipairs(src) do
            local view = formulaEngine.battlerView(m, session) or {}
            view.index = idx
            view.actorData = m.actorData or {}
            table.insert(out, view)
        end
        return out
    end
    function api.partyCount()
        local src = ctx.party or session.party or {}
        local n = 0
        for _, m in pairs(src) do
            if m then n = n + 1 end
        end
        return n
    end
    api.getSkill = function(id)
        local l = ctx.loader or session.loader
        return l and l.getSkill(id)
    end
    api.getItem = function(id)
        local l = ctx.loader or session.loader
        return l and l.getItem(id)
    end
    api.getTerm = function(key, fallback)
        local l = ctx.loader or session.loader
        return l and l.getTerm(key, fallback) or fallback
    end
    api.getTermList = function(key, fallback)
        local l = ctx.loader or session.loader
        return (l and l.getTermList and l.getTermList(key, fallback)) or fallback or {}
    end
    api.formatTerm = function(key, fallback, ...)
        local l = ctx.loader or session.loader
        return l and l.formatTerm(key, fallback, ...) or fallback
    end
    api.systemConfig = require("engine.config")
    function api.allActors()
        local l = ctx.loader or session.loader
        local list = {}
        for _, actor in ipairs(l and l.actors or {}) do
            table.insert(list, {
                id = actor.id,
                name = actor.name or "",
                icon = actor.icon or 0,
                unlocked = actor.unlocked or false,
                tier = actor.tier or 1,
                discipline = actor.discipline or "None",
                meta = actor.meta or {}
            })
        end
        return list
    end
    function api.summon(actorId, isReserve, index, level)
        local actorData = session.loader.getActor(actorId)
        if not actorData then return false end
        -- Never overwrite an occupied slot: Summon targets an EMPTY slot only
        -- (the Reserve menu offers it solely for empty slots). Returning false
        -- here is the engine-level safety net so a creature already in the
        -- target slot can never be silently destroyed by a Summon.
        local arr = isReserve and session.reserve or session.party
        if arr[index] then return false end
        local battler = require("engine.session").Battler.new(actorData, level or actorData.level or 1)
        battler.hp = battler:getMaxHp(session)
        arr[index] = battler
        return true
    end
    function api.sacrifice(isReserve, index)
        local arr = isReserve and session.reserve or session.party
        arr[index] = nil
        if not isReserve then session:autoFieldIfEmpty() end
    end

    -- EXP Bank: shared pool accrued by sacrifices, spent to summon above
    -- base level. Curve math lives in engine/session.lua (expCurveCost) so
    -- summon pricing and sacrifice yields conserve training value.
    function api.getExpBank()
        return session.expBank or 0
    end
    function api.changeExpBank(amount)
        session.expBank = math.max(0, (session.expBank or 0) + math.floor(amount or 0))
    end
    -- EXP the bank charges to summon this actor at targetLevel (0 at or
    -- below its base level).
    function api.summonExpCost(actorId, targetLevel)
        local actorData = session.loader.getActor(actorId)
        if not actorData then return 0 end
        local base = actorData.level or 1
        if not targetLevel or targetLevel <= base then return 0 end
        return require("engine.session").expCurveCost(base, targetLevel)
    end
    -- Stat/skill preview for a NOT-yet-summoned actor at a given level:
    -- builds a throwaway Battler so traits/params resolve exactly as the
    -- real summon would.
    function api.actorPreview(actorId, level)
        local actorData = session.loader.getActor(actorId)
        if not actorData then return nil end
        local b = require("engine.session").Battler.new(actorData, level or actorData.level or 1)
        b.hp = b:getMaxHp(session)
        local view = formulaEngine.battlerView(b, session) or {}
        view.name = b.name or ""
        view.actorData = actorData
        local skillNames = {}
        for _, sid in ipairs(b.skills or {}) do
            local sk = session.loader.getSkill(sid)
            table.insert(skillNames, { name = (sk and sk.name) or tostring(sid) })
        end
        view.skillList = skillNames
        return view
    end

    -- Sacrifice yields. Preview is non-mutating (the ritual scene shows it
    -- before confirming); execute removes the creature, deposits EXP and
    -- rolls the reward table. Yield = totalExp × summoner.sacrificeExpRate
    -- × (1 + SACRIFICE_EXP_RATE trait sum). Rewards come from the actor's
    -- sacrificeRewards table, falling back to
    -- summoner.defaultSacrificeRewards; entries: {itemId, chance, count,
    -- minLevel}.
    local function sacrificeRewardTable(b)
        local rewards = (b.actorData and b.actorData.sacrificeRewards)
        if not rewards or #rewards == 0 then
            local sys = session.loader and session.loader.system
            rewards = sys and sys.summoner and sys.summoner.defaultSacrificeRewards or {}
        end
        local eligible = {}
        for _, r in ipairs(rewards) do
            if not r.minLevel or (b.level or 1) >= r.minLevel then
                table.insert(eligible, r)
            end
        end
        return eligible
    end
    local function sacrificeExpYield(b)
        local sys = session.loader and session.loader.system
        local rate = sys and sys.summoner and sys.summoner.sacrificeExpRate or 1.0
        local traitBonus = traits.getRate(b, "SACRIFICE_EXP_RATE", session)
        return math.floor(b:totalExp() * rate * (1 + traitBonus))
    end
    function api.sacrificePreview(isReserve, index)
        local arr = isReserve and session.reserve or session.party
        local b = arr and arr[index]
        if not b then return nil end
        local rewards = {}
        for _, r in ipairs(sacrificeRewardTable(b)) do
            local item = session.loader.getItem(r.itemId)
            table.insert(rewards, {
                itemId = r.itemId,
                name = (item and item.name) or ("item#" .. tostring(r.itemId)),
                chance = r.chance or 1,
                count = r.count or 1,
            })
        end
        return { exp = sacrificeExpYield(b), rewards = rewards, name = b.name or "" }
    end
    function api.executeSacrifice(isReserve, index)
        local arr = isReserve and session.reserve or session.party
        local b = arr and arr[index]
        if not b then return nil end
        local exp = sacrificeExpYield(b)
        local granted = {}
        for _, r in ipairs(sacrificeRewardTable(b)) do
            if math.random() < (r.chance or 1) then
                session:addItem(r.itemId, r.count or 1)
                local item = session.loader.getItem(r.itemId)
                table.insert(granted, {
                    itemId = r.itemId,
                    name = (item and item.name) or ("item#" .. tostring(r.itemId)),
                    count = r.count or 1,
                })
            end
        end
        arr[index] = nil
        session.expBank = math.max(0, (session.expBank or 0) + exp)
        return { exp = exp, items = granted, name = b.name or "" }
    end
    function api.swap(idx1, isReserve1, idx2, isReserve2)
        local arr1 = isReserve1 and session.reserve or session.party
        local arr2 = isReserve2 and session.reserve or session.party
        arr1[idx1], arr2[idx2] = arr2[idx2], arr1[idx1]
    end

    -- overhaul-6 F6: Promotion. A creature is promotable when it has an
    -- evolution whose `level` threshold it has reached and whose `evolvesTo`
    -- actor exists. Cost is read from the evolution entry: absent = free,
    -- {mp = N} = MP, {item = id} = a promotion-key item (category
    -- "promotion_key" in items.json). api.promote performs the evolution,
    -- keeping level/exp/states/equipment and swapping in the new actorData.
    function api.canPromote(isReserve, index)
        local arr = isReserve and session.reserve or session.party
        local b = arr and arr[index]
        if not b or not b.actorData then return false end
        for _, e in ipairs(b.actorData.evolutions or {}) do
            if e.level and b.level >= e.level and e.evolvesTo and session.loader.getActor(e.evolvesTo) then
                return true
            end
        end
        return false
    end

    -- Nth ELIGIBLE evolution entry (level reached, target actor exists) for
    -- a battler; choice defaults to 1. Shared by promoteInfo/promote so the
    -- ritual scene's path picker and the executed promotion always agree.
    local function eligibleEvolution(b, choice)
        if not b or not b.actorData then return nil end
        local n = 0
        for _, e in ipairs(b.actorData.evolutions or {}) do
            if e.level and b.level >= e.level and e.evolvesTo and session.loader.getActor(e.evolvesTo) then
                n = n + 1
                if n == (choice or 1) then return e end
            end
        end
        return nil
    end

    function api.promoteInfo(isReserve, index, choice)
        local arr = isReserve and session.reserve or session.party
        local b = arr and arr[index]
        local e = b and eligibleEvolution(b, choice)
        if e then
            local cost = e.cost
            local txt = ""
            if cost then
                if cost.mp then txt = "  Cost: " .. tostring(cost.mp) .. " MP" end
                if cost.item then
                    local it = session.loader.getItem(cost.item)
                    txt = txt .. "  Needs: " .. (it and (it.name .. " x1") or ("item#" .. tostring(cost.item)))
                end
            else
                txt = "  (free)"
            end
            return true, txt
        end
        return false, ""
    end

    function api.promote(isReserve, index, choice)
        local arr = isReserve and session.reserve or session.party
        local b = arr and arr[index]
        local e = b and eligibleEvolution(b, choice)
        local target = e and e.evolvesTo or nil
        local cost = e and e.cost or nil
        if not target then return false end
        local actorData = session.loader.getActor(target)
        if not actorData then return false end
        if cost then
            if cost.mp and session.mp < cost.mp then return false end
            if cost.item and not session:hasItem(cost.item, 1) then return false end
            if cost.mp then session.mp = session.mp - cost.mp end
            if cost.item then session:addItem(cost.item, -1) end
        end
        -- Evolve: keep progression (level/exp/states/equipment), swap actorData.
        local lvl = b.level
        local exp = b.exp
        local states = b.states
        local equip = b.equipment
        local newB = require("engine.session").Battler.new(actorData, lvl)
        newB.name = b.name
        newB.exp = exp
        newB.states = states or {}
        newB.equipment = equip or { nil, nil, nil }
        newB.hp = b.hp > 0 and math.min(newB:getMaxHp(session), b.hp) or newB:getMaxHp(session)
        arr[index] = newB
        return true
    end

    function api.changeMp(amount)
        session.mp = math.max(0, math.min(session.maxMp or 9999, session.mp + amount))
    end
    function api.getMp()
        return session.mp
    end
    function api.dungeonFloor()
        return session.dungeonFloor or 1
    end
    function api.reserve(i)
        local out = {}
        for idx = 1, 8 do
            local m = session.reserve and session.reserve[idx]
            if m then
                local view = formulaEngine.battlerView(m, session) or {}
                view.index = idx
                view.name = m.name or ""
                view.actorData = m.actorData or {}
                table.insert(out, view)
            else
                table.insert(out, { index = idx, empty = true, name = "--Empty--" })
            end
        end
        if i ~= nil then return out[i] end
        return out
    end
    api.battle = {
        commitAction = function(index, action)
            require("engine.scenes.battle").commitAction(index, action)
        end,
        startTargetSelection = function(pendingAction)
            require("engine.scenes.battle").startTargetSelection(pendingAction)
        end,
        undoAction = function()
            return require("engine.scenes.battle").undoAction()
        end,
        showMessage = function(msg)
            require("engine.scenes.battle").showMessage(msg)
        end,
        advanceLog = function()
            require("engine.scenes.battle").advanceLog()
        end,
        handleTransition = function(action)
            return require("engine.scenes.battle").handleTransition(action)
        end,
        isLogRevealing = function()
            local battle = require("engine.scenes.battle")
            return require("presentation.renderer").isBattleLogRevealing(battle.getState().combatLog)
        end,
        finishLogReveal = function()
            require("presentation.renderer").finishBattleLogReveal()
        end,
        isAnimationPlaying = function()
            return require("presentation.animation_player").isAnythingPlaying()
        end
    }
    api.targeting = require("engine.targeting")
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
        type = type,
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
