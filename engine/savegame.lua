-- Save/load system. Serializes GameSession (party, reserve, summoner,
-- inventory, flags, EXP bank, map position) to JSON files under saves/,
-- written the same dual-write way campaign.json is (engine/interpreter.lua
-- switchCampaign, engine/server.lua saveFile): both into the LOVE save
-- directory (so a packaged build persists saves normally) and into the
-- project source dir when running from source (so dev tooling / the editor
-- can see save files on disk). love.filesystem reads already prefer the
-- save-dir copy, so the two stay in sync.
local json = require("data.json")

local savegame = {}

local SAVE_DIR = "saves"

local function sourceAbsPath(relPath)
    return love.filesystem.getSource() .. "/" .. relPath
end

-- ---------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------

local function serializeBattler(b)
    if not b then return nil end
    local states = {}
    for _, s in ipairs(b.states or {}) do
        table.insert(states, { id = s.id, duration = s.duration, maxDuration = s.maxDuration })
    end
    local passives = {}
    for _, p in ipairs(b.passives or {}) do table.insert(passives, p) end
    local skills = {}
    for _, s in ipairs(b.skills or {}) do table.insert(skills, s) end
    return {
        id = b.id,
        name = b.name,
        level = b.level,
        exp = b.exp,
        hp = b.hp,
        row = b.row,
        equipment = { b.equipment[1], b.equipment[2], b.equipment[3] },
        states = states,
        passives = passives,
        skills = skills,
        paramPlus = b.paramPlus,
    }
end

local function deserializeBattler(data, loader)
    if not data then return nil end
    local session = require("engine.session")
    local actorData = loader.getActor(data.id)
    if not actorData then return nil end
    local b = session.Battler.new(actorData, data.level)
    b.name = data.name or b.name
    b.exp = data.exp or 0
    b.hp = data.hp or b.hp
    b.row = data.row
    b.equipment = { data.equipment and data.equipment[1] or nil,
                    data.equipment and data.equipment[2] or nil,
                    data.equipment and data.equipment[3] or nil }
    b.states = {}
    for _, s in ipairs(data.states or {}) do
        table.insert(b.states, { id = s.id, duration = s.duration, maxDuration = s.maxDuration })
    end
    if data.passives then
        b.passives = {}
        for _, p in ipairs(data.passives) do table.insert(b.passives, p) end
    end
    if data.skills then
        b.skills = {}
        for _, s in ipairs(data.skills) do table.insert(b.skills, s) end
    end
    if data.paramPlus then b.paramPlus = data.paramPlus end
    return b
end

-- Only "map" (dungeon) and "town" carry a currentMapData/mapGrid worth
-- capturing; other scenes (battle, dialogue, menus) are mid-transition
-- state that isn't safe to resume into, so save/load is only offered from
-- those two.
local function serializeMap(sessionObj)
    if not sessionObj.currentMapData then return nil end
    return {
        mapIndex = sessionObj.currentMapIndex,
        playerX = sessionObj.playerX,
        playerY = sessionObj.playerY,
        playerDir = sessionObj.playerDir,
        mapGrid = sessionObj.mapGrid,
        visitedGrid = sessionObj.visitedGrid,
        events = sessionObj.currentMapData.events,
        dungeonFloor = sessionObj.dungeonFloor,
    }
end

local function restoreMap(sessionObj, data, loader)
    if not data or not data.mapIndex then return end
    local mapData = loader.maps[data.mapIndex]
    if not mapData then return end
    sessionObj.currentMapIndex = data.mapIndex
    sessionObj.currentMapData = mapData
    sessionObj.currentMapData.events = data.events
    sessionObj.mapGrid = data.mapGrid
    sessionObj.visitedGrid = data.visitedGrid
    sessionObj.playerX = data.playerX
    sessionObj.playerY = data.playerY
    sessionObj.playerDir = data.playerDir
    sessionObj.dungeonFloor = data.dungeonFloor or sessionObj.dungeonFloor
end

-- Builds the full save payload for a session. `sceneName` should be
-- scene_host.getCurrent() ("map" or "town") — the caller decides whether
-- saving is currently allowed.
function savegame.serialize(sessionObj, loader, sceneName)
    local reserve = {}
    for k, b in pairs(sessionObj.reserve or {}) do
        reserve[tostring(k)] = serializeBattler(b)
    end
    local party = {}
    for i = 1, 4 do
        party[i] = serializeBattler(sessionObj.party[i])
    end
    return {
        version = 1,
        savedAt = os.time(),
        campaignRoot = loader.root,
        scene = sceneName,
        gold = sessionObj.gold,
        inventory = sessionObj.inventory,
        flags = sessionObj.flags,
        dungeonFloor = sessionObj.dungeonFloor,
        mp = sessionObj.mp,
        maxMp = sessionObj.maxMp,
        expBank = sessionObj.expBank,
        summoner = serializeBattler(sessionObj.summoner),
        party = party,
        reserve = reserve,
        map = serializeMap(sessionObj),
    }
end

-- Rebuilds a GameSession (and returns the scene it was saved from) from a
-- decoded save payload. Does not touch scene_host; the caller is
-- responsible for switching campaigns first if needed and pushing the
-- returned scene.
function savegame.deserialize(data, loader)
    local session = require("engine.session")
    local sess = session.GameSession.new(loader)
    sess.gold = data.gold or 0
    sess.inventory = data.inventory or {}
    sess.flags = data.flags or {}
    sess.dungeonFloor = data.dungeonFloor or 1
    sess.mp = data.mp or sess.mp
    sess.maxMp = data.maxMp or sess.maxMp
    sess.expBank = data.expBank or 0

    local summoner = deserializeBattler(data.summoner, loader)
    if summoner then sess.summoner = summoner end

    sess.party = {}
    for i = 1, 4 do
        sess.party[i] = deserializeBattler(data.party and data.party[i], loader)
    end

    sess.reserve = {}
    for k, bdata in pairs(data.reserve or {}) do
        local key = tonumber(k) or k
        sess.reserve[key] = deserializeBattler(bdata, loader)
    end

    restoreMap(sess, data.map, loader)

    return sess, data.scene
end

-- ---------------------------------------------------------------------
-- File I/O (dual-write: LOVE save dir + project source dir, campaign.json
-- convention)
-- ---------------------------------------------------------------------

local function slotPath(slot)
    return SAVE_DIR .. "/" .. slot .. ".json"
end

function savegame.list()
    love.filesystem.createDirectory(SAVE_DIR)
    local items = love.filesystem.getDirectoryItems(SAVE_DIR)
    local slots = {}
    for _, name in ipairs(items) do
        local slot = name:match("^(.+)%.json$")
        if slot then
            local info = love.filesystem.getInfo(slotPath(slot))
            local meta = nil
            local contents = love.filesystem.read(slotPath(slot))
            if contents then
                local ok, decoded = pcall(json.decode, contents)
                if ok then meta = decoded end
            end
            table.insert(slots, {
                slot = slot,
                modtime = info and info.modtime,
                gold = meta and meta.gold,
                dungeonFloor = meta and meta.dungeonFloor,
                savedAt = meta and meta.savedAt,
            })
        end
    end
    table.sort(slots, function(a, b) return (a.modtime or 0) > (b.modtime or 0) end)
    return slots
end

function savegame.save(sessionObj, loader, sceneName, slot)
    slot = slot or "quicksave"
    love.filesystem.createDirectory(SAVE_DIR)
    local payload = savegame.serialize(sessionObj, loader, sceneName)
    local body = json.encode(payload)

    love.filesystem.write(slotPath(slot), body)

    -- Dev-convenience dual-write into the project source dir, mirroring
    -- switchCampaign's campaign.json write (engine/interpreter.lua).
    local absPath = sourceAbsPath(slotPath(slot))
    local file = io.open(absPath, "w")
    if file then
        file:write(body)
        file:close()
    end

    return true
end

function savegame.load(slot, loader)
    local contents = love.filesystem.read(slotPath(slot))
    if not contents then return nil, "save not found: " .. tostring(slot) end
    local ok, data = pcall(json.decode, contents)
    if not ok then return nil, "corrupt save: " .. tostring(data) end
    return data
end

function savegame.delete(slot)
    love.filesystem.remove(slotPath(slot))
    os.remove(sourceAbsPath(slotPath(slot)))
end

return savegame
