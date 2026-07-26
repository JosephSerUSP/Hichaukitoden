-- Generated ground truth: `lovec . engine-state` writes docs/ENGINE-STATE.md,
-- a machine-produced inventory of what the engine and data actually contain
-- right now. G4 (tools/golden/check-state.ps1) regenerates it and fails on any
-- diff, so this file can never silently rot the way hand-written prose does.
--
-- Why this exists: on 24.07.2026 four separate design/spec documents asserted
-- implementation facts that had become false (battle "frozen" on the legacy
-- renderer, permadeath "not implemented", Item Creation "quite early", the
-- validator's location), which cost an agent a full wasted planning pass.
-- Prose describes INTENT; this file reports STATE. Never hand-edit it.
--
-- The report is deliberately ASCII-only: it is byte-compared by both a
-- PowerShell and a bash gate, and PowerShell 5.1 reads files in the system
-- ANSI codepage by default, so any em dash or multiplication sign here would
-- make G4 fail on Windows for encoding reasons alone.
local engine_state = {}

-- Source trees scanned for "is this registry entry actually referenced by
-- code?" checks. A declared-but-unreferenced trait/effect/command is the
-- specific failure mode that let ON_PERMADEATH sit dead for months while a
-- passive advertised it in-game.
local SOURCE_DIRS = { "engine", "presentation", "data" }
local SOURCE_FILES = { "main.lua" }

local function readSources()
    local blobs = {}
    for _, dir in ipairs(SOURCE_DIRS) do
        for _, name in ipairs(love.filesystem.getDirectoryItems(dir)) do
            local path = dir .. "/" .. name
            local info = love.filesystem.getInfo(path)
            if info and info.type == "file" and name:match("%.lua$") then
                local body = love.filesystem.read(path)
                if body then blobs[path] = body end
            elseif info and info.type == "directory" then
                for _, sub in ipairs(love.filesystem.getDirectoryItems(path)) do
                    if sub:match("%.lua$") then
                        local body = love.filesystem.read(path .. "/" .. sub)
                        if body then blobs[path .. "/" .. sub] = body end
                    end
                end
            end
        end
    end
    for _, path in ipairs(SOURCE_FILES) do
        local body = love.filesystem.read(path)
        if body then blobs[path] = body end
    end
    return blobs
end

-- Behavior-carrying data: flows and scenes hold command lists, formulas and
-- SCRIPT bodies, so a registry entry consumed there IS implemented -- just in
-- data rather than Lua (POST_BATTLE_HEAL is read by a battle flow, for
-- instance). Everything else under data/ (passives, items, actors, states) only
-- ASSIGNS a code to content, which is not an implementation.
-- Anything holding command lists counts: flows (phase logic), scenes (hooks and
-- SCRIPT bodies), common events, and maps (their events carry command trees).
-- Missing commonEvents.json here once made RECOVERY_XP_BONUS report as dead
-- immediately after it was implemented in the shared recovery event.
local IMPL_DATA_FILES = { "data/flows.json", "data/scenes.json", "data/engine.json",
    "data/commonEvents.json", "data/maps.json" }
local ASSIGN_DATA_FILES = {
    "data/passives.json", "data/items.json", "data/actors.json",
    "data/states.json", "data/skills.json",
}

local function readJsonBlobs(paths)
    local blobs = {}
    for _, path in ipairs(paths) do
        local body = love.filesystem.read(path)
        if body then blobs[path] = body end
    end
    return blobs
end

local function appearsIn(blobs, needle, skipPath)
    for path, body in pairs(blobs) do
        if path ~= skipPath and body:find(needle, 1, true) then return true end
    end
    return false
end

-- `engine/traits.lua` PROVIDES trait lookups; it does not consume them. Its
-- getRate tail names HIT/EVA/CRI/HRG only to give them base values, so a code
-- mentioned solely there is read by nobody -- exactly the shape CRI had while
-- seven weapons advertised a critical rate that nothing ever rolled, and G4
-- reported "assigned: none" the whole time. Excluded for the same reason the
-- declaring registry file is: a definition is not a use.
--
-- Deliberately scoped to trait codes. effects.lua and interpreter.lua really do
-- implement their ids, so nothing equivalent applies to effect types or
-- commands.
local TRAIT_PROVIDER_FILES = { ["engine/traits.lua"] = true }

-- True when `needle` appears as a quoted string or a `.needle =` / `.needle(`
-- reference in Lua source. `skipFiles` drops provider modules from the scan.
local function referencedInCode(sources, needle, skipFiles)
    for path, body in pairs(sources) do
        if not (skipFiles and skipFiles[path]) then
            if body:find('"' .. needle .. '"', 1, true)
                or body:find("'" .. needle .. "'", 1, true)
                or body:find("%." .. needle .. "%s*=")
                or body:find("%." .. needle .. "%s*%(") then
                return true
            end
        end
    end
    return false
end

-- Classifies a registry id as "lua" (engine code implements it), "data"
-- (a flow/scene consumes it), "assigned" (content references it but nothing
-- implements it -- the actionable rot bucket) or "unused" (declared only).
local function classify(sources, implBlobs, assignBlobs, id, declaringFile, skipFiles)
    if referencedInCode(sources, id, skipFiles) then return "lua" end
    if appearsIn(implBlobs, id, declaringFile) then return "data" end
    if appearsIn(assignBlobs, id) then return "assigned" end
    return "unused"
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do table.insert(keys, tostring(k)) end
    table.sort(keys)
    return keys
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function engine_state.build(loader)
    local sources = readSources()
    local eng = loader.engine or {}
    local out = {}
    local function line(s) table.insert(out, s or "") end

    line("# Engine State (generated -- do not edit)")
    line()
    line("Produced by `lovec . engine-state` (`engine/engine_state.lua`) and gated")
    line("by G4 (`tools/golden/check-state.ps1`), which regenerates this file and")
    line("fails on any diff. This is the authority on **what exists**; `docs/SPEC.md`")
    line("is the authority on **why and how**. Hand edits will be overwritten and")
    line("will fail G4.")
    line()
    line("Campaign root: `" .. tostring(loader.root or "data") .. "`")
    line()

    -- ---------------------------------------------------------------- scenes
    line("## Scenes")
    line()
    line("Every scene must declare a draw mode (SPEC Sec.1.2); G1 enforces it.")
    line()
    line("| id | kind | draw | world | windows | hooks |")
    line("|---|---|---|---|---|---|")
    local scenes = {}
    for _, sc in ipairs(loader.scenes or {}) do table.insert(scenes, sc) end
    table.sort(scenes, function(a, b) return tostring(a.id) < tostring(b.id) end)
    for _, sc in ipairs(scenes) do
        line(("| `%s` | %s | %s | %s | %d | %d |"):format(
            tostring(sc.id), tostring(sc.kind or "-"), tostring(sc.draw or "**MISSING**"),
            tostring(sc.world or "-"), #(sc.windows or {}), countKeys(sc.hooks)))
    end
    line()

    -- -------------------------------------------------------------- registry
    line("## Registry (data/engine.json)")
    line()
    line(("- commands: **%d**"):format(#(eng.commands or {})))
    line(("- effect types: **%d**"):format(#(eng.effectTypes or {})))
    line(("- trait codes: **%d**"):format(#(eng.traitCodes or {})))
    line(("- meta keys: **%d** (%s)"):format(#(eng.metaKeys or {}),
        table.concat((function()
            local t = {}
            for _, m in ipairs(eng.metaKeys or {}) do table.insert(t, m.key) end
            return t
        end)(), ", ")))
    line()

    -- The rot detector. This is the check that would have caught ON_PERMADEATH
    -- sitting dead while the `rebirth` passive advertised it to players.
    local implBlobs = readJsonBlobs(IMPL_DATA_FILES)
    local assignBlobs = readJsonBlobs(ASSIGN_DATA_FILES)
    local buckets = {
        traitCodes = { assigned = {}, unused = {} },
        effectTypes = { assigned = {}, unused = {} },
        commands = { assigned = {}, unused = {} },
    }
    local function bucket(kind, id, skipFiles)
        local how = classify(sources, implBlobs, assignBlobs, id, "data/engine.json", skipFiles)
        if how == "assigned" or how == "unused" then
            table.insert(buckets[kind][how], id)
        end
    end
    for _, tc in ipairs(eng.traitCodes or {}) do
        bucket("traitCodes", tc.code, TRAIT_PROVIDER_FILES)
    end
    for _, et in ipairs(eng.effectTypes or {}) do bucket("effectTypes", et.id) end
    for _, c in ipairs(eng.commands or {}) do bucket("commands", c.id) end

    line("### Registry entries with no implementation")
    line()
    line("A registry id counts as implemented when Lua source references it OR a")
    line("flow/scene consumes it (behavior can live in data). The two lists below")
    line("are what's left:")
    line()
    line("- **assigned** -- content (a passive, item, actor...) references it, but")
    line("  nothing consumes it. **These lie to the player**: the passive shows up")
    line("  in-game and does nothing. `ON_PERMADEATH` sat in this bucket for months.")
    line("- **unused** -- declared in the registry and never referenced anywhere.")
    line("  Harmless, but dead weight the editor still offers as a choice.")
    line()
    local function bucketLines(label, b)
        for _, how in ipairs({ "assigned", "unused" }) do
            local list = b[how]
            table.sort(list)
            line(("- %s (%s): %s"):format(label, how,
                #list > 0 and ("`" .. table.concat(list, "`, `") .. "`") or "none"))
        end
    end
    bucketLines("trait codes", buckets.traitCodes)
    bucketLines("effect types", buckets.effectTypes)
    bucketLines("commands", buckets.commands)
    line()

    -- ----------------------------------------------------------------- flows
    line("## Flow phases (data/flows.json)")
    line()
    for _, group in ipairs(sortedKeys(loader.flows)) do
        local phases = loader.flows[group]
        if type(phases) == "table" then
            local names = sortedKeys(phases)
            line(("- `%s`: %s"):format(group,
                #names > 0 and ("`" .. table.concat(names, "`, `") .. "`") or "(none)"))
        end
    end
    line()

    -- --------------------------------------------------------------- content
    line("## Content inventory")
    line()
    local actors = loader.actors or {}
    local disciplines, unlocked, promotable = {}, 0, 0
    for _, a in ipairs(actors) do
        local d = a.discipline or "(none)"
        disciplines[d] = (disciplines[d] or 0) + 1
        if a.unlocked then unlocked = unlocked + 1 end
        if a.evolutions and #a.evolutions > 0 then promotable = promotable + 1 end
    end
    line(("- actors: **%d** (%d summonable-from-start, %d with promotion paths)"):format(
        #actors, unlocked, promotable))
    local discParts = {}
    for _, d in ipairs(sortedKeys(disciplines)) do
        table.insert(discParts, ("%sx%d"):format(d, disciplines[d]))
    end
    line(("- item-creation disciplines across the roster: %s"):format(
        table.concat(discParts, ", ")))

    local items = loader.items or {}
    local byType = {}
    local itemCount = 0
    for _, it in pairs(items) do
        itemCount = itemCount + 1
        local t = it.type or "(none)"
        byType[t] = (byType[t] or 0) + 1
    end
    local typeParts = {}
    for _, t in ipairs(sortedKeys(byType)) do
        table.insert(typeParts, ("%sx%d"):format(t, byType[t]))
    end
    line(("- items: **%d** (%s)"):format(itemCount, table.concat(typeParts, ", ")))
    line(("- skills: **%d**, passives: **%d**, states: **%d**, roles: **%d**, elements: **%d**"):format(
        countKeys(loader.skills), countKeys(loader.passives), countKeys(loader.states),
        countKeys(loader.roles), countKeys(loader.elements)))
    line(("- maps: **%d**, common events: **%d**, shops: **%d**, quests: **%d**"):format(
        #(loader.maps or {}), countKeys(loader.commonEvents),
        countKeys(loader.shops), countKeys(loader.quests)))
    line(("- animations: **%d**, tilesets: **%d**"):format(
        countKeys(loader.animations), countKeys(loader.tilesets)))
    line()

    line("## Notes for agents")
    line()
    line("- This file is generated. To change it, change the engine or the data.")
    line("- `docs/SPEC.md` is the living spec; `docs/archive/**` is frozen history")
    line("  and never authoritative.")
    line("- Design docs under `docs/design/` and `docs/game design/` describe")
    line("  intent. Where they state implementation status, trust THIS file.")
    line()

    return table.concat(out, "\n")
end

return engine_state
