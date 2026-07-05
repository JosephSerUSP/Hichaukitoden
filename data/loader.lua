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
    
    loader.animations = require("data.animations")
    loader.states = require("data.states")
    loader.passives = require("data.passives")
    loader.skills = require("data.skills")
    loader.party = require("data.party")

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

return loader
