local loader = require("data.loader")
local session = require("engine.session")
local exploration = require("engine.exploration")
local battleSystem = require("engine.battle")
local director = require("engine.director")
local renderer = require("presentation.renderer")
local traits = require("engine.traits")
local effects = require("engine.effects")
local scene_host = require("engine.scene.host")
local interpreter = require("engine.interpreter")
local flow = require("engine.flow")
require("engine.scenes.crafting")
local viewport_3d = require("presentation.viewport_3d")

-- Game resolution dimensions
local gameWidth, gameHeight = 256, 240
local canvas
local scale, scaleX, scaleY = 1, 1, 1

-- Global Session and State Router

local function getPopupFormat(key)
    if config.battle_screen and config.battle_screen.popup and config.battle_screen.popup[key] then
        return config.battle_screen.popup[key]
    end
    -- Fallbacks
    if key == "damageFormat" then return "-{0}" end
    if key == "damageColor" then return {1, 0.2, 0.2, 1} end
    if key == "healFormat" then return "+{0}" end
    if key == "healColor" then return {0.2, 1, 0.2, 1} end
    if key == "critFormat" then return "CRITICAL!" end
    if key == "critColor" then return {1, 0.2, 0.2, 1} end
    if key == "deadFormat" then return "DEAD" end
    if key == "deadColor" then return {0.6, 0.6, 0.6, 1} end
    if key == "stateFormat" then return "{0}" end
    if key == "stateColor" then return {0.8, 0.4, 1.0, 1} end
    return ""
end

activeSession = nil
currentScene = "title"

activeSceneHost = nil

function setScene(sceneIdOrName)
    if activeSceneHost then
        activeSceneHost:exit()
    end

    if type(sceneIdOrName) == "number" then
        local sceneData = loader.getScene(sceneIdOrName)
        if sceneData then
            activeSceneHost = scene_host.SceneHost.new(activeSession, loader, sceneData)
            activeSceneHost:enter()
            currentScene = sceneData.kind or "scene"
            return
        end
    elseif type(sceneIdOrName) == "string" and sceneIdOrName == "crafting" then
        -- Legacy strings compatibility: we specifically look up the crafting scene
        -- since it's the only one migrating immediately for testing/fallback
        local sceneData = nil
        for _, s in ipairs(loader.scenes or {}) do
            if s.kind == "crafting" then
                sceneData = s
                break
            end
        end
        if sceneData then
            activeSceneHost = scene_host.SceneHost.new(activeSession, loader, sceneData)
            activeSceneHost:enter()
        else
            activeSceneHost = nil
        end
        currentScene = "crafting"
        return
    end

    activeSceneHost = nil
    currentScene = sceneIdOrName
end

local isTestBattle = false
local isValidateMode = false
local isGoldenMode = false
local triggerTestBattle
local runValidation

-- Scene States Cache
local townSelectedIdx = 1

-- Battle State
local activeBattle
local battleCombatLog = {}
local battleCombatState = "input" -- "input" or "log"
local battleSelectedIndex = 1
local battleSpellSelect = false
local battleEventsQueue = {}
local battleEventQueueIndex = 1
local battleEscaped = false

-- Dialogue State
local activeWalker
local dialogueSelectIdx = 1

-- Shop State
local activeShopId = ""
local activeShopName = ""
local shopItems = {}
local shopSelectedIdx = 1

-- Menu State
local previousSceneBeforeMenu = "town"
local menuSelectedIdx = 1
local menuActiveCol = 1 -- 1 = Left menu column, 2 = Right panel details
menuSubScene = "main"
local menuSelectedSubIdx = 1
local selectedItemIdToUse = nil
local selectedCreatureIndex = 1
local selectedSlotIndex = 1
statusInspectMode = false
statusInspectIdx = 1

local inputCooldown = 0

-- Interactive Battle Input variables
local battleLivingMembers = {}
local battleActiveMemberIndex = 1
local battleCollectedActions = {}

local server = require("engine.server")
config = require("engine.config")

-- Config accessor with fallback for missing keys
local function conf(group, key, default)
    local g = config[group]
    if g and g[key] ~= nil then return g[key] end
    return default
end

-- Database validation for `lovec . validate`: cross-reference integrity plus
-- a scripted battle round, so data edits can be smoke-tested headlessly.

-- Golden-master battle log validation
local function runGolden()
    math.randomseed(12345)

    local vSession = session.GameSession.new(loader)

    -- Explicitly construct party and enemies
    vSession.party = {}

    -- Fixed party: High Pixie (2), Skeleton (3), Angel (4)
    local actIds = {2, 3, 4}
    for _, id in ipairs(actIds) do
        local actorData = loader.getActor(id)
        if actorData then
            local b = session.Battler.new(actorData, 1)
            b.hp = b:getMaxHp(vSession)
            table.insert(vSession.party, b)
        end
    end

    local enemies = {}
    for i=1, 3 do
        local enemyData = loader.getActor(1) -- Pixie
        if enemyData then
            local b = session.Battler.new(enemyData, 1)
            b.hp = b:getMaxHp(vSession)
            table.insert(enemies, b)
        end
    end

    local vBattle = battleSystem.Battle.new(vSession, enemies)

    local function logEvents(events)
        for _, ev in ipairs(events) do
            local t = ev.type or ""
            local a = ev.actor and ev.actor.name or ""
            local trg = ev.target and ev.target.name or ""
            local v = ev.value or ""
            local s = ev.state or ""
            print(string.format("%s|%s|%s|%s|%s", t, a, trg, tostring(v), s))
        end
    end

    print("GOLDEN BEGIN")

    -- Round 1: all attack
    local actionsR1 = {}
    actionsR1[1] = { type = "attack", target = enemies[1] } -- Summoner
    for i=1, 3 do
        if vSession.party[i] then
            actionsR1[i+1] = { type = "attack", target = enemies[1] }
        end
    end
    logEvents(vBattle:resolveRound(actionsR1))

    -- Round 2: spell + defend + attacks
    local actionsR2 = {}
    local sysSpells = loader.system and loader.system.summoner and loader.system.summoner.spells or {}
    local firstSpell = sysSpells[1]
    if type(firstSpell) == "table" then firstSpell = firstSpell.id end

    if firstSpell then
        actionsR2[1] = { type = "spell", id = firstSpell, target = vSession.party[1] }
    else
        actionsR2[1] = { type = "attack", target = enemies[2] }
    end

    if vSession.party[1] then actionsR2[2] = { type = "defend", target = vSession.party[1] } end
    if vSession.party[2] then actionsR2[3] = { type = "attack", target = enemies[2] } end
    if vSession.party[3] then actionsR2[4] = { type = "attack", target = enemies[2] } end

    logEvents(vBattle:resolveRound(actionsR2))

    -- Round 3: flee
    local actionsR3 = {}
    actionsR3[1] = { type = "flee" }
    for i=1, 3 do
        if vSession.party[i] then
            actionsR3[i+1] = { type = "attack", target = enemies[2] }
        end
    end
    logEvents(vBattle:resolveRound(actionsR3))

    -- One victory resolution against a 1-HP enemy
    local vSessionVic = session.GameSession.new(loader)
    vSessionVic.party = {}
    local bVic = session.Battler.new(loader.getActor(2), 1)
    bVic.hp = bVic:getMaxHp(vSessionVic)
    table.insert(vSessionVic.party, bVic)

    local enemiesVic = {}
    local bVicEnm = session.Battler.new(loader.getActor(1), 1)
    bVicEnm.hp = 1
    table.insert(enemiesVic, bVicEnm)

    local vBattleVic = battleSystem.Battle.new(vSessionVic, enemiesVic)
    local actionsVic = {}
    actionsVic[1] = { type = "attack", target = enemiesVic[1] }
    actionsVic[2] = { type = "attack", target = enemiesVic[1] }
    logEvents(vBattleVic:resolveRound(actionsVic))

    print("GOLDEN END")
end

runValidation = function()
    local problems = {}
    local function check(cond, msg)
        if not cond then table.insert(problems, msg) end
        return cond
    end

    -- Registry lookup sets from data/engine.json
    local validEffectTypes = {}
    for _, et in ipairs((loader.engine and loader.engine.effectTypes) or {}) do
        validEffectTypes[et.id] = true
    end
    local validTraitCodes = {}
    for _, tc in ipairs((loader.engine and loader.engine.traitCodes) or {}) do
        validTraitCodes[tc.code] = true
    end

    -- Meta system validation (C10)
    local registeredMeta = {}
    for _, mk in ipairs((loader.engine and loader.engine.metaKeys) or {}) do
        local applies = {}
        for _, coll in ipairs(mk.appliesTo or {}) do
            applies[coll] = true
        end
        registeredMeta[mk.key] = {
            type = mk.type,
            appliesTo = applies
        }
    end

    local undeclaredWarnings = 0
    local function validateMeta(metaObj, collName, entryId)
        if not metaObj then return end
        for k, v in pairs(metaObj) do
            local reg = registeredMeta[k]
            if reg then
                if not reg.appliesTo[collName] then
                    check(false, "meta key '" .. tostring(k) .. "' does not apply to collection '" .. collName .. "' (on entry '" .. tostring(entryId) .. "')")
                else
                    local ok = false
                    if reg.type == "number" then
                        ok = (type(v) == "number")
                    elseif reg.type == "string" then
                        ok = (type(v) == "string")
                    elseif reg.type == "flag" then
                        ok = (type(v) == "boolean")
                    end
                    check(ok, "meta key '" .. tostring(k) .. "' on entry '" .. tostring(entryId) .. "' in '" .. collName .. "' has wrong type (expected " .. reg.type .. ", got " .. type(v) .. ")")
                end
            else
                print("[validator] warning: undeclared meta key '" .. tostring(k) .. "' on entry '" .. tostring(entryId) .. "' in '" .. collName .. "'")
                undeclaredWarnings = undeclaredWarnings + 1
            end
        end
    end

    for _, actor in ipairs(loader.actors or {}) do
        validateMeta(actor.meta, "actors", actor.id or actor.name or "?")
    end
    for _, item in ipairs(loader.items or {}) do
        validateMeta(item.meta, "items", item.id or item.name or "?")
    end
    for _, ce in ipairs(loader.commonEvents or {}) do
        validateMeta(ce.meta, "commonEvents", ce.id or ce.name or "?")
    end

    local dictColls = {
        elements = loader.elements,
        maps = loader.maps,
        quests = loader.quests,
        shops = loader.shops,
        sounds = loader.sounds,
        themes = loader.themes,
        skills = loader.skills,
        passives = loader.passives,
        states = loader.states,
        roles = loader.roles
    }
    for collName, dict in pairs(dictColls) do
        for id, entry in pairs(dict or {}) do
            validateMeta(entry.meta, collName, id)
        end
    end

    if undeclaredWarnings > 0 then
        print("[validator] total undeclared meta warnings: " .. undeclaredWarnings)
    end
    local function checkTraits(traitList, ownerDesc)
        for _, tr in ipairs(traitList or {}) do
            check(validTraitCodes[tr.code], ownerDesc .. " uses unregistered trait code '" .. tostring(tr.code) .. "'")
        end
    end
    local function checkEffects(effList, ownerDesc)
        for _, eff in ipairs(effList or {}) do
            check(validEffectTypes[eff.type], ownerDesc .. " uses unregistered effect type '" .. tostring(eff.type) .. "'")
            if eff.type == "add_status" then
                check(loader.getState(eff.status), ownerDesc .. " references missing state '" .. tostring(eff.status) .. "'")
            end
        end
    end

    -- Actors must reference existing skills/passives/elements/roles
    for _, actor in ipairs(loader.actors) do
        for _, skId in ipairs(actor.skills or {}) do
            check(loader.getSkill(skId), "actor " .. tostring(actor.id) .. " references missing skill '" .. tostring(skId) .. "'")
        end
        for _, pId in ipairs(actor.passives or {}) do
            check(loader.getPassive(pId), "actor " .. tostring(actor.id) .. " references missing passive '" .. tostring(pId) .. "'")
        end
        for _, el in ipairs(actor.elements or {}) do
            check(loader.getElement(el), "actor " .. tostring(actor.id) .. " references missing element '" .. tostring(el) .. "'")
        end
        if actor.role then
            check(loader.getRole(actor.role), "actor " .. tostring(actor.id) .. " references missing role '" .. tostring(actor.role) .. "'")
        end
        checkTraits(actor.traits, "actor " .. tostring(actor.id))
    end

    -- Skills: effect types, states and elements must exist
    for id, skill in pairs(loader.skills) do
        checkEffects(skill.effects, "skill '" .. tostring(id) .. "'")
        if skill.element then
            check(loader.getElement(skill.element), "skill '" .. tostring(id) .. "' references missing element '" .. tostring(skill.element) .. "'")
        end
    end

    -- Passives/states/items: trait codes must be registered
    for id, passive in pairs(loader.passives) do
        checkTraits(passive.traits, "passive '" .. tostring(id) .. "'")
    end
    for id, state in pairs(loader.states) do
        checkTraits(state.traits, "state '" .. tostring(id) .. "'")
    end
    for _, item in ipairs(loader.items) do
        checkTraits(item.traits, "item " .. tostring(item.id))
        checkEffects(item.effects, "item " .. tostring(item.id))
    end

    -- Elements: affinity lists must point at registered elements
    for id, elem in pairs(loader.elements or {}) do
        for _, other in ipairs(elem.strongAgainst or {}) do
            check(loader.getElement(other), "element '" .. tostring(id) .. "' strongAgainst missing element '" .. tostring(other) .. "'")
        end
        for _, other in ipairs(elem.weakAgainst or {}) do
            check(loader.getElement(other), "element '" .. tostring(id) .. "' weakAgainst missing element '" .. tostring(other) .. "'")
        end
    end

    -- System config references
    local sys = loader.system or {}
    local combat = sys.combat or {}
    check(loader.getSkill(combat.defendSkillId or "defend"), "combat.defendSkillId references a missing skill")
    check(loader.getSkill(combat.attackSkillId or "attack"), "combat.attackSkillId references a missing skill")
    check(loader.getItem(combat.battleItem or 1), "combat.battleItem references a missing item")
    local spells = (sys.summoner and sys.summoner.spells) or {}
    for _, spellId in ipairs(spells) do
        if type(spellId) == "table" then spellId = spellId.id end
        check(loader.getSkill(spellId), "summoner spell references missing skill '" .. tostring(spellId) .. "'")
    end
    for i, opt in ipairs((sys.town and sys.town.options) or {}) do
        check(opt.label and opt.action, "town option #" .. i .. " is missing label/action")
    end

    -- Shop stock must reference existing items
    for shopId, shop in pairs(loader.shops or {}) do
        for _, stock in ipairs(shop.items or {}) do
            check(loader.getItem(stock.id), "shop " .. tostring(shopId) .. " stocks missing item '" .. tostring(stock.id) .. "'")
        end
    end

    -- Simulated battle round with a starting party
    local vSession = session.GameSession.new(loader)
    vSession:initializeStartingParty()
    check(#vSession.party > 0, "new game produced an empty party")

    local enemyData = loader.getActor(1)
    if check(enemyData, "actor id 1 missing (needed for validation battle)") then
        local enemy = session.Battler.new(enemyData, 1)
        enemy.hp = enemy:getMaxHp(vSession)
        local vBattle = battleSystem.Battle.new(vSession, { enemy })

        local actions = {}
        local firstSpell = spells[1]
        if type(firstSpell) == "table" then firstSpell = firstSpell.id end
        if firstSpell then
            actions[1] = { type = "spell", id = firstSpell, target = vSession.party[1] }
        end
        for i = 1, 4 do
            if vSession.party[i] then
                actions[i + 1] = { type = (i == 1) and "defend" or "attack", target = enemy }
            end
        end
        local events = vBattle:resolveRound(actions)
        check(#events > 0, "battle round produced no events")
    end

    -- Formula sandbox: a representative reward-curve expression must compile
    -- and evaluate against a mock context (SPEC S5 / task A2).
    do
        local formulaEngine = require("engine.formula")
        local mockCtx = {
            enemy = { level = 4, hp = 30, maxHp = 40, atk = 12, def = 8, mat = 10, mdf = 9 },
            session = { gold = 100, mp = 20, maxMp = 30, floor = 3 },
        }
        local expr = "floor(enemy.maxHp * 0.5) + random(1, session.floor * 2) + round(enemy.level * 1.5)"
        local val, ferr = formulaEngine.eval(expr, mockCtx)
        check(ferr == nil and type(val) == "number" and val >= 27 and val <= 32,
            "formula sandbox failed reward-curve check: " .. tostring(ferr or val))
        -- The sandbox must reject environment escapes
        local _, escErr = formulaEngine.eval("os.time()", mockCtx)
        check(escErr ~= nil, "formula sandbox allowed access to os.*")
    end

    -- Unified Event Engine Validator (SPEC A7)
    local scriptUsageCount = 0
    local deprecatedUsageCount = 0
    local registry = {}
    for _, c in ipairs((loader.engine and loader.engine.commands) or {}) do
        registry[c.id] = c
    end

    -- Handler coverage: every command the registry offers must actually be
    -- implemented. Without this, a registered-but-unimplemented command (a
    -- "stub") appears in the editor's palette and silently no-ops when a
    -- designer authors it — the dead-content failure this validator exists to
    -- prevent. Registry entries are a contract: an id needs a Lua handler (or
    -- an interpreter.compile case) to mean anything.
    for _, c in ipairs((loader.engine and loader.engine.commands) or {}) do
        check(interpreter.isImplemented(c.id),
            "engine.json registers command '" .. tostring(c.id) ..
            "' with no handler in engine/interpreter.lua (stub commands are not allowed)")
    end

    local function validateCommands(cmds, hostCtx, isImmediate, allowScript, ownerDesc)
        for _, cmd in ipairs(cmds or {}) do

            local id = cmd.cmd or cmd.type
            if id == nil then
                check(false, ownerDesc .. " uses unknown command 'nil' (missing cmd or type field)")
                goto continue
            end
            if id == "COMMENT" then
                -- COMMENT is accepted everywhere and never flagged.
                -- comment field is also accepted everywhere, which we just ignore.
                goto continue
            end

            local cmdDef = registry[id]
            check(cmdDef ~= nil, ownerDesc .. " uses unknown command '" .. tostring(id) .. "'")

            if cmdDef then
                if cmdDef.deprecatedBy then
                    deprecatedUsageCount = deprecatedUsageCount + 1
                end

                -- Check context
                local ctxAllowed = false
                for _, c in ipairs(cmdDef.contexts or {}) do
                    if c == "any" or c == hostCtx then ctxAllowed = true; break end
                end
                check(ctxAllowed, ownerDesc .. " uses command '" .. id .. "' in invalid context '" .. hostCtx .. "'")

                -- Check interactive in immediate mode
                if isImmediate and cmdDef.interactive then
                    check(false, ownerDesc .. " immediate mode cannot use interactive command '" .. id .. "'")
                end

                if id == "SCRIPT" then
                    scriptUsageCount = scriptUsageCount + 1
                    check(allowScript, ownerDesc .. " contains a SCRIPT command (S6 zero-SCRIPT rule)")
                end

                -- Validate params
                for _, paramDef in ipairs(cmdDef.params or {}) do
                    local val = cmd[paramDef.key]
                    if val ~= nil then

                if paramDef.type == "formula" then
                    local mockCtx = {
                        enemy = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        ally = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        target = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        a = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        b = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        session = { gold = 100, mp = 20, maxMp = 30, floor = 3, mapSafe = false, encounterRate = 0.1 },
                        combat = { minEnemies = 1, maxEnemies = 3, victoryGoldMin = 1, victoryGoldMax = 5, victoryExp = 10, baseFleeChance = 0.5, goldLossOnFleeMin = 1, goldLossOnFleeMax = 5, mpExhaustionDamage = 5 },
                        v = { roll = 0.5, bonus = 10 },
                        party = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, fleeBonus = 0.1 },
                        enemies = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, fleeBonus = 0.1 }
                    }
                    local formulaEngine = require("engine.formula")
                    if type(val) == "string" and (val:match("^flag:") or val:match("^hasItem:")) then
                        -- Allow legacy condition strings
                    else
                        local ok, _, ferr = pcall(formulaEngine.eval, val, mockCtx)
                        check(ok and ferr == nil, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' failed to compile formula '" .. tostring(val) .. "': " .. tostring(ferr))
                    end
                elseif paramDef.type == "commands" then
                    -- val could be a list of commands, OR for CHOICE it could be a list of options where each option has .commands
                    -- Task A4b: nested lists of a NON-interactive block command
                    -- (IF, FOR_EACH, ...) always execute in immediate mode —
                    -- even in map/common hosts, where the RUN_IMMEDIATE bridge
                    -- runs them through runImmediate. Interactive commands
                    -- inside them would error at runtime, so flag them here.
                    local nestedImmediate = isImmediate or (cmdDef.interactive ~= true)
                    if id == "CHOICE" and type(val) == "table" then
                        for oi, opt in ipairs(val) do
                            if opt.commands then validateCommands(opt.commands, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> CHOICE opt") end
                            if opt.script then validateCommands(opt.script, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> CHOICE opt") end
                        end
                    else
                        validateCommands(val, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> nested")
                    end
elseif paramDef.type == "script" then
                            local chunk, err = load(val, "validator", "t", {})
                            check(chunk ~= nil, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' script syntax error: " .. tostring(err))
                        elseif paramDef.type == "term" then
                            -- Ensure it's a string, resolution is implicit as getTerm falls back to the key, but we check type
                            check(type(val) == "string", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a string term")
                        elseif paramDef.type == "state" then
                            check(loader.getState(val), ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing state '" .. tostring(val) .. "'")
                        elseif paramDef.type == "item" then
                            check(loader.getItem(val), ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing item '" .. tostring(val) .. "'")
                        elseif paramDef.type == "scope" then
                            local validScopes = { enemies=true, living_enemies=true, allies=true, living_allies=true, party=true, slot_allies=true }
                            check(validScopes[val], ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' has invalid scope '" .. tostring(val) .. "'")
                        elseif paramDef.type == "battlerRef" then
                            -- Usually just a string like "target", "a", "b", "summoner", etc.
                            check(type(val) == "string" or type(val) == "table", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a valid battlerRef")
                        elseif paramDef.type == "commands" then
                            validateCommands(val, hostCtx, isImmediate or (cmdDef.interactive ~= true), allowScript, ownerDesc .. " -> nested")
                        end
                    end
                end
            end

            ::continue::
        end
    end

    -- Run the tree walker over all data files
    for _, map in ipairs(loader.maps or {}) do
        for i, ev in ipairs(map.events or {}) do
            local desc = "map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) .. ")"
            if ev.commands then
                validateCommands(ev.commands, "map", false, true, desc)
            end
            if ev.script then
                validateCommands(ev.script, "map", false, true, desc)
            end
        end
    end

    for ceId, ce in pairs(loader.commonEvents or {}) do
        if ce.commands then
            validateCommands(ce.commands, "common", false, true, "common event '" .. tostring(ceId) .. "'")
        end
        if ce.script then
            validateCommands(ce.script, "common", false, true, "common event '" .. tostring(ceId) .. "'")
        end
    end

    for phaseName, cmds in pairs((loader.flows or {}).battle or {}) do
        if type(cmds) == "table" then
            -- Default battle phases enforce zero-SCRIPT (S6)
            validateCommands(cmds, "battle_phase", true, false, "flows.json battle." .. phaseName)
        end
    end

    for phaseName, cmds in pairs((loader.flows or {})._test or {}) do
        if type(cmds) == "table" then
            validateCommands(cmds, "battle_phase", true, true, "flows.json _test." .. phaseName)
        end
    end



    -- Interpreter immediate mode: the _test flow exercises every implemented
    -- non-interactive command (SPEC S1/S2; ROLL_ENCOUNTER/SPAWN_ENEMIES land
    -- with task A5d and are registry-only for now).
    do
        local tSession = session.GameSession.new(loader)
        tSession:initializeStartingParty()
        local tEnemy = session.Battler.new(loader.getActor(1), 1)
        tEnemy.hp = tEnemy:getMaxHp(tSession)
        local tCtx = {
            session = tSession,
            party = tSession.party,
            enemies = { tEnemy },
            target = tSession.party[1],
            a = tSession.party[1],
        }
        local okFlow, flowErr = pcall(flow.run, "_test.scene", tCtx)
        check(okFlow, "_test.scene flow failed: " .. tostring(flowErr))
        if okFlow then
            local sawDamage, sawScript, sawScene = false, false, false
            for _, ev in ipairs(tCtx.events or {}) do
                if ev.type == "damage" then sawDamage = true end
                if ev.type == "text" and tostring(ev.text):match("^script ran") then sawScript = true end
                if ev.type == "scene_change" then sawScene = true end
            end
            check(sawDamage, "_test.scene emitted no damage events (api.damage / DAMAGE broken)")
            check(sawScript, "_test.scene SCRIPT did not emit through api.emit")
            check(sawScene, "_test.scene SCENE_EVENT did not emit scene_change")
        end

        -- SCRIPT sandbox negative test: raw access must error by default
        check((loader.engine.scripting or {}).allowRawAccess == false,
            "engine.json scripting.allowRawAccess must default to false")
        local okEsc = pcall(flow.run, "_test.script_escape", { session = tSession })
        check(not okEsc, "SCRIPT sandbox allowed os.* access with allowRawAccess=false")

        -- Task A4b: the interactive-immediate bridge. A mixed command list
        -- must compile its contiguous non-interactive run (COMMENTs swallowed)
        -- into ONE RUN_IMMEDIATE node between the TEXT nodes, and executing
        -- that run must share flow-locals (SET_VAR -> IF) and emit text.
        do
            local nodes = {}
            local mixed = {
                { type = "TEXT", text = "before" },
                { cmd = "SET_VAR", name = "n", value = "2 + 3" },
                { cmd = "COMMENT", text = "swallowed into the run" },
                { cmd = "IF", condition = "v.n == 5", ["then"] = {
                    { cmd = "GAIN_GOLD", amount = "v.n" },
                    { cmd = "EMIT_TEXT", fallback = "bridge ran" },
                } },
                { type = "TEXT", text = "after" },
            }
            local firstId = interpreter.compile(nodes, mixed, "a4b", nil,
                { loader = loader, recoverParty = function() end, session = tSession })
            check(nodes[firstId] and nodes[firstId].type == "TEXT", "A4b: first mixed node should be TEXT")
            local runNode = nodes[firstId] and nodes[nodes[firstId].next]
            check(runNode and runNode.type == "ACTION" and runNode.action == "RUN_IMMEDIATE",
                "A4b: non-interactive run did not compile to RUN_IMMEDIATE")
            if runNode then
                check(#runNode.commands == 3, "A4b: run should group 3 commands (SET_VAR, COMMENT, IF), got " .. tostring(#runNode.commands))
                check(nodes[runNode.next] and nodes[runNode.next].type == "TEXT" and nodes[runNode.next].content == "after",
                    "A4b: RUN_IMMEDIATE must chain to the trailing TEXT node")
                local goldBefore = tSession.gold
                local okRun, evs = pcall(interpreter.runImmediate, runNode.commands,
                    { session = tSession, loader = loader, party = tSession.party })
                check(okRun, "A4b: RUN_IMMEDIATE execution failed: " .. tostring(evs))
                if okRun then
                    check(tSession.gold == goldBefore + 5, "A4b: SET_VAR -> IF -> GAIN_GOLD did not share flow-locals across the run")
                    local sawBridgeText = false
                    for _, ev in ipairs(evs) do
                        if ev.type == "text" and ev.text == "bridge ran" then sawBridgeText = true end
                    end
                    check(sawBridgeText, "A4b: EMIT_TEXT inside the run emitted no text event")
                end
            end
        end
    end

    -- Interactive compile sweep: every map event and common event must
    -- compile to a well-formed dialogue graph (all node links resolve).
    do
        local cSession = session.GameSession.new(loader)
        local cCtx = { loader = loader, recoverParty = function() end, session = cSession }
        local function checkGraph(desc, commands)
            if not commands or #commands == 0 then return end
            local nodes = {}
            local ok, firstOrErr = pcall(interpreter.compile, nodes, commands, "node", nil, cCtx)
            if not check(ok, desc .. " failed to compile: " .. tostring(firstOrErr)) then return end
            for id, node in pairs(nodes) do
                for _, key in ipairs({ "next", "trueNode", "falseNode" }) do
                    local link = node[key]
                    check(link == nil or nodes[link] ~= nil,
                        desc .. " node '" .. id .. "' links to missing node '" .. tostring(link) .. "'")
                end
                for _, opt in ipairs(node.options or {}) do
                    check(opt.target == nil or nodes[opt.target] ~= nil,
                        desc .. " choice option links to missing node '" .. tostring(opt.target) .. "'")
                end
            end
        end
        for _, map in ipairs(loader.maps or {}) do
            for _, ev in ipairs(map.events or {}) do
                checkGraph("map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) .. ")", ev.commands)
            end
        end
        for ceId, ce in pairs(loader.commonEvents or {}) do
            checkGraph("common event " .. tostring(ceId), ce.commands)
        end
    end



    -- battle.victory flow must reproduce the legacy reward block exactly:
    -- same gold roll, same XP, same POST_BATTLE_HEAL (task A5a).
    if flow.has("battle.victory") then
        local function freshParty()
            local s = session.GameSession.new(loader)
            s:initializeStartingParty()
            for _, c in ipairs(s.party) do c.hp = math.max(1, math.floor(c:getMaxHp(s) / 2)) end
            return s
        end
        math.randomseed(4242)
        local sFlow = freshParty()
        flow.run("battle.victory", { session = sFlow, party = sFlow.party, enemies = {} })
        math.randomseed(4242)
        local sLegacy = freshParty()
        sLegacy.gold = sLegacy.gold + math.random(conf("combat", "victoryGoldMin", 10), conf("combat", "victoryGoldMax", 30))
        for _, c in ipairs(sLegacy.party) do
            if not c:isDead() then
                c:gainExp(conf("combat", "victoryExp", 5), sLegacy)
                local regenVal = traits.getRate(c, "POST_BATTLE_HEAL", sLegacy)
                if regenVal > 0 then
                    c.hp = math.min(c:getMaxHp(sLegacy), c.hp + regenVal)
                end
            end
        end
        check(sFlow.gold == sLegacy.gold,
            "battle.victory flow gold mismatch: flow=" .. sFlow.gold .. " legacy=" .. sLegacy.gold)
        for i, c in ipairs(sFlow.party) do
            local l = sLegacy.party[i]
            check(c.hp == l.hp and c.exp == l.exp and c.level == l.level,
                "battle.victory flow diverges from legacy for party member " .. i ..
                " (hp " .. c.hp .. "/" .. l.hp .. ", exp " .. tostring(c.exp) .. "/" .. tostring(l.exp) .. ")")
        end
    end

    -- Item effects go through the same pipeline in and out of battle
    local item = loader.getItem(combat.battleItem or 1)
    if item and vSession.party[1] then
        for _, eff in ipairs(item.effects or {}) do
            effects.apply(eff, vSession.party[1], vSession.party[1], vSession)
        end
    end

    -- Scenes validation (C9)
    local function validateScenes()
        local formulaEngine = require("engine.formula")
        local mockItem1 = loader.getItem(1)
        local mockItem2 = loader.getItem(2)
        local mockCrafter = session.Battler.new(loader.getActor(1), 1)
        
        local mockCtx = {
            i1 = formulaEngine.itemView(mockItem1),
            i2 = formulaEngine.itemView(mockItem2),
            crafter = mockCrafter,
            alpha = 0.5,
            S = 10
        }
        
        for _, scene in ipairs(loader.scenes or {}) do
            local sceneDesc = "scene '" .. tostring(scene.id) .. "' (" .. tostring(scene.name) .. ")"
            check(type(scene.id) == "number", sceneDesc .. " ID must be a number")
            check(scene.kind == "crafting", sceneDesc .. " unknown scene kind '" .. tostring(scene.kind) .. "'")
            
            local config = scene.config or {}
            check(config.disciplines ~= nil, sceneDesc .. " missing disciplines config")
            if config.disciplines then
                for _, disc in ipairs(config.disciplines) do
                    check(disc.kind ~= nil, sceneDesc .. " discipline missing kind")
                    check(disc.stat ~= nil, sceneDesc .. " discipline missing stat")
                    local validStats = { atk = true, def = true, mat = true, mdf = true, maxHp = true, asp = true, mpd = true, level = true }
                    check(validStats[disc.stat], sceneDesc .. " discipline uses invalid stat parameter '" .. tostring(disc.stat) .. "'")
                end
            end
            
            check(config.yieldFormula ~= nil, sceneDesc .. " missing yieldFormula")
            if config.yieldFormula then
                local ok, _, ferr = pcall(formulaEngine.eval, config.yieldFormula, mockCtx)
                check(ok and ferr == nil, sceneDesc .. " yieldFormula failed to compile: " .. tostring(ferr or ""))
            end
            
            check(config.penaltyFormula ~= nil, sceneDesc .. " missing penaltyFormula")
            if config.penaltyFormula then
                local ok, _, ferr = pcall(formulaEngine.eval, config.penaltyFormula, mockCtx)
                check(ok and ferr == nil, sceneDesc .. " penaltyFormula failed to compile: " .. tostring(ferr or ""))
            end
            
            check(config.anomalyFormula ~= nil, sceneDesc .. " missing anomalyFormula")
            if config.anomalyFormula then
                local ok, _, ferr = pcall(formulaEngine.eval, config.anomalyFormula, mockCtx)
                check(ok and ferr == nil, sceneDesc .. " anomalyFormula failed to compile: " .. tostring(ferr or ""))
            end
            
            check(config.brackets ~= nil, sceneDesc .. " missing brackets config")
            if config.brackets then
                for _, br in ipairs(config.brackets) do
                    check(br.max ~= nil, sceneDesc .. " bracket missing max value")
                    check(br.tier ~= nil, sceneDesc .. " bracket missing tier value")
                    check(type(br.max) == "number", sceneDesc .. " bracket max must be a number")
                    check(type(br.tier) == "number", sceneDesc .. " bracket tier must be a number")
                end
            end

            if config.disciplines and config.brackets then
                for _, disc in ipairs(config.disciplines) do
                    for _, br in ipairs(config.brackets) do
                        local count = 0
                        for _, item in ipairs(loader.items or {}) do
                            if item.meta and item.meta.craftKind == disc.kind and item.meta.tier == br.tier then
                                count = count + 1
                            end
                        end
                        check(count > 0, sceneDesc .. " no items match discipline '" .. tostring(disc.kind) .. "' and tier " .. tostring(br.tier))
                    end
                end
            end
            
            check(config.timing ~= nil, sceneDesc .. " missing timing config")
        end
    end
    validateScenes()

    print("[validator] total SCRIPT usages: " .. scriptUsageCount)
    print("[validator] total deprecated usages: " .. deprecatedUsageCount)

    if #problems > 0 then
        error(table.concat(problems, "\n"), 0)
    end
end

function love.load(arg)
    print("--------------------------------------------------")
    print("HICHAUKITODEN GAME LOADED (WITH INPUT COOLDOWN FIX)")
    print("--------------------------------------------------")
    
    -- Check for CLI arguments (test-battle, validate)
    if arg then
        for _, val in ipairs(arg) do
            if val == "test-battle" then
                isTestBattle = true
            elseif val == "validate" then
                isValidateMode = true
            elseif val == "golden" then
                isGoldenMode = true
            end
        end
    end

    -- Headless data validation: check database cross-references and simulate
    -- a battle round, then quit. Run via `lovec . validate` (used by CI/tools).
    if isValidateMode then
        loader.init()
        local ok, err
        if isGoldenMode then
            ok, err = pcall(runGolden)
        else
            ok, err = pcall(runValidation)
        end

        if ok and not isGoldenMode then
            print("VALIDATE OK")
        elseif not ok then
            print("VALIDATE FAIL:\n" .. tostring(err))
        end
        love.event.quit(ok and 0 or 1)
        return
    end
    
    love.graphics.setDefaultFilter("nearest", "nearest")
    canvas = love.graphics.newCanvas(gameWidth, gameHeight)
    love.resize(love.graphics.getWidth(), love.graphics.getHeight())
    
    -- Initialize database loader
    loader.init()
    
    -- Initialize activeSession
    activeSession = session.GameSession.new(loader)
    activeSession:initializeStartingParty()
    
    -- Initialize renderer graphics
    renderer.init(activeSession)
    
    -- Initialize 3D viewport textures
    viewport_3d.init()
    
    -- Start developer server
    server.start()
    
    -- If in test battle mode, launch immediately into battle
    if isTestBattle then
        triggerTestBattle()
    end
end

function love.update(dt)
    renderer.update(dt)
    server.update(dt)
    if activeSession and activeSession.transitionTimer and activeSession.transitionTimer > 0 then
        activeSession.transitionTimer = activeSession.transitionTimer - dt
    end
    
    if inputCooldown > 0 then
        inputCooldown = inputCooldown - dt
    end
    
    -- Exiting scene transition (slide-out animation)
    if renderer.closing then
        renderer.closingTimer = renderer.closingTimer - dt
        if renderer.closingTimer <= 0 then
            renderer.closing = false
            currentScene = renderer.closingTargetScene
            if renderer.closingTargetSubScene ~= "" then
                menuSubScene = renderer.closingTargetSubScene
            end
            renderer.resetMenuTimer()
            inputCooldown = conf("ui", "inputCooldown", 0.30)
        end
    end
    
    if activeSceneHost then
        activeSceneHost:update(dt)
    elseif currentScene == "crafting" then
        if updateCraftingScene then updateCraftingScene(dt) end
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1) -- reset color at start of frame
    
    if currentScene == "title" then
        renderer.drawTitle()
    elseif currentScene == "town" then
        renderer.drawTown(townSelectedIdx)
    elseif currentScene == "map" then
        renderer.drawMap()
    elseif currentScene == "dialogue" then
        renderer.drawDialogue(activeWalker, dialogueSelectIdx)
    elseif currentScene == "battle" then
        renderer.drawBattle(activeBattle, battleCombatLog, battleCombatState, battleSelectedIndex, battleSpellSelect, battleLivingMembers, battleActiveMemberIndex)
    elseif currentScene == "shop" then
        renderer.drawShop(activeShopName, shopSelectedIdx, shopItems)
    elseif currentScene == "menu" then
        if previousSceneBeforeMenu == "town" then
            renderer.drawTown(townSelectedIdx)
        else
            renderer.drawMap()
        end
        if menuSubScene == "use_target" then
            renderer.drawTargetSelector(menuSelectedSubIdx, activeSession)
        elseif menuSubScene == "equip_passive" then
            renderer.drawEquipMenu(activeSession.party[selectedCreatureIndex], menuSelectedSubIdx, activeSession)
        elseif menuSubScene == "select_passive" then
            local slotType = (selectedSlotIndex == 1) and "Weapon" or (selectedSlotIndex == 2 and "Armor" or "Accessory")
            renderer.drawSelectEquipMenu(menuSelectedSubIdx, activeSession, slotType, activeSession.party[selectedCreatureIndex], selectedSlotIndex)
        else
            renderer.drawMainMenu(menuSelectedIdx, menuActiveCol, menuSelectedSubIdx, activeSession, menuSubScene)
        end
    elseif activeSceneHost then
        activeSceneHost:draw()
    elseif currentScene == "crafting" then
        if drawCraftingScene then drawCraftingScene() end
    end
    
    if server.isActive() then
        love.graphics.setColor(0.1, 0.4, 0.8, 0.8)
        love.graphics.rectangle("fill", 216, 2, 38, 9)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("DEV ON", 219, 3)
    end
    
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1, 1) -- reset color before drawing canvas to prevent dark tinting leak
    love.graphics.draw(canvas, scaleX, scaleY, 0, scale, scale)
end

local handleDialogueAction -- forward declaration
local triggerBattle -- forward declaration
local rebuildBattleLivingMembers -- forward declaration

local function isSafeMap()
    if activeSession and activeSession.currentMapData then
        return activeSession.currentMapData.safe == true
    end
    return true
end

-- Fully restores HP/MP and revives the whole party
local function recoverParty()
    activeSession.mp = activeSession.maxMp
    for _, c in ipairs(activeSession.party) do
        c.hp = c:getMaxHp(activeSession)
        c:removeState("dead")
    end
    activeSession.summoner.hp = activeSession.summoner:getMaxHp(activeSession)
    activeSession.summoner:removeState("dead")
end

-- Applies an item's data-defined effects (from items.json) to a party member.
-- Delegates to engine/effects.lua so field and battle item use share one
-- implementation.
local function applyItemToTarget(item, target)
    for _, eff in ipairs(item.effects or {}) do
        effects.apply(eff, target, target, activeSession)
    end
end

-- Command compilation moved to engine/interpreter.lua (task A4); main.lua
-- keeps only this thin glue that supplies the loader and the recoverParty
-- callback the RECOVER_PARTY command needs.
local function interpreterCtx()
    return { loader = loader, recoverParty = recoverParty, session = activeSession }
end

local function compileCommands(nodes, commands, prefix, tailNodeId)
    return interpreter.compile(nodes, commands, prefix, tailNodeId, interpreterCtx())
end

local function openShop(shopId)
    activeShopId = shopId
    shopItems = {}
    shopSelectedIdx = 1

    -- Shops are stored as a string-keyed table (JSON object keys are always
    -- strings) even though shopId itself arrives as a number from dialogue
    -- graphs, so the lookup needs an explicit tostring() -- same pattern used
    -- for commonEvents lookups by scriptId elsewhere in this file.
    local shopData = loader.shops[tostring(shopId)]
    activeShopName = (shopData and shopData.name) or tostring(shopId)
    if shopData and shopData.items then
        for _, shopItem in ipairs(shopData.items) do
            local allowed = true
            if shopItem.condition then
                local cond = shopItem.condition
                if cond:match("^level:(%d+)") then
                    local lvl = tonumber(cond:match("^level:(%d+)"))
                    allowed = (activeSession.summoner.level >= lvl)
                elseif cond:match("^flag:(.+)") then
                    local flag = cond:match("^flag:(.+)")
                    allowed = (activeSession.flags[flag] == true)
                elseif cond:match("^gold:(%d+)") then
                    local gold = tonumber(cond:match("^gold:(%d+)"))
                    allowed = (activeSession.gold >= gold)
                end
            end
            
            if allowed then
                local itemData = loader.getItem(shopItem.id)
                if itemData then
                    -- Honor the per-shop price override set in the editor;
                    -- everything else reads through to the item database entry.
                    local entry = setmetatable({ cost = shopItem.price or itemData.cost }, { __index = itemData })
                    table.insert(shopItems, entry)
                end
            end
        end
    end
    currentScene = "shop"
end

handleDialogueAction = function()
    local node, nodeId = activeWalker:getCurrentNode()
    if not node then return end

    if node.type == "ACTION" then
        if node.action == "RUN_IMMEDIATE" then
            -- Task A4b: a compiled run of non-interactive registry commands.
            -- Mutations (gold, items, states, flags) apply through the same
            -- handlers battle phases use; emitted text events render as
            -- dialogue lines by converting this node into a TEXT chain, the
            -- same trick GIVE_ITEM_ACTION uses.
            local events = interpreter.runImmediate(node.commands, {
                session = activeSession,
                loader = loader,
                party = activeSession.party,
            })
            local texts = {}
            for _, ev in ipairs(events) do
                if ev.type == "text" and ev.text and ev.text ~= "" then
                    table.insert(texts, ev.text)
                end
            end
            if #texts > 0 then
                local tail = node.next
                node.type = "TEXT"
                node.content = texts[1]
                node.action = nil
                node.commands = nil
                local prev = node
                for k = 2, #texts do
                    local tid = nodeId .. "_imtext" .. k
                    activeWalker.graph.nodes[tid] = { type = "TEXT", content = texts[k], next = tail }
                    prev.next = tid
                    prev = activeWalker.graph.nodes[tid]
                end
            else
                activeWalker:advance()
                handleDialogueAction()
            end
        elseif node.action == "OPEN_SHOP" then
            openShop(node.shopId)
        elseif node.action == "OFFER_QUEST" then
            activeSession.flags["quest:" .. node.questId .. ":active"] = true
            activeWalker:goToNode(node.acceptNode or node.next)
            handleDialogueAction()
        elseif node.action == "COMPLETE_QUEST" then
            activeSession.flags["quest:" .. node.questId .. ":active"] = nil
            activeSession.flags["quest:" .. node.questId .. ":completed"] = true
            if node.takeItem then
                activeSession:addItem(node.takeItem, -1)
            end
            activeWalker:goToNode(node.completeNode or node.next)
            handleDialogueAction()
        elseif node.action == "DESCEND_FLOOR" then
            local maxFloor = conf("dungeon", "maxFloor", 5)
            activeSession.dungeonFloor = activeSession.dungeonFloor + 1
            if activeSession.dungeonFloor > maxFloor then
                activeSession.dungeonFloor = maxFloor
            end
            exploration.loadMap(activeSession, activeSession.dungeonFloor + 1)
            currentScene = "map"
        elseif node.action == "START_BATTLE" then
            triggerBattle()
        elseif node.action == "GIVE_ITEM_ACTION" then
            local loot = conf("dungeon", "defaultLoot", 1) -- 1 = HP Tonic
            if activeSession.currentMapData.treasures and #activeSession.currentMapData.treasures > 0 then
                loot = activeSession.currentMapData.treasures[math.random(#activeSession.currentMapData.treasures)]
            end
            local item = loader.getItem(loot)
            activeSession:addItem(loot, 1)

            node.type = "TEXT"
            node.content = loader.formatTerm("events.found_item", "Found a {0}!", (item and item.name or loot))
            node.action = nil
        elseif node.action == "CALL_COMMON_EVENT_ACTION" then
            local ce = loader.commonEvents and loader.commonEvents[tostring(node.commonEventId)]
            if ce and ce.commands then
                -- Build and inject sub-nodes into current walker graph dynamically
                local prefix = "ce_" .. node.commonEventId .. "_" .. tostring(os.clock()):gsub("%.", "_")
                local firstCeNode = compileCommands(activeWalker.graph.nodes, ce.commands, prefix, node.next)
                activeWalker:goToNode(firstCeNode)
                handleDialogueAction()
            else
                activeWalker:advance()
                handleDialogueAction()
            end
        elseif node.action == "RECOVER_PARTY_ACTION" then
            recoverParty()

            node.type = "TEXT"
            node.content = loader.getTerm("events.recover_party", "Your party has been fully recovered!")
            node.action = nil
        else
            activeWalker:advance()
            handleDialogueAction()
        end
    end
end

-- Translates JSON command lists to dynamic conversation graphs
local function runEventCommands(eventTitle, commands)
    local graph = interpreter.runInteractive(commands, interpreterCtx())
    if not graph then return end
    graph.name = eventTitle

    activeWalker = director.GraphWalker.new(activeSession, graph)
    activeWalker.eventName = eventTitle
    currentScene = "dialogue"
    handleDialogueAction()
end

local function checkStepEvents()
    local px, py = activeSession.playerX - 1, activeSession.playerY - 1
    if activeSession.currentMapData.events then
        for _, ev in ipairs(activeSession.currentMapData.events) do
            if ev.x == px and ev.y == py and ev.trigger == "step" then
                local commands = nil
                if ev.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = ev.script
                end
                
                if commands then
                    runEventCommands(ev.name or "Event", commands)
                    return true
                end
            end
        end
    end
    return false
end

-- Triggers a conversation graph
local function triggerDialogue(graphName)
    local walker = director.startConversation(activeSession, graphName)
    if walker then
        activeWalker = walker
        dialogueSelectIdx = 1
        currentScene = "dialogue"
        handleDialogueAction()
    end
end

-- Rebuilds the list of party members that still get to act this round
rebuildBattleLivingMembers = function()
    battleLivingMembers = {}
    table.insert(battleLivingMembers, { type = "summoner", actor = activeSession.summoner, index = 1 })
    for i = 1, 4 do
        local c = activeSession.party[i]
        if c and not c:isDead() then
            table.insert(battleLivingMembers, { type = "monster", actor = c, index = i + 1 })
        end
    end
    battleActiveMemberIndex = 1
    battleCollectedActions = {}
end

triggerBattle = function()
    local mapData = activeSession.currentMapData
    local possibleEnemies = mapData.encounters
    if not possibleEnemies or #possibleEnemies == 0 then return end

    local enemyList = {}
    if flow.has("battle.battle_start") then
        for _, ev in ipairs(flow.run("battle.battle_start", { session = activeSession })) do
            if ev.type == "spawn_enemies" then enemyList = ev.enemies end
        end
        if #enemyList == 0 then return end
    else
        -- Legacy composition (SPEC S4 fallback rule)
        local numEnemies = math.random(conf("combat", "minEnemies", 1), conf("combat", "maxEnemies", 3))

        for i = 1, numEnemies do
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

            local enemyData = loader.getActor(enemyId)
            if enemyData then
                local enemyBattler = session.Battler.new(enemyData, enemyData.level or activeSession.dungeonFloor)
                enemyBattler.hp = enemyBattler:getMaxHp(activeSession)
                table.insert(enemyList, enemyBattler)
            end
        end
    end

    activeBattle = battleSystem.Battle.new(activeSession, enemyList)
    battleCombatLog = { loader.getTerm("battle.encounter", "A hostile group blocks your path!") }
    battleEventsQueue = {}
    battleEventQueueIndex = 1
    battleCombatState = "input"
    battleSelectedIndex = 1
    battleSpellSelect = false
    battleEscaped = false

    rebuildBattleLivingMembers()

    currentScene = "battle"
    renderer.initBattleAnims(enemyList)
end

triggerTestBattle = function()
    -- Initialize session if not initialized
    if not activeSession then
        activeSession = session.GameSession.new(loader)
        activeSession:initializeStartingParty()
    end
    
    -- Spawn mock enemies (use database entries if they exist, otherwise fall back to generic dummy data)
    local enemyList = {}
    local gData = loader.getActor(1) or { id = "enemy_1", name = "Test Target A", level = 1 } -- Pixie
    local b1 = session.Battler.new(gData, 1)
    b1.hp = b1:getMaxHp(activeSession)
    table.insert(enemyList, b1)

    local pData = loader.getActor(2) or { id = "enemy_2", name = "Test Target B", level = 1 } -- High Pixie
    local b2 = session.Battler.new(pData, 1)
    b2.hp = b2:getMaxHp(activeSession)
    table.insert(enemyList, b2)
    
    activeBattle = battleSystem.Battle.new(activeSession, enemyList)
    battleCombatLog = { "--- BATTLE SCREEN TEST MODE ---", "Press SPACE or P to spawn damage popups!" }
    battleEventsQueue = {}
    battleEventQueueIndex = 1
    battleCombatState = "input"
    battleSelectedIndex = 1
    battleSpellSelect = false
    
    rebuildBattleLivingMembers()

    currentScene = "battle"
    renderer.initBattleAnims(enemyList)
end

-- Map a battler to screen coordinates on the battle scene. The layout lives
-- in the renderer (shared with drawBattle) so popups always match the drawn
-- positions.
local function getTargetCoords(target)
    return renderer.getBattlerCoords(activeBattle, activeSession, target)
end

-- Resolves combat rounds with dynamic state backup/restore for sequential action rendering
local function resolveBattleRound()
    local backups = {}
    for _, b in ipairs(activeBattle:getAllActiveBattlers()) do
        local stateCopy = {}
        for _, st in ipairs(b.states) do
            table.insert(stateCopy, { id = st.id, duration = st.duration, maxDuration = st.maxDuration })
        end
        backups[b] = {
            hp = b.hp,
            states = stateCopy
        }
    end
    local mpBackup = activeSession.mp

    local events = activeBattle:resolveRound(battleCollectedActions)

    -- Restore backup states immediately so the UI can apply changes step-by-step
    for b, bk in pairs(backups) do
        b.hp = bk.hp
        b.states = bk.states
    end
    activeSession.mp = mpBackup

    return events
end

-- Advances the combat logs queue by one event and formats it
local function advanceBattleLog()
    if battleEventQueueIndex <= #battleEventsQueue then
        local ev = battleEventsQueue[battleEventQueueIndex]
        battleEventQueueIndex = battleEventQueueIndex + 1
        
        local desc = ""
        local popupX, popupY = getTargetCoords(ev.target)
        
        if ev.type == "text" then
            desc = ev.text
        elseif ev.type == "action" then
            desc = loader.formatTerm("battle.uses_skill", "{0} uses {1} on {2}!", ev.actor.name, ev.skill.name, ev.target.name)
            if activeBattle then
                for idx, enemy in ipairs(activeBattle.enemies) do
                    if enemy == ev.actor then
                        renderer.triggerActionFlash(idx, "action")
                        break
                    end
                end
            end
        elseif ev.type == "damage" then
            desc = loader.formatTerm("battle.takes_damage", "- {0} takes {1} damage.", ev.target.name, ev.value)
            local text = getPopupFormat("damageFormat"):gsub("{0}", tostring(ev.value))
            renderer.addDamagePopup(text, popupX, popupY, getPopupFormat("damageColor"))
            -- Apply damage sequentially
            ev.target.hp = math.max(0, ev.target.hp - ev.value)
            if activeBattle then
                for idx, enemy in ipairs(activeBattle.enemies) do
                    if enemy == ev.target then
                        renderer.triggerActionFlash(idx, "damage")
                        break
                    end
                end
            end
        elseif ev.type == "heal" then
            desc = loader.formatTerm("battle.recovers_hp", "- {0} recovers {1} HP.", ev.target.name, ev.value)
            local text = getPopupFormat("healFormat"):gsub("{0}", tostring(ev.value))
            renderer.addDamagePopup(text, popupX, popupY, getPopupFormat("healColor"))
            -- Apply heal sequentially
            ev.target.hp = math.min(ev.target:getMaxHp(activeSession), ev.target.hp + ev.value)
        elseif ev.type == "death" then
            desc = loader.formatTerm("battle.has_fallen", "! {0} has fallen!", ev.target.name)
            renderer.addDamagePopup(getPopupFormat("deadFormat"), popupX, popupY, getPopupFormat("deadColor"))
            -- Apply death state sequentially
            ev.target:addState("dead")
            ev.target.hp = 0
            -- Trigger death animation if enemy
            if activeBattle then
                for idx, enemy in ipairs(activeBattle.enemies) do
                    if enemy == ev.target then
                        renderer.triggerDeathAnim(idx)
                        break
                    end
                end
            end
        elseif ev.type == "state_add" then
            desc = loader.formatTerm("battle.got_status", "- {0} got {1} status.", ev.target.name, ev.state:upper())
            local text = getPopupFormat("stateFormat"):gsub("{0}", ev.state:upper())
            renderer.addDamagePopup(text, popupX, popupY, getPopupFormat("stateColor"))
            -- Apply state add sequentially
            ev.target:addState(ev.state)
        elseif ev.type == "state_remove" then
            desc = loader.formatTerm("battle.status_wore_off", "- {0}'s {1} wore off.", ev.target.name, ev.state:upper())
            -- Apply state removal sequentially
            ev.target:removeState(ev.state)
        elseif ev.type == "mp_drain" then
            desc = loader.formatTerm("battle.consumes_mp", "- {0} consumes {1} MP.", ev.actor.name, ev.value)
            -- Apply MP drain sequentially
            activeSession.mp = math.max(0, activeSession.mp - ev.value)
        elseif ev.type == "victory" then
            desc = loader.getTerm("battle.victory_full", "Victory! All hostile forces vanquished.")
        elseif ev.type == "defeat" then
            desc = loader.getTerm("battle.defeat_full", "Defeat! The party has fallen in battle...")
        elseif ev.type == "flee_success" then
            desc = loader.getTerm("battle.flee_success", "Escaped successfully!")
            battleEscaped = true
        end
        
        if desc ~= "" then
            table.insert(battleCombatLog, desc)
        else
            advanceBattleLog() -- skip empty and try next
        end
    end
end

-- Records the chosen action for the active member; resolves the round once everyone has acted
local function commitBattleAction(memberIndex, action)
    battleCollectedActions[memberIndex] = action
    battleActiveMemberIndex = battleActiveMemberIndex + 1
    battleSelectedIndex = 1
    battleSpellSelect = false

    if battleActiveMemberIndex > #battleLivingMembers then
        battleEscaped = false
        battleEventsQueue = resolveBattleRound()
        battleEventQueueIndex = 1
        battleCombatLog = {}
        advanceBattleLog()
        battleCombatState = "log"
    end
end

-- Interrupts input to show a one-line battle message
local function showBattleMessage(text)
    battleEventsQueue = { { type = "text", text = text } }
    battleEventQueueIndex = 1
    battleCombatLog = {}
    advanceBattleLog()
    battleCombatState = "log"
end

-- Action handling for key presses
local function handleKeyPressed(key)
    if inputCooldown > 0 then return end
    if renderer.closing then return end
    if activeSceneHost then
        activeSceneHost:keypressed(key)
        return
    elseif currentScene == "crafting" then
        if keypressedCraftingScene then keypressedCraftingScene(key) end
        return
    end
    if key == "escape" then
        if currentScene == "title" then
            love.event.quit()
        elseif currentScene == "town" or currentScene == "map" then
            -- Open Main Menu instead of exiting!
            previousSceneBeforeMenu = currentScene
            menuSelectedIdx = 1
            menuSubScene = "main"
            renderer.resetMenuTimer()
            currentScene = "menu"
            return
        elseif currentScene == "menu" then
            -- Only the top-level menu is handled here; submenus each have
            -- their own escape branch below that steps back exactly one
            -- level (intercepting them here used to close the whole menu).
            if menuSubScene == "main" then
                if menuActiveCol == 2 then
                    menuActiveCol = 1
                    menuSelectedSubIdx = 1
                else
                    renderer.startClosing("menu", previousSceneBeforeMenu)
                end
                return
            end
        elseif currentScene == "dialogue" then
            currentScene = "map"
            return
        end
    end
    
    if currentScene == "title" then
        if key == "return" or key == "space" then
            -- Initialize session if not exists
            if not activeSession then
                activeSession = session.GameSession.new(loader)
                activeSession:initializeStartingParty()
            end
            exploration.loadMap(activeSession, 1) -- Load Town Map (mapIdx = 1)
            currentScene = "map"
        end
        
    elseif currentScene == "town" then
        -- Town menu entries come from system.town.options (label + action),
        -- editable from the editor's System tab.
        local townOptions = conf("town", "options", {})
        local optCount = math.max(1, #townOptions)
        if key == "up" or key == "w" then
            townSelectedIdx = (townSelectedIdx - 2) % optCount + 1
        elseif key == "down" or key == "s" then
            townSelectedIdx = townSelectedIdx % optCount + 1
        elseif key == "return" or key == "space" then
            local opt = townOptions[townSelectedIdx]
            if opt then
                if opt.action == "enter_dungeon" then
                    activeSession.dungeonFloor = 1
                    exploration.loadMap(activeSession, opt.mapId or 2)
                    currentScene = "map"
                elseif opt.action == "dialogue" then
                    triggerDialogue(opt.graph)
                elseif opt.action == "rest" then
                    recoverParty()
                    if opt.graph then triggerDialogue(opt.graph) end
                end
            end
        end
        
    elseif currentScene == "map" then
        local moved = false
        if key == "up" or key == "w" then
            moved = exploration.moveForward(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "forward"
            end
        elseif key == "down" or key == "s" then
            moved = exploration.moveBackward(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "backward"
            end
        elseif key == "left" or key == "a" then
            exploration.turnLeft(activeSession)
            activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
            activeSession.transitionDir = "turn_left"
        elseif key == "right" or key == "d" then
            exploration.turnRight(activeSession)
            activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
            activeSession.transitionDir = "turn_right"
        elseif key == "q" then
            moved = exploration.strafeLeft(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "strafe_left"
            end
        elseif key == "e" then
            moved = exploration.strafeRight(activeSession)
            if moved then
                activeSession.transitionTimer = conf("ui", "moveTransitionDuration", 0.15)
                activeSession.transitionDir = "strafe_right"
            end
        elseif key == "space" or key == "return" then
            local frontTile, tx, ty = exploration.getFrontTile(activeSession)
            
            -- Check for coordinate-based events from the map's JSON array
            local eventObj = nil
            if activeSession.currentMapData.events then
                for _, ev in ipairs(activeSession.currentMapData.events) do
                    if ev.x == tx - 1 and ev.y == ty - 1 then
                        eventObj = ev
                        break
                    end
                end
            end
            
            if eventObj and (eventObj.trigger == nil or eventObj.trigger == "interact") then
                local commands = nil
                if eventObj.scriptId then
                    local commonEvent = loader.commonEvents and loader.commonEvents[tostring(eventObj.scriptId)]
                    if commonEvent then
                        commands = commonEvent.commands
                    end
                else
                    commands = eventObj.script
                end
                
                if commands then
                    runEventCommands(eventObj.name or "Event", commands)
                end
            end
        end
        
        if moved then
            local triggered = checkStepEvents()
            if not triggered and not isSafeMap() then
                if flow.has("battle.encounter_check") then
                    for _, ev in ipairs(flow.run("battle.encounter_check", { session = activeSession })) do
                        if ev.type == "encounter" then triggerBattle() end
                    end
                else
                    -- Legacy roll (SPEC S4 fallback rule)
                    local chance = activeSession.currentMapData.encounterRate
                        or conf("combat", "encounterChance", 0.10)
                    if math.random() < chance then
                        triggerBattle()
                    end
                end
            end
        end
        
    elseif currentScene == "dialogue" then
        local node = activeWalker:getCurrentNode()
        if node then
            if node.type == "TEXT" then
                if key == "space" or key == "return" then
                    activeWalker:advance()
                    dialogueSelectIdx = 1
                    handleDialogueAction()
                    if not activeWalker:getCurrentNode() then
                        currentScene = "map"
                    end
                end
            elseif node.type == "CHOICE" then
                if key == "up" or key == "w" then
                    dialogueSelectIdx = (dialogueSelectIdx - 2) % #node.options + 1
                elseif key == "down" or key == "s" then
                    dialogueSelectIdx = dialogueSelectIdx % #node.options + 1
                elseif key == "space" or key == "return" then
                    activeWalker:selectChoice(dialogueSelectIdx)
                    dialogueSelectIdx = 1
                    handleDialogueAction()
                    if not activeWalker:getCurrentNode() then
                        currentScene = "map"
                    end
                end
            end
        end
        
    elseif currentScene == "menu" then
        if menuSubScene == "main" then
            local mainOpts = loader.getTermList("menu.main_options", { "ITEMS", "STATUS", "EQUIP", "EXIT" })
            local numOpts = #mainOpts
            if key == "up" or key == "w" then
                menuSelectedIdx = (menuSelectedIdx - 2) % numOpts + 1
            elseif key == "down" or key == "s" then
                menuSelectedIdx = menuSelectedIdx % numOpts + 1
            elseif key == "space" or key == "return" then
                local opt = mainOpts[menuSelectedIdx]
                if opt == "ITEMS" then
                    menuSubScene = "items_list"
                    menuSelectedSubIdx = 1
                elseif opt == "STATUS" or opt == "EQUIP" then
                    menuSubScene = "party_select"
                    menuSelectedSubIdx = 1
                elseif opt == "CRAFTING" then
                    setScene("crafting")
                    if initCraftingScene then initCraftingScene() end
                elseif opt == "EXIT" then
                    menuSubScene = "exit_confirm"
                    menuSelectedSubIdx = 2 -- Default to NO
                end
            end
            
        elseif menuSubScene == "party_select" then
            -- 2x2 grid navigation inputs for selecting creatures in the party
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 3) % 4 + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = (menuSelectedSubIdx + 1) % 4 + 1
            elseif key == "left" or key == "a" then
                if menuSelectedSubIdx == 2 then menuSelectedSubIdx = 1
                elseif menuSelectedSubIdx == 4 then menuSelectedSubIdx = 3
                end
            elseif key == "right" or key == "d" then
                if menuSelectedSubIdx == 1 then menuSelectedSubIdx = 2
                elseif menuSelectedSubIdx == 3 then menuSelectedSubIdx = 4
                end
            elseif key == "escape" then
                menuSubScene = "main"
                menuSelectedSubIdx = 1
            elseif key == "space" or key == "return" then
                if activeSession.party[menuSelectedSubIdx] then
                    selectedCreatureIndex = menuSelectedSubIdx
                    local mainOpts = loader.getTermList("menu.main_options", { "ITEMS", "STATUS", "EQUIP", "EXIT" })
                    local opt = mainOpts[menuSelectedIdx]
                    if opt == "STATUS" then
                        menuSubScene = "status_detail"
                        statusInspectMode = false
                        statusInspectIdx = 1
                    else
                        menuSubScene = "equip_passive"
                        menuSelectedSubIdx = 1
                    end
                end
            end
            
        elseif menuSubScene == "items_list" then
            local items = {}
            for itemId, qty in pairs(activeSession.inventory) do
                local item = loader.getItem(itemId)
                if item then table.insert(items, { item = item, qty = qty }) end
            end
            
            if key == "up" or key == "w" then
                if #items > 0 then
                    menuSelectedSubIdx = (menuSelectedSubIdx - 2) % #items + 1
                end
            elseif key == "down" or key == "s" then
                if #items > 0 then
                    menuSelectedSubIdx = menuSelectedSubIdx % #items + 1
                end
            elseif key == "escape" then
                renderer.startClosing("items_list", "menu", "main")
            elseif key == "space" or key == "return" then
                local selectedEntry = items[menuSelectedSubIdx]
                if selectedEntry then
                    local item = selectedEntry.item
                    if item.targetScope == "party" then
                        -- Instantly use on the whole party
                        for _, c in ipairs(activeSession.party) do
                            applyItemToTarget(item, c)
                        end
                        activeSession:addItem(item.id, -1)
                    else
                        selectedItemIdToUse = item.id
                        menuSubScene = "use_target"
                        menuSelectedSubIdx = 1
                    end
                end
            end
            
        elseif menuSubScene == "use_target" then
            -- 2x2 grid navigation inputs for item target selection
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 3) % 4 + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = (menuSelectedSubIdx + 1) % 4 + 1
            elseif key == "left" or key == "a" then
                if menuSelectedSubIdx == 2 then menuSelectedSubIdx = 1
                elseif menuSelectedSubIdx == 4 then menuSelectedSubIdx = 3
                end
            elseif key == "right" or key == "d" then
                if menuSelectedSubIdx == 1 then menuSelectedSubIdx = 2
                elseif menuSelectedSubIdx == 3 then menuSelectedSubIdx = 4
                end
            elseif key == "escape" then
                menuSubScene = "items_list"
                menuSelectedSubIdx = 1
                selectedItemIdToUse = nil
            elseif key == "space" or key == "return" then
                local target = activeSession.party[menuSelectedSubIdx]
                if target and selectedItemIdToUse then
                    local item = loader.getItem(selectedItemIdToUse)
                    if item then
                        applyItemToTarget(item, target)
                        activeSession:addItem(item.id, -1)
                    end
                    menuSubScene = "items_list"
                    menuSelectedSubIdx = 1
                    selectedItemIdToUse = nil
                end
            end
            
        elseif menuSubScene == "equip_passive" then
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 2) % 3 + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = menuSelectedSubIdx % 3 + 1
            elseif key == "escape" then
                renderer.startClosing("equip_passive", "menu", "party_select")
            elseif key == "space" or key == "return" then
                selectedSlotIndex = menuSelectedSubIdx
                menuSubScene = "select_passive"
                menuSelectedSubIdx = 1
            end
            
        elseif menuSubScene == "select_passive" then
            local slotType = (selectedSlotIndex == 1) and "Weapon" or (selectedSlotIndex == 2 and "Armor" or "Accessory")
            local list = {}
            table.insert(list, { id = "empty", name = "[ UNEQUIP ]", description = "Unequip current gear." })
            for itemId, qty in pairs(activeSession.inventory) do
                local item = loader.getItem(itemId)
                if item and item.type == "equipment" and item.equipType == slotType then
                    table.insert(list, item)
                end
            end
            
            if key == "up" or key == "w" then
                menuSelectedSubIdx = (menuSelectedSubIdx - 2) % #list + 1
            elseif key == "down" or key == "s" then
                menuSelectedSubIdx = menuSelectedSubIdx % #list + 1
            elseif key == "escape" then
                renderer.startClosing("select_passive", "menu", "equip_passive")
            elseif key == "space" or key == "return" then
                local choice = list[menuSelectedSubIdx]
                local targetCreature = activeSession.party[selectedCreatureIndex]
                if targetCreature and choice then
                    local prevItem = targetCreature.equipment[selectedSlotIndex]
                    if choice.id == "empty" then
                        if prevItem then
                            activeSession:addItem(prevItem.id, 1)
                        end
                        targetCreature.equipment[selectedSlotIndex] = nil
                    else
                        if prevItem then
                            activeSession:addItem(prevItem.id, 1)
                        end
                        targetCreature.equipment[selectedSlotIndex] = choice
                        activeSession:addItem(choice.id, -1)
                    end
                end
                menuSubScene = "equip_passive"
                menuSelectedSubIdx = selectedSlotIndex
            end
            
        elseif menuSubScene == "status_detail" then
            local c = activeSession.party[selectedCreatureIndex]
            local numPassives = c and #(c.actorData.passives or {}) or 0
            local numSkills = c and #(c.actorData.skills or {}) or 0
            local totalTraits = numPassives + numSkills
            
            if statusInspectMode then
                if key == "escape" or key == "space" or key == "return" then
                    statusInspectMode = false
                elseif key == "up" or key == "w" then
                    if totalTraits > 0 then
                        statusInspectIdx = (statusInspectIdx - 2) % totalTraits + 1
                    end
                elseif key == "down" or key == "s" then
                    if totalTraits > 0 then
                        statusInspectIdx = statusInspectIdx % totalTraits + 1
                    end
                end
            else
                if key == "escape" then
                    renderer.startClosing("status_detail", "menu", "party_select")
                elseif key == "space" or key == "return" or key == "tab" then
                    if totalTraits > 0 then
                        statusInspectMode = true
                        statusInspectIdx = 1
                    end
                elseif key == "left" or key == "a" or key == "up" or key == "w" then
                    local nextIdx = selectedCreatureIndex
                    repeat
                        nextIdx = (nextIdx - 2) % 4 + 1
                    until activeSession.party[nextIdx] or nextIdx == selectedCreatureIndex
                    selectedCreatureIndex = nextIdx
                elseif key == "right" or key == "d" or key == "down" or key == "s" then
                    local nextIdx = selectedCreatureIndex
                    repeat
                        nextIdx = nextIdx % 4 + 1
                    until activeSession.party[nextIdx] or nextIdx == selectedCreatureIndex
                    selectedCreatureIndex = nextIdx
                end
            end
            
        elseif menuSubScene == "exit_confirm" then
            if key == "up" or key == "w" or key == "down" or key == "s" then
                menuSelectedSubIdx = menuSelectedSubIdx == 1 and 2 or 1
            elseif key == "escape" then
                menuSubScene = "main"
                menuSelectedSubIdx = 1
            elseif key == "space" or key == "return" then
                if menuSelectedSubIdx == 1 then
                    love.event.quit()
                else
                    menuSubScene = "main"
                    menuSelectedSubIdx = 1
                end
            end
        end
        
    elseif currentScene == "battle" then
        if battleCombatState == "input" then
            local memberInfo = battleLivingMembers[battleActiveMemberIndex]
            if not memberInfo then
                battleCombatState = "log"
                return
            end
            
            local isSummoner = (memberInfo.type == "summoner")
            
            if battleSpellSelect then
                -- Get skills/spells list
                local options = {}
                if isSummoner then
                    -- summoner.spells lists skill ids; costs come from the
                    -- skill database (skills.json mpCost). Legacy {id, mp}
                    -- entries are still accepted.
                    for _, spellId in ipairs(conf("summoner", "spells", {})) do
                        if type(spellId) == "table" then spellId = spellId.id end
                        local sk = loader.getSkill(spellId)
                        if sk then table.insert(options, sk) end
                    end
                else
                    for _, skId in ipairs(memberInfo.actor.skills or {}) do
                        local sk = loader.getSkill(skId)
                        if sk then table.insert(options, sk) end
                    end
                end
                
                if key == "up" or key == "w" then
                    if #options > 0 then
                        battleSelectedIndex = (battleSelectedIndex - 2) % #options + 1
                    end
                elseif key == "down" or key == "s" then
                    if #options > 0 then
                        battleSelectedIndex = battleSelectedIndex % #options + 1
                    end
                elseif key == "escape" then
                    battleSpellSelect = false
                    battleSelectedIndex = 2 -- Back to Spell/Skill option
                elseif key == "space" or key == "return" then
                    local choice = options[battleSelectedIndex]
                    if choice then
                        local allowed = true
                        if isSummoner then
                            allowed = (activeSession.mp >= (choice.mpCost or choice.mp or 0))
                        end
                        
                        if allowed then
                            local spell = loader.getSkill(choice.id)
                            local target = activeSession.summoner
                            if spell and (spell.target == "enemy-any" or spell.target == "enemy") then
                                -- Target first living enemy
                                for _, e in ipairs(activeBattle.enemies) do
                                    if not e:isDead() then target = e break end
                                end
                            else
                                -- Heal target lowest HP ally
                                local lowestHp = 9999
                                for _, c in ipairs(activeSession.party) do
                                    if not c:isDead() and c.hp < lowestHp then
                                        lowestHp = c.hp
                                        target = c
                                    end
                                end
                            end
                            
                            commitBattleAction(memberInfo.index, {
                                type = isSummoner and "spell" or "skill",
                                id = choice.id,
                                target = target
                            })
                        else
                            showBattleMessage(loader.getTerm("battle.not_enough_mp", "Not enough MP!"))
                        end
                    end
                end
            else
                -- Main commands: Attack (1), Spell/Skill (2), Item/Defend (3), Flee (4)
                if key == "up" or key == "w" then
                    battleSelectedIndex = (battleSelectedIndex - 2) % 4 + 1
                elseif key == "down" or key == "s" then
                    battleSelectedIndex = battleSelectedIndex % 4 + 1
                elseif key == "space" or key == "return" then
                    if battleSelectedIndex == 1 then
                        -- Attack
                        local target = activeBattle.enemies[1]
                        for _, e in ipairs(activeBattle.enemies) do
                            if not e:isDead() then target = e break end
                        end
                        
                        commitBattleAction(memberInfo.index, {
                            type = "attack",
                            target = target
                        })
                    elseif battleSelectedIndex == 2 then
                        -- Spell/Skill selection submenu
                        battleSpellSelect = true
                        battleSelectedIndex = 1
                    elseif battleSelectedIndex == 3 then
                        -- Item (Summoner) or Defend (Monster)
                        if isSummoner then
                            local battleItemId = conf("combat", "battleItem", 1) -- 1 = HP Tonic
                            local battleItem = loader.getItem(battleItemId)
                            if battleItem and activeSession:hasItem(battleItemId, 1) then
                                local target = activeSession.summoner
                                local lowestHp = 9999
                                for _, c in ipairs(activeSession.party) do
                                    if not c:isDead() and c.hp < lowestHp then
                                        lowestHp = c.hp
                                        target = c
                                    end
                                end

                                commitBattleAction(memberInfo.index, {
                                    type = "item",
                                    id = battleItemId,
                                    target = target
                                })
                            else
                                showBattleMessage(loader.formatTerm("battle.no_item_left", "No {0}s left!", (battleItem and battleItem.name or battleItemId)))
                            end
                        else
                            -- Monster Defend action
                            commitBattleAction(memberInfo.index, { type = "defend" })
                        end
                    elseif battleSelectedIndex == 4 then
                        -- Flee
                        commitBattleAction(memberInfo.index, { type = "flee" })
                    end
                end
            end
            
        elseif battleCombatState == "log" then
            if key == "space" or key == "return" then
                if battleEventQueueIndex <= #battleEventsQueue then
                    advanceBattleLog()
                else
                    if activeBattle:isVictory() then
                        if flow.has("battle.victory") then
                            flow.run("battle.victory", {
                                session = activeSession,
                                battle = activeBattle,
                                party = activeSession.party,
                                enemies = activeBattle.enemies,
                            })
                        else
                            -- Legacy block: runs only when the phase is
                            -- removed from flows.json (SPEC S4 fallback rule)
                            local goldGain = math.random(conf("combat", "victoryGoldMin", 10), conf("combat", "victoryGoldMax", 30))
                            activeSession.gold = activeSession.gold + goldGain

                            -- Apply passive mending / trick heal if present on survivors
                            for _, c in ipairs(activeSession.party) do
                                if not c:isDead() then
                                    c:gainExp(conf("combat", "victoryExp", 5), activeSession)
                                    local regenVal = traits.getRate(c, "POST_BATTLE_HEAL", activeSession)
                                    if regenVal > 0 then
                                        c.hp = math.min(c:getMaxHp(activeSession), c.hp + regenVal)
                                    end
                                end
                            end
                        end

                        currentScene = "map"
                    elseif activeBattle:isDefeat() then
                        local doReset = true
                        if flow.has("battle.defeat") then
                            -- The flow only signals; the reset itself stays here
                            doReset = false
                            for _, ev in ipairs(flow.run("battle.defeat", { session = activeSession, battle = activeBattle })) do
                                if ev.type == "scene_change" and ev.kind == "defeat" then doReset = true end
                            end
                        end
                        if doReset then
                            currentScene = "title"
                            activeSession = session.GameSession.new(loader)
                            activeSession:initializeStartingParty()
                            renderer.init(activeSession)
                        end
                    else
                        -- battleEscaped is set when a flee_success event is
                        -- processed (no string comparison against log text)
                        if battleEscaped then
                            local toMap = true
                            if flow.has("battle.escaped") then
                                toMap = false
                                for _, ev in ipairs(flow.run("battle.escaped", { session = activeSession, battle = activeBattle })) do
                                    if ev.type == "scene_change" and ev.kind == "map" then toMap = true end
                                end
                            end
                            if toMap then currentScene = "map" end
                        else
                            -- Rebuild living members list for the next round
                            rebuildBattleLivingMembers()
                            battleCombatState = "input"
                            battleSelectedIndex = 1
                            battleSpellSelect = false
                        end
                    end
                end
            end
        end
    elseif currentScene == "shop" then
        if key == "up" or key == "w" then
            if #shopItems > 0 then
                shopSelectedIdx = (shopSelectedIdx - 2) % #shopItems + 1
            end
        elseif key == "down" or key == "s" then
            if #shopItems > 0 then
                shopSelectedIdx = shopSelectedIdx % #shopItems + 1
            end
        elseif key == "escape" then
            renderer.startClosing("shop", "map")
        elseif key == "space" or key == "return" then
            local selectedItem = shopItems[shopSelectedIdx]
            if selectedItem then
                if activeSession.gold >= selectedItem.cost then
                    activeSession.gold = activeSession.gold - selectedItem.cost
                    activeSession:addItem(selectedItem.id, 1)
                end
            end
        end
    end
end

function love.keypressed(key, scancode, isrepeat)
    local repeat_event = isrepeat or (type(scancode) == "boolean" and scancode)
    if repeat_event then return end
    
    -- If in test battle mode, only handle popup triggers and ignore/block other inputs
    if isTestBattle then
        if key == "space" or key == "p" then
            if activeBattle and activeSession then
                -- Collect potential targets
                local targets = {}
                for _, e in ipairs(activeBattle.enemies) do
                    table.insert(targets, e)
                end
                for _, c in ipairs(activeSession.party) do
                    table.insert(targets, c)
                end
                table.insert(targets, activeSession.summoner)
                
                if #targets > 0 then
                    local target = targets[math.random(#targets)]
                    local isHeal = math.random() < 0.25
                    local val = isHeal and math.random(5, 20) or math.random(5, 30)
                    local isCrit = not isHeal and math.random() < 0.1
                    local txt = isCrit and getPopupFormat("critFormat") or (isHeal and getPopupFormat("healFormat") or getPopupFormat("damageFormat"))
                    txt = txt:gsub("{0}", tostring(val))
                    
                    local x, y = getTargetCoords(target)
                    if x and y then
                        local col = isCrit and getPopupFormat("critColor") or (isHeal and getPopupFormat("healColor") or getPopupFormat("damageColor"))
                        renderer.addDamagePopup(txt, x, y, col)
                    end
                end
            end
        end
        return -- Block all other keys from progressing state/crashing
    end
    
    if inputCooldown > 0 then return end
    if key == "f9" then
        if server.isActive() then
            server.stop()
            print("Developer server stopped.")
        else
            server.start()
        end
        return
    end
    
    local oldScene = currentScene
    local oldSub = menuSubScene
    
    handleKeyPressed(key)
    
    local function isMajorSubSceneTransition(oldSub, newSub)
        if oldSub == newSub then return false end
        if (oldSub == "main" and newSub == "party_select") or (oldSub == "party_select" and newSub == "main") then
            return false
        end
        if (oldSub == "items_list" and newSub == "use_target") or (oldSub == "use_target" and newSub == "items_list") then
            return false
        end
        return true
    end

    if currentScene ~= oldScene or (currentScene == "menu" and isMajorSubSceneTransition(oldSub, menuSubScene)) then
        if not renderer.closing then
            renderer.resetMenuTimer()
        end
    end
end

function love.resize(w, h)
    scale = math.min(w / gameWidth, h / gameHeight)
    scale = math.max(1, math.floor(scale))
    scaleX = math.floor((w - gameWidth * scale) / 2)
    scaleY = math.floor((h - gameHeight * scale) / 2)
end
