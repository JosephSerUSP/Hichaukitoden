local validator = {}

local session = require("engine.session")
local battleSystem = require("engine.battle")
local traits = require("engine.traits")
local effects = require("engine.effects")
local interpreter = require("engine.interpreter")
local flow = require("engine.flow")
local config = require("engine.config")
local itemModelView = require("presentation.item_model_view")

validator.run = function(loader)
    local problems = {}
    local function check(cond, msg)
        if not cond then table.insert(problems, msg) end
        return cond
    end

    -- The params a battler's paramPlus table carries (engine/session.lua
    -- Battler.new) — the set `param_plus` effects may target.
    local VALID_PARAM_PLUS = { maxHp = true, atk = true, def = true, mat = true, mdf = true }

    -- The params anything ever READS back off a battler (the traits.getParam
    -- call sites across engine/ and presentation/) — the set PARAM_PLUS and
    -- PARAM_RATE traits may name in dataId. traits.getParam matches
    -- `t.dataId == paramName` literally, so a param nobody reads is a trait
    -- that silently never applies.
    local VALID_TRAIT_PARAM = { maxHp = true, atk = true, def = true, mat = true,
        mdf = true, mpd = true, asp = true }

    -- Registry lookup sets from data/engine.json
    local validEffectTypes = {}
    for _, et in ipairs((loader.engine and loader.engine.effectTypes) or {}) do
        validEffectTypes[et.id] = true
    end
    local validTraitCodes = {}
    local traitCodeDefs = {}
    for _, tc in ipairs((loader.engine and loader.engine.traitCodes) or {}) do
        validTraitCodes[tc.code] = true
        traitCodeDefs[tc.code] = tc
    end
    -- Every registered trait/effect must carry the compact display vocabulary
    -- the item panes read (presentation/item_presentation.lua). Without it a
    -- new trait silently falls back to its editor label, which is the sentence
    -- form that wrapped to three lines in the info pane -- exactly the drift
    -- this registry exists to prevent.
    local VALID_VALUE_FORMATS = { signed = true, percent = true, percentSigned = true,
        multiplier = true, multiplierSigned = true, subject = true, none = true }
    local VALID_POLARITY = { higher = true, lower = true, none = true }
    local VALID_SUBJECT = { param = true, state = true, stateCategory = true,
        element = true, skill = true, actor = true }

    local function checkDisplay(desc, def, requireValue)
        local d = def.display
        if not check(type(d) == "table", desc .. " has no display block") then return end
        check(type(d.short) == "string" and d.short ~= "",
            desc .. ".display.short must be a non-empty string")
        check(VALID_POLARITY[d.polarity],
            desc .. ".display.polarity '" .. tostring(d.polarity) .. "' is not higher/lower/none")
        if requireValue or d.value ~= nil then
            check(VALID_VALUE_FORMATS[d.value],
                desc .. ".display.value '" .. tostring(d.value) .. "' is not a known format")
        end
        if d.subject ~= nil then
            check(VALID_SUBJECT[d.subject],
                desc .. ".display.subject '" .. tostring(d.subject) .. "' is not a known subject kind")
        end
        -- A {d} slot with nothing to fill it prints a half-sentence.
        if d.short and d.short:find("{d}", 1, true) then
            check(d.subject ~= nil, desc .. ".display.short uses {d} but declares no subject")
        end
        check(d.icon == nil or (type(d.icon) == "number" and d.icon > 0),
            desc .. ".display.icon must be a positive iconset index")
    end

    for _, et in ipairs((loader.engine and loader.engine.effectTypes) or {}) do
        checkDisplay("effectType '" .. tostring(et.id) .. "'", et, false)
        if et.display and et.display.subjectParam then
            local named = false
            for _, key in ipairs(et.params or {}) do
                if key == et.display.subjectParam then named = true end
            end
            check(named, "effectType '" .. tostring(et.id) .. "'.display.subjectParam '"
                .. tostring(et.display.subjectParam) .. "' is not one of its params")
        end
    end
    for _, tc in ipairs((loader.engine and loader.engine.traitCodes) or {}) do
        checkDisplay("traitCode '" .. tostring(tc.code) .. "'", tc, true)
        -- A trait whose value column IS its dataId must actually have one.
        if tc.display and (tc.display.value == "subject" or (tc.display.short or ""):find("{d}", 1, true)) then
            check(tc.usesDataId == true, "traitCode '" .. tostring(tc.code)
                .. "' displays a subject but usesDataId is not true")
        end
    end

    local validFoodTags = {}
    for _, tag in ipairs((loader.engine and loader.engine.foodTags) or {}) do
        validFoodTags[tag.tag] = true
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
        check(fog.psxBands == nil or (type(fog.psxBands) == "number"
                and fog.psxBands >= 2 and fog.psxBands == math.floor(fog.psxBands)),
            desc .. ".psxBands (" .. tostring(fog.psxBands) .. ") must be an integer >= 2")
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

    -- Command contexts (engine.json `commandContexts`). A context is where a
    -- command can be authored, and the set is closed: the validator checks
    -- against it and the editor builds its command pickers from it, so a
    -- command naming a context nobody honours is a command nobody can author.
    --
    -- This check exists because two of them already were. TRANSFORM_ACTOR
    -- declared `event` and `flow`, and TICK_SAVOR declared `flow` -- labels no
    -- host context ever matches, which quietly made TRANSFORM_ACTOR scene-only.
    -- Nothing failed; the command was simply missing from every map and common
    -- event picker, and there was no way to notice except by looking for it.
    local knownContexts = {}
    local contextNames = {}
    for _, c in ipairs((loader.engine and loader.engine.commandContexts) or {}) do
        check(c.id ~= nil and c.id ~= "", "engine.json commandContexts entry needs an id")
        check(c.label ~= nil and c.label ~= "",
            "engine.json commandContexts '" .. tostring(c.id) .. "' needs a label")
        check(c.authoredIn ~= nil and c.authoredIn ~= "",
            "engine.json commandContexts '" .. tostring(c.id) .. "' must say where it is "
            .. "authored; a context with no editor surface is a command nobody can write")
        if c.id then
            knownContexts[c.id] = true
            table.insert(contextNames, c.id)
        end
    end
    table.sort(contextNames)
    check(#contextNames > 0, "engine.json declares no commandContexts")
    local contextList = table.concat(contextNames, ", ")
    local contextUsed = {}
    for _, cmd in ipairs((loader.engine and loader.engine.commands) or {}) do
        for _, ctxName in ipairs(cmd.contexts or {}) do
            check(knownContexts[ctxName],
                "command '" .. tostring(cmd.id) .. "' declares context '" .. tostring(ctxName)
                .. "', which is not a registered command context (" .. contextList .. ")"
                .. " -- nothing will ever author it there")
            contextUsed[ctxName] = true
        end
    end
    for _, ctxName in ipairs(contextNames) do
        check(ctxName == "any" or contextUsed[ctxName],
            "command context '" .. ctxName .. "' is registered but no command declares it")
    end

    -- Troops (data/troops.json). A troop that builds no enemies is a battle
    -- against nothing, and a slot naming a missing actor is a fight that
    -- crashes when it starts -- neither shows up until someone walks into it.
    local baseTroop = loader.troops and loader.troops[require("engine.troop").BASE_ID]
    check(baseTroop ~= nil,
        "data/troops.json has no 'base' troop; every troop inherits it")
    check(baseTroop == nil or baseTroop.abstract == true,
        "the 'base' troop must be abstract -- it exists to be inherited, not fought")
    for tid, t in pairs(loader.troops or {}) do
        local twhere = "troop '" .. tostring(tid) .. "'"
        check(t.id == nil or t.id == tid,
            twhere .. " has id '" .. tostring(t.id) .. "', which does not match its key")
        check(t.abstract == true or #(t.members or {}) > 0,
            twhere .. " has no members, so fighting it is a battle against nothing"
            .. " (mark it abstract if it exists only to be inherited)")
        for si, slot in ipairs(t.members or {}) do
            local swhere = twhere .. " members[" .. si .. "]"
            -- Exactly one of: a named actor, a pool written here, or a pool
            -- taken from somewhere else (`poolFrom`). Two of them, or none, is
            -- a slot that cannot be read.
            local kinds = 0
            if slot.actor ~= nil then kinds = kinds + 1 end
            if slot.pool ~= nil then kinds = kinds + 1 end
            if slot.poolFrom ~= nil then kinds = kinds + 1 end
            check(kinds == 1,
                swhere .. " must be exactly one of: a named actor, a `pool`, or a"
                .. " `poolFrom` source")
            check(slot.poolFrom == nil or slot.poolFrom == "map",
                swhere .. " poolFrom '" .. tostring(slot.poolFrom)
                .. "' is not a pool source; only 'map' (the current map's"
                .. " encounter table) exists")
            if slot.actor ~= nil then
                check(loader.getActor(slot.actor) ~= nil,
                    swhere .. " names missing actor '" .. tostring(slot.actor) .. "'")
            end
            for pi, entry in ipairs(slot.pool or {}) do
                local pwhere = swhere .. " pool[" .. pi .. "]"
                check(loader.getActor(entry.actor) ~= nil,
                    pwhere .. " names missing actor '" .. tostring(entry.actor) .. "'")
                check(entry.weight == nil or (type(entry.weight) == "number" and entry.weight > 0),
                    pwhere .. " weight must be a positive number")
                check(entry.levelMax == nil or entry.levelMin ~= nil,
                    pwhere .. " levelMax requires levelMin")
                check(entry.levelMin == nil or entry.levelMax == nil
                        or entry.levelMax >= entry.levelMin,
                    pwhere .. " levelMax must be at least levelMin")
            end
            check((slot.pool == nil and slot.poolFrom == nil) or slot.count ~= nil,
                swhere .. " draws from a pool and needs a count")
        end
        -- Battle events. An event declared at a phase nothing runs, or with a
        -- duplicate id, is an event that quietly never happens -- and `once`
        -- bookkeeping is keyed by id, so two events sharing one would spend
        -- each other.
        local troopMod = require("engine.troop")
        local seenEventIds = {}
        for ei, ev in ipairs(t.events or {}) do
            local ewhere = twhere .. " events[" .. ei .. "]"
            check(ev.id ~= nil and ev.id ~= "", ewhere .. " needs an id")
            if ev.id then
                check(not seenEventIds[ev.id],
                    ewhere .. " reuses event id '" .. tostring(ev.id) .. "'")
                seenEventIds[ev.id] = true
            end
            local at = ev.at or "round_start"
            check(troopMod.PHASES[at],
                ewhere .. " runs at '" .. tostring(at) .. "', which is not a battle event "
                .. "phase (battle_start, round_start, after_action, round_end)")
            check(type(ev.commands) == "table" and #ev.commands > 0,
                ewhere .. " has no commands, so firing it does nothing")
        end

        -- Suppressing an id nothing declares is a silent no-op, and reads in
        -- the data as though a rule were disabled when it is still running.
        for _, sid in ipairs(t.suppress or {}) do
            local found = false
            for _, ev in ipairs((baseTroop and baseTroop.events) or {}) do
                if ev.id == sid then found = true end
            end
            check(found, twhere .. " suppresses '" .. tostring(sid)
                .. "', which the base troop does not declare")
        end
    end

    -- Battle commands (engine.json `battleCommands`). A creature whose command
    -- list is wrong is a creature that cannot act, or can act in a way the
    -- design forbids, and neither shows up until someone fights with it.
    local knownBattleCommands = {}
    local battleCommandNames = {}
    for _, cmd in ipairs((loader.engine and loader.engine.battleCommands) or {}) do
        local cwhere = "engine.json battleCommands '" .. tostring(cmd.id) .. "'"
        check(cmd.id ~= nil and cmd.id ~= "", "engine.json battleCommands entry needs an id")
        check(cmd.label ~= nil and cmd.label ~= "", cwhere .. " needs a label")
        check(cmd.resolve == "target" or cmd.resolve == "submenu" or cmd.resolve == "commit",
            cwhere .. " has resolve '" .. tostring(cmd.resolve)
            .. "'; expected 'target', 'submenu' or 'commit'")
        if cmd.resolve == "submenu" then
            check(cmd.submenu == "skill" or cmd.submenu == "item",
                cwhere .. " opens submenu '" .. tostring(cmd.submenu)
                .. "'; the console only draws 'skill' and 'item'")
        end
        -- A command that commits a skill must name one that exists, or the
        -- creature spends its turn on nothing.
        if cmd.action and cmd.action.type == "skill" then
            check(loader.getSkill(cmd.action.id) ~= nil,
                cwhere .. " commits missing skill '" .. tostring(cmd.action.id) .. "'")
            check(cmd.action.target == "self",
                cwhere .. " commits without target selection, so its target must be 'self'")
        end
        if cmd.id then
            knownBattleCommands[cmd.id] = true
            table.insert(battleCommandNames, cmd.id)
        end
    end
    table.sort(battleCommandNames)
    local battleCommandList = table.concat(battleCommandNames, ", ")
    local defaultCommands = (loader.engine and loader.engine.defaultBattleCommands) or {}
    check(#defaultCommands > 0,
        "engine.json defaultBattleCommands is empty, so an ordinary creature could not act")
    for _, id in ipairs(defaultCommands) do
        check(knownBattleCommands[id],
            "engine.json defaultBattleCommands names unknown command '" .. tostring(id)
            .. "' (known: " .. battleCommandList .. ")")
    end

    -- Item Creation disciplines (engine.json `disciplines`) are named from three
    -- places that used to have nothing tying them together: an item's
    -- `meta.disciplines`, an actor's `discipline`, and the crafting scene. A typo
    -- in any of them fails silently -- the item simply never appears in a pool,
    -- or the creature can craft nothing -- so it is gated here rather than left
    -- to be noticed in play.
    local knownDisciplines = {}
    local disciplineNames = {}
    for _, d in ipairs((loader.engine and loader.engine.disciplines) or {}) do
        if d.kind then
            knownDisciplines[d.kind] = true
            table.insert(disciplineNames, d.kind)
        end
    end
    table.sort(disciplineNames)
    local disciplineList = table.concat(disciplineNames, ", ")
    if #disciplineNames > 0 then
        for _, item in ipairs(loader.items or {}) do
            for _, kind in ipairs((item.meta and item.meta.disciplines) or {}) do
                check(knownDisciplines[kind] == true,
                    "item '" .. tostring(item.id) .. "' ('" .. tostring(item.name)
                    .. "') meta.disciplines names '" .. tostring(kind)
                    .. "', which is not a registered discipline (" .. disciplineList .. ")")
            end
        end

        -- An item with no discipline membership is invisible to Item Creation:
        -- it can never be produced. Often deliberate, so this reports rather
        -- than fails -- but silently uncraftable content is exactly the kind of
        -- thing that goes unnoticed for a long time in a growing database.
        local craftMod = require("engine.craft")
        local orphans = 0
        for _, item in ipairs(loader.items or {}) do
            if (item.meta or {}).craftable ~= false then
                if #craftMod.disciplinesOf(item, loader) == 0 then
                    print("[validator] warning: item '" .. tostring(item.id) .. "' ('"
                        .. tostring(item.name) .. "') has no discipline membership; "
                        .. "it can never be crafted")
                    orphans = orphans + 1
                end
            end
        end
        if orphans > 0 then
            print("[validator] total items with no discipline membership: " .. orphans)
        end

        -- Crafting reads element contributions off registry tables and a name
        -- lexicon. A word or effect naming an element that does not exist adds
        -- nothing and says nothing -- exactly the silent-no-op this project
        -- treats as the worst outcome.
        local function checkElementMap(map, what)
            for key, weights in pairs(map or {}) do
                for elem in pairs(weights) do
                    check(loader.getElement(elem) ~= nil,
                        "engine.craftElementSources." .. what .. "." .. tostring(key)
                        .. " names missing element '" .. tostring(elem) .. "'")
                end
            end
        end
        local ces = (loader.engine and loader.engine.craftElementSources) or {}
        checkElementMap(ces.effects, "effects")
        checkElementMap(ces.traits, "traits")
        checkElementMap(ces.params, "params")
        for word, elem in pairs((loader.engine and loader.engine.craftLexicon) or {}) do
            check(loader.getElement(elem) ~= nil,
                "engine.craftLexicon['" .. tostring(word) .. "'] names missing element '"
                .. tostring(elem) .. "'")
        end

        local grades = {}
        for _, g in ipairs((loader.engine and loader.engine.intensityGrades) or {}) do
            grades[g.grade] = true
        end
        for _, item in ipairs(loader.items or {}) do
            local grade = item.meta and item.meta.intensityGrade
            if grade then
                check(grades[grade] == true,
                    "item '" .. tostring(item.id) .. "' ('" .. tostring(item.name)
                    .. "') meta.intensityGrade '" .. tostring(grade)
                    .. "' is not a registered grade")
            end
        end

        -- disciplineDefaults decide membership for every item that does not
        -- author it, so a typo there silently empties a discipline's pool.
        local dd = (loader.engine and loader.engine.disciplineDefaults) or {}
        for _, group in ipairs({ "byEquipType", "byEffect", "byType" }) do
            for key, kind in pairs(dd[group] or {}) do
                check(knownDisciplines[kind] == true,
                    "engine.disciplineDefaults." .. group .. "." .. tostring(key)
                    .. " names '" .. tostring(kind) .. "', which is not a registered discipline ("
                    .. disciplineList .. ")")
            end
        end
        for _, actor in ipairs(loader.actors or {}) do
            local disc = actor.discipline
            if disc ~= nil and disc ~= "" then
                check(knownDisciplines[disc] == true,
                    "actor '" .. tostring(actor.id) .. "' ('" .. tostring(actor.name)
                    .. "') discipline '" .. tostring(disc)
                    .. "' is not a registered discipline (" .. disciplineList .. ")")
            end
        end
    end

    -- Use occasion. `scope` is the independent axis that decides whether an item
    -- is offered in battle, in the field, both, or never (engine/usability.lua),
    -- and it is registry-enumerated so the editor offers the same four words the
    -- engine understands. Gated because an unknown scope reads as a restriction
    -- and behaves as none: usability's if-chain falls through to usable
    -- everywhere, so a typo'd "feild" silently ships a battle-usable meal.
    local scopeNames = {}
    local knownScopes = {}
    for _, s in ipairs((loader.engine and loader.engine.itemScopes) or {}) do
        if s.scope then
            knownScopes[s.scope] = true
            table.insert(scopeNames, s.scope)
        end
    end
    table.sort(scopeNames)
    if #scopeNames > 0 then
        for _, item in ipairs(loader.items or {}) do
            if item.scope ~= nil then
                check(knownScopes[item.scope] == true,
                    "item '" .. tostring(item.id) .. "' ('" .. tostring(item.name)
                    .. "') has unknown scope '" .. tostring(item.scope)
                    .. "' (" .. table.concat(scopeNames, ", ") .. ")")
            end
        end
    end

    -- State categories. Broad resistances key off these (STATE_CATEGORY_RATE),
    -- so a typo'd category is worse than a no-op: it produces a state that no
    -- blanket immunity covers and no cleanse finds, and nothing says so.
    -- Traits naming a category are checked the same way, since a Ribbon that
    -- resists "negatve" simply protects against nothing.
    local knownCategories = {}
    local categoryNames = {}
    for _, c in ipairs((loader.engine and loader.engine.stateCategories) or {}) do
        if c.category then
            knownCategories[c.category] = true
            table.insert(categoryNames, c.category)
        end
    end
    table.sort(categoryNames)
    if #categoryNames > 0 then
        local categoryList = table.concat(categoryNames, ", ")
        for stateId, state in pairs(loader.states or {}) do
            local cats = state.categories
            if cats ~= nil then
                check(type(cats) == "table",
                    "state '" .. tostring(stateId) .. "' categories must be a list")
                if type(cats) == "table" then
                    for _, c in ipairs(cats) do
                        check(knownCategories[c] == true,
                            "state '" .. tostring(stateId) .. "' names unknown category '"
                            .. tostring(c) .. "' (" .. categoryList .. ")")
                    end
                end
            end
        end

        local function checkCategoryTraits(traitList, ownerDesc)
            for _, t in ipairs(traitList or {}) do
                if t.code == "STATE_CATEGORY_RATE" then
                    check(knownCategories[t.dataId] == true,
                        ownerDesc .. " STATE_CATEGORY_RATE names unknown category '"
                        .. tostring(t.dataId) .. "' (" .. categoryList .. ")")
                elseif t.code == "STATE_RATE" then
                    check(loader.getState(t.dataId) ~= nil,
                        ownerDesc .. " STATE_RATE names unknown state '"
                        .. tostring(t.dataId) .. "'")
                elseif t.code == "FORCE_ACTION" then
                    -- A forced action naming a missing skill would leave the
                    -- holder unable to act at all, silently.
                    check(loader.getSkill(t.dataId) ~= nil,
                        ownerDesc .. " FORCE_ACTION names unknown skill '"
                        .. tostring(t.dataId) .. "'")
                end
            end
        end
        for _, item in ipairs(loader.items or {}) do
            checkCategoryTraits(item.traits, "item '" .. tostring(item.id) .. "'")
        end
        for _, actor in ipairs(loader.actors or {}) do
            checkCategoryTraits(actor.traits, "actor '" .. tostring(actor.id) .. "'")
        end
        for pid, passive in pairs(loader.passives or {}) do
            checkCategoryTraits(passive.traits, "passive '" .. tostring(pid) .. "'")
        end
        for sid, state in pairs(loader.states or {}) do
            checkCategoryTraits(state.traits, "state '" .. tostring(sid) .. "'")
        end
    end

    -- An item excluded from ingredient selection AND from output pools can only
    -- be sold or consumed by something other than Item Creation -- that is the
    -- promotion-key shape, and it is deliberate. Reported, not failed, so the
    -- author can see the total is what they meant it to be.
    local craftInert = 0
    for _, item in ipairs(loader.items or {}) do
        local meta = item.meta or {}
        if meta.craftable == false and meta.craftIngredient == false then
            craftInert = craftInert + 1
        end
    end
    if craftInert > 0 then
        print("[validator] items outside Item Creation entirely (neither ingredient nor output): " .. craftInert)
    end

    -- Validate iconPalettes.json and iconKeyProfiles.json
    local validPalettes = {}
    for paletteId, entry in pairs(loader.iconPalettes or {}) do
        validPalettes[paletteId] = true
        check(type(entry) == "table", "icon palette '" .. tostring(paletteId) .. "' must be an object")
        if type(entry) == "table" then
            check(type(entry.colors) == "table" and #entry.colors == 4, "icon palette '" .. tostring(paletteId) .. "' must have exactly 4 hex colors")
        end
    end

    for iconKey, prof in pairs(loader.iconKeyProfiles or {}) do
        check(iconKey == "default" or tonumber(iconKey) ~= nil, "icon key profile '" .. tostring(iconKey) .. "' must be 'default' or a numeric icon ID")
        if type(prof) == "table" then
            if prof.minimumLightness and prof.maximumLightness then
                check(prof.minimumLightness <= prof.maximumLightness, "icon key profile '" .. tostring(iconKey) .. "' minimumLightness exceeds maximumLightness")
            end
        end
    end

    -- Validate items and skills icon palette references
    local function validateEntityIcon(entity, collectionName)
        local iconId = tonumber(entity.icon)
        if entity.iconPalette and entity.iconPalette ~= "" then
            check(validPalettes[entity.iconPalette] == true, collectionName .. " '" .. tostring(entity.id or entity.name) .. "' iconPalette '" .. tostring(entity.iconPalette) .. "' is not registered in iconPalettes.json")
            check(iconId and iconId > 0, collectionName .. " '" .. tostring(entity.id or entity.name) .. "' specifies iconPalette without a positive icon ID")
        end
    end

    for _, item in ipairs(loader.items or {}) do
        validateEntityIcon(item, "item")
    end
    for _, skill in ipairs(loader.skills or {}) do
        validateEntityIcon(skill, "skill")
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
                    elseif reg.type == "list" then
                        ok = (type(v) == "table")
                        if ok and reg.itemType then
                            for _, entry in ipairs(v) do
                                if type(entry) ~= reg.itemType then ok = false break end
                            end
                        end
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
        lore = loader.lore,
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
    -- Trait codes must be registered, AND their dataId must agree with the
    -- registry's `usesDataId` declaration and resolve. Only the code was ever
    -- checked, so `usesDataId` was a claim nothing enforced: a PARAM_RATE with
    -- a misspelled param or an ELEMENT_ADD naming a dropped element compares
    -- unequal forever in traits.getParam / traits.elementsOf and does nothing
    -- at all. Same shape as the one-way element affinities this file already
    -- rejects -- paired data where only one side is ever consulted.
    local function checkTraits(traitList, ownerDesc)
        for _, tr in ipairs(traitList or {}) do
            local def = traitCodeDefs[tr.code]
            check(def ~= nil, ownerDesc .. " uses unregistered trait code '" .. tostring(tr.code) .. "'")
            if def then
                local where = ownerDesc .. " trait '" .. tostring(tr.code) .. "'"
                if def.usesDataId then
                    check(tr.dataId ~= nil, where .. " is declared usesDataId in the registry but carries no dataId")
                    if tr.code == "PARAM_PLUS" or tr.code == "PARAM_RATE" then
                        check(VALID_TRAIT_PARAM[tr.dataId],
                            where .. " targets unknown param '" .. tostring(tr.dataId) .. "'")
                    elseif tr.code == "ELEMENT_CHANGE" or tr.code == "ELEMENT_ADD"
                        or tr.code == "ELEMENT_RATE" then
                        check(tr.dataId == nil or loader.getElement(tr.dataId) ~= nil,
                            where .. " references missing element '" .. tostring(tr.dataId) .. "'")
                    elseif tr.code == "STATE_RATE" or tr.code == "STATE_IMMUNITY" then
                        check(loader.getState(tr.dataId) ~= nil,
                            where .. " references missing state '" .. tostring(tr.dataId) .. "'")
                    end
                else
                    check(tr.dataId == nil,
                        where .. " carries dataId '" .. tostring(tr.dataId) ..
                        "' but the registry declares usesDataId=false, so nothing reads it")
                end

                -- A rate is a slope, not a switch: 0 makes a state vanishingly
                -- unlikely but a critical still forces it. Anyone authoring 0
                -- means immunity and would otherwise never find out they did
                -- not get it -- so say so instead of accepting it.
                if tr.code == "STATE_RATE" or tr.code == "STATE_CATEGORY_RATE" then
                    check(tonumber(tr.value) ~= 0, where
                        .. " is authored as a rate of 0. Rates no longer mean immunity"
                        .. " (a critical hit bypasses them); use "
                        .. (tr.code == "STATE_RATE" and "STATE_IMMUNITY" or "STATE_CATEGORY_IMMUNITY")
                        .. " for absolute immunity, or a small non-zero rate for"
                        .. " 'almost never'.")
                end
            end
        end
    end
    local function checkEffects(effList, ownerDesc)
        for _, eff in ipairs(effList or {}) do
            check(validEffectTypes[eff.type], ownerDesc .. " uses unregistered effect type '" .. tostring(eff.type) .. "'")
            if eff.type == "add_status" then
                check(loader.getState(eff.status), ownerDesc .. " references missing state '" .. tostring(eff.status) .. "'")
            elseif eff.type == "remove_status" then
                -- The cure half of the pair. effects.lua calls
                -- b:removeState(effectData.value) with no lookup, so a stale
                -- state name is a consumable that quietly cures nothing.
                check(loader.getState(eff.value),
                    ownerDesc .. " (remove_status) references missing state '" .. tostring(eff.value) .. "'")
            elseif eff.type == "learn_skill" then
                -- Skillbooks name a real skill, or they'd be dud items.
                local skillId = eff.skill or eff.value
                check(loader.getSkill(skillId),
                    ownerDesc .. " (learn_skill) references missing skill '" .. tostring(skillId) .. "'")
            elseif eff.type == "common_event" then
                -- An item promising a scripted encounter and naming an event
                -- that does not exist would be consumed for a line of error
                -- text. Gated here rather than left to runtime, because the
                -- item is the whole gate on that content (a Forbidden Lamp is
                -- the only way to reach what it calls).
                check(loader.commonEvents and loader.commonEvents[tostring(eff.value)],
                    ownerDesc .. " (common_event) references missing common event '"
                    .. tostring(eff.value) .. "'")
            elseif eff.type == "param_plus" then
                -- Only the params a battler's paramPlus table actually carries
                -- (engine/session.lua Battler.new) can be raised.
                local param = eff.param or eff.dataId
                check(VALID_PARAM_PLUS[param],
                    ownerDesc .. " (param_plus) targets unknown param '" .. tostring(param) .. "'")
                check(type(eff.value) == "number",
                    ownerDesc .. " (param_plus) needs a numeric value")
            end
        end
    end

    -- Actors must reference existing skills/passives/elements/roles
    for _, actor in ipairs(loader.actors) do
        local actorDesc = "actor " .. tostring(actor.id)
        -- An actor authoring an empty list would sit in battle with no rows to
        -- pick, which reads as a frozen game rather than a design choice. A
        -- creature meant to be helpless authors ["wait"], not [].
        if actor.battleCommands ~= nil then
            check(type(actor.battleCommands) == "table" and #actor.battleCommands > 0,
                actorDesc .. " has an empty battleCommands list; author [\"wait\"] for a "
                .. "creature that should be unable to act")
            for _, id in ipairs(actor.battleCommands or {}) do
                check(knownBattleCommands[id],
                    actorDesc .. " battleCommands names unknown command '" .. tostring(id)
                    .. "' (known: " .. battleCommandList .. ")")
            end
        end
        check(type(actor.names) == "table" and #actor.names > 0,
            actorDesc .. " ('" .. tostring(actor.name) .. "') needs at least one default personal name")
        check(type(actor.flavor) == "string" and actor.flavor ~= "",
            actorDesc .. " ('" .. tostring(actor.name) .. "') needs a biography")
        check(not actor.isEvolved or actor.unlocked ~= true,
            actorDesc .. " cannot be both a promotion result and unlocked by default")
        check(not actor.isEvolved or actor.isRecruitable ~= true,
            actorDesc .. " cannot be both a promotion result and directly recruitable")
        check(not actor.isEvolved or actor.initialParty ~= true,
            actorDesc .. " cannot be both a promotion result and eligible for the initial party")
        for _, skId in ipairs(actor.skills or {}) do
            check(loader.getSkill(skId), "actor " .. tostring(actor.id) .. " references missing skill '" .. tostring(skId) .. "'")
        end
        for _, pId in ipairs(actor.passives or {}) do
            check(loader.getPassive(pId), "actor " .. tostring(actor.id) .. " references missing passive '" .. tostring(pId) .. "'")
        end
        for _, el in ipairs(actor.elements or {}) do
            check(loader.getElement(el), "actor " .. tostring(actor.id) .. " references missing element '" .. tostring(el) .. "'")
        end
        -- Evolution targets. Candle pointed at a "lantern" that never existed
        -- (dropped 25.07.2026): the creature simply never evolved, with nothing
        -- reporting why -- exactly the silent failure this gate exists for.
        -- The promotion cost is the other half interpreter.promoteInfo reads:
        -- a cost.item that is not a real promotion key means the ritual charges
        -- for something the player can never be holding.
        for _, evo in ipairs(actor.evolutions or {}) do
            check(evo.evolvesTo ~= nil and loader.getActor(evo.evolvesTo) ~= nil,
                "actor " .. tostring(actor.id) .. " ('" .. tostring(actor.name)
                .. "') evolves into missing actor '" .. tostring(evo.evolvesTo) .. "'")
            check(evo.level == nil or type(evo.level) == "number",
                "actor " .. tostring(actor.id) .. " evolution level must be a number, got '"
                .. tostring(evo.level) .. "'")
            -- The fixed one-time promotion bonus, folded into the creature's
            -- permanent growth record. A misspelled parameter here would be
            -- read by nothing and grant nothing, while still reading in the
            -- editor as though the promotion rewarded something.
            if evo.bonus ~= nil then
                check(type(evo.bonus) == "table",
                    "actor " .. tostring(actor.id) .. " evolution bonus must be a table")
                if type(evo.bonus) == "table" then
                    local growthMod = require("engine.growth")
                    local known = {}
                    for _, p in ipairs(growthMod.PARAMS) do known[p] = true end
                    for param, value in pairs(evo.bonus) do
                        check(known[param], "actor " .. tostring(actor.id)
                            .. " evolution bonus names '" .. tostring(param)
                            .. "', which is not a growing parameter")
                        check(type(value) == "number", "actor " .. tostring(actor.id)
                            .. " evolution bonus '" .. tostring(param) .. "' must be a number")
                    end
                end
            end
            local cost = evo.cost
            if cost and cost.item ~= nil then
                local key = loader.getItem(cost.item)
                check(key ~= nil, "actor " .. tostring(actor.id)
                    .. " evolution cost references missing item '" .. tostring(cost.item) .. "'")
                if key then
                    check(key.category == "promotion_key", "actor " .. tostring(actor.id)
                        .. " evolution costs item '" .. tostring(key.name)
                        .. "' which is not category 'promotion_key'")
                end
            end
        end
        local lastBandEnd = 1
        for bi, band in ipairs(actor.growthBands or {}) do
            local desc = actorDesc .. " growthBands[" .. bi .. "]"
            check(type(band.from) == "number" and type(band.to) == "number"
                    and band.from >= 2 and band.to >= band.from,
                desc .. " needs numeric levels with 2 <= from <= to")
            if type(band.from) == "number" then
                check(band.from > lastBandEnd, desc .. " overlaps or is out of order")
            end
            if type(band.to) == "number" then lastBandEnd = band.to end
            for param, value in pairs(band) do
                if param ~= "from" and param ~= "to" then
                    check(VALID_PARAM_PLUS[param], desc .. " names unknown growth parameter '" .. tostring(param) .. "'")
                    check(type(value) == "number" and value >= 0,
                        desc .. " parameter '" .. tostring(param) .. "' must be a non-negative number")
                end
            end
            if type(band.from) == "number" and type(band.to) == "number" and type(band.maxHp) == "number" then
                check(band.maxHp >= band.to - band.from + 1,
                    desc .. " maxHp budget must permit HP to rise by at least 1 each level")
            end
        end
        for fi, itemId in ipairs(actor.favoriteFoods or {}) do
            local food = loader.getItem(itemId)
            check(food ~= nil, actorDesc .. " favoriteFoods[" .. fi .. "] references missing item '" .. tostring(itemId) .. "'")
            if food then
                check(food.meal == true or #(food.foodTags or {}) > 0,
                    actorDesc .. " favorite food '" .. tostring(food.name) .. "' is not tagged as food")
            end
        end
        for ri, line in ipairs(actor.foodReactions or {}) do
            check(type(line) == "string" and line ~= "",
                actorDesc .. " foodReactions[" .. ri .. "] must be a non-empty string")
        end
        for provenance, outcome in pairs(actor.hatchOutcomes or {}) do
            check(type(outcome) == "table" and loader.getActor(outcome and outcome.actor),
                actorDesc .. " hatch outcome '" .. tostring(provenance) .. "' references a missing actor")
        end
        for ei, eligibleId in ipairs(actor.eligibleFrom or {}) do
            check(loader.getActor(eligibleId),
                actorDesc .. " eligibleFrom[" .. ei .. "] references missing actor '" .. tostring(eligibleId) .. "'")
        end
        for si, rule in ipairs(actor.secretTransforms or {}) do
            local desc = actorDesc .. " secretTransforms[" .. si .. "]"
            check(type(rule.condition) == "string" and rule.condition ~= "",
                desc .. ".condition must be a non-empty formula")
            check(loader.getActor(rule.actor),
                desc .. " references missing actor '" .. tostring(rule.actor) .. "'")
            if type(rule.condition) == "string" then
                local _, err = require("engine.formula").eval(rule.condition, {
                    intrinsic = {
                        level = 10, maxHp = 100, atk = 20, def = 20,
                        mat = 20, mdf = 20
                    }
                })
                check(err == nil, desc .. " condition does not compile: " .. tostring(err))
            end
        end
        for ai, rule in ipairs(actor.autoTransforms or {}) do
            local desc = actorDesc .. " autoTransforms[" .. ai .. "]"
            local special = rule.actor == "hatch" or rule.actor == "metamorph" or rule.actor == "revert"
            check(type(rule.actor) == "string" and (special or loader.getActor(rule.actor)),
                desc .. " references missing actor '" .. tostring(rule.actor) .. "'")
            check(rule.atLevel == nil or (type(rule.atLevel) == "number" and rule.atLevel >= 1),
                desc .. ".atLevel must be a positive number")
            check(rule.afterOriginLevels == nil
                    or (type(rule.afterOriginLevels) == "number" and rule.afterOriginLevels >= 1),
                desc .. ".afterOriginLevels must be a positive number")
        end
        if actor.role then
            check(loader.getRole(actor.role), "actor " .. tostring(actor.id) .. " references missing role '" .. tostring(actor.role) .. "'")
        end
        checkTraits(actor.traits, "actor " .. tostring(actor.id))
    end

    -- Stand-in caster for the skill-cost formula sweep below: the fields a
    -- real formula.battlerView exposes, including the `base` table the charge
    -- formulas read (`b.base.mdf`).
    local formulaEngine = require("engine.formula")
    local MOCK_SKILL_ENV = {
        level = 5, hp = 40, maxHp = 60,
        atk = 12, def = 10, mat = 14, mdf = 11, mpd = 3, asp = 10,
        row = "front", meta = {},
        base = { maxHp = 60, atk = 12, def = 10, mat = 14, mdf = 11, mpd = 3, asp = 10 },
        trait = setmetatable({}, { __index = function() return 0 end }),
    }

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

        -- Skill costs (docs/design/skill-costs.md). No skill costs MP: the
        -- fields are gone, not tolerated, per the no-compat decision. Both were
        -- authored across the database and read by NOTHING -- exactly the kind
        -- of decorative field that silently reappears unless a gate says no.
        local where = "skill '" .. tostring(id) .. "'"
        check(skill.mpCost == nil, where
            .. " still carries mpCost -- no skill costs MP. Magic spends charges"
            .. " (with Overcast as the one path to the Summoner's pool); physical"
            .. " skills use cooldown/warmup/condition.")
        check(skill.spCost == nil, where .. " carries spCost, which nothing reads")

        -- Cost formulas must actually evaluate, against the same shape the
        -- caster view provides at runtime (b.base.mdf and friends). Same
        -- reason the effect formulas are swept: a formula that only fails when
        -- a specific creature casts a specific spell is a crash the player
        -- finds, not the author.
        local costEnv = {
            a = MOCK_SKILL_ENV, b = MOCK_SKILL_ENV,
        }
        if skill.charges ~= nil then
            if type(skill.charges) == "number" then
                check(skill.charges >= 0, where .. " has a negative charges count")
            else
                check(type(skill.charges) == "string",
                    where .. " charges must be a number or a formula string")
                if type(skill.charges) == "string" then
                    local val, ferr = formulaEngine.eval(skill.charges, costEnv)
                    check(ferr == nil and type(val) == "number",
                        where .. " has an uncompilable charges formula: " .. tostring(ferr or val))
                end
            end
        end

        -- Overcast needs a pool to exhaust, even a permanently empty one:
        -- `charges: 0` is the Overcast-only shape (a dragon's Breath). Without
        -- a charges key the skill never reaches the zero-charge branch, so the
        -- Overcast cost would simply never be paid.
        if skill.overcast ~= nil then
            check(skill.charges ~= nil, where
                .. " declares overcast but no charges; Overcast is only offered at"
                .. " zero charges, so use \"charges\": 0 for an Overcast-only skill")
            check(type(skill.overcast) == "table" and tonumber(skill.overcast.mp),
                where .. " overcast must carry a numeric mp cost")
        end

        -- HP cost: a flat number or a formula against the user. Paying can
        -- never kill (skill_cost floors the payer at 1 HP), so a skill is never
        -- a suicide button and cannot be used to dodge permadeath's timing.
        if skill.hpCost ~= nil then
            if type(skill.hpCost) == "number" then
                check(skill.hpCost >= 0, where .. " has a negative hpCost")
            else
                check(type(skill.hpCost) == "string",
                    where .. " hpCost must be a number or a formula string")
                if type(skill.hpCost) == "string" then
                    local val, ferr = formulaEngine.eval(skill.hpCost, costEnv)
                    check(ferr == nil and type(val) == "number",
                        where .. " has an uncompilable hpCost formula: " .. tostring(ferr or val))
                end
            end
        end

        for _, field in ipairs({ "cooldown", "warmup" }) do
            local v = skill[field]
            if v ~= nil then
                check(type(v) == "number" and v >= 0 and math.floor(v) == v,
                    where .. " " .. field .. " must be a non-negative whole number of turns")
            end
        end

        -- A formula cannot produce readable text, and a greyed row with no
        -- reason is a bug report waiting to happen.
        if skill.condition ~= nil then
            check(type(skill.condition) == "string",
                where .. " condition must be a string")
            check(skill.conditionText ~= nil and skill.conditionText ~= "",
                where .. " has a condition but no conditionText to explain it when blocked")
            -- A prefixed condition (state:, flag:, hasItem:, ...) is grammar
            -- engine/conditions.lua owns; only the formula fallback is swept.
            if type(skill.condition) == "string"
                and not skill.condition:match("^[%w_]+:") then
                local _, ferr = formulaEngine.eval(skill.condition, costEnv)
                check(ferr == nil,
                    where .. " has an uncompilable condition formula: " .. tostring(ferr))
            end
        end
    end

    -- Passives/states/items: trait codes must be registered
    for id, passive in pairs(loader.passives) do
        checkTraits(passive.traits, "passive '" .. tostring(id) .. "'")
    end
    for id, state in pairs(loader.states) do
        checkTraits(state.traits, "state '" .. tostring(id) .. "'")
    end
    check(love.filesystem.getInfo(itemModelView.FALLBACK_PATH) ~= nil,
        "item_model_view FALLBACK_PATH resolves to no asset: "
            .. tostring(itemModelView.FALLBACK_PATH))

    for _, item in ipairs(loader.items) do
        if item.keyArt ~= nil then
            local validKeyArt = type(item.keyArt) == "string" and item.keyArt ~= ""
            check(validKeyArt,
                "item " .. tostring(item.id) .. " keyArt must be a non-empty asset path")
            if validKeyArt then
                check(love.filesystem.getInfo(item.keyArt) ~= nil,
                    "item " .. tostring(item.id) .. " keyArt resolves to no asset: "
                        .. tostring(item.keyArt))
            end
        end
        if item.model ~= nil then
            local validModelPath = type(item.model) == "string" and item.model ~= "" and item.model:match("%.obj$") ~= nil
            check(validModelPath,
                "item " .. tostring(item.id) .. " model must be a non-empty asset path ending in .obj")
            if validModelPath then
                check(love.filesystem.getInfo(item.model) ~= nil,
                    "item " .. tostring(item.id) .. " model resolves to no asset: "
                        .. tostring(item.model))
                local text = love.filesystem.read(item.model)
                if text then
                    local mtlName = text:match("^mtllib%s+(%S+)") or text:match("\nmtllib%s+(%S+)")
                    if mtlName then
                        local baseDir = item.model:match("^(.*[/\\])") or ""
                        local mtlPath = baseDir .. mtlName
                        check(love.filesystem.getInfo(mtlPath) ~= nil,
                            "item " .. tostring(item.id) .. " model MTL resolves to no asset: " .. mtlPath)
                    end
                end
            end
        end
        checkTraits(item.traits, "item " .. tostring(item.id))
        checkEffects(item.effects, "item " .. tostring(item.id))
        for ti, tag in ipairs(item.foodTags or {}) do
            check(validFoodTags[tag],
                "item " .. tostring(item.id) .. " foodTags[" .. ti .. "] uses unregistered tag '" .. tostring(tag) .. "'")
        end
        if item.meal then
            check(item.scope == "field",
                "meal item " .. tostring(item.id) .. " must use scope 'field'")
        end
        if item.savor ~= nil then
            check(item.meal == true or #(item.foodTags or {}) > 0,
                "item " .. tostring(item.id) .. " has Savor but is not food")
            check(type(item.savor) == "table"
                    and (item.savor.battles == nil
                        or (type(item.savor.battles) == "number" and item.savor.battles >= 1)),
                "item " .. tostring(item.id) .. " Savor battles must be a positive number")
            if type(item.savor) == "table" then
                checkTraits(item.savor.traits, "item " .. tostring(item.id) .. " Savor")
            end
        end
        -- An item with effects but a non-consumable `type` is silently
        -- unusable: usability.canUseItem refuses anything that isn't
        -- "consumable", so it never appears as usable in the items menu and its
        -- effects can never fire. Caught here because the failure is invisible
        -- in-game -- nothing errors, the item just does nothing forever.
        if item.effects and #item.effects > 0 then
            check((item.type or "consumable") == "consumable",
                "item " .. tostring(item.id) .. " ('" .. tostring(item.name)
                .. "') has effects but type '" .. tostring(item.type)
                .. "' -- usability.canUseItem only accepts \"consumable\", so it "
                .. "would be silently unusable")
        end
        if item.category == "promotion_key" then
            check((item.meta or {}).craftable == false
                    and (item.meta or {}).craftIngredient == false,
                "promotion key " .. tostring(item.id)
                    .. " must be excluded from Item Creation inputs and outputs")
            check(not item.effects or #item.effects == 0,
                "promotion key " .. tostring(item.id) .. " must have no ordinary use effects")
            check(item.type ~= "equipment",
                "promotion key " .. tostring(item.id) .. " must not be equipment")
        end
        if item.meta and item.meta.tier ~= nil then
            check(item.meta.tier >= 1 and item.meta.tier <= 5
                    and item.meta.tier == math.floor(item.meta.tier),
                "item " .. tostring(item.id) .. " meta.tier must be an integer from 1 to 5")
        end
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

    -- Elements: affinity must be reciprocal. Only the ATTACKER's lists are read
    -- at damage time (engine/effects.lua), so a one-way entry is a penalty or
    -- bonus that nobody on the other side ever sees -- invisible dead data.
    -- Two such orphans ("White weak to Green", "Black weak to Red") sat in
    -- elements.json unnoticed until this check existed. A mutually strong pair
    -- (White <-> Black) is the deliberate exception: true opposites clash both
    -- ways, and that shape cannot be expressed as a single directed relation.
    local function listHas(list, value)
        for _, v in ipairs(list or {}) do
            if v == value then return true end
        end
        return false
    end
    for id, elem in pairs(loader.elements or {}) do
        for _, other in ipairs(elem.strongAgainst or {}) do
            local o = loader.getElement(other)
            if o then
                check(listHas(o.weakAgainst, id) or listHas(o.strongAgainst, id),
                    "element '" .. tostring(id) .. "' is strongAgainst '" .. tostring(other) ..
                    "' but '" .. tostring(other) .. "' lists neither weakAgainst nor strongAgainst '" .. tostring(id) .. "'")
            end
        end
        for _, other in ipairs(elem.weakAgainst or {}) do
            local o = loader.getElement(other)
            if o then
                check(listHas(o.strongAgainst, id),
                    "element '" .. tostring(id) .. "' is weakAgainst '" .. tostring(other) ..
                    "' but '" .. tostring(other) .. "' is not strongAgainst '" .. tostring(id) .. "'")
            end
        end
    end

    -- Story flags are the other classic one-way pair: SET_FLAG (and quest
    -- reward `flags`) writes session.flags, and "flag:<name>" condition strings
    -- read it, with nothing tying the two halves together. A condition on a
    -- flag nobody sets is a branch the player can never take -- the Gate
    -- Guard's "Report Progress" hub asked about `boss_killed_floor_3` and
    -- `boss_killed_floor_6`, neither of which any event ever set, so two of its
    -- three replies were unreachable. The reverse (set, never read) is only
    -- suspicious, not broken: a flag may be staged ahead of the content that
    -- reads it, so it warns.
    local flagWrites, flagReads, conditionItemReads = {}, {}, {}
    local function collectFlags(node, seen, where)
        if type(node) ~= "table" then return end
        seen = seen or {}
        if seen[node] then return end
        seen[node] = true
        -- COMMENT bodies are never evaluated, so a flag named in prose (an
        -- author's note about content that is not built yet) is not a read.
        if node.cmd == "COMMENT" then return end
        if node.cmd == "SET_FLAG" and type(node.flag) == "string" then
            flagWrites[node.flag] = true
        end
        if type(node.setFlag) == "string" then flagWrites[node.setFlag] = true end
        if type(node.flags) == "table" then
            for _, f in ipairs(node.flags) do
                if type(f) == "string" then flagWrites[f] = true end
            end
        end
        for key, val in pairs(node) do
            if type(val) == "string" then
                for name in val:gmatch("flag:([%w_]+)") do
                    flagReads[name] = flagReads[name] or where
                end
                if key == "condition" then
                    for itemRef in val:gmatch("hasItem:([^,%s]+)") do
                        conditionItemReads[itemRef] = conditionItemReads[itemRef] or where
                    end
                end
            else
                collectFlags(val, seen, where)
            end
        end
    end
    for name, root in pairs({ scenes = loader.scenes, flows = loader.flows,
        commonEvents = loader.commonEvents, maps = loader.maps, quests = loader.quests,
        shops = loader.shops, items = loader.items, actors = loader.actors,
        system = loader.system }) do
        collectFlags(root, nil, name)
    end
    for name, where in pairs(flagReads) do
        check(flagWrites[name], "condition reads flag '" .. name .. "' (in " .. where ..
            ") but no SET_FLAG or quest reward ever sets it -- that branch is unreachable")
    end
    for name in pairs(flagWrites) do
        if not flagReads[name] then
            print("[validator] warning: flag '" .. name .. "' is set but no condition reads it")
        end
    end
    for itemRef, where in pairs(conditionItemReads) do
        local itemId = tonumber(itemRef)
        check(itemId ~= nil, "condition reads hasItem:'" .. tostring(itemRef) .. "' (in " ..
            where .. ") but item condition references must be numeric ids")
        if itemId ~= nil then
            check(loader.getItem(itemId), "condition reads hasItem:" .. tostring(itemRef) ..
                " (in " .. where .. ") but that item does not exist")
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
    local newGameParty = (sys.newGame and sys.newGame.party) or {}
    for i, m in ipairs(newGameParty.fixedMembers or {}) do
        check(loader.getActor(m.id), "fixedMember #" .. i .. " references missing actor '" .. tostring(m.id) .. "'")
        if m.slot ~= nil then
            check(type(m.slot) == "number" and m.slot >= 1 and m.slot <= 4,
                "fixedMember #" .. i .. " slot must be a number 1..4, got " .. tostring(m.slot))
        end
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

    -- Map-level id POOLS. These are read only at runtime, by authored map id,
    -- after the loader resolves that id to its current array index, from a
    -- random roll -- `treasures` by CHANGE_ITEM item="random", `recruits` by
    -- the RECRUIT compile path in main.lua/exploration.lua -- and neither
    -- resolves the id it picked: session:addItem stores whatever it was handed,
    -- so a stale id becomes a phantom inventory row instead of an error.
    -- data/maps.json carried four ("potion", "antidote", "hi_potion",
    -- "iron_sword") from before items were renumbered, and two floors of chests
    -- had been handing out nothing at all.
    for mi, map in ipairs(loader.maps or {}) do
        local where = "map #" .. mi .. " ('" .. tostring(map.name or map.title or "?") .. "')"
        -- The shared Stairs Down common event descends with
        -- `LOAD_MAP mapId: session.floor + 2`, which is only correct while a
        -- dungeon map's id is its depth plus one. Safe maps (town, the
        -- developer room) are exempt: they are at depth 0 and nothing
        -- descends to them by arithmetic.
        check(map.safe == true or (map.depth or 0) < 1 or map.id == (map.depth or 0) + 1,
            where .. " is at depth " .. tostring(map.depth) .. " so its id must be "
            .. tostring((map.depth or 0) + 1) .. " for the stairs to reach it, but it is "
            .. tostring(map.id))
        for ti, itemId in ipairs(map.treasures or {}) do
            check(loader.getItem(itemId) ~= nil,
                where .. " treasures[" .. ti .. "] references missing item '" .. tostring(itemId) .. "'")
        end
        for ri, actorId in ipairs(map.recruits or {}) do
            local actor = loader.getActor(actorId)
            check(actor ~= nil,
                where .. " recruits[" .. ri .. "] references missing actor '" .. tostring(actorId) .. "'")
            check(actor == nil or actor.isRecruitable == true,
                where .. " recruits[" .. ri .. "] actor '" .. tostring(actorId)
                .. "' is not marked isRecruitable")
        end
        -- A map's encounter table is the floor's roster: a weighted pool of
        -- actors, in exactly the shape a troop's pool slot uses, because the
        -- `wandering` troop reads it as one. The map owns WHAT can appear; the
        -- troop owns what a wandering fight is.
        for ei, enc in ipairs(map.encounters or {}) do
            local encWhere = where .. " encounters[" .. ei .. "]"
            check(type(enc) == "table" and loader.getActor(enc.actor) ~= nil,
                encWhere .. " references missing actor '"
                .. tostring(type(enc) == "table" and enc.actor or enc) .. "'")
            if type(enc) == "table" then
                check(type(enc.weight) == "number" and enc.weight > 0 and enc.weight == math.floor(enc.weight),
                    encWhere .. " weight must be a positive integer")
                check(enc.levelMin == nil or (type(enc.levelMin) == "number"
                        and enc.levelMin >= 1 and enc.levelMin == math.floor(enc.levelMin)),
                    encWhere .. " levelMin must be a positive integer")
                check(enc.levelMax == nil or (type(enc.levelMax) == "number"
                        and enc.levelMax >= 1 and enc.levelMax == math.floor(enc.levelMax)),
                    encWhere .. " levelMax must be a positive integer")
                check(enc.levelMax == nil or enc.levelMin ~= nil,
                    encWhere .. " levelMax requires levelMin")
                check(enc.levelMin == nil or enc.levelMax == nil or enc.levelMax >= enc.levelMin,
                    encWhere .. " levelMax must be at least levelMin")
            end
        end
        -- An override for a floor whose random battles are not ordinary ones.
        if map.encounterTroop ~= nil then
            local t = loader.troops and loader.troops[tostring(map.encounterTroop)]
            check(t ~= nil, where .. " encounterTroop '" .. tostring(map.encounterTroop)
                .. "' is not a troop")
            check(t == nil or t.abstract ~= true,
                where .. " encounterTroop '" .. tostring(map.encounterTroop)
                .. "' is abstract, so it cannot be fought")
        end
    end

    -- Item Creation disciplines pair a `stat` with the params traits.getParam
    -- can return; craft.crafterStat falls back silently otherwise, so a typo
    -- would make a whole discipline's reach a constant.
    for _, disc in ipairs((loader.engine and loader.engine.disciplines) or {}) do
        check(VALID_TRAIT_PARAM[disc.stat],
            "discipline '" .. tostring(disc.kind) .. "' uses stat '" .. tostring(disc.stat)
            .. "' which is not a readable battler param")
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
        check(type(actor.smallBattler) == "string" and actor.smallBattler ~= "",
            who .. " must define smallBattler")
        if type(actor.smallBattler) == "string" and actor.smallBattler ~= "" then
            check(sb.resolveFile(actor.smallBattler) ~= nil,
                who .. " smallBattler '" .. tostring(actor.smallBattler) .. "' resolves to no file")
        end
        check(type(actor.portrait) == "string" and actor.portrait ~= "",
            who .. " must define portrait")
        check(type(actor.bigBattler) == "string" and actor.bigBattler ~= "",
            who .. " must define bigBattler")
        for _, asset in ipairs({
            { field = "portrait", directory = "assets/portraits" },
            { field = "bigBattler", directory = "assets/bigBattlers" },
        }) do
            local id = tostring(actor[asset.field] or "")
            local found = false
            for _, p in ipairs({
                asset.directory .. "/" .. id .. ".png",
                asset.directory .. "/" .. id:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "") .. ".png",
                asset.directory .. "/" .. id:lower() .. ".png",
                asset.directory .. "/" .. id:sub(1, 1):upper() .. id:sub(2):lower() .. ".png",
            }) do
                if love.filesystem.getInfo(p) then found = true break end
            end
            check(id == "" or found,
                who .. " " .. asset.field .. " '" .. id
                    .. "' resolves to no image in " .. asset.directory)
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

    -- Lore is campaign content, and event commands refer to it by id. Validate
    -- both the authored entry shape and every unlock edge so discoveries can
    -- never silently point at a missing datalog page.
    for loreId, entry in pairs(loader.lore or {}) do
        check(type(loreId) == "string" and loreId ~= "", "lore entry has an empty id")
        check(type(entry) == "table", "lore '" .. tostring(loreId) .. "' must be an object")
        if type(entry) == "table" then
            check(type(entry.title) == "string" and entry.title ~= "",
                "lore '" .. tostring(loreId) .. "' needs a title")
            check(type(entry.category) == "string" and entry.category ~= "",
                "lore '" .. tostring(loreId) .. "' needs a category")
            check(type(entry.body) == "string" and entry.body ~= "",
                "lore '" .. tostring(loreId) .. "' needs body text")
        end
    end
    local function validateLoreUnlocks(node, seen, where)
        if type(node) ~= "table" then return end
        seen = seen or {}
        if seen[node] then return end
        seen[node] = true
        if node.cmd == "UNLOCK_LORE" then
            check(type(node.loreId) == "string" and loader.getLore(node.loreId),
                where .. " UNLOCK_LORE references missing lore '" .. tostring(node.loreId) .. "'")
        end
        for _, value in pairs(node) do validateLoreUnlocks(value, seen, where) end
    end
    for name, root in pairs({
        scenes = loader.scenes, flows = loader.flows, commonEvents = loader.commonEvents,
        maps = loader.maps, quests = loader.quests, actionSequences = loader.actionSequences,
    }) do
        validateLoreUnlocks(root, nil, name)
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
            local sys = loader and loader.system
            local rate = sys and sys.summoner and sys.summoner.sacrificeExpRate or 1.0
            check((s.expBank or 0) > bankBefore or rate == 0, "REAP_FALLEN banked no EXP for the fallen")
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

    -- Flow-locals (`v.*`) are DATA, not engine surface: a formula reads a
    -- local because some SET_VAR in the same tree (or a SCENE_EVENT pushing
    -- into the scene) assigns it. So the mock `v` is not hand-maintained
    -- here -- every formula check seeds it by PRE-SCANNING the tree it is
    -- about to validate (collectAssignedVars/resolveSeedVars below), which
    -- means adding a new local is pure data work, no engine edit. Seeding
    -- stays strictly limited to names something actually assigns, so a
    -- formula reading a name NOTHING assigns still evaluates against nil
    -- and fails G1 -- that is what catches typo'd locals.
    --
    -- Only the entries below survive as hardcoded: the ENGINE puts them in
    -- `v` as a side effect, no SET_VAR ever names them, so no pre-scan of
    -- data could find them.
    local HOST_SEEDED_VARS = {
        -- engine/scene_host.lua: raw key of the press being captured, set
        -- while v._capturingKey is on (controls scene rebinding).
        rawKey = "escape",
        -- engine/interpreter.lua list-builder commands, each of which fills
        -- a rows list plus its count as a side effect. Row shapes mirror the
        -- handlers so `v.xRows[i].field` formulas see the real fields.
        campaignRows = { { name = "Mock Campaign", campaign = "" } },
        campaignCount = 1,
        saveRows = { { name = "Slot 1 - (empty)", slot = "slot1", empty = true,
            gold = 0, dungeonFloor = 1, savedAt = 0 } },
        saveCount = 1,
        questRows = { { name = "Mock Quest", id = "mock", summary = "",
            objectives = "", completed = false } },
        questCount = 1,
        bindingRows = { { name = "A - z", button = "A", key = "z" } },
        bindingCount = 1,
        -- USE_ITEM's result record (engine/interpreter.lua).
        lastItemResult = { success = true, reason = "", itemName = "Mock Item" },
        -- Shop stock the Lua host materializes before pushing the shop scene
        -- (main.lua openShop / engine/cli_tools.lua), not any SET_VAR.
        shopName = "Mock Shop",
        items = { { id = 1, cost = 50, name = "Item 1", stock = 9 },
                  { id = 2, cost = 100, name = "Item 2", stock = 9 },
                  { id = 3, cost = 200, name = "Item 3", stock = 9 } },
        count = 3,
    }

    -- Mock scene actors, built once: a Battler and item views are expensive
    -- enough that rebuilding them per formula check is wasteful.
    local mockItemView1 = require("engine.formula").itemView(loader.getItem(1))
    local mockItemView2 = require("engine.formula").itemView(loader.getItem(2))
    -- Guarded: a campaign missing actor 1 fails its own check above; the
    -- mock must not crash the run before that message is collected.
    local mockCrafter = loader.getActor(1) and session.Battler.new(loader.getActor(1), 1) or nil

    -- Mock context shared by every formula-compiling param check (the
    -- 'formula' type and E7's 'assignments' list-of-pairs type) and by the
    -- scene checks. `seedVars` is the pre-scanned flow-local seed for the
    -- tree being validated (see resolveSeedVars).
    local function buildFormulaMockCtx(seedVars)
        -- Any registered trait code must resolve for `x.trait.<CODE>` formulas
        -- (engine/formula.lua battlerView/groupView). A permissive stub: the
        -- validator checks that a formula COMPILES and evaluates, not what a
        -- particular trait's live rate is.
        local function mockTraits()
            return setmetatable({}, { __index = function() return 0.1 end })
        end
        local v = {}
        for k, val in pairs(HOST_SEEDED_VARS) do v[k] = val end
        for k, val in pairs(seedVars or {}) do v[k] = val end
        return {
                        enemy = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1, trait = mockTraits() },
                        ally = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1, trait = mockTraits() },
                        target = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1, trait = mockTraits() },
                        a = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1, trait = mockTraits() },
                        b = { level = 1, hp = 1, maxHp = 1, atk = 1, def = 1, mat = 1, mdf = 1, mpd = 1, trait = mockTraits() },
                        session = { gold = 100, mp = 20, maxMp = 30, floor = 3, mapSafe = false, encounterRate = 0.1, itemCount = 3, equipCount = { 1, 1, 1 } },
                        combat = { minEnemies = 1, maxEnemies = 3, victoryGoldMin = 1, victoryGoldMax = 5, victoryGoldBase = 5, victoryGoldPerEnemy = 5, victoryExp = 10, victoryExpBase = 10, victoryExpLevelScale = 0.5, baseFleeChance = 0.5, goldLossOnFleeMin = 1, goldLossOnFleeMax = 5, mpExhaustionDamage = 5 },
                        v = v,
                        -- These mirror formula.groupView by hand and will drift
                        -- from it again: `mpd` had to be added here before a
                        -- flow could charge the party's traversal cost, even
                        -- though groupView had always been able to answer.
                        -- Anything groupView returns belongs in both.
                        party = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, mpd = 2, trait = mockTraits() },
                        enemies = { size = 1, count = 1, aliveCount = 1, avgLevel = 1, totalLevel = 1, totalMaxHp = 1, mpd = 2, trait = mockTraits() },
                        -- Battle phases really do receive a battle (the hosts
                        -- pass one unconditionally), so a phase formula reading
                        -- battle.round is legitimate and must compile here.
                        battle = { round = 1 },
                        ingredient1 = { id = 1, name = "Mock Ingredient 1", meta = { potency = 5, tier = 1, craftElement = "fire" } },
                        ingredient2 = { id = 2, name = "Mock Ingredient 2", meta = { potency = 3, tier = 0, craftElement = "water" } },
                        -- Scene-side aliases (crafting scenes read i1/i2/crafter).
                        i1 = mockItemView1,
                        i2 = mockItemView2,
                        -- At runtime `crafter` is a formula.battlerView, which
                        -- carries generic `.trait` access; the raw Battler used
                        -- here does not, so a yield formula reading
                        -- crafter.trait.<CODE> failed to compile against a mock
                        -- that was simply the wrong shape. Layer trait over the
                        -- Battler rather than replacing it, so every real field
                        -- stays reachable.
                        crafter = setmetatable({ trait = mockTraits() },
                            { __index = mockCrafter or {} }),
                        alpha = 0.5,
                        S = 10
        }
    end

    -- A sandboxed SCRIPT body is data too (it lives in scenes.json), and
    -- `v.invCount = #inv` in one is as much an authored local as a SET_VAR
    -- row -- so its assignments are pre-scanned out of the source text.
    -- `==`/`~=`/`<=`/`>=` can't match: only a bare `=` not followed by
    -- another `=` counts. No value comes back, so these seed neutrally.
    local function collectScriptAssignedVars(text, out)
        if type(text) ~= "string" then return out end
        for name in text:gmatch("v%.([%a_][%w_]*)%s*=[^=]") do
            table.insert(out, { name = name })
        end
        return out
    end

    -- Pre-scan: every flow-local a command tree assigns, in author order,
    -- as { name, value } rows. Nested command lists (IF then/else, FOR_EACH
    -- commands, CHOICE options, ...) are walked generically rather than by
    -- key name, so a new block command needs no change here. A SCENE_EVENT's
    -- `vars` rows are skipped: they land in the PUSHED scene's v, not this
    -- tree's (collected per target scene by collectScenePushedVars).
    local function collectAssignedVars(cmds, out)
        out = out or {}
        for _, cmd in ipairs(cmds or {}) do
            if type(cmd) == "table" then
                if cmd.cmd == "SET_VAR" then
                    if type(cmd.name) == "string" and cmd.name ~= "" then
                        table.insert(out, { name = cmd.name, value = cmd.value })
                    end
                    for _, a in ipairs(cmd.assignments or {}) do
                        if type(a) == "table" and type(a.name) == "string" and a.name ~= "" then
                            table.insert(out, { name = a.name, value = a.value })
                        end
                    end
                elseif cmd.cmd == "SCRIPT" then
                    collectScriptAssignedVars(cmd.code, out)
                end
                for key, val in pairs(cmd) do
                    if type(val) == "table" and key ~= "assignments" and key ~= "vars" then
                        collectAssignedVars(val, out)
                    end
                end
            end
        end
        return out
    end

    -- Shape hint for locals a pre-scan found but could not evaluate (SCRIPT
    -- assignments, mostly): if the data itself indexes one, takes its length
    -- or reads a field off it, a scalar seed would blow up where a plain
    -- number can't be indexed. Collected from how the tree USES the name, so
    -- it stays data-driven like the rest of the seeding.
    local function collectTableShapedVars(node, out, seen)
        out = out or {}
        if type(node) == "string" then
            for name in node:gmatch("#%s*v%.([%a_][%w_]*)") do out[name] = true end
            for name in node:gmatch("v%.([%a_][%w_]*)%s*%[") do out[name] = true end
            for name in node:gmatch("v%.([%a_][%w_]*)%.") do out[name] = true end
            return out
        end
        if type(node) ~= "table" then return out end
        seen = seen or {}
        if seen[node] then return out end
        seen[node] = true
        for _, val in pairs(node) do collectTableShapedVars(val, out, seen) end
        return out
    end

    -- Stand-in for a table-shaped local: three rows long, and every field
    -- read off it (or off a row) answers 1, so `#v.pool`, `v.items[v.idx]`
    -- and `v.items[v.idx].cost` all evaluate without pretending to know the
    -- real row shape.
    local function mockTableValue()
        local anyField = { __index = function() return 1 end }
        local row = function() return setmetatable({}, anyField) end
        return setmetatable({ row(), row(), row() }, anyField)
    end

    -- Turn pre-scanned assignments into concrete mock values by evaluating
    -- each assigned expression -- the same thing the SET_VAR handler does at
    -- runtime, so a seed carries the real TYPE (index numbers stay numbers,
    -- `'summon'`-style mode strings stay strings). FIRST successful
    -- assignment per name wins: that is the author's initializer (on_enter's
    -- `idx = 1`), where a later `idx = v.idx - 1` would leave the seed
    -- drifted out of range. Two passes, so an initializer that reads a local
    -- assigned further down the tree still lands on a real value. Whatever
    -- is left -- SCRIPT-assigned names, self-referential expressions --
    -- takes a neutral seed: a table stand-in if the data uses the name
    -- table-like, otherwise 1. A seed only has to be type-plausible.
    -- formula.eval never raises (it returns 0, err); the pcall is belt and
    -- braces.
    local function resolveSeedVars(assigned, tableShaped)
        local formulaEngine = require("engine.formula")
        local ctx = buildFormulaMockCtx(nil)
        -- Seeding evaluates speculatively (a pass-1 row may read a local
        -- pass 2 fills in), so formula.lua's per-expression console warning
        -- is muted here: those misses are not problems, and printing them
        -- would bury the real check output. An expression that still fails
        -- its own check reports through check() with the same error text.
        local realPrint = print
        print = function() end
        for _ = 1, 2 do
            for _, a in ipairs(assigned) do
                if ctx.v[a.name] == nil then
                    if type(a.value) == "string" then
                        local ok, result, ferr = pcall(formulaEngine.eval, a.value, ctx)
                        if ok and ferr == nil then ctx.v[a.name] = result end
                    elseif a.value ~= nil then
                        ctx.v[a.name] = a.value
                    end
                end
            end
        end
        print = realPrint
        for _, a in ipairs(assigned) do
            if ctx.v[a.name] == nil then
                ctx.v[a.name] = (tableShaped or {})[a.name] and mockTableValue() or 1
            end
        end
        return ctx.v
    end

    local function seedVarsFor(cmds, pushedVars)
        local assigned = {}
        -- Pushed vars are seeded before the scene's own assignments: they
        -- exist in v before on_enter runs (engine/scene_host.lua push).
        for _, a in ipairs(pushedVars or {}) do table.insert(assigned, a) end
        collectAssignedVars(cmds, assigned)
        return resolveSeedVars(assigned, collectTableShapedVars(cmds))
    end

    -- SCENE_EVENT hands `vars` to the scene it pushes, so for the RECEIVING
    -- scene those names count as assigned even though nothing inside it
    -- SET_VARs them. Collected once across every host that can push a scene.
    local scenePushedVars = {}
    local function collectScenePushedVars(node, seen)
        if type(node) ~= "table" then return end
        seen = seen or {}
        if seen[node] then return end
        seen[node] = true
        if node.cmd == "SCENE_EVENT" and node.scene ~= nil and type(node.vars) == "table" then
            local key = tostring(node.scene)
            scenePushedVars[key] = scenePushedVars[key] or {}
            for _, a in ipairs(node.vars) do
                if type(a) == "table" and type(a.name) == "string" and a.name ~= "" then
                    table.insert(scenePushedVars[key], { name = a.name, value = a.value })
                end
            end
        end
        for _, val in pairs(node) do collectScenePushedVars(val, seen) end
    end
    for _, root in ipairs({ loader.scenes, loader.flows, loader.commonEvents,
        loader.maps, loader.quests, loader.actionSequences }) do
        collectScenePushedVars(root)
    end

    -- `seedVars` is the pre-scanned flow-local seed for the whole tree; it is
    -- computed once at the top-level call and handed to nested lists, since
    -- a nested IF branch reads locals its enclosing tree assigned.
    local function validateCommands(cmds, hostCtx, isImmediate, allowScript, ownerDesc, seedVars)
        seedVars = seedVars or seedVarsFor(cmds)
        for _, cmd in ipairs(cmds or {}) do

            local id = cmd.cmd
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

                if id == "CHOICE" and cmd.cancelOption ~= nil then
                    local cancelOption = tonumber(cmd.cancelOption)
                    check(cancelOption ~= nil and cancelOption % 1 == 0
                            and cancelOption >= 1 and cancelOption <= #(cmd.options or {}),
                        ownerDesc .. " command 'CHOICE' cancelOption must be a one-based authored option index")
                end

                -- Validate params
                for _, paramDef in ipairs(cmdDef.params or {}) do
                    local val = cmd[paramDef.key]
                    if val ~= nil then

                if paramDef.type == "formula" then
                    local mockCtx = buildFormulaMockCtx(seedVars)
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
                        local mockCtx = buildFormulaMockCtx(seedVars)
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
                            if opt.commands then validateCommands(opt.commands, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> CHOICE opt", seedVars) end
                        end
                    else
                        validateCommands(val, hostCtx, nestedImmediate, allowScript, ownerDesc .. " -> nested", seedVars)
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
                            validateCommands(val, hostCtx, isImmediate or (cmdDef.interactive ~= true), allowScript, ownerDesc .. " -> nested", seedVars)
                        end
                    end
                end

                if id == "SET_MAP_PRESENTATION" then
                    if cmd.tileset ~= nil then
                        check(loader.getTileset(cmd.tileset) ~= nil,
                            ownerDesc .. " command '" .. id .. "' references unknown tileset '"
                            .. tostring(cmd.tileset) .. "'")
                    end
                    if cmd.fogPreset ~= nil then
                        check(validFogPresets[cmd.fogPreset] == true,
                            ownerDesc .. " command '" .. id .. "' references unknown fog preset '"
                            .. tostring(cmd.fogPreset) .. "'")
                    end
                end
                if id == "ENTER_LOCATION" and cmd.image ~= nil then
                    check(love.filesystem.getInfo(
                            "assets/locationArt/" .. tostring(cmd.image)) ~= nil,
                        ownerDesc .. " command '" .. id .. "' references missing location art '"
                        .. tostring(cmd.image) .. "'")
                end
                if id == "SHOW_IMAGE_PICTURE" and cmd.path ~= nil then
                    check(love.filesystem.getInfo(tostring(cmd.path)) ~= nil,
                        ownerDesc .. " command '" .. id .. "' references missing image '"
                        .. tostring(cmd.path) .. "'")
                end
                if id == "START_COMMON_EVENT" and cmd.commonEventId ~= nil then
                    check(loader.commonEvents[tostring(cmd.commonEventId)] ~= nil,
                        ownerDesc .. " command '" .. id .. "' references missing common event '"
                        .. tostring(cmd.commonEventId) .. "'")
                end
            end

            ::continue::
        end
    end

    local function validateFixturePredicate(predicate, where, featureIds)
        check(type(predicate) == "table", where .. " must be an object")
        if type(predicate) ~= "table" then return end
        local operators = { "all", "any", "not", "adjacent", "distance", "zone" }
        local present = {}
        for _, operator in ipairs(operators) do
            if predicate[operator] ~= nil then present[#present + 1] = operator end
        end
        check(#present == 1, where .. " must contain exactly one predicate operator")
        if #present ~= 1 then return end
        local operator, value = present[1], predicate[present[1]]
        if operator == "all" or operator == "any" then
            check(type(value) == "table" and #value > 0,
                where .. "." .. operator .. " must be a non-empty array")
            if type(value) == "table" then
                for i, child in ipairs(value) do
                    validateFixturePredicate(child, where .. "." .. operator .. "[" .. i .. "]", featureIds)
                end
            end
        elseif operator == "not" then
            validateFixturePredicate(value, where .. ".not", featureIds)
        elseif operator == "zone" then
            check(type(value) == "string" and value ~= "", where .. ".zone must be a non-empty string")
        elseif operator == "adjacent" then
            if type(value) == "string" then
                check(value == "wall" or value == "floor" or value == "opening",
                    where .. ".adjacent has unknown tile class '" .. tostring(value) .. "'")
            else
                check(type(value) == "table", where .. ".adjacent must be a tile string or object")
                if type(value) == "table" then
                    local targets = (value.tile and 1 or 0) + (value.zone and 1 or 0)
                        + (value.feature and 1 or 0)
                    check(targets == 1, where .. ".adjacent requires exactly one of tile, zone or feature")
                    if value.tile then
                        check(value.tile == "wall" or value.tile == "floor" or value.tile == "opening",
                            where .. ".adjacent.tile has unknown class '" .. tostring(value.tile) .. "'")
                    end
                    if value.zone then check(type(value.zone) == "string" and value.zone ~= "",
                        where .. ".adjacent.zone must be a non-empty string") end
                    if value.feature then check(featureIds[value.feature] == true,
                        where .. ".adjacent.feature references unknown feature '" .. tostring(value.feature) .. "'") end
                    check(value.diagonal == nil or type(value.diagonal) == "boolean",
                        where .. ".adjacent.diagonal must be boolean")
                end
            end
        elseif operator == "distance" then
            check(type(value) == "table", where .. ".distance must be an object")
            if type(value) == "table" then
                local targets = (value.zone and 1 or 0) + (value.feature and 1 or 0)
                check(targets == 1, where .. ".distance requires exactly one of zone or feature")
                if value.zone then check(type(value.zone) == "string" and value.zone ~= "",
                    where .. ".distance.zone must be a non-empty string") end
                if value.feature then check(featureIds[value.feature] == true,
                    where .. ".distance.feature references unknown feature '" .. tostring(value.feature) .. "'") end
                check(value.min == nil or (type(value.min) == "number" and value.min >= 0),
                    where .. ".distance.min must be non-negative")
                check(value.max == nil or (type(value.max) == "number" and value.max >= 0),
                    where .. ".distance.max must be non-negative")
                if type(value.min) == "number" and type(value.max) == "number" then
                    check(value.min <= value.max, where .. ".distance min exceeds max")
                end
            end
        end
    end

    -- Tileset variant pools are resolved deterministically by authored weight.
    -- Reject malformed weights here rather than letting one bad pool make a
    -- renderer choice disappear or fall through silently.
    for tilesetId, tileset in pairs(loader.tilesets or {}) do
        local tilesetWhere = "tileset '" .. tostring(tilesetId) .. "'"
        if tileset.heightMap ~= nil then
            check(type(tileset.heightMap) == "string" and tileset.heightMap ~= "",
                tilesetWhere .. ".heightMap must name a PNG")
            if type(tileset.heightMap) == "string" then
                check(love.filesystem.getInfo(tileset.heightMap) ~= nil,
                    tilesetWhere .. ".heightMap is missing (" .. tileset.heightMap .. ")")
                local okHeight, heightData = pcall(love.image.newImageData, tileset.heightMap)
                check(okHeight, tilesetWhere .. ".heightMap is unreadable")
                if okHeight and heightData then
                    local tileWidth = tileset.tileWidth or 64
                    local tileHeight = tileset.tileHeight or 64
                    local texturePath = tileset.texture
                    local okTexture, textureData = false, nil
                    if texturePath then
                        okTexture, textureData = pcall(love.image.newImageData, texturePath)
                    end
                    if okTexture and textureData then
                        local full = heightData:getWidth() == textureData:getWidth()
                            and heightData:getHeight() == textureData:getHeight()
                        local tile = heightData:getWidth() == tileWidth
                            and heightData:getHeight() == tileHeight
                        check(full or tile, tilesetWhere .. ".heightMap must match its texture atlas"
                            .. " or one tile (got " .. heightData:getWidth() .. "x"
                            .. heightData:getHeight() .. ")")
                    end
                    check(require("engine.geometry.images").checkGrayscale(heightData, 0),
                        tilesetWhere .. ".heightMap must be grayscale")
                end
            end
            local scale = tileset.heightMapScale
            if scale ~= nil and type(scale) ~= "number" and type(scale) ~= "table" then
                check(false, tilesetWhere .. ".heightMapScale must be numeric or an object")
            elseif type(scale) == "number" then
                check(scale >= 0 and scale <= 1, tilesetWhere .. ".heightMapScale must be 0..1")
            elseif type(scale) == "table" then
                for surface, value in pairs(scale) do
                    check(surface == "wall" or surface == "floor"
                            or surface == "ceiling" or surface == "default",
                        tilesetWhere .. ".heightMapScale has unknown surface '" .. tostring(surface) .. "'")
                    check(type(value) == "number" and value >= 0 and value <= 1,
                        tilesetWhere .. ".heightMapScale." .. tostring(surface) .. " must be 0..1")
                end
            end
            if tileset.heightMapOperation ~= nil then
                check(tileset.heightMapOperation == "add"
                        or tileset.heightMapOperation == "replace"
                        or tileset.heightMapOperation == "none",
                    tilesetWhere .. ".heightMapOperation must be add, replace or none")
            end
        end
        local featureIds = {}
        for _, feature in ipairs(tileset.features or {}) do featureIds[feature.id] = true end
        local prefabIds = {}
        for pi, prefab in ipairs(tileset.fixturePrefabs or {}) do
            local where = "tileset '" .. tostring(tilesetId) .. "' fixturePrefabs[" .. pi .. "]"
            check(type(prefab.id) == "string" and prefab.id ~= "", where .. " needs a non-empty id")
            if type(prefab.id) == "string" then
                check(not prefabIds[prefab.id], where .. " duplicates prefab id '" .. prefab.id .. "'")
                prefabIds[prefab.id] = true
            end
            validateFixturePredicate(prefab.where, where .. ".where", featureIds)
            if prefab.probability ~= nil then
                local range = prefab.probability
                check(type(range) == "table", where .. ".probability must be an object")
                if type(range) == "table" then
                    local min, max, default = range.min or 0, range.max or 1, range.default
                    check(type(min) == "number" and min >= 0 and min <= 1,
                        where .. ".probability.min must be between 0 and 1")
                    check(type(max) == "number" and max >= 0 and max <= 1,
                        where .. ".probability.max must be between 0 and 1")
                    check(type(min) ~= "number" or type(max) ~= "number" or min <= max,
                        where .. ".probability min exceeds max")
                    check(default == nil or (type(default) == "number"
                            and type(min) == "number" and type(max) == "number"
                            and default >= min and default <= max),
                        where .. ".probability.default must be inside min/max")
                end
            end
        end
        local pools = {
            walls = tileset.base and tileset.base.walls,
            floors = tileset.base and tileset.base.floors,
            ceilings = tileset.base and tileset.base.ceilings,
            doors = tileset.doors,
            features = tileset.features,
        }
        for poolName, pool in pairs(pools) do
            for vi, variant in ipairs(pool or {}) do
                local where = "tileset '" .. tostring(tilesetId) .. "' "
                    .. poolName .. "[" .. vi .. "]"
                check(type(variant.weight or 1) == "number" and (variant.weight or 1) > 0,
                    where .. " weight must be a positive number")
                if poolName == "features" then
                    check(variant.role == "wall_feature" or variant.role == "floor_feature",
                        where .. " role must be wall_feature or floor_feature")
                    check(type(variant.injectProbability or 0.1) == "number"
                            and (variant.injectProbability or 0.1) >= 0
                            and (variant.injectProbability or 0.1) <= 1,
                        where .. " injectProbability must be between 0 and 1")
                    check(variant.requiresAdjacentFloor == nil,
                        where .. " uses removed requiresAdjacentFloor; author where.adjacent instead")
                    check(not (variant.prefab ~= nil and variant.where ~= nil),
                        where .. " cannot author both prefab and where")
                    if variant.prefab ~= nil then
                        check(type(variant.prefab) == "string" and prefabIds[variant.prefab] == true,
                            where .. " references unknown fixture prefab '"
                                .. tostring(variant.prefab) .. "'")
                        local prefab
                        for _, candidate in ipairs(tileset.fixturePrefabs or {}) do
                            if candidate.id == variant.prefab then prefab = candidate break end
                        end
                        local range = prefab and prefab.probability
                        if range and variant.injectProbability ~= nil then
                            check(variant.injectProbability >= (range.min or 0)
                                    and variant.injectProbability <= (range.max or 1),
                                where .. " injectProbability is outside prefab range")
                        end
                    end
                    if variant.where ~= nil then
                        validateFixturePredicate(variant.where, where .. ".where", featureIds)
                    end
                    if variant.emitsLight then
                        check(type(variant.emitsLight.color) == "table"
                                and #variant.emitsLight.color == 3,
                            where .. " emitsLight needs an RGB color")
                        check(type(variant.emitsLight.radius) == "number"
                                and variant.emitsLight.radius > 0,
                            where .. " emitsLight radius must be positive")
                    end
                    if variant.blocksMovement ~= nil then
                        check(type(variant.blocksMovement) == "boolean",
                            where .. " blocksMovement must be true or false")
                        -- A wall fixture stands on a "#", which already blocks.
                        -- Accepting it there would be a flag that reads as
                        -- authoritative and does nothing.
                        check(variant.role ~= "wall_feature",
                            where .. " blocksMovement applies to floor fixtures;"
                                .. " a wall fixture already stands on a wall")
                    end
                    if variant.effect ~= nil then
                        check(type(variant.effect) == "string"
                                and variant.effect:match("%.efkefc$") ~= nil,
                            where .. " effect must name an .efkefc file")
                        check(type(variant.effect) ~= "string"
                                or love.filesystem.getInfo(variant.effect) ~= nil,
                            where .. " effect is missing (" .. tostring(variant.effect) .. ")")
                        check(variant.effectHeight == nil or type(variant.effectHeight) == "number",
                            where .. " effectHeight must be numeric")
                        check(variant.effectMagnification == nil
                                or (type(variant.effectMagnification) == "number"
                                    and variant.effectMagnification > 0),
                            where .. " effectMagnification must be positive")
                    end
                end
                check(variant.model == nil or variant.geometry == nil,
                    where .. " authors both model and geometry; a variant has one mesh source")
                if variant.geometry ~= nil then
                    -- Image-authored geometry compiles from a PNG pair at load.
                    -- Checking it here turns a malformed asset into a build
                    -- failure rather than a crash the first time a player walks
                    -- into the cell that uses it.
                    -- Base walls MAY carry geometry, unlike models: an
                    -- image-authored wall is the surface a fixture composes
                    -- onto, and without it there is nothing to compose into.
                    check(poolName == "doors" or poolName == "features"
                            or poolName == "walls" or poolName == "floors"
                            or poolName == "ceilings",
                        where .. " geometry is supported only for wall, floor, ceiling, door/opening or fixture variants")
                    if type(variant.geometry) ~= "string" then
                        check(false, where .. " geometry must name an asset directory")
                    else
                        local okGeometry, errGeometry = pcall(function()
                            local _, warnings = require("engine.geometry").check(variant.geometry)
                            for _, warning in ipairs(warnings) do
                                print("[validator] " .. warning)
                            end
                        end)
                        check(okGeometry, where .. " geometry is invalid: " .. tostring(errGeometry))
                    end
                elseif variant.model ~= nil then
                    check(poolName == "doors" or poolName == "features",
                        where .. " model is currently supported only for door/opening or fixture variants")
                    check(type(variant.model) == "string" and variant.model:match("%.obj$") ~= nil,
                        where .. " model must name an .obj file")
                    check(type(variant.model) ~= "string" or love.filesystem.getInfo(variant.model) ~= nil,
                        where .. " model is missing (" .. tostring(variant.model) .. ")")
                elseif poolName == "walls" then
                    check(type(variant.middle) == "table" and #variant.middle >= 2,
                        where .. " needs middle atlas coordinates or model")
                else
                    check(type(variant.atlas) == "table" and #variant.atlas >= 2,
                        where .. " needs atlas coordinates or model")
                end
            end
        end
    end

    local dungeonConfig = loader.system and loader.system.dungeon or {}
    local generationProfiles = dungeonConfig.generationProfiles or {}
    check(type(dungeonConfig.generationProfile) == "string"
            and generationProfiles[dungeonConfig.generationProfile] ~= nil,
        "system.dungeon.generationProfile must reference a generation profile")
    for profileId, profile in pairs(generationProfiles) do
        local where = "system.dungeon.generationProfiles." .. tostring(profileId)
        check(type(profile.minRooms) == "number" and profile.minRooms >= 1,
            where .. ".minRooms must be at least 1")
        check(type(profile.maxRooms) == "number" and type(profile.minRooms) == "number"
                and profile.maxRooms >= profile.minRooms,
            where .. ".maxRooms must be at least minRooms")
        check(type(profile.minRoomSize) == "number" and profile.minRoomSize >= 3,
            where .. ".minRoomSize must be at least 3")
        check(type(profile.maxRoomSize) == "number" and type(profile.minRoomSize) == "number"
                and profile.maxRoomSize >= profile.minRoomSize,
            where .. ".maxRoomSize must be at least minRoomSize")
    end

    for mi, map in ipairs(loader.maps or {}) do
        for _, removed in ipairs({ "genMinRooms", "genMaxRooms", "genMinRoomSize", "genMaxRoomSize" }) do
            check(map[removed] == nil,
                "map[" .. mi .. "] uses removed " .. removed .. "; select generationProfile instead")
        end
        if map.generationProfile ~= nil then
            check(type(map.generationProfile) == "string"
                    and generationProfiles[map.generationProfile] ~= nil,
                "map[" .. mi .. "] references unknown generationProfile '"
                    .. tostring(map.generationProfile) .. "'")
        end
        -- Ambient (map-level, camera-following) weather. Checked exactly like a
        -- tileset variant's effect: the .efkefc is opaque to G1, so the
        -- REFERENCE is what gets validated. A typo would otherwise be weather
        -- that silently never plays on one map.
        if map.ambientEffect ~= nil then
            local ambient = map.ambientEffect
            local owner = "map[" .. mi .. "].ambientEffect"
            check(type(ambient) == "table", owner .. " must be an object")
            if type(ambient) == "table" then
                for key in pairs(ambient) do
                    check(key == "effect" or key == "height" or key == "magnification",
                        owner .. " has unknown field '" .. tostring(key) .. "'")
                end
                check(type(ambient.effect) == "string"
                        and ambient.effect:match("%.efkefc$") ~= nil,
                    owner .. ".effect must name an .efkefc file")
                check(type(ambient.effect) ~= "string"
                        or love.filesystem.getInfo(ambient.effect) ~= nil,
                    owner .. ".effect is missing (" .. tostring(ambient.effect) .. ")")
                check(ambient.height == nil or type(ambient.height) == "number",
                    owner .. ".height must be numeric")
                check(ambient.magnification == nil
                        or (type(ambient.magnification) == "number"
                            and ambient.magnification > 0),
                    owner .. ".magnification must be positive")
            end
        end
        if map.tilesetOverride ~= nil then
            local delta = map.tilesetOverride
            local owner = "map[" .. mi .. "].tilesetOverride"
            check(type(delta) == "table", owner .. " must be an object")
            if type(delta) == "table" then
                local allowed = { features = true, doors = true, fixturePrefabs = true, base = true }
                for key in pairs(delta) do
                    check(allowed[key] == true, owner .. " has unknown field '" .. tostring(key) .. "'")
                end
                local baseTileset = loader.getTileset(map.tileset)
                local function validateDeltaPool(patches, basePool, where)
                    check(type(patches) == "table", where .. " must be an array")
                    if type(patches) ~= "table" then return end
                    local baseIds, seen = {}, {}
                    for _, entry in ipairs(basePool or {}) do baseIds[entry.id] = true end
                    for i, entry in ipairs(patches) do
                        local item = where .. "[" .. i .. "]"
                        check(type(entry) == "table", item .. " must be an object")
                        if type(entry) == "table" then
                            check(type(entry.id) == "string" and entry.id ~= "", item .. " needs an id")
                            if type(entry.id) == "string" then
                                check(not seen[entry.id], item .. " duplicates id '" .. entry.id .. "'")
                                seen[entry.id] = true
                            end
                            if entry.remove == true then
                                check(baseIds[entry.id] == true,
                                    item .. " cannot remove missing base id '" .. tostring(entry.id) .. "'")
                                for key in pairs(entry) do
                                    check(key == "id" or key == "remove",
                                        item .. " remove entry cannot also author '" .. tostring(key) .. "'")
                                end
                            else
                                check(entry.remove == nil, item .. ".remove must be true or omitted")
                            end
                        end
                    end
                end
                if delta.features ~= nil then
                    validateDeltaPool(delta.features, baseTileset and baseTileset.features,
                        owner .. ".features")
                end
                if delta.doors ~= nil then
                    validateDeltaPool(delta.doors, baseTileset and baseTileset.doors,
                        owner .. ".doors")
                end
                if delta.fixturePrefabs ~= nil then
                    validateDeltaPool(delta.fixturePrefabs, baseTileset and baseTileset.fixturePrefabs,
                        owner .. ".fixturePrefabs")
                end
                if delta.base ~= nil then
                    check(type(delta.base) == "table", owner .. ".base must be an object")
                    if type(delta.base) == "table" then
                        local allowedBase = { walls = true, floors = true, ceilings = true, skies = true }
                        for key in pairs(delta.base) do
                            check(allowedBase[key] == true,
                                owner .. ".base has unknown field '" .. tostring(key) .. "'")
                        end
                        for _, pool in ipairs({ "walls", "floors", "ceilings", "skies" }) do
                            if delta.base[pool] ~= nil then
                                validateDeltaPool(delta.base[pool],
                                    baseTileset and baseTileset.base and baseTileset.base[pool],
                                    owner .. ".base." .. pool)
                            end
                        end
                    end
                end

                local resolved = require("engine.tileset_resolver").resolve(loader, map)
                local prefabIds, resolvedFeatureIds = {}, {}
                for _, feature in ipairs((resolved and resolved.features) or {}) do
                    resolvedFeatureIds[feature.id] = true
                end
                for pi, prefab in ipairs((resolved and resolved.fixturePrefabs) or {}) do
                    local where = owner .. " resolved fixturePrefabs[" .. pi .. "]"
                    check(type(prefab.id) == "string" and prefab.id ~= "", where .. " needs an id")
                    if type(prefab.id) == "string" then
                        check(not prefabIds[prefab.id], where .. " duplicates id '" .. prefab.id .. "'")
                        prefabIds[prefab.id] = true
                    end
                    validateFixturePredicate(prefab.where, where .. ".where", resolvedFeatureIds)
                    if prefab.probability ~= nil then
                        local range = prefab.probability
                        check(type(range) == "table", where .. ".probability must be an object")
                        if type(range) == "table" then
                            local min, max, default = range.min or 0, range.max or 1, range.default
                            check(type(min) == "number" and min >= 0 and min <= 1,
                                where .. ".probability.min must be between 0 and 1")
                            check(type(max) == "number" and max >= 0 and max <= 1,
                                where .. ".probability.max must be between 0 and 1")
                            check(type(min) ~= "number" or type(max) ~= "number" or min <= max,
                                where .. ".probability min exceeds max")
                            check(default == nil or (type(default) == "number"
                                    and type(min) == "number" and type(max) == "number"
                                    and default >= min and default <= max),
                                where .. ".probability.default must be inside min/max")
                        end
                    end
                end
                for fi, feature in ipairs((resolved and resolved.features) or {}) do
                    local where = owner .. " resolved features[" .. fi .. "]"
                    check(feature.role == "wall_feature" or feature.role == "floor_feature",
                        where .. " role must be wall_feature or floor_feature")
                    check(type(feature.injectProbability or 0.1) == "number"
                            and (feature.injectProbability or 0.1) >= 0
                            and (feature.injectProbability or 0.1) <= 1,
                        where .. " injectProbability must be between 0 and 1")
                    check(not (feature.prefab ~= nil and feature.where ~= nil),
                        where .. " cannot author both prefab and where")
                    if feature.prefab ~= nil then
                        check(prefabIds[feature.prefab] == true,
                            where .. " references unknown fixture prefab '"
                                .. tostring(feature.prefab) .. "'")
                    elseif feature.where ~= nil then
                        validateFixturePredicate(feature.where, where .. ".where", resolvedFeatureIds)
                    end
                    check(feature.model ~= nil or (type(feature.atlas) == "table" and #feature.atlas >= 2),
                        where .. " needs atlas coordinates or model")
                end
            end
        end
        for zi, zone in ipairs(map.zones or {}) do
            local where = "map[" .. mi .. "] zone[" .. zi .. "]"
            local tags = zone.tags or { zone.id }
            check(type(tags) == "table" and #tags > 0, where .. " requires id or non-empty tags")
            for ti, tag in ipairs(tags) do
                check(type(tag) == "string" and tag ~= "", where .. " tag[" .. ti .. "] must be non-empty")
            end
            if zone.cells ~= nil then
                check(type(zone.cells) == "table" and #zone.cells > 0,
                    where .. ".cells must be a non-empty array")
                for ci, cell in ipairs(zone.cells or {}) do
                    check(type(cell.x) == "number" and type(cell.y) == "number",
                        where .. ".cells[" .. ci .. "] requires numeric x/y")
                end
                check(zone.x == nil and zone.y == nil and zone.width == nil and zone.height == nil,
                    where .. " cannot combine cells with rectangle fields")
            else
                check(type(zone.x) == "number" and type(zone.y) == "number"
                        and type(zone.width) == "number" and zone.width > 0
                        and type(zone.height) == "number" and zone.height > 0,
                    where .. " rectangle requires numeric x/y and positive width/height")
            end
        end
    end

    -- Run the tree walker over all data files
    for _, map in ipairs(loader.maps or {}) do
        check(map.generateOpenings == nil or type(map.generateOpenings) == "boolean",
            "map '" .. tostring(map.name) .. "' generateOpenings must be boolean")
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
                if tsDef.skyPanorama then
                    local skyName = tostring(tsDef.skyPanorama):gsub("^assets/panorama/", ""):gsub("%.png$", "")
                    local skyPath = "assets/panorama/" .. skyName .. ".png"
                    check(love.filesystem.getInfo(skyPath) ~= nil,
                        "map '" .. tostring(map.name) .. "' tileset '" .. tostring(map.tileset)
                        .. "' sky panorama missing (" .. skyPath .. ")")
                end
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
            -- A wall event renders into the wall slice it occupies, so it only
            -- makes sense sitting on a wall cell of a fixed (non-procedural)
            -- layout; procedural dungeons regenerate their grid at runtime
            -- so authored positions can't be checked against it here.
            if ev.wallEvent and map.layout then
                local row = map.layout[ev.y + 1]
                local cell = row and row:sub(ev.x + 1, ev.x + 1)
                check(cell == "#", desc .. " is a wall event but its map cell is not a wall ('" .. tostring(cell) .. "')")
                check(ev.trigger == "bump",
                    desc .. " is wall-bound and must use trigger 'bump'")
                check(type(ev.sprite) == "string" and ev.sprite ~= ""
                        and love.filesystem.getInfo(ev.sprite) ~= nil,
                    desc .. " references missing wall-event sprite '" .. tostring(ev.sprite) .. "'")
            end
            if ev.commands then
                validateCommands(ev.commands, "map", false, true, desc)
            end
            -- Event pages carry their own command overrides; each is a full
            -- command tree and validates exactly like the base list.
            for pi, page in ipairs(ev.pages or {}) do
                if page.commands then
                    validateCommands(page.commands, "map", false, true, desc .. " page " .. pi)
                end
            end
        end

        local function validateDenseArray(tbl, desc)
            check(type(tbl) == "table", desc .. " must be a table")
            if type(tbl) ~= "table" then return 0 end
            local count = 0
            for key in pairs(tbl) do
                check(type(key) == "number" and key >= 1 and key == math.floor(key),
                    desc .. " must contain only positive integer indices")
                count = count + 1
            end
            for i = 1, count do
                check(tbl[i] ~= nil, desc .. " is sparse at index " .. i)
            end
            return count
        end

        -- Map treasures validation
        if map.treasures ~= nil then
            local tCount = validateDenseArray(map.treasures, "map '" .. tostring(map.name) .. "'.treasures")
            for ti = 1, tCount do
                local itemId = map.treasures[ti]
                check(loader.getItem(itemId) ~= nil,
                    "map '" .. tostring(map.name) .. "'.treasures[" .. ti .. "] references unknown item '" .. tostring(itemId) .. "'")
            end
        end

        local KNOWN_FOCUS_PRESETS = { low_prop = true }
        local function validatePresentation(pres, ownerDesc)
            if pres.model ~= nil and pres.model ~= false then
                check(type(pres.model) == "string" and pres.model ~= "", ownerDesc .. ".model must be a non-empty string or false")
                if type(pres.model) == "string" and pres.model ~= "" then
                    check(pres.model:sub(-4) == ".obj", ownerDesc .. ".model '" .. pres.model .. "' must be a .obj file")
                    check(love.filesystem.getInfo(pres.model) ~= nil, ownerDesc .. ".model is missing (" .. pres.model .. ")")
                end
            end
            if pres.interactionFocus ~= nil and pres.interactionFocus ~= false then
                local kind = nil
                if type(pres.interactionFocus) == "string" then
                    kind = pres.interactionFocus
                elseif type(pres.interactionFocus) == "table" then
                    kind = pres.interactionFocus.kind
                end
                check(kind ~= nil and KNOWN_FOCUS_PRESETS[kind] == true,
                    ownerDesc .. ".interactionFocus specifies unknown preset '" .. tostring(kind) .. "'")
            end
        end

        for _, ev in ipairs(map.events or {}) do
            local desc = "map '" .. tostring(map.name) .. "' event (" .. tostring(ev.x) .. "," .. tostring(ev.y) .. ")"
            validatePresentation(ev, desc)
            for pi, page in ipairs(ev.pages or {}) do
                validatePresentation(page, desc .. " page " .. pi)
            end
        end

        -- Registry-driven command scanner for CHANGE_ITEM random loot
        local cmdDefsById = {}
        for _, def in ipairs((loader.engine and loader.engine.commands) or {}) do
            cmdDefsById[def.id] = def
        end

        local function commandListHasRandomLoot(cmds, visitedCEs)
            if not cmds or type(cmds) ~= "table" then return false end
            for _, cmd in ipairs(cmds) do
                if cmd.cmd == "CHANGE_ITEM" and cmd.item == "random" then return true end

                if cmd.scriptId or cmd.commonEventId or cmd.cmd == "CALL_COMMON_EVENT" then
                    local ceId = tostring(cmd.commonEventId or cmd.scriptId)
                    if ceId and not visitedCEs[ceId] then
                        visitedCEs[ceId] = true
                        local ce = loader.commonEvents and loader.commonEvents[ceId]
                        if ce and ce.commands and commandListHasRandomLoot(ce.commands, visitedCEs) then return true end
                    end
                end

                local def = cmdDefsById[cmd.cmd]
                if def and def.params then
                    for _, pdef in ipairs(def.params) do
                        if pdef.type == "commands" then
                            local val = cmd[pdef.key]
                            if cmd.cmd == "CHOICE" and type(val) == "table" then
                                for _, opt in ipairs(val) do
                                    if opt.commands and commandListHasRandomLoot(opt.commands, visitedCEs) then return true end
                                end
                            elseif type(val) == "table" then
                                if commandListHasRandomLoot(val, visitedCEs) then return true end
                            end
                        end
                    end
                else
                    for key, val in pairs(cmd) do
                        if key == "options" and type(val) == "table" then
                            for _, opt in ipairs(val) do
                                if opt.commands and commandListHasRandomLoot(opt.commands, visitedCEs) then return true end
                            end
                        elseif type(val) == "table" and val[1] and type(val[1]) == "table" and val[1].cmd then
                            if commandListHasRandomLoot(val, visitedCEs) then return true end
                        end
                    end
                end
            end
            return false
        end

        local function eventHasRandomLoot(ev, visitedCEs)
            if ev.commands and commandListHasRandomLoot(ev.commands, visitedCEs) then return true end
            for _, page in ipairs(ev.pages or {}) do
                if page.commands and commandListHasRandomLoot(page.commands, visitedCEs) then return true end
                if page.scriptId then
                    local ceId = tostring(page.scriptId)
                    if not visitedCEs[ceId] then
                        visitedCEs[ceId] = true
                        local ce = loader.commonEvents and loader.commonEvents[ceId]
                        if ce and ce.commands and commandListHasRandomLoot(ce.commands, visitedCEs) then return true end
                    end
                end
            end
            if ev.scriptId then
                local ceId = tostring(ev.scriptId)
                if not visitedCEs[ceId] then
                    visitedCEs[ceId] = true
                    local ce = loader.commonEvents and loader.commonEvents[ceId]
                    if ce and ce.commands and commandListHasRandomLoot(ce.commands, visitedCEs) then return true end
                end
            end
            return false
        end

        local mapHasRandomLoot = false
        for _, ev in ipairs(map.events or {}) do
            if eventHasRandomLoot(ev, {}) then
                mapHasRandomLoot = true
                break
            end
        end
        if mapHasRandomLoot then
            check(type(map.treasures) == "table" and #map.treasures > 0,
                "map '" .. tostring(map.name) .. "' uses CHANGE_ITEM item: 'random' but has missing or empty treasures array")
        end
    end

    for ceId, ce in pairs(loader.commonEvents or {}) do
        local desc = "common event '" .. tostring(ceId) .. "'"
        if ce.model ~= nil and ce.model ~= false then
            check(type(ce.model) == "string" and ce.model ~= "", desc .. ".model must be a non-empty string or false")
            if type(ce.model) == "string" and ce.model ~= "" then
                check(ce.model:sub(-4) == ".obj", desc .. ".model '" .. ce.model .. "' must be a .obj file")
                check(love.filesystem.getInfo(ce.model) ~= nil, desc .. ".model is missing (" .. ce.model .. ")")
            end
        end
        if ce.interactionFocus ~= nil and ce.interactionFocus ~= false then
            local kind = nil
            if type(ce.interactionFocus) == "string" then kind = ce.interactionFocus
            elseif type(ce.interactionFocus) == "table" then kind = ce.interactionFocus.kind end
            check(kind ~= nil and ({ low_prop = true })[kind] == true,
                desc .. ".interactionFocus specifies unknown preset '" .. tostring(kind) .. "'")
        end
        if ce.commands then
            validateCommands(ce.commands, "common", false, true, "common event '" .. tostring(ceId) .. "'")
            local labels, skips = {}, {}
            local function scanSkipTargets(cmds)
                for _, cmd in ipairs(cmds or {}) do
                    if cmd.cmd == "LABEL" then labels[cmd.name] = true end
                    if cmd.cmd == "ENABLE_EVENT_SKIP" then
                        skips[#skips + 1] = cmd.label
                    end
                    for key, val in pairs(cmd) do
                        if key == "options" and type(val) == "table" then
                            for _, opt in ipairs(val) do scanSkipTargets(opt.commands) end
                        elseif type(val) == "table" and val[1]
                            and type(val[1]) == "table" and val[1].cmd then
                            scanSkipTargets(val)
                        end
                    end
                end
            end
            scanSkipTargets(ce.commands)
            for _, label in ipairs(skips) do
                check(labels[label] == true,
                    "common event '" .. tostring(ceId)
                    .. "' enables skip to missing LABEL '" .. tostring(label) .. "'")
            end
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
            battle = { round = 1 },
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
                { cmd = "TEXT", text = "before" },
                { cmd = "SET_VAR", name = "n", value = "2 + 3" },
                { cmd = "COMMENT", text = "swallowed into the run" },
                { cmd = "IF", condition = "v.n == 5", ["then"] = {
                    { cmd = "GAIN_GOLD", amount = "v.n" },
                    { cmd = "EMIT_TEXT", fallback = "bridge ran" },
                } },
                { cmd = "TEXT", text = "after" },
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
    -- round_end, flee_attempt and battle_start joined this list on 26.07.2026,
    -- when the last three `if flow.has(phase) then ... else <legacy Lua> end`
    -- fallbacks were deleted. With nothing to fall back to, a missing phase
    -- would silently skip every end-of-round tick, make fleeing impossible, or
    -- spawn an encounter with no enemies -- all quiet, all worse than failing.
    for _, phase in ipairs({ "battle.victory", "battle.defeat", "battle.escaped", "battle.encounter_check",
        "battle.round_end", "battle.flee_attempt", "battle.battle_start",
        -- round_start and after_action are how a troop acts at the top of a
        -- round or the instant a blow lands. They are required for the same
        -- reason as the rest: missing, they would skip every troop event
        -- declared at them, silently.
        "battle.round_start", "battle.after_action", "exploration.step" }) do
        check(flow.has(phase), "flows.json is missing required phase '" .. phase .. "'")
        if flow.has(phase) then
            local s = session.GameSession.new(loader)
            s:initializeStartingParty()
            for _, c in ipairs(s.party) do c.hp = math.max(1, math.floor(c:getMaxHp(s) / 2)) end
            local okPhase, phaseErr = pcall(flow.run, phase, {
                session = s, party = s.party, enemies = {}, battle = { round = 1 }
            })
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

        for _, scene in ipairs(loader.scenes or {}) do
            local sceneDesc = "scene '" .. tostring(scene.id) .. "' (" .. tostring(scene.name) .. ")"
            if scene.backdropImage then
                check(love.filesystem.getInfo(scene.backdropImage) ~= nil,
                    sceneDesc .. " references missing backdropImage '"
                    .. tostring(scene.backdropImage) .. "'")
            end

            -- One mock context per scene, its `v` seeded from what THIS
            -- scene assigns. Hooks share a single v for the scene's whole
            -- lifetime (engine/scene_host.lua), so the seed is the union
            -- over every hook -- on_input formulas legitimately read what
            -- on_enter set -- plus the scene's named SCRIPT bodies and
            -- whatever a SCENE_EVENT pushes in. on_enter comes first (it is
            -- the initializer scene_host runs before any input hook) and the
            -- rest in sorted order, so the seed never depends on pairs()
            -- iteration order.
            local sceneAssigned = {}
            for _, a in ipairs(scenePushedVars[tostring(scene.id)] or {}) do
                table.insert(sceneAssigned, a)
            end
            local hookNames = {}
            for hookName in pairs(scene.hooks or {}) do
                if hookName ~= "on_enter" then table.insert(hookNames, hookName) end
            end
            table.sort(hookNames)
            if (scene.hooks or {}).on_enter then table.insert(hookNames, 1, "on_enter") end
            for _, hookName in ipairs(hookNames) do
                collectAssignedVars(scene.hooks[hookName], sceneAssigned)
            end
            local scriptNames = {}
            for name in pairs(scene.scripts or {}) do table.insert(scriptNames, name) end
            table.sort(scriptNames)
            for _, name in ipairs(scriptNames) do
                collectScriptAssignedVars(scene.scripts[name], sceneAssigned)
            end
            local sceneSeeds = resolveSeedVars(sceneAssigned, collectTableShapedVars(scene))
            local mockCtx = buildFormulaMockCtx(sceneSeeds)

            -- Every scene must declare how it draws (the legacy "no flag =
            -- fall back to Lua drawing" rule was purged 24.07.2026), and a
            -- world scene's `world` id must be one the world renderer knows.
            check(scene.draw == "windows" or scene.draw == "world",
                sceneDesc .. " must declare draw = \"windows\" or \"world\" (got '"
                .. tostring(scene.draw) .. "')")
            if scene.draw == "world" then
                local worldIds = {}
                for _, id in ipairs(require("presentation.world_renderer").ids()) do
                    worldIds[id] = true
                end
                check(worldIds[scene.world],
                    sceneDesc .. " declares unknown world '" .. tostring(scene.world) .. "'")
            end

            -- Generic config validation (D13): no scene-kind-specific checks.
            -- Any config key ending in "Formula" whose value is a string must
            -- compile against the mock scene context.
            for key, val in pairs(scene.config or {}) do
                if type(val) == "string" and key:match("Formula$") then
                    local ok, _, ferr = pcall(formulaEngine.eval, val, mockCtx)
                    check(ok and ferr == nil, sceneDesc .. " config." .. key .. " failed to compile: " .. tostring(ferr or ""))
                end
            end
            if scene.id == "map" then
                local fieldCommands = (scene.config or {}).fieldCommands
                check(type(fieldCommands) == "table" and #fieldCommands <= 5,
                    sceneDesc .. " config.fieldCommands must contain at most five main-menu commands")
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
                        local id = cmd.cmd
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
                    validateCommands(cmds, "scene", true, allowSceneScript, sceneDesc .. " hook '" .. tostring(hookName) .. "'", sceneSeeds)
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
                                -- Row formulas evaluated per row: they cannot be
                                -- compiled here (the mock context has no row
                                -- fields), but a non-string is a silent no-op --
                                -- `filter: true` would drop nothing while reading
                                -- as if it filtered.
                                for _, rowKey in ipairs({ "filter", "priority", "highlight" }) do
                                    if block[rowKey] ~= nil then
                                        check(type(block[rowKey]) == "string",
                                            sceneDesc .. " windows[" .. wi .. "] '" .. tostring(winDef.id) .. "' content[" .. bi .. "] list block: '" .. rowKey .. "' must be a string expression")
                                    end
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
        effekseer = true,
    }

    -- The one constant normalising the effect library's authoring scale to
    -- canvas pixels. A zero or negative value would collapse every effect at
    -- once, which is exactly the sort of invisible whole-system breakage the
    -- validator exists to turn into a build failure.
    local efkCfg = (loader.engine or {}).effekseer
    if efkCfg ~= nil then
        check(type(efkCfg) == "table", "engine.effekseer must be a table")
        if type(efkCfg) == "table" then
            check(efkCfg.magnification == nil
                or (type(efkCfg.magnification) == "number" and efkCfg.magnification > 0),
                "engine.effekseer.magnification must be a positive number (got "
                .. tostring(efkCfg.magnification) .. ")")
            -- Both are allocated eagerly at init, so a typo here is startup
            -- memory rather than a gradual slowdown: instanceMax costs ~2.2KB
            -- per slot (a million slots is 2.4GB) and squareMaxCount sizes a
            -- vertex buffer at 4 * 88 bytes per square.
            for _, field in ipairs({ "instanceMax", "squareMaxCount" }) do
                local value = efkCfg[field]
                check(value == nil
                    or (type(value) == "number" and value > 0 and value == math.floor(value)),
                    "engine.effekseer." .. field
                        .. " must be a positive whole number (got "
                        .. tostring(value) .. ")")
            end
        end
    end

    -- An `effekseer` track names an external .efk asset. The FILE is opaque to
    -- the validator, exactly as a PNG is (SPEC: effects are assets, not data),
    -- but the REFERENCE is ours to check: a typo would otherwise become an
    -- effect that silently never plays, which is the outcome the
    -- non-negotiables call the worst one.
    for id, entry in pairs(loader.animations or {}) do
        for ti, track in ipairs((type(entry) == "table" and entry.tracks) or {}) do
            if type(track) == "table" and track.type == "effekseer" then
                check(type(track.effect) == "string" and track.effect ~= "",
                    "animation system: entry '" .. tostring(id) .. "' track " .. ti
                    .. " is an effekseer track with no `effect` path")
                if type(track.effect) == "string" and track.effect ~= "" then
                    check(love.filesystem.getInfo(track.effect) ~= nil,
                        "animation system: entry '" .. tostring(id) .. "' track " .. ti
                        .. " references missing effect file '" .. tostring(track.effect) .. "'")
                end
                check(track.magnification == nil or type(track.magnification) == "number",
                    "animation system: entry '" .. tostring(id) .. "' track " .. ti
                    .. " magnification must be a number")
            end
        end
    end
    -- Anchor spec (every entry, not just system ones): the drawer RAISES on an
    -- unknown point rather than quietly centering, so an authoring typo must be
    -- a build failure instead of a crash the first time the animation plays.
    local battler_geometry = require("presentation.battler_geometry")
    for id, entry in pairs(loader.animations or {}) do
        local anchor = entry.anchor
        if anchor ~= nil then
            check(type(anchor) == "table",
                "animation system: entry '" .. tostring(id) .. "' anchor must be a table")
            if type(anchor) == "table" then
                check(anchor.point == nil or battler_geometry.ANCHOR_POINTS[anchor.point],
                    "animation system: entry '" .. tostring(id) .. "' has unknown anchor point '"
                    .. tostring(anchor.point) .. "' (expected center, feet, head or top_left)")
                for _, field in ipairs({ "offsetX", "offsetY", "relativeOffsetX", "relativeOffsetY" }) do
                    check(anchor[field] == nil or type(anchor[field]) == "number",
                        "animation system: entry '" .. tostring(id) .. "' anchor." .. field
                        .. " must be a number")
                end
            end
        end
    end

    -- The battleLayout anchor defaults are authored data too, and reach the
    -- same resolver: an invalid point here breaks every animation at once.
    local battleLayout = (loader.engine or {}).battleLayout or {}
    for _, key in ipairs({ "popupAnchorPoint", "animationAnchorPoint" }) do
        local point = battleLayout[key]
        check(point == nil or battler_geometry.ANCHOR_POINTS[point],
            "battleLayout." .. key .. " is '" .. tostring(point)
            .. "' (expected center, feet, head or top_left)")
    end

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
                    -- `effekseer` is exempt from `duration`: the track is a
                    -- one-shot spawn at t0 and the Effekseer runtime owns the
                    -- effect's lifetime thereafter. A duration here would be a
                    -- number nothing reads -- worse than absent, because it
                    -- would read as authoritative.
                    if track.type ~= "effekseer" then
                        check(type(track.duration) == "number",
                            "animation system: entry '" .. tostring(id) .. "' track " .. ti .. " missing numeric duration")
                    end
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
