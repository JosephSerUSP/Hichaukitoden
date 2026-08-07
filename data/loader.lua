local json = require("data.json")
local collection_loader = require("data.collection_loader")

local loader = {}

-- Load JSON helper
local function load_json(path)
    local contents, size = love.filesystem.read(path)
    if not contents then
        error("Could not read JSON file: " .. path)
    end
    return json.decode(contents)
end

-- A campaign may replace a complete scene without copying or reserializing the
-- monolithic scene registry. Replacements remain ordinary declarative scene
-- objects; the loader merely swaps them by stable scene id before indexing.
local function applySceneOverrides()
    local path = loader.root .. "/scene_overrides.json"
    if not love.filesystem.getInfo(path) then return end

    local data = load_json(path)
    local replacements = data and data.sceneReplacements
    if type(replacements) ~= "table" then
        error("scene_overrides.json must contain a sceneReplacements array")
    end

    local indexById = {}
    for index, scene in ipairs(loader.scenes or {}) do
        indexById[scene.id] = index
    end

    for _, scene in ipairs(replacements) do
        if type(scene) ~= "table" or scene.id == nil then
            error("scene_overrides.json contains a replacement without an id")
        end
        local index = indexById[scene.id]
        if not index then
            error("scene_overrides.json cannot replace unknown scene '"
                .. tostring(scene.id) .. "'")
        end
        loader.scenes[index] = scene
    end
end

-- Campaign roots (no-move design, owner decision 18.07.2026): data/ IS the
-- default campaign; campaigns/<name>/ directories are drop-in alternates
-- with the same file set. Which one drives this run resolves as:
-- explicit init arg (CLI campaign=<name>) > campaign.json pointer file at
-- the repo root ({"active": "<name>"}) > data/. Golden logs are recorded
-- against the default campaign, so G2/G3 only gate runs where data/ is
-- active.
loader.root = "data"

function loader.resolveRoot(explicit)
    if explicit and explicit ~= "" then return explicit end
    if love.filesystem.getInfo("campaign.json") then
        local contents = love.filesystem.read("campaign.json")
        local ok, ptr = pcall(json.decode, contents or "")
        if ok and type(ptr) == "table" and type(ptr.active) == "string" and ptr.active ~= "" then
            local dir = "campaigns/" .. ptr.active
            if love.filesystem.getInfo(dir .. "/system.json") then
                return dir
            end
            print("[loader] warning: campaign.json points at '" .. ptr.active ..
                "' but " .. dir .. "/system.json is missing; using data/")
        end
    end
    return "data"
end

-- Campaign selector support (title-screen testing tool): default root first,
-- then every campaigns/<x>/ dir that has a system.json. Title comes from a
-- title-ish field in that system.json when present, else the dir name
-- (system.json has no title field today, so the dir name is the usual case).
function loader.listCampaigns()
    local list = { { name = "", title = "(default)" } }
    local dirs = love.filesystem.getDirectoryItems("campaigns")
    table.sort(dirs)
    for _, dir in ipairs(dirs) do
        local sysPath = "campaigns/" .. dir .. "/system.json"
        if love.filesystem.getInfo(sysPath) then
            local ok, sys = pcall(load_json, sysPath)
            local title = ok and type(sys) == "table" and (sys.title or sys.gameTitle) or nil
            table.insert(list, { name = dir, title = type(title) == "string" and title or dir })
        end
    end
    return list
end

function loader.init(root)
    loader.root = loader.resolveRoot(root)
    if loader.root ~= "data" then
        print("[loader] active campaign root: " .. loader.root)
    end
    local function J(name) return load_json(loader.root .. "/" .. name) end
    loader.actors = J("actors.json")
    loader.elements = J("elements.json")
    loader.items = J("items.json")
    loader.maps, loader.mapsStorage = collection_loader.load(loader.root, "maps")
    loader.mapsById = {}
    for index, map in ipairs(loader.maps) do
        local key = tostring(map.id)
        if loader.mapsById[key] then
            error("duplicate authored map id: " .. key)
        end
        loader.mapsById[key] = index
    end
    loader.lore = J("lore.json")
    loader.quests = J("quests.json")
    loader.shops = J("shops.json")
    loader.sounds = J("sounds.json")
    loader.terms = J("terms.json")
    loader.actionSequences = J("actionSequences.json")
    loader.system = J("system.json")
    loader.commonEvents = J("commonEvents.json")
    loader.skills = J("skills.json")
    local validSkillScopes = { battle = true, field = true, always = true, none = true }
    for id, skill in pairs(loader.skills or {}) do
        if type(skill.scope) ~= "string" or not validSkillScopes[skill.scope] then
            error("skill '" .. tostring(id) .. "' has invalid or missing scope '"
                .. tostring(skill.scope) .. "' (expected battle, field, always, or none)")
        end
    end
    loader.passives = J("passives.json")
    loader.states = J("states.json")
    loader.roles = J("roles.json")
    -- Engine registries: effect types, trait codes, battle layout, element rules
    loader.engine = J("engine.json")
    -- Phase flows (SPEC S4): scene phase -> command list, run in immediate mode
    loader.flows = J("flows.json")
    -- Troops: what a battle is made of (member slots, rigid or pooled) and its
    -- battle events. `base` is inherited by all of them.
    loader.troops = J("troops.json")
    -- Scenes configuration. Optional replacements are applied before the
    -- lookup registry is built, so every consumer sees one canonical scene.
    loader.scenes, loader.scenesStorage = collection_loader.load(loader.root, "scenes")
    applySceneOverrides()

    -- overhaul-7 A1: animations data loaded from JSON
    loader.animations = J("animations.json")
    local animation_player = require("presentation.animation_player")
    animation_player.load(loader.animations)

    -- Decoupled tilesets data registry
    loader.tilesets = J("tilesets.json")

    -- Icon palettes and key profiles
    loader.iconPalettes = J("iconPalettes.json")
    loader.iconKeyProfiles = J("iconKeyProfiles.json")

    -- Create lookup indices for scalability
    loader.actorsById = {}
    for _, actor in ipairs(loader.actors) do
        loader.actorsById[actor.id] = actor
    end

    loader.itemsById = {}
    for _, item in ipairs(loader.items) do
        loader.itemsById[item.id] = item
    end

    loader.scenesById = {}
    for _, scene in ipairs(loader.scenes or {}) do
        loader.scenesById[scene.id] = scene
    end
end

function loader.getTileset(id)
    if not loader.tilesets then return nil end
    local key = (id and tostring(id) ~= "") and tostring(id) or "dungeon_default"
    return loader.tilesets[key] or loader.tilesets["dungeon_default"]
end

function loader.getMapIndex(id)
    if not loader.mapsById then return nil end
    return loader.mapsById[tostring(id)]
end

-- Helpers to find items/skills by ID (O(1) lookups)
function loader.getActor(id)
    return loader.actorsById[id]
end

-- Finds an actor by its role (e.g. "Summoner") instead of a numeric id, for
-- the handful of actors the engine references structurally rather than by
-- content-catalog id.
function loader.getActorByRole(role)
    for _, actor in ipairs(loader.actors) do
        if actor.role == role then return actor end
    end
    return nil
end

function loader.getItem(id)
    if not id then return nil end
    local item = loader.itemsById[id]
    if not item and tonumber(id) then
        item = loader.itemsById[tonumber(id)]
    end
    return item
end

function loader.getSkill(id)
    return loader.skills[id]
end

function loader.getPassive(id)
    return loader.passives[id]
end

function loader.getState(id)
    return loader.states[id]
end

function loader.getElement(id)
    return loader.elements and loader.elements[id]
end

function loader.getScene(id)
    return loader.scenesById[id]
end

function loader.getRole(id)
    return loader.roles and loader.roles[id]
end

-- Quests are keyed by string id (JSON object keys); tostring so numeric or
-- string ids both resolve — same convention as the shops/commonEvents
-- lookups in main.lua.
function loader.getQuest(id)
    return loader.quests and loader.quests[tostring(id)]
end

function loader.getLore(id)
    return loader.lore and loader.lore[tostring(id)]
end

-- Looks up a UI/battle string from data/terms.json by dotted path
-- (e.g. "battle.flee_success"); falls back to the engine default when the
-- key is missing so incomplete terms files never crash the game.
function loader.getTerm(path, fallback)
    local node = loader.terms
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return fallback end
        node = node[part]
    end
    if type(node) == "string" then return node end
    return fallback
end

-- Like getTerm but for list-valued terms (e.g. menu command label arrays).
function loader.getTermList(path, fallback)
    local node = loader.terms
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return fallback end
        node = node[part]
    end
    if type(node) == "table" and #node > 0 then return node end
    return fallback
end

-- getTerm + positional substitution: replaces {0}, {1}, ... with the extra
-- arguments (the same placeholder style terms.json already uses).
function loader.formatTerm(path, fallback, ...)
    local str = loader.getTerm(path, fallback)
    local args = { ... }
    return (str:gsub("{(%d+)}", function(idx)
        local v = args[tonumber(idx) + 1]
        return v ~= nil and tostring(v) or ("{" .. idx .. "}")
    end))
end

return loader
