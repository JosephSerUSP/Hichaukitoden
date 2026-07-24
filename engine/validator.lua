local validator = {}

local session = require("engine.session")
local battleSystem = require("engine.battle")
local traits = require("engine.traits")
local effects = require("engine.effects")
local interpreter = require("engine.interpreter")
local flow = require("engine.flow")
local config = require("engine.config")

validator.run = function(loader)
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
    local validFogPresets = {}
    for _, fp in ipairs((loader.engine and loader.engine.fogPresets) or {}) do
        validFogPresets[fp.id] = true
    end

    local validBlendModes = { alpha = true, add = true, multiply = true, screen = true }

    -- Shared shape check for a fog config table -- used both for a map's
    -- own `fog` (docs/design/fog-presets-and-panorama.md) and for each
    -- entry in engine.fogPresets, since a preset IS a fog config (plus id/
    -- label). `desc` is a human-readable prefix, e.g. "map 'x' fog" or
    -- "fog preset 'y'".
    local function checkFogShape(desc, fog)
        local c = fog.color
        if c ~= nil then
            local isTriple = type(c) == "table" and #c == 3
                and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
            if check(isTriple, desc .. ".color must be an {r,g,b} triple") then
                for ch = 1, 3 do
                    check(c[ch] >= 0 and c[ch] <= 1,
                        desc .. ".color channel " .. ch .. " (" .. tostring(c[ch]) .. ") is out of range 0..1")
                end
            end
        end
        check(fog.density == nil or (type(fog.density) == "number" and fog.density > 0),
            desc .. ".density (" .. tostring(fog.density) .. ") must be a number > 0")
        check(fog.minFactor == nil or (type(fog.minFactor) == "number"
                and fog.minFactor >= 0 and fog.minFactor <= 1),
            desc .. ".minFactor (" .. tostring(fog.minFactor) .. ") must be a number in 0..1")
        if fog.panorama ~= nil then
            if check(type(fog.panorama) == "table", desc .. ".panorama must be a list") then
                for pi, layer in ipairs(fog.panorama) do
                    local pdesc = desc .. ".panorama[" .. pi .. "]"
                    check(type(layer.image) == "string" and layer.image ~= "",
                        pdesc .. ".image must be a non-empty string (assets/panorama/<image>.png)")
                    check(layer.blendMode == nil or validBlendModes[layer.blendMode],
                        pdesc .. ".blendMode '" .. tostring(layer.blendMode) .. "' is not a recognized blend mode")
                    check(layer.opacity == nil or (type(layer.opacity) == "number"
                            and layer.opacity >= 0 and layer.opacity <= 1),
                        pdesc .. ".opacity (" .. tostring(layer.opacity) .. ") must be a number in 0..1")
                end
            end
        end
    end

    for _, fp in ipairs((loader.engine and loader.engine.fogPresets) or {}) do
        if check(type(fp.id) == "string" and fp.id ~= "", "a fog preset is missing its id") then
            checkFogShape("fog preset '" .. fp.id .. "'", fp)
        end
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
        if skill.actionSequence then
            check(loader.actionSequences[skill.actionSequence] ~= nil, "skill '" .. tostring(id) .. "' actionSequence references missing sequence '" .. tostring(skill.actionSequence) .. "'")
        end
        if skill.actionSequenceCommands then
            validateCommands(skill.actionSequenceCommands, "action_sequence", true, false, "skill '" .. tostring(id) .. "' custom action sequence")
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
        if item.actionSequence then
            check(loader.actionSequences[item.actionSequence] ~= nil, "item '" .. tostring(item.id) .. "' actionSequence references missing sequence '" .. tostring(item.actionSequence) .. "'")
        end
        if item.actionSequenceCommands then
            validateCommands(item.actionSequenceCommands, "action_sequence", true, false, "item '" .. tostring(item.id) .. "' custom action sequence")
        end
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
    for i, opt in ipairs((sys.town and sys.town.options) or {}) do
        check(opt.label and opt.action, "town option #" .. i .. " is missing label/action")
    end

    -- Shop stock must reference existing items. Entries must be {id, ...}
    -- objects -- generated data sometimes emits bare item-id numbers, which
    -- must FAIL with a repairable message, never crash the validator (the
    -- generator's repair loop feeds these lines back to the model).
    for shopId, shop in pairs(loader.shops or {}) do
        for si, stock in ipairs(shop.items or {}) do
            if type(stock) ~= "table" then
                check(false, "shop " .. tostring(shopId) .. " stock #" .. si ..
                    " must be an object like {\"id\": N}, got bare value '" .. tostring(stock) .. "'")
            else
                check(loader.getItem(stock.id), "shop " .. tostring(shopId) .. " stocks missing item '" .. tostring(stock.id) .. "'")
            end
        end
    end

    -- Event scriptId links must resolve to a common event, and asset
    -- references must resolve to real files -- a generated campaign that
    -- invents a sprite path should fail G1, not render a blank at runtime.
    -- Sprite keys resolve through small_battlers.resolveFile so validation
    -- matches the exact lookup drawing will use (case variants + [fps=N]
    -- token-bearing filenames). Actor portraits stay a warning: getPortrait
    -- degrades gracefully and many creatures legitimately have none.
    local sb = require("presentation.small_battlers")
    local function checkEventAssets(map, ev, whereSuffix)
        local where = "map '" .. tostring(map.title or map.id) .. "' event '" .. tostring(ev.name or "?") .. "'" .. whereSuffix
        if ev.sprite and ev.sprite ~= "" then
            check(love.filesystem.getInfo(ev.sprite) ~= nil or sb.resolveFile(ev.sprite) ~= nil,
                where .. " sprite '" .. tostring(ev.sprite) .. "' resolves to no file")
        end
    end
    for _, map in ipairs(loader.maps or {}) do
        for _, ev in ipairs(map.events or {}) do
            if ev.scriptId then
                check(loader.commonEvents and loader.commonEvents[tostring(ev.scriptId)] ~= nil,
                    "map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) ..
                    ") references missing common event '" .. tostring(ev.scriptId) .. "'")
            end
            checkEventAssets(map, ev, "")
            for pi, page in ipairs(ev.pages or {}) do
                checkEventAssets(map, page, " page " .. pi)
                if page.scriptId then
                    check(loader.commonEvents and loader.commonEvents[tostring(page.scriptId)] ~= nil,
                        "map '" .. tostring(map.name) .. "' event '" .. tostring(ev.name or "?") ..
                        "' page " .. pi .. " references missing common event '" .. tostring(page.scriptId) .. "'")
                end
            end
        end
    end
    for _, actor in ipairs(loader.actors or {}) do
        local who = "actor '" .. tostring(actor.name or actor.id) .. "'"
        if actor.smallBattler and actor.smallBattler ~= "" then
            check(sb.resolveFile(actor.smallBattler) ~= nil,
                who .. " smallBattler '" .. tostring(actor.smallBattler) .. "' resolves to no file")
        end
        if actor.spriteKey and actor.spriteKey ~= "" then
            local id = tostring(actor.spriteKey)
            local found = false
            for _, p in ipairs({
                "assets/portraits/" .. id .. ".png",
                "assets/portraits/NPC_" .. id .. ".png",
                "assets/portraits/" .. id:lower() .. ".png",
                "assets/portraits/" .. id:sub(1, 1):upper() .. id:sub(2):lower() .. ".png",
            }) do
                if love.filesystem.getInfo(p) then found = true break end
            end
            if not found then
                print("[validator] warning: " .. who .. " spriteKey '" .. id .. "' has no portrait in assets/portraits")
            end
        end
    end

    -- Quest requirement/reward items must exist
    for qId, quest in pairs(loader.quests or {}) do
        for _, req in ipairs((quest.requirements or {}).items or {}) do
            check(loader.getItem(req.id), "quest '" .. tostring(qId) .. "' requires missing item '" .. tostring(req.id) .. "'")
        end
        for _, rew in ipairs((quest.rewards or {}).items or {}) do
            check(loader.getItem(rew.id), "quest '" .. tostring(qId) .. "' rewards missing item '" .. tostring(rew.id) .. "'")
        end
        if quest.acceptHook then
            validateCommands(quest.acceptHook, "quest", true, false, "quest '" .. tostring(qId) .. "' accept hook")
        end
        if quest.completeHook then
            validateCommands(quest.completeHook, "quest", true, false, "quest '" .. tostring(qId) .. "' complete hook")
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

        -- Actions are slot-indexed 1-4 (no summoner slot; the old +1 offset
        -- and the "spell" opener died with the summoner-spell mechanic).
        local actions = {}
        for i = 1, 4 do
            if vSession.party[i] then
                actions[i] = { type = (i == 1) and "defend" or "attack", target = enemy }
            end
        end
        local events = vBattle:resolveRound(actions)
        check(#events > 0, "battle round produced no events")
    end

    -- Summoner rework: emergency wave, row defaults, REAP_FALLEN permadeath
    do
        local s = session.GameSession.new(loader)
        -- Level 3: a level-1 spirit's totalExp is 0, which would make the
        -- bank check vacuous.
        local function mk(id)
            local b = session.Battler.new(loader.getActor(id), 3)
            b.hp = b:getMaxHp(s)
            return b
        end
        s.party = { mk(2), mk(3), mk(4) }
        s.reserve = { mk(2), mk(3) }
        local wb = battleSystem.Battle.new(s, { mk(1) })
        check(s.party[1].row == "front" and s.party[3].row == "back",
            "Battle.new did not assign default rows by slot (1-2 front, 3-4 back)")

        -- Wipe the fielded party; the wave must deploy the whole reserve
        for i = 1, 3 do
            s.party[i].hp = 0
            s.party[i]:addState("dead")
        end
        local evs = {}
        check(wb:tryDeployWave(evs), "emergency wave did not deploy with reserves available")
        check(s.party[1] and not s.party[1]:isDead() and s.party[2] and not s.party[2]:isDead(),
            "emergency wave did not field the reserve spirits")
        check(next(s.reserve) == nil, "emergency wave left spirits in the reserve")
        check(#wb.fallen == 3, "emergency wave did not move the fallen party to battle.fallen")
        local waveEv = nil
        for _, ev in ipairs(evs) do if ev.type == "wave" then waveEv = ev end end
        check(waveEv ~= nil, "emergency wave emitted no wave event")
        if waveEv then
            -- pending carries what the presentation layer needs to replay
            -- the swap at log-reveal time (engine/scenes/battle.lua
            -- processEvent's "wave" handler): per slot, the incoming
            -- battler, its reserve key (to re-consume on replay), and the
            -- outgoing battler it's replacing (to shrink first).
            check(#(waveEv.pending or {}) == 2, "wave event should carry one pending entry per deployed spirit, got " .. tostring(#(waveEv.pending or {})))
            for _, p in ipairs(waveEv.pending or {}) do
                check(type(p.slot) == "number" and p.slot >= 1 and p.slot <= 4, "wave pending entry missing a valid slot")
                check(p.battler ~= nil, "wave pending entry missing the incoming battler")
                check(p.reserveKey ~= nil, "wave pending entry missing its reserveKey")
                check(p.outgoing ~= nil, "wave pending entry should carry the outgoing battler it replaced")
            end
        end

        -- REAP_FALLEN: banks wave casualties + any dead party member, emits
        -- one reap event per fallen spirit carrying {target, slot} (the
        -- presentation layer animates/captions each individually and only
        -- THEN clears party[slot], once that spirit's system.reap animation
        -- finishes — see engine/scenes/battle.lua processEvent's "reap"
        -- branch). REAP_FALLEN itself must NOT mutate party membership.
        s.party[2].hp = 0
        s.party[2]:addState("dead")
        local deadSpirit = s.party[2]
        local bankBefore = s.expBank or 0
        local okReap, reapEvs = pcall(interpreter.runImmediate,
            { { cmd = "REAP_FALLEN" } }, { session = s, battle = wb, loader = loader })
        check(okReap, "REAP_FALLEN failed: " .. tostring(reapEvs))
        local slotOfDeadSpirit = nil
        if okReap then
            check((s.expBank or 0) > bankBefore, "REAP_FALLEN banked no EXP for the fallen")
            check(#wb.fallen == 0, "REAP_FALLEN did not clear battle.fallen")
            check(s.party[2] == deadSpirit, "REAP_FALLEN must not remove party members itself -- that's deferred to animation completion")
            check(s.party[1] ~= nil, "REAP_FALLEN removed a living spirit")
            check(#reapEvs == 4, "REAP_FALLEN should emit one reap event per fallen spirit (3 wave casualties + 1), got " .. tostring(#reapEvs))
            local sawTarget = false
            for _, ev in ipairs(reapEvs) do
                check(ev.type == "reap", "REAP_FALLEN emitted a non-reap event: " .. tostring(ev.type))
                if ev.target == deadSpirit then sawTarget = true; slotOfDeadSpirit = ev.slot end
            end
            check(sawTarget, "REAP_FALLEN's reap events did not carry the fallen battler as target")
            check(slotOfDeadSpirit == 2, "REAP_FALLEN's reap event for the still-fielded spirit should carry its party slot")
        end

        -- Simulate the presentation layer's deferred removal (what
        -- animation_player.onComplete's callback does once system.reap
        -- finishes): only THEN does the spirit actually leave the party.
        if slotOfDeadSpirit then s.party[slotOfDeadSpirit] = nil end
        check(s.party[2] == nil, "deferred removal did not clear the party slot")

        -- Auto-field: reaping the whole party redeploys the reserve instead
        -- of leaving it empty. Wipe the newly-fielded party, reap (deferred
        -- removal again), then check auto-field with an empty reserve
        -- simply leaves the party empty.
        for i = 1, 4 do
            if s.party[i] then s.party[i].hp = 0; s.party[i]:addState("dead") end
        end
        check(not s:isPartyEmpty(), "sanity: party should not read empty before the reap")
        local reapEvs2 = interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, { session = s, battle = wb, loader = loader })
        for _, ev in ipairs(reapEvs2) do
            if ev.slot then s.party[ev.slot] = nil end
        end
        check(s:isPartyEmpty(), "REAP_FALLEN with no reserve should leave the party empty once removals are applied")
        check(not s:autoFieldIfEmpty(), "autoFieldIfEmpty deployed from an empty reserve")

        -- With an empty reserve the wave must refuse (defeat stands)
        check(not wb:tryDeployWave({}), "emergency wave deployed from an empty reserve")
    end

    -- newgame.rollGold randomness testing
    do
        local newgame = require("engine.newgame")
        local orig_random = math.random

        -- Test with mocked config bounds
        local mockLoader = { system = { newGame = { goldMin = 10, goldMax = 20 } } }

        -- Force minimum
        math.random = function(min, max) return min end
        local goldMin = newgame.rollGold(mockLoader)
        check(goldMin == 10, "rollGold failed: expected min 10, got " .. tostring(goldMin))

        -- Force maximum
        math.random = function(min, max) return max end
        local goldMax = newgame.rollGold(mockLoader)
        check(goldMax == 20, "rollGold failed: expected max 20, got " .. tostring(goldMax))

        -- Test fallbacks
        local fallbackLoader = {}

        math.random = function(min, max) return min end
        local fbMin = newgame.rollGold(fallbackLoader)
        check(fbMin == 25, "rollGold failed: expected fallback min 25, got " .. tostring(fbMin))

        math.random = function(min, max) return max end
        local fbMax = newgame.rollGold(fallbackLoader)
        check(fbMax == 75, "rollGold failed: expected fallback max 75, got " .. tostring(fbMax))

        -- Restore original math.random
        math.random = orig_random
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

    -- Validate skill and item animations (Task A2)
    for id, skill in pairs(loader.skills or {}) do
        if skill.animation then
            check(loader.animations and loader.animations[skill.animation] ~= nil, "skill '" .. tostring(id) .. "' references missing animation '" .. tostring(skill.animation) .. "'")
        end
    end
    for _, item in ipairs(loader.items or {}) do
        if item.animation then
            check(loader.animations and loader.animations[item.animation] ~= nil, "item '" .. tostring(item.id) .. "' references missing animation '" .. tostring(item.animation) .. "'")
        end
    end

    -- Validate skill and item targeting specs (Tasks T1 & T2).
    -- expand() ERRORS on unrecognized specs (no silent fallthrough), so the
    -- pcall here is the real gate: bad data fails G1, gameplay never sees it.
    -- Skills must always carry a target — battle calls expand(skill.target)
    -- directly, with no fallback like the item paths' `or "ally"`.
    local targeting = require("engine.targeting")
    for id, skill in pairs(loader.skills or {}) do
        check(skill.target ~= nil, "skill '" .. tostring(id) .. "' is missing a target spec")
        if skill.target then
            local ok, err = pcall(targeting.expand, skill.target)
            check(ok, "skill '" .. tostring(id) .. "' has invalid target spec '" .. tostring(skill.target) .. "'" .. (ok and "" or (": " .. tostring(err))))
        end
    end
    -- Items may omit target (the battle/field paths default to "ally").
    for _, item in ipairs(loader.items or {}) do
        if item.target then
            local ok, err = pcall(targeting.expand, item.target)
            check(ok, "item '" .. tostring(item.id) .. "' has invalid target spec '" .. tostring(item.target) .. "'" .. (ok and "" or (": " .. tostring(err))))
        end
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

    -- Mock context shared by every formula-compiling param check (the
    -- 'formula' type and E7's 'assignments' list-of-pairs type).
    local function buildFormulaMockCtx()
        return {
                        enemy = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        ally = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        target = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        a = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        b = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1 },
                        session = { gold = 100, mp = 20, maxMp = 30, floor = 3, mapSafe = false, encounterRate = 0.1, itemCount = 3, equipCount = { 1, 1, 1 } },
                        combat = { minEnemies = 1, maxEnemies = 3, victoryGoldMin = 1, victoryGoldMax = 5, victoryExp = 10, baseFleeChance = 0.5, goldLossOnFleeMin = 1, goldLossOnFleeMax = 5, mpExhaustionDamage = 5 },
                        v = { roll = 0.5, bonus = 10, state = 1, disciplineIdx = 2, crafterIdx = 1, slot = 1, i1Idx = 3, i2Idx = 1, confirmIdx = 1, i1Id = 1, i2Id = 2, rouletteStep = 0, S = 10, idx = 1, count = 3, items = { { id = 1, cost = 50, name = "Item 1" }, { id = 2, cost = 100, name = "Item 2" }, { id = 3, cost = 200, name = "Item 3" } }, selectedDisciplineIdx = 2, selectedCrafterIdx = 1, selectedIngredient1Idx = 3, selectedIngredient2Idx = 1, cursorSlot = 1, confirmOptionIdx = 1, i1_item_id = 1, i2_item_id = 2, invCount = 3, rouletteDelay = 0.05, isAnomaly = false, yieldScore = 10, yieldAnomalyScore = 15, poolSize = 3, poolTargetIdx = 1, poolCurrentIdx = 1, resultItemId = 1, resultItemName = "Mock Item", opt = 1, subIdx = 1, selectedIdx = 1, targetIdx = 1, _guard = 0, eqIdx = 1, skillIdx = 1, passiveIdx = 1, mode = 1, focus = "cmd", cmdIdx = 1, partyIdx = 1, memberIdx = 1, popupIdx = 1, seededCrafterIdx = 1, focusArea = "party", cursorIdx = 1, summonIdx = 1, summonPool = {}, popupCount = 1, popupOptions = {}, ritualMode = "summon", targetIsReserve = true, targetIndex = 1, pool = {}, poolIdx = 1, level = 1, baseLevel = 1, _stepDir = 1, mpCost = 0, expCost = 0, done = 0, titleText = "", previewText = "", costText = "", helpText = "", resultText = "", memberName = "", confirmOptions = {}, ritualPush = "", popupTargetIsReserve = true, popupTargetIndex = 1, page = 1, evoIdx = 1, evoPaths = {}, popupTimer = 0, popupText = "", _popupItemName = "", qty = 1, shopName = "" },
                        party = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, fleeBonus = 0.1 },
                        enemies = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, fleeBonus = 0.1 },
                        ingredient1 = { id = 1, name = "Mock Ingredient 1", meta = { potency = 5, tier = 1, craftElement = "fire" } },
                        ingredient2 = { id = 2, name = "Mock Ingredient 2", meta = { potency = 3, tier = 0, craftElement = "water" } },
                        alpha = 0.5,
                        S = 10
        }
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
                    local mockCtx = buildFormulaMockCtx()
                    local formulaEngine = require("engine.formula")
                    if type(val) == "string" and (val:match("^flag:") or val:match("^hasItem:")) then
                        -- Allow legacy condition strings
                    else
                        local ok, _, ferr = pcall(formulaEngine.eval, val, mockCtx)
                        check(ok and ferr == nil, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' failed to compile formula '" .. tostring(val) .. "': " .. tostring(ferr))
                    end
                elseif paramDef.type == "assignments" then
                    -- E7: list of { name, value } pairs; every value must
                    -- compile as a formula and every name be a non-empty
                    -- string. Rows are checked IN ORDER against one shared
                    -- mock context, assigning each result into mock v — the
                    -- same semantics the handler runs with, so later rows
                    -- reading earlier ones validate correctly. Any future
                    -- list-of-pairs command inherits this.
                    check(type(val) == "table", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a list of {name, value} rows")
                    if type(val) == "table" then
                        local formulaEngine = require("engine.formula")
                        local mockCtx = buildFormulaMockCtx()
                        for ai, a in ipairs(val) do
                            check(type(a) == "table" and type(a.name) == "string" and a.name ~= "",
                                ownerDesc .. " command '" .. id .. "' " .. paramDef.key .. "[" .. ai .. "] needs a non-empty string name")
                            if type(a) == "table" then
                                local ok, result, ferr = pcall(formulaEngine.eval, a.value, mockCtx)
                                check(ok and ferr == nil, ownerDesc .. " command '" .. id .. "' " .. paramDef.key .. "[" .. ai .. "] value failed to compile formula '" .. tostring(a.value) .. "': " .. tostring(ferr))
                                if type(a.name) == "string" and a.name ~= "" then
                                    -- Feed the row's result (or a neutral 1)
                                    -- forward for later rows' formulas.
                                    if ok and result ~= nil then mockCtx.v[a.name] = result
                                    else mockCtx.v[a.name] = 1 end
                                end
                            end
                        end
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
                        elseif paramDef.type == "text" then
                            check(type(val) == "string" or type(val) == "table", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a string or array")
                        elseif paramDef.type == "number" then
                            check(type(val) == "number" or type(val) == "string", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a number or expression")
                        elseif paramDef.type == "term" then
                            -- Ensure it's a string, resolution is implicit as getTerm falls back to the key, but we check type
                            check(type(val) == "string", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' expects a string term")
                        elseif paramDef.key == "windowId" and val ~= nil then
                            check(type(val) == "string" and val ~= "", ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' must be a valid window id string")
                        elseif paramDef.key == "scene" and val ~= nil then
                            -- Validate that if scene is provided, it references a valid scene ID or name
                            local foundScene = false
                            for _, s in ipairs(loader.scenes or {}) do
                                if tostring(s.id) == tostring(val) or s.name == val or s.kind == val then
                                    foundScene = true
                                    break
                                end
                            end
                            check(foundScene, ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing scene '" .. tostring(val) .. "'")
                        elseif paramDef.type == "state" then
                            check(loader.getState(val), ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing state '" .. tostring(val) .. "'")
                        elseif paramDef.type == "item" then
                            local isExpr = type(val) == "string" and (val:find("%[") or val:find("%.") or val:find("%(") or val:find("%+"))
                            check(val == "random" or isExpr or loader.getItem(val), ownerDesc .. " command '" .. id .. "' param '" .. paramDef.key .. "' references missing item '" .. tostring(val) .. "'")
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
        -- docs/design/raycaster-tileset-lighting.md: per-map ceiling flag and
        -- optional vertex-light grid. Both are additive/optional so older
        -- maps without them still validate cleanly.
        check(map.ceilingStyle == nil or map.ceilingStyle == "sky" or map.ceilingStyle == "solid",
            "map '" .. tostring(map.name) .. "' has invalid ceilingStyle '" .. tostring(map.ceilingStyle)
            .. "' (expected 'sky' or 'solid')")
        if map.tileset then
            local tsDef = loader.getTileset(map.tileset)
            check(tsDef ~= nil,
                "map '" .. tostring(map.name) .. "' references unknown tileset '" .. tostring(map.tileset) .. "'")
            if tsDef then
                local tsPath = tsDef.texture or ("assets/tilesets/" .. tostring(map.tileset) .. ".png")
                check(love.filesystem.getInfo(tsPath) ~= nil,
                    "map '" .. tostring(map.name) .. "' tileset '" .. tostring(map.tileset) .. "' texture missing (" .. tsPath .. ")")
            end
        end
        if map.light and map.layout then
            local expectH = #map.layout + 1
            local expectW = #map.layout[1] + 1
            check(#map.light == expectH,
                "map '" .. tostring(map.name) .. "' light grid has " .. #map.light
                .. " rows, expected " .. expectH .. " (layout height + 1)")
            for ri, row in ipairs(map.light) do
                check(#row == expectW,
                    "map '" .. tostring(map.name) .. "' light grid row " .. ri .. " has " .. #row
                    .. " values, expected " .. expectW .. " (layout width + 1)")
                for ci, cell in ipairs(row) do
                    local isTriple = type(cell) == "table" and #cell == 3
                        and type(cell[1]) == "number" and type(cell[2]) == "number" and type(cell[3]) == "number"
                    if check(isTriple,
                        "map '" .. tostring(map.name) .. "' light grid [" .. ri .. "][" .. ci
                        .. "] must be an {r,g,b} triple") then
                        for ch = 1, 3 do
                            check(cell[ch] >= 0 and cell[ch] <= 1,
                                "map '" .. tostring(map.name) .. "' light grid [" .. ri .. "][" .. ci
                                .. "] channel " .. ch .. " (" .. tostring(cell[ch]) .. ") is out of range 0..1")
                        end
                    end
                end
            end
        end

        -- Lighting-only objects are authored independently of gameplay
        -- events.  Fixed maps may bake them into `light`; procedural maps
        -- use the same schema at generation/load time.
        for li, source in ipairs(map.lightObjects or {}) do
            local desc = "map '" .. tostring(map.name) .. "' light object " .. li
            check(type(source.x) == "number" and type(source.y) == "number", desc .. " needs numeric x/y")
            check(type(source.radius) == "number" and source.radius > 0, desc .. " needs radius > 0")
            check(type(source.color) == "table" and #source.color == 3, desc .. " needs an RGB color")
            if source.color then
                for ci, ch in ipairs(source.color) do
                    check(type(ch) == "number" and ch >= 0 and ch <= 1, desc .. " color channel " .. ci .. " is out of range")
                end
            end
        end
        if map.materials and map.layout then
            check(#map.materials == #map.layout, "map '" .. tostring(map.name) .. "' materials height must match layout")
            for ri, row in ipairs(map.materials) do
                check(type(row) == "table" and #row == #map.layout[1], "map '" .. tostring(map.name) .. "' materials row " .. ri .. " must match layout width")
            end
        end

        -- Optional per-map fog: either { preset = "id" } referencing
        -- engine.fogPresets, or an inline config (docs/design/
        -- fog-presets-and-panorama.md). The renderer treats absent fog as
        -- black fog (plain distance darkening), so only a PRESENT fog
        -- table is checked.
        if map.fog ~= nil then
            local fogDesc = "map '" .. tostring(map.name) .. "' fog"
            if check(type(map.fog) == "table", fogDesc .. " must be a table") then
                if map.fog.preset ~= nil then
                    check(validFogPresets[map.fog.preset],
                        fogDesc .. " references unknown preset '" .. tostring(map.fog.preset) .. "'")
                else
                    checkFogShape(fogDesc, map.fog)
                end
            end
        end

        for i, ev in ipairs(map.events or {}) do
            local desc = "map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) .. ")"
            -- A door renders into the wall slice it occupies, so it only
            -- makes sense sitting on a wall cell of a fixed (non-procedural)
            -- layout; procedural dungeons regenerate their grid at runtime
            -- so authored door positions can't be checked against it here.
            if ev.door and map.layout then
                local row = map.layout[ev.y + 1]
                local cell = row and row:sub(ev.x + 1, ev.x + 1)
                check(cell == "#", desc .. " is a door but its map cell is not a wall ('" .. tostring(cell) .. "')")
            end
            if ev.commands then
                validateCommands(ev.commands, "map", false, true, desc)
            end
            if ev.script then
                validateCommands(ev.script, "map", false, true, desc)
            end
            -- Event pages carry their own script overrides; each is a full
            -- command tree and validates exactly like the base script.
            for pi, page in ipairs(ev.pages or {}) do
                if page.script then
                    validateCommands(page.script, "map", false, true, desc .. " page " .. pi)
                end
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

    -- Validate action sequences
    check(loader.actionSequences ~= nil, "Missing actionSequences.json")
    if loader.actionSequences then
        check(loader.actionSequences["default"] ~= nil, "actionSequences.json must define a 'default' sequence")
        check(loader.actionSequences["default_item"] ~= nil, "actionSequences.json must define a 'default_item' sequence")
        for seqId, seq in pairs(loader.actionSequences) do
            check(type(seq) == "table", "action sequence '" .. tostring(seqId) .. "' must be an object")
            if type(seq) == "table" then
                check(type(seq.name) == "string", "action sequence '" .. tostring(seqId) .. "' must have a string name")
                check(type(seq.commands) == "table", "action sequence '" .. tostring(seqId) .. "' must have a commands array")
                if type(seq.commands) == "table" then
                    validateCommands(seq.commands, "action_sequence", true, false, "action sequence '" .. tostring(seqId) .. "'")
                end
            end
        end
    end

    -- Validate quest flows
    check(loader.flows and loader.flows.quest ~= nil, "flows.json must define a 'quest' host")
    if loader.flows and loader.flows.quest then
        check(loader.flows.quest.offer ~= nil, "flows.json must define a 'quest.offer' flow")
        check(loader.flows.quest.complete ~= nil, "flows.json must define a 'quest.complete' flow")
    end
    for phaseName, cmds in pairs((loader.flows or {}).quest or {}) do
        if type(cmds) == "table" then
            validateCommands(cmds, "quest", true, false, "flows.json quest." .. phaseName)
        end
    end



    -- Test flow.run execution: simple mock of context and interpreter commands
    do
        local origRunImmediate = interpreter.runImmediate
        local mockRunCalled = false
        local mockPassedCommands = nil
        local mockPassedCtx = nil
        interpreter.runImmediate = function(commands, ctx)
            mockRunCalled = true
            mockPassedCommands = commands
            mockPassedCtx = ctx
            return { { type = "mock_flow_event" } }
        end

        local mockLoader = {
            flows = {
                _test = {
                    mock_phase = { { cmd = "MOCK_CMD" } }
                }
            }
        }
        local mockCtx = { loader = mockLoader }

        -- Valid phase
        local evs = flow.run("_test.mock_phase", mockCtx)
        check(mockRunCalled, "flow.run did not call interpreter.runImmediate")
        check(mockPassedCommands and mockPassedCommands[1] and mockPassedCommands[1].cmd == "MOCK_CMD", "flow.run passed incorrect commands to interpreter")
        check(mockPassedCtx == mockCtx, "flow.run passed incorrect context to interpreter")
        check(evs and evs[1] and evs[1].type == "mock_flow_event", "flow.run did not return events from interpreter")

        -- Invalid phase
        mockRunCalled = false
        local emptyEvs = flow.run("_test.missing_phase", mockCtx)
        check(not mockRunCalled, "flow.run called interpreter for missing phase")
        check(type(emptyEvs) == "table" and #emptyEvs == 0, "flow.run did not return empty table for missing phase")

        interpreter.runImmediate = origRunImmediate
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



    -- Flows are the single source of truth for battle outcomes: the phases
    -- the hosts call unconditionally must exist and execute cleanly against
    -- a fresh session (behavioral regressions are covered by the golden
    -- battle log, tools/golden/check).
    for _, phase in ipairs({ "battle.victory", "battle.defeat", "battle.escaped", "battle.encounter_check" }) do
        check(flow.has(phase), "flows.json is missing required phase '" .. phase .. "'")
        if flow.has(phase) then
            local s = session.GameSession.new(loader)
            s:initializeStartingParty()
            for _, c in ipairs(s.party) do c.hp = math.max(1, math.floor(c:getMaxHp(s) / 2)) end
            local okPhase, phaseErr = pcall(flow.run, phase, { session = s, party = s.party, enemies = {} })
            check(okPhase, phase .. " flow failed to execute: " .. tostring(phaseErr))
        end
    end

    -- Item effects go through the same pipeline in and out of battle
    local item = loader.getItem(combat.battleItem or 1)
    if item and vSession.party[1] then
        for _, eff in ipairs(item.effects or {}) do
            effects.apply(eff, vSession.party[1], vSession.party[1], vSession)
        end
    end

    -- Traits evaluateCondition validation
    local function validateTraitsCondition()
        local battler = session.Battler.new(loader.getActor(1), 1)
        local maxHp = traits.getParam(battler, "maxHp", vSession)

        check(traits.evaluateCondition(nil, battler, vSession) == true, "nil condition must evaluate to true")
        check(traits.evaluateCondition("invalid", battler, vSession) == false, "invalid condition must evaluate to false")

        -- HP conditions
        battler.hp = 0 -- 0% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == true, "0% HP is < 50%")
        check(traits.evaluateCondition("HP<50%", battler, vSession) == true, "0% HP is < 50% without spaces")

        battler.hp = maxHp -- 100% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == false, "100% HP is not < 50%")

        battler.hp = math.ceil(maxHp * 0.5) -- >= 50% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == false, ">= 50% HP is not < 50%")

        battler.hp = math.floor(maxHp * 0.4) -- < 50% HP
        check(traits.evaluateCondition("HP < 50%", battler, vSession) == true, "< 50% HP is < 50%")
    end
    validateTraitsCondition()

    -- Scenes validation (C9)
    local function validateScenes()
        local formulaEngine = require("engine.formula")
        local mockItem1 = loader.getItem(1)
        local mockItem2 = loader.getItem(2)
        local mockCrafter = session.Battler.new(loader.getActor(1), 1)
        
        local mockCtx = {
            i1 = formulaEngine.itemView(mockItem1),
            i2 = formulaEngine.itemView(mockItem2),
            ingredient1 = formulaEngine.itemView(mockItem1),
            ingredient2 = formulaEngine.itemView(mockItem2),
            crafter = mockCrafter,
            alpha = 0.5,
            S = 10,
            v = {
                -- Crafting variables
                state = 1, disciplineIdx = 1, crafterIdx = 1, slot = 1,
                i1Idx = 1, i2Idx = 1, confirmIdx = 1, i1Id = 0, i2Id = 0,
                rouletteStep = 0, selectedDisciplineIdx = 1,
                selectedCrafterIdx = 1, selectedIngredient1Idx = 1,
                selectedIngredient2Idx = 1, cursorSlot = 1,
                confirmOptionIdx = 1, i1_item_id = 0, i2_item_id = 0,
                invCount = 0, rouletteDelay = 0, isAnomaly = false,
                yieldScore = 0, yieldAnomalyScore = 0, poolSize = 0,
                poolTargetIdx = 0, poolCurrentIdx = 0, resultItemId = 0,
                resultItemName = "",
                -- Common menu variables (D6 scenes)
                opt = 1, subIdx = 1, idx = 1, count = 1,
                selectedIdx = 1, _guard = 0, eqIdx = 1,
                -- Map scene's cursor/overlay state
                mode = 1, focus = "cmd", cmdIdx = 1, partyIdx = 1,
                memberIdx = 1, popupIdx = 1, confirmIdx = 1,
                seededCrafterIdx = 1,
                -- Reserve scene variables
                focusArea = "party", cursorIdx = 1, summonIdx = 1,
                summonPool = {}, popupTimer = 0, popupText = "",
                _popupItemName = "", qty = 1, shopName = "",
                items = { { id = 1, cost = 50, name = "Item 1" } }
            }
        }
        
        for _, scene in ipairs(loader.scenes or {}) do
            local sceneDesc = "scene '" .. tostring(scene.id) .. "' (" .. tostring(scene.name) .. ")"
            
            -- Generic config validation (D13): no scene-kind-specific checks.
            -- Any config key ending in "Formula" whose value is a string must
            -- compile against the mock scene context.
            for key, val in pairs(scene.config or {}) do
                if type(val) == "string" and key:match("Formula$") then
                    local ok, _, ferr = pcall(formulaEngine.eval, val, mockCtx)
                    check(ok and ferr == nil, sceneDesc .. " config." .. key .. " failed to compile: " .. tostring(ferr or ""))
                end
            end

            -- Scene-local named scripts (SCRIPT ref targets) must be strings
            -- with valid Lua syntax.
            for name, code in pairs(scene.scripts or {}) do
                check(type(code) == "string", sceneDesc .. " scripts." .. tostring(name) .. " must be a string")
                if type(code) == "string" then
                    local chunk, serr = load(code, "scene-script", "t", {})
                    check(chunk ~= nil, sceneDesc .. " scripts." .. tostring(name) .. " syntax error: " .. tostring(serr))
                end
            end

            -- Hook validation (all scene kinds).
            -- Zero-SCRIPT (S6) applies to built-in scenes only; extra
            -- (user-authored) scenes may use SCRIPT as their escape hatch
            -- (owner feedback 09.07.2026, FEEDBACK.md).
            local builtinSceneIds = {
                title = true, menu = true, items = true,
                status = true, shop = true,
            }
            local allowSceneScript = not builtinSceneIds[scene.id]
            -- SCRIPT commands may reference a scene-local named script via
            -- `ref` instead of inline `code`; every ref must resolve.
            local function checkScriptRefs(cmds, where)
                for _, cmd in ipairs(cmds or {}) do
                    if type(cmd) == "table" then
                        local id = cmd.cmd or cmd.type
                        if id == "SCRIPT" then
                            check(cmd.code ~= nil or cmd.ref ~= nil, where .. " SCRIPT has neither code nor ref")
                            if cmd.ref ~= nil then
                                check((scene.scripts or {})[cmd.ref] ~= nil, where .. " SCRIPT ref '" .. tostring(cmd.ref) .. "' not found in scene scripts")
                            end
                        end
                        for _, k in ipairs({ "then", "else", "commands" }) do
                            if type(cmd[k]) == "table" then checkScriptRefs(cmd[k], where) end
                        end
                    end
                end
            end
            if scene.hooks then
                for hookName, cmds in pairs(scene.hooks) do
                    validateCommands(cmds, "scene", true, allowSceneScript, sceneDesc .. " hook '" .. tostring(hookName) .. "'")
                    checkScriptRefs(cmds, sceneDesc .. " hook '" .. tostring(hookName) .. "'")
                end
            end

            -- S1w: validate data-authored windows array (if present).
            if scene.windows and type(scene.windows) == "table" and #scene.windows > 0 then
                local seenIds = {}
                for wi, winDef in ipairs(scene.windows) do
                    -- id required and unique per scene.
                    check(type(winDef.id) == "string" and winDef.id ~= "",
                        sceneDesc .. " windows[" .. wi .. "]: missing or non-string 'id'")
                    check(seenIds[winDef.id] == nil,
                        sceneDesc .. " windows[" .. wi .. "]: duplicate window id '" .. tostring(winDef.id) .. "'")
                    seenIds[winDef.id] = true

                    -- rect must be present with x,y,w,h (values may be exprs) —
                    -- UNLESS this window id has an engine.json windowLayout
                    -- entry to fall back on. A scene omitting rect entirely
                    -- means "use windowLayout's geometry as-is", which keeps
                    -- that geometry editable via the Windows-tab drag-resize
                    -- tool (it only ever writes to windowLayout — an inline
                    -- scene rect would otherwise always shadow it at render
                    -- time, silently making the tool's edits inert).
                    local hasLayoutFallback = (loader.engine and loader.engine.windowLayout
                        and loader.engine.windowLayout[winDef.id]) ~= nil
                    if winDef.rect == nil then
                        check(hasLayoutFallback,
                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': missing 'rect' (and no engine.json windowLayout entry to fall back on)")
                    else
                        check(type(winDef.rect) == "table",
                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': 'rect' must be a table")
                        if type(winDef.rect) == "table" then
                            for _, dim in ipairs({ "x", "y", "w", "h" }) do
                                check(winDef.rect[dim] ~= nil,
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': rect missing '" .. dim .. "'")
                            end
                        end
                    end

                    -- visible (optional) must be a string expression.
                    if winDef.visible ~= nil then
                        check(type(winDef.visible) == "string",
                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': 'visible' must be a string expression")
                    end

                    -- content must be an array of typed blocks.
                    check(type(winDef.content) == "table",
                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "': missing 'content' array")
                    if type(winDef.content) == "table" then
                        for bi, block in ipairs(winDef.content) do
                            check(type(block) == "table" and type(block.type) == "string",
                                sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "]: missing or non-string 'type'")

                            local bt = block.type
                            if bt == "text" then
                                -- text block: a literal or {expr} template. The window
                                -- renderer never term-resolves text content (only "term:"
                                -- LIST sources go through loader.getTermList), so there is
                                -- nothing further to validate here beyond the string type.
                                check(type(block.text) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] text block: missing or non-string 'text'")
                            elseif bt == "list" then
                                check(type(block.listId) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: missing or non-string 'listId'")
                                -- format and cursor (optional) must be strings.
                                if block.format ~= nil then
                                    check(type(block.format) == "string",
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: 'format' must be a string")
                                end
                                if block.cursor ~= nil then
                                    check(type(block.cursor) == "string",
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: 'cursor' must be a string expression")
                                end
                                -- Verify known list sources resolve syntactically.
                                local src = block.listId or ""
                                local knownSources = { inventory = true, party = true, reserve = true,
                                    equipSlots = true, equipment = true, memberSkills = true, memberPassives = true }
                                if not knownSources[src] and not src:find("^config:") and not src:find("^v:")
                                    and not src:find("^static:") and not src:find("^term:") then
                                    print("[validator] warning: " .. sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] unknown list source '" .. src .. "'")
                                end
                                -- "term:" sources must resolve to a real terms.json list —
                                -- a typo'd path would otherwise render an empty list with no
                                -- error anywhere (S1w: term-key refs resolve or G1 fails).
                                if src:find("^term:") then
                                    local termPath = src:sub(6)
                                    local resolved = loader.getTermList(termPath, nil)
                                    check(type(resolved) == "table" and #resolved > 0,
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list source '" .. src .. "' does not resolve to a non-empty list in terms.json")
                                end
                                -- Row-scoped gauge cost/gain preview (Summoner rework):
                                -- same shared widget as the standalone gauge block, optional
                                -- but must compile when present.
                                for _, previewKey in ipairs({ "gaugePreviewCost", "gaugePreviewGain" }) do
                                    if block[previewKey] ~= nil then
                                        check(type(block[previewKey]) == "string",
                                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list '" .. previewKey .. "' must be a string expression")
                                        if type(block[previewKey]) == "string" then
                                            local ok, _, ferr = pcall(formulaEngine.eval, block[previewKey], mockCtx)
                                            check(ok and ferr == nil, sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list '" .. previewKey .. "' failed to compile: " .. tostring(ferr or ""))
                                        end
                                    end
                                end
                            elseif bt == "gauge" then
                                -- gauge block: value and max are required exprs.
                                check(type(block.value) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge block: missing or non-string 'value'")
                                check(type(block.max) == "string",
                                    sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge block: missing or non-string 'max'")
                                -- Optionally verify formulas compile.
                                if type(block.value) == "string" then
                                    local ok, _, ferr = pcall(formulaEngine.eval, block.value, mockCtx)
                                    check(ok and ferr == nil, sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge 'value' failed to compile: " .. tostring(ferr or ""))
                                end
                                if type(block.max) == "string" then
                                    local ok, _, ferr = pcall(formulaEngine.eval, block.max, mockCtx)
                                    check(ok and ferr == nil, sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge 'max' failed to compile: " .. tostring(ferr or ""))
                                end
                                -- Cost/gain preview (Summoner rework): optional, but must
                                -- compile as a formula when present. Shared by every gauge
                                -- (MP, EXP, gold, ritual/shop) — one widget, one check.
                                for _, previewKey in ipairs({ "previewCost", "previewGain" }) do
                                    if block[previewKey] ~= nil then
                                        check(type(block[previewKey]) == "string",
                                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge '" .. previewKey .. "' must be a string expression")
                                        if type(block[previewKey]) == "string" then
                                            local ok, _, ferr = pcall(formulaEngine.eval, block[previewKey], mockCtx)
                                            check(ok and ferr == nil, sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] gauge '" .. previewKey .. "' failed to compile: " .. tostring(ferr or ""))
                                        end
                                    end
                                end
                            elseif bt == "image" then
                                -- image block (v1): portraitField expr or path expr.
                                if block.portraitField ~= nil then
                                    check(type(block.portraitField) == "string",
                                        sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] image block: 'portraitField' must be a string expression")
                                end
                            else
                                -- Unknown block types: warn but don't fail (extensibility rule).
                                print("[validator] warning: " .. sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] unknown block type '" .. tostring(bt) .. "' — ignored at runtime")
                            end
                        end
                    end
                end
            end
        end
    end
    validateScenes()

    -- overhaul-7 A1: validate animation system reserved IDs
    local animation_player = require("presentation.animation_player")
    local RESERVED_SYSTEM_IDS = {
        "system.damage_flash",
        "system.damage_shake",
        "system.death",
        "system.small_damage",
        "system.enemy_slide_in",
        "system.heal",
        "system.reap",
        "system.wave",
        "system.swap_out",
        "system.swap_in",
    }
    for _, reservedId in ipairs(RESERVED_SYSTEM_IDS) do
        check(animation_player.getEntry(reservedId) ~= nil,
            "animation system: missing reserved entry '" .. reservedId .. "' in data/animations.json")
    end
    -- Check that all system-class entries have valid track structures
    -- (at minimum: each track has a known type and numeric duration)
    -- Must mirror what presentation/animation_player.lua actually implements:
    -- a system entry using an unimplemented type would silently no-op, which
    -- is exactly what this hard check exists to prevent. (text_flow was
    -- listed here without any player implementation — a leftover from the
    -- dropped healing_sparkle port; force_field was implemented but missing.)
    -- Assignable entries stay soft-validated on purpose: unknown track types
    -- fail soft at runtime so future types can ship in data first.
    local VALID_TRACK_TYPES = {
        tint = true, blend = true, transform = true,
        shake = true, particles = true, force_field = true,
        gradient_map = true, screen_flash = true,
    }
    for id, entry in pairs(loader.animations or {}) do
        if entry.class == "system" then
            check(type(entry.tracks) == "table",
                "animation system: entry '" .. tostring(id) .. "' missing tracks array")
            for ti, track in ipairs(entry.tracks or {}) do
                check(type(track) == "table",
                    "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " is not a table")
                if type(track) == "table" then
                    check(VALID_TRACK_TYPES[track.type],
                        "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " has unknown type '" .. tostring(track.type) .. "'")
                    check(type(track.duration) == "number",
                        "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " missing numeric duration")
                end
            end
        end
    end

    print("[validator] total SCRIPT usages: " .. scriptUsageCount)
    print("[validator] total deprecated usages: " .. deprecatedUsageCount)

    if #problems > 0 then
        error(table.concat(problems, "\n"), 0)
    end
end

return validator
