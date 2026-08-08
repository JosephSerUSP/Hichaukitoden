-- Save/load system. Serializes GameSession (party, reserve, summoner,
-- inventory, flags, EXP bank, map position) to JSON files under saves/,
-- written the same dual-write way campaign.json is (engine/interpreter.lua
-- switchCampaign, engine/server.lua saveFile): both into the LOVE save
-- directory (so a packaged build persists saves normally) and into the
-- project source dir when running from source (so dev tooling / the editor
-- can see save files on disk). love.filesystem reads already prefer the
-- save-dir copy, so the two stay in sync.
local json = require("data.json")
local config = require("engine.config")

local savegame = {}

local SAVE_DIR = "saves"
local SAVE_VERSION = 3

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
        equipment = { b.equipment[1], b.equipment[2], b.equipment[3] },
        states = states,
        passives = passives,
        skills = skills,
        paramPlus = b.paramPlus,
        -- Seeded growth. Both halves must round-trip: the seed IS the
        -- creature's individuality, and the accumulated record is its history.
        -- Saving only the level and re-deriving would let a reload reroll a
        -- level-up, which the design forbids outright.
        instanceId = b.instanceId,
        growthSeed = b.growthSeed,
        growth = b.growth,
        -- Per-instance identity that survives every change of form: where the
        -- creature came from (Egg provenance), what it was before a reversible
        -- curse, and its one Favorite Food with whether it has been discovered.
        -- All of it is the creature's own, not its species'.
        provenance = b.provenance,
        originForm = b.originForm,
        originAtLevel = b.originAtLevel,
        favoriteFood = b.favoriteFood,
        favoriteFoodFound = b.favoriteFoodFound,
        savor = b.savor,
        -- Death-ward charges live on the battler (never on the shared loader
        -- item table), so they must round-trip with it.
        wardCharges = b.wardCharges,
        -- Spell charges, same precedent as wardCharges: creature state, not
        -- loader state, so it must round-trip with the creature. Note the
        -- battle-scoped skillTimers (cooldown/warmup) are deliberately NOT
        -- here -- they answer "what can I do this turn", not "how much is left
        -- of the day", and a save is only ever taken outside battle anyway.
        charges = b.charges,
        history = b.history,
    }
end

local function deserializeBattler(data, loader)
    if not data then return nil end
    local session = require("engine.session")
    local actorData = loader.getActor(data.id)
    if not actorData then return nil end
    local b = session.Battler.new(actorData, data.level, data.growthSeed, data.instanceId)
    b.name = data.name or b.name
    b.exp = data.exp or 0
    b.hp = data.hp or b.hp
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
    if data.growthSeed then b.growthSeed = data.growthSeed end
    if data.growth then b.growth = data.growth end
    b.provenance = data.provenance
    b.originForm = data.originForm
    b.originAtLevel = data.originAtLevel
    b.favoriteFood = data.favoriteFood
    b.favoriteFoodFound = data.favoriteFoodFound
    b.savor = data.savor
    if data.wardCharges then b.wardCharges = data.wardCharges end
    -- Absent = full, which is exactly what a save written before charges
    -- existed should mean: the creature arrives rested, not mute.
    if data.charges then b.charges = data.charges end
    if data.history then b.history = data.history end
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
        runtimeLight = sessionObj.currentMapData.runtimeLight,
        generatedLightObjects = sessionObj.generatedLightObjects,
        generatedFeatures = sessionObj.generatedFeatures,
        generatedZones = sessionObj.generatedZones,
        dungeonFloor = sessionObj.dungeonFloor,
    }
end

local function restoreMap(sessionObj, data, loader)
    if not data or not data.mapIndex then return end
    local rawMapData = loader.maps[data.mapIndex]
    if not rawMapData then return end
    local mapData = {}
    for k, v in pairs(rawMapData) do mapData[k] = v end
    sessionObj.currentMapIndex = data.mapIndex
    sessionObj.currentMapData = mapData
    sessionObj.currentMapData.events = data.events
    sessionObj.currentMapData.runtimeLight = data.runtimeLight
    sessionObj.generatedLightObjects = data.generatedLightObjects
    sessionObj.generatedFeatures = data.generatedFeatures
    sessionObj.fixtureBlockIndex = nil  -- rebuilt lazily from the restored placements
    sessionObj.generatedZones = data.generatedZones
    sessionObj.mapGrid = data.mapGrid
    sessionObj.visitedGrid = data.visitedGrid
    sessionObj.playerX = data.playerX
    sessionObj.playerY = data.playerY
    sessionObj.playerDir = data.playerDir
    sessionObj.dungeonFloor = data.dungeonFloor or sessionObj.dungeonFloor
    local presentation = sessionObj.mapPresentationOverrides
        and sessionObj.mapPresentationOverrides[data.mapIndex]
    if presentation then
        require("engine.exploration").applyMapPresentation(
            sessionObj, data.mapIndex, presentation)
    end
end

-- Builds the full save payload for a session. `sceneName` should be
-- scene_host.getCurrent() ("map" or "town") — the caller decides whether
-- saving is currently allowed.
function savegame.serialize(sessionObj, loader, sceneName)
    local reserve = {}
    for k, b in pairs(sessionObj.reserve or {}) do
        reserve[tostring(k)] = serializeBattler(b)
    end
    local storage = {}
    for k, b in pairs(sessionObj.storage or {}) do
        storage[tostring(k)] = serializeBattler(b)
    end
    local party = {}
    for i = 1, config.MAX_PARTY_SIZE do
        local b = sessionObj.party[i]
        if b then
            party[i] = serializeBattler(b)
        else
            party[i] = false
        end
    end
    local recruitNodes = {}
    for k, node in pairs(sessionObj.recruitNodes or {}) do
        recruitNodes[tostring(k)] = {
            completed = node.completed,
            recruitedInstanceId = node.recruitedInstanceId,
            requirementSatisfied = node.requirementSatisfied,
            requirement = node.requirement,
            suggestedSlot = node.suggestedSlot,
            candidate = serializeBattler(node.candidate),
        }
    end
    return {
        version = SAVE_VERSION,
        savedAt = os.time(),
        campaignRoot = loader.root,
        scene = sceneName,
        gold = sessionObj.gold,
        inventory = sessionObj.inventory,
        flags = sessionObj.flags,
        unlockedLore = sessionObj.unlockedLore,
        eventOverrides = sessionObj.eventOverrides,
        mapStates = sessionObj.mapStates,
        portalReturn = sessionObj.portalReturn,
        mapPresentationOverrides = sessionObj.mapPresentationOverrides,
        dungeonFloor = sessionObj.dungeonFloor,
        mp = sessionObj.mp,
        maxMp = sessionObj.maxMp,
        expBank = sessionObj.expBank,
        nextCreatureInstanceId = sessionObj.nextCreatureInstanceId or 1,
        firstRecruitInstanceId = sessionObj.firstRecruitInstanceId,
        firstRecruitOriginalActorId = sessionObj.firstRecruitOriginalActorId,
        recruitNodes = recruitNodes,
        -- The graveyard outlives every creature in it, so it must persist.
        memorial = sessionObj.memorial,
        autoRedirect = sessionObj.autoRedirect,
        summoner = serializeBattler(sessionObj.summoner),
        party = party,
        reserve = reserve,
        storage = storage,
        map = serializeMap(sessionObj),
    }
end

-- Rebuilds a GameSession (and returns the scene it was saved from) from a
-- decoded save payload. Does not touch scene_host; the caller is
-- responsible for switching campaigns first if needed and pushing the
-- returned scene.
function savegame.deserialize(data, loader)
    if type(data) ~= "table" or data.version ~= SAVE_VERSION then
        error("unsupported save version " .. tostring(data and data.version)
            .. "; current version is " .. tostring(SAVE_VERSION)
            .. " (pre-symbolic Unit-ID development saves are intentionally not migrated)")
    end
    local session = require("engine.session")
    local sess = session.GameSession.new(loader)
    sess.gold = data.gold or 0
    sess.inventory = data.inventory or {}
    sess.flags = data.flags or {}
    sess.unlockedLore = data.unlockedLore or {}
    sess.eventOverrides = data.eventOverrides or {}
    sess.mapStates = {}
    for k, state in pairs(data.mapStates or {}) do
        sess.mapStates[tonumber(k) or k] = state
    end
    sess.portalReturn = data.portalReturn
    sess.mapPresentationOverrides = {}
    for k, state in pairs(data.mapPresentationOverrides or {}) do
        sess.mapPresentationOverrides[tonumber(k) or k] = state
    end
    sess.dungeonFloor = data.dungeonFloor or 1
    sess.mp = data.mp or sess.mp
    sess.maxMp = data.maxMp or sess.maxMp
    sess.expBank = data.expBank or 0
    sess.nextCreatureInstanceId = data.nextCreatureInstanceId or 1
    sess.firstRecruitInstanceId = data.firstRecruitInstanceId
    sess.firstRecruitOriginalActorId = data.firstRecruitOriginalActorId
    sess.memorial = data.memorial or {}
    if data.autoRedirect ~= nil then sess.autoRedirect = data.autoRedirect end

    local summoner = deserializeBattler(data.summoner, loader)
    if summoner then sess.summoner = summoner end

    sess.party = {}
    if data.version == 2 then
        for i = 1, config.MAX_PARTY_SIZE do
            local bdata = data.party and data.party[i]
            if type(bdata) == "table" then
                sess.party[i] = deserializeBattler(bdata, loader)
            end
        end
    else
        -- Version 1 migration (dense party array without slot / false placeholders)
        local formation = require("engine.formation")
        local legacyParty = {}
        for i = 1, config.MAX_PARTY_SIZE do
            local bdata = data.party and data.party[i]
            if type(bdata) == "table" then
                table.insert(legacyParty, deserializeBattler(bdata, loader))
            end
        end
        sess.party = formation.autoPack(legacyParty, config.MAX_PARTY_SIZE)
    end

    sess.reserve = {}
    for k, bdata in pairs(data.reserve or {}) do
        local key = tonumber(k) or k
        sess.reserve[key] = deserializeBattler(bdata, loader)
    end

    sess.storage = {}
    for k, bdata in pairs(data.storage or {}) do
        local key = tonumber(k) or k
        sess.storage[key] = deserializeBattler(bdata, loader)
    end

    sess.recruitNodes = {}
    for k, nData in pairs(data.recruitNodes or {}) do
        sess.recruitNodes[k] = {
            completed = nData.completed,
            recruitedInstanceId = nData.recruitedInstanceId,
            requirementSatisfied = nData.requirementSatisfied,
            requirement = nData.requirement,
            suggestedSlot = nData.suggestedSlot,
            candidate = deserializeBattler(nData.candidate, loader),
        }
    end

    -- Validate nextCreatureInstanceId strictly exceeds all existing instance IDs
    local maxInstanceNum = 0
    local function checkBattlerInst(b)
        if b and b.instanceId then
            local num = tonumber(tostring(b.instanceId):match("creature:(%d+)"))
            if num and num > maxInstanceNum then maxInstanceNum = num end
        end
    end
    for _, b in pairs(sess.party) do checkBattlerInst(b) end
    for _, b in pairs(sess.reserve) do checkBattlerInst(b) end
    for _, b in pairs(sess.storage) do checkBattlerInst(b) end
    for _, n in pairs(sess.recruitNodes) do
        checkBattlerInst(n.candidate)
        if n.recruitedInstanceId then
            local num = tonumber(tostring(n.recruitedInstanceId):match("creature:(%d+)"))
            if num and num > maxInstanceNum then maxInstanceNum = num end
        end
    end
    if maxInstanceNum >= sess.nextCreatureInstanceId then
        sess.nextCreatureInstanceId = maxInstanceNum + 1
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
