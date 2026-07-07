local json = require("data.json")

local loader = {}

-- Load JSON helper
local function load_json(path)
    local contents, size = love.filesystem.read(path)
    if not contents then
        error("Could not read JSON file: " .. path)
    end
    return json.decode(contents)
end

function loader.init()
    loader.actors = load_json("data/actors.json")
    loader.elements = load_json("data/elements.json")
    loader.events = load_json("data/events.json")
    loader.items = load_json("data/items.json")
    loader.maps = load_json("data/maps.json")
    loader.quests = load_json("data/quests.json")
    loader.shops = load_json("data/shops.json")
    loader.sounds = load_json("data/sounds.json")
    loader.terms = load_json("data/terms.json")
    loader.themes = load_json("data/themes.json")
    loader.system = load_json("data/system.json")
    loader.commonEvents = load_json("data/commonEvents.json")
    loader.skills = load_json("data/skills.json")
    loader.passives = load_json("data/passives.json")
    loader.states = load_json("data/states.json")
    loader.roles = load_json("data/roles.json")
    -- Engine registries: effect types, trait codes, battle layout, element rules
    loader.engine = load_json("data/engine.json")
    -- Phase flows (SPEC S4): scene phase -> command list, run in immediate mode
    loader.flows = load_json("data/flows.json")

    loader.animations = require("data.animations")

    -- Create lookup indices for scalability
    loader.actorsById = {}
    for _, actor in ipairs(loader.actors) do
        loader.actorsById[actor.id] = actor
    end

    loader.itemsById = {}
    for _, item in ipairs(loader.items) do
        loader.itemsById[item.id] = item
    end
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
    return loader.itemsById[id]
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

function loader.getRole(id)
    return loader.roles and loader.roles[id]
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
