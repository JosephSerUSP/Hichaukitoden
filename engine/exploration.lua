local config = require("engine.config")
local conditions = require("engine.conditions")
local formulaEngine = require("engine.formula")
local lighting = require("engine.lighting")
local loader = require("data.loader")

local exploration = {}

-- RPG Maker-style event pages: `ev.pages` is an ordered list of
-- {condition, script/scriptId, sprite, trigger, name, ...} overrides. The
-- LAST page whose condition passes wins (so authors order pages
-- least-to-most specific, same convention as RPG Maker), overriding
-- whichever fields it defines onto a copy of the base event; an
-- unconditioned page always matches, so it's the natural final fallback.
-- An event with no pages resolves to itself unchanged. condition accepts
-- the same flag:/hasItem:/questStatus: grammar as CONDITIONAL_BRANCH,
-- falling back to a formula (mirrors engine/director.lua's ROUTER).
function exploration.resolvePage(ev, session)
    if not ev then return nil end
    local effective = ev
    if ev.pages and #ev.pages > 0 then
        for _, page in ipairs(ev.pages) do
            local result = true
            if page.condition and page.condition ~= "" then
                local matched
                matched, result = conditions.evalPrefixed(page.condition, session)
                if not matched then
                    local fctx = formulaEngine.makeContext({}, session)
                    local val, err = formulaEngine.eval(page.condition, fctx)
                    result = (not err) and val ~= false and val ~= 0 and val ~= nil
                end
            end
            if result then
                local merged = {}
                for k, v in pairs(effective) do merged[k] = v end
                for k, v in pairs(page) do
                    if k ~= "condition" and k ~= "name" and k ~= "label" then
                        merged[k] = v
                    end
                end
                merged.name = ev.name
                merged.label = ev.label
                effective = merged
            end
        end
    end

    if session and ev.id then
        local mapIdx = session.currentMapIndex or 1
        local pOverride = session.eventOverrides and session.eventOverrides[mapIdx] and session.eventOverrides[mapIdx][ev.id]
        local tOverride = session.tempEventOverrides and session.tempEventOverrides[ev.id]
        if pOverride or tOverride then
            local merged = {}
            for k, v in pairs(effective) do merged[k] = v end
            if pOverride then
                for k, v in pairs(pOverride) do merged[k] = v end
            end
            if tOverride then
                for k, v in pairs(tOverride) do merged[k] = v end
            end
            effective = merged
        end
    end

    return effective
end

-- Dungeon-generation settings from data/system.json (with engine defaults)
local function dungeonConf(key, default)
    local d = config.dungeon
    if d and d[key] ~= nil then return d[key] end
    return default
end

-- Direction vectors
local DIRS = {
    N = { dx = 0, dy = -1 },
    E = { dx = 1, dy = 0 },
    S = { dx = 0, dy = 1 },
    W = { dx = -1, dy = 0 }
}
local DIR_ORDER = { "N", "E", "S", "W" }

-- Generate random room-based dungeon map
-- Resolve the visual fixtures defined by a tileset into per-map material
-- placements. This applies to authored safe maps as well as generated
-- dungeons, so a fixture configured in Tileset Studio is actually visible
-- when testing a town map.
function exploration.injectTilesetFeatures(grid, mapData)
    local tilesetDef = loader.getTileset(mapData and mapData.tileset)
    local featureList = (tilesetDef and tilesetDef.features) or {
        { id = "wall_torch", role = "wall_feature", injectProbability = 0.11, requiresAdjacentFloor = true, emitsLight = { color = { 1, 0.58, 0.22 }, radius = 4 } }
    }
    local generated = {}
    local height = #grid
    for _, feat in ipairs(featureList) do
        local prob = feat.injectProbability or 0.1
        for y = 2, height - 1 do
            local width = #grid[y]
            for x = 2, width - 1 do
                if feat.role == "wall_feature" and grid[y][x] == "#" then
                    local adjFloor = (grid[y - 1] and grid[y - 1][x] == ".")
                        or (grid[y + 1] and grid[y + 1][x] == ".")
                        or grid[y][x - 1] == "." or grid[y][x + 1] == "."
                    if (not feat.requiresAdjacentFloor or adjFloor) and math.random() < prob then
                        local lColor = feat.emitsLight and feat.emitsLight.color or { 1, 0.58, 0.22 }
                        local lRadius = feat.emitsLight and feat.emitsLight.radius or 4
                        table.insert(generated, { x = x - 1, y = y - 1, material = feat.id, color = lColor, radius = lRadius })
                    end
                end
            end
        end
    end
    return generated
end

-- Selects a weighted variant from a variant pool (walls/floors/ceilings)
-- deterministically based on seed key (e.g. "x,y") or randomly.
function exploration.resolveTilesetVariant(pool, seedKey)
    if not pool or #pool == 0 then return nil end
    if #pool == 1 then return pool[1] end

    local totalWeight = 0
    for _, item in ipairs(pool) do
        totalWeight = totalWeight + (item.weight or 1)
    end
    if totalWeight <= 0 then return pool[1] end

    local r
    if seedKey then
        local hash = 0
        local str = tostring(seedKey)
        for i = 1, #str do
            hash = (hash * 31 + str:byte(i)) % 100000
        end
        r = (hash / 100000) * totalWeight
    else
        r = math.random() * totalWeight
    end

    local accumulated = 0
    for _, item in ipairs(pool) do
        accumulated = accumulated + (item.weight or 1)
        if r <= accumulated then
            return item
        end
    end
    return pool[#pool]
end

function exploration.generateDungeon(mapData, seed, session)
    if seed then math.randomseed(seed) end
    
    local width = mapData.width or dungeonConf("genWidth", 21)
    local height = mapData.height or dungeonConf("genHeight", 21)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = "#" -- Solid wall
        end
    end
    
    local rooms = {}
    local occupiedGrid = {}
    for y = 1, height do occupiedGrid[y] = {} end

    -- 1. Apply Fixed/Authored Anchors (Diablo 1 style pre-authored quest/special rooms)
    if mapData.anchors and #mapData.anchors > 0 then
        for _, anchor in ipairs(mapData.anchors) do
            local ax = (anchor.x or 0) + 1
            local ay = (anchor.y or 0) + 1
            local layout = anchor.layout or {}
            local ah = #layout
            local aw = ah > 0 and #layout[1] or 0
            
            for ry = 1, ah do
                local line = layout[ry]
                local gy = ay + ry - 1
                if gy >= 1 and gy <= height then
                    for rx = 1, #line do
                        local char = line:sub(rx, rx)
                        local gx = ax + rx - 1
                        if gx >= 1 and gx <= width then
                            grid[gy][gx] = char
                            occupiedGrid[gy][gx] = true
                        end
                    end
                end
            end
            
            local cx = math.floor(ax + aw / 2)
            local cy = math.floor(ay + ah / 2)
            table.insert(rooms, { x = ax, y = ay, w = aw, h = ah, cx = cx, cy = cy, isAnchor = true, allowRandomEvents = (anchor.allowRandomEvents ~= false) })
        end
    end

    -- 2. Carve Procedural Interstitial Rooms around anchors
    local numProcedural = math.random(dungeonConf("genMinRooms", 4), dungeonConf("genMaxRooms", 6))
    local minRoom = dungeonConf("genMinRoomSize", 3)
    local maxRoom = dungeonConf("genMaxRoomSize", 5)

    local attempts = 0
    local createdProcedural = 0
    while createdProcedural < numProcedural and attempts < 100 do
        attempts = attempts + 1
        local rw = math.random(minRoom, maxRoom)
        local rh = math.random(minRoom, maxRoom)
        local rx = math.random(2, width - rw - 1)
        local ry = math.random(2, height - rh - 1)
        
        -- Check collision with existing anchors/rooms
        local overlaps = false
        for y = ry - 1, ry + rh do
            for x = rx - 1, rx + rw do
                if y >= 1 and y <= height and x >= 1 and x <= width then
                    if occupiedGrid[y][x] then
                        overlaps = true
                        break
                    end
                end
            end
            if overlaps then break end
        end

        if not overlaps then
            for y = ry, ry + rh - 1 do
                for x = rx, rx + rw - 1 do
                    grid[y][x] = "."
                    occupiedGrid[y][x] = true
                end
            end
            local cx = math.floor(rx + rw / 2)
            local cy = math.floor(ry + rh / 2)
            table.insert(rooms, { x = rx, y = ry, w = rw, h = rh, cx = cx, cy = cy, isAnchor = false, allowRandomEvents = true })
            createdProcedural = createdProcedural + 1
        end
    end

    -- If no rooms exist at all, make a fallback center room
    if #rooms == 0 then
        local rw, rh = 5, 5
        local rx, ry = math.floor((width - rw) / 2), math.floor((height - rh) / 2)
        for y = ry, ry + rh - 1 do
            for x = rx, rx + rw - 1 do grid[y][x] = "." end
        end
        table.insert(rooms, { x = rx, y = ry, w = rw, h = rh, cx = math.floor(rx + rw/2), cy = math.floor(ry + rh/2), isAnchor = false, allowRandomEvents = true })
    end
    
    -- 3. Connect rooms (Anchors + Procedural) with Hallways
    for i = 1, #rooms - 1 do
        local r1 = rooms[i]
        local r2 = rooms[i+1]
        
        local x1, x2 = math.min(r1.cx, r2.cx), math.max(r1.cx, r2.cx)
        for x = x1, x2 do
            if grid[r1.cy][x] == "#" then grid[r1.cy][x] = "." end
        end
        
        local y1, y2 = math.min(r1.cy, r2.cy), math.max(r1.cy, r2.cy)
        for y = y1, y2 do
            if grid[y][r2.cx] == "#" then grid[y][r2.cx] = "." end
        end
    end
    
    local startX, startY = rooms[1].cx, rooms[1].cy
    local exitX, exitY = rooms[#rooms].cx, rooms[#rooms].cy
    
    local generatedEvents = {}
    
    -- Gather candidate open tiles, prioritizing ROOM tiles over corridor tiles
    local roomOpenTiles = {}
    local corridorOpenTiles = {}
    
    for y = 2, height - 1 do
        for x = 2, width - 1 do
            if grid[y][x] == "." and not (x == startX and y == startY) and not (x == exitX and y == exitY) then
                local inRoom = false
                for _, rm in ipairs(rooms) do
                    if rm.allowRandomEvents and x >= rm.x and x < rm.x + rm.w and y >= rm.y and y < rm.y + rm.h then
                        inRoom = true
                        break
                    end
                end
                if inRoom then
                    table.insert(roomOpenTiles, { x = x, y = y })
                else
                    table.insert(corridorOpenTiles, { x = x, y = y })
                end
            end
        end
    end
    
    -- Shuffle both pools
    for i = #roomOpenTiles, 2, -1 do
        local j = math.random(i)
        roomOpenTiles[i], roomOpenTiles[j] = roomOpenTiles[j], roomOpenTiles[i]
    end
    for i = #corridorOpenTiles, 2, -1 do
        local j = math.random(i)
        corridorOpenTiles[i], corridorOpenTiles[j] = corridorOpenTiles[j], corridorOpenTiles[i]
    end

    -- Combined pool: room tiles first, fallback to corridors if rooms run out
    local openTiles = {}
    for _, t in ipairs(roomOpenTiles) do table.insert(openTiles, t) end
    for _, t in ipairs(corridorOpenTiles) do table.insert(openTiles, t) end

    local generatedLights = exploration.injectTilesetFeatures(grid, mapData)
    
    local placedCount = 1
    
    -- Spawn exit stairs dynamically
    table.insert(generatedEvents, {
        id = 99,
        x = exitX - 1,
        y = exitY - 1,
        scriptId = dungeonConf("exitScriptId", 1), -- Stairs trigger descend script
        sprite = dungeonConf("exitSprite", "assets/sprites/NPC00.png"),
        trigger = "interact"
    })
    
    -- Process events from mapData.events database
    if mapData.events then
        for _, ev in ipairs(mapData.events) do
            local tx, ty
            if ev.spawn == "Fixed" and ev.x and ev.y then
                tx, ty = ev.x + 1, ev.y + 1
            elseif ev.spawn == "Random" or not (ev.x and ev.y) then
                local tile = openTiles[placedCount]
                if tile then
                    tx, ty = tile.x, tile.y
                    placedCount = placedCount + 1
                end
            else
                tx, ty = ev.x + 1, ev.y + 1
            end
            
            if tx and ty then
                -- Carry the WHOLE authored event through, overriding only the
                -- resolved position. This used to copy a whitelist of six
                -- fields, which silently dropped everything else an author had
                -- written on the event -- `meta` (so trap/secret detection saw
                -- nothing), `label`, `minimapColor`, `pages`, and any field a
                -- future feature adds. Placement is the only thing generation
                -- owns; the rest of the event is the author's.
                local placed = {}
                for k, v in pairs(ev) do placed[k] = v end
                placed.x = tx - 1
                placed.y = ty - 1
                placed.trigger = ev.trigger or "interact"
                table.insert(generatedEvents, placed)
            end
        end
    end

    -- Process mapData.recruits pool to spawn a recruit event if none exists
    if mapData.recruits and #mapData.recruits > 0 then
        local hasRecruitEvent = false
        for _, ev in ipairs(generatedEvents) do
            if ev.id == "recruit" or ev.type == "recruit" then
                hasRecruitEvent = true
                break
            end
        end
        if not hasRecruitEvent then
            local tile = openTiles[placedCount]
            if tile then
                placedCount = placedCount + 1
                local candidateActorId = mapData.recruits[math.random(#mapData.recruits)]
                local loader = session and session.loader
                local actorData = loader and loader.getActor(candidateActorId)
                local spritePath = (actorData and actorData.spriteKey and ("assets/sprites/" .. actorData.spriteKey .. ".png")) or "assets/sprites/OBJ_Statue_001.png"
                table.insert(generatedEvents, {
                    id = "recruit_" .. candidateActorId,
                    type = "recruit",
                    actorId = candidateActorId,
                    x = tile.x - 1,
                    y = tile.y - 1,
                    sprite = spritePath,
                    trigger = "touch",
                    commands = {
                        { cmd = "RECRUIT" }
                    }
                })
            end
        end
    end
    
    return grid, startX, startY, generatedEvents, generatedLights
end

-- Unified per-cell override table (docs/design/tileset-and-events-redesign.md
-- §8.1): `mapData.overrides` is a flat array of
-- {x, y (0-indexed, author-facing), visual, passable, mutateTo, hidden}
-- entries, replacing the dead `tiles{}`/free-text-`material` split. Indexed
-- once per map load, keyed 1-indexed ("x,y") to match session.mapGrid.
function exploration.buildOverrideIndex(session)
    local index = {}
    local data = session.currentMapData or {}
    for _, ov in ipairs(data.overrides or {}) do
        index[(ov.x + 1) .. "," .. (ov.y + 1)] = ov
    end
    session.overrideIndex = index
    return index
end

-- Mutates the structure layer at runtime (e.g. a hidden-passage-reveal
-- event turning a wall into floor). `to` is a raw layout char ("#"/"."),
-- matching session.mapGrid's existing 1-indexed char-grid representation.
function exploration.mutateTile(session, x, y, to)
    local gx, gy = x + 1, y + 1
    local row = session.mapGrid[gy]
    if not row then return false end
    row[gx] = to
    local ov = session.overrideIndex and session.overrideIndex[gx .. "," .. gy]
    if ov then ov.mutateTo = nil end -- consumed: already applied to the grid
    return true
end

-- Initialize map state in GameSession
function exploration.loadMap(session, mapIdx)
    local rawMapData = session.loader.maps[mapIdx]
    -- A transfer to a map that does not exist used to load an empty table and
    -- leave the player standing in a blank world; say so instead.
    if not rawMapData then
        error("exploration.loadMap: no map with index " .. tostring(mapIdx))
    end
    -- An "expedition" is one trip out of safety, not one floor: fire the phase
    -- only on the safe -> dangerous transition. What that phase counts is data
    -- (data/flows.json exploration.expedition_start).
    local wasSafe = not (session.currentMapData and session.currentMapData.safe == false)
        and (session.currentMapData == nil or session.currentMapData.safe == true)
    local goingDangerous = not (rawMapData.safe == true)
    if wasSafe and goingDangerous and session.party then
        require("engine.flow").run("exploration.expedition_start", { session = session, party = session.party })
    end
    session.currentMapIndex = mapIdx
    -- How deep the party is, is a property of the map it is standing on, not a
    -- counter that one command remembers to bump. Deriving it here means every
    -- transfer keeps it true -- including going back up, which the old
    -- increment-only counter never did: returning to Town left the party
    -- "on floor 6" for enemy levels and recruitment.
    session.dungeonFloor = rawMapData.depth or session.dungeonFloor or 0
    local mapData = {}
    for k, v in pairs(rawMapData) do mapData[k] = v end
    session.currentMapData = mapData
    session.tempEventOverrides = {}
    
    local grid, startX, startY
    if mapData.safe then
        -- Load fixed town layout
        grid = {}
        for y, rowStr in ipairs(mapData.layout) do
            grid[y] = {}
            for x = 1, #rowStr do
                grid[y][x] = rowStr:sub(x, x)
            end
        end
        -- Spawn point configuration from system settings
        local startXDef = session.loader.system and session.loader.system.spawn and session.loader.system.spawn.x or 10
        local startYDef = session.loader.system and session.loader.system.spawn and session.loader.system.spawn.y or 17
        startX, startY = startXDef + 1, startYDef + 1 -- Lua is 1-indexed, systems spawn is 0-indexed

        -- Safe/authored maps use the same tileset fixture rules as generated
        -- maps. Without this, wall fixtures configured in a tileset never
        -- appeared while testing a town.
        session.generatedLightObjects = exploration.injectTilesetFeatures(grid, mapData)
        if not mapData.light then
            local lightSources = {}
            for _, source in ipairs(mapData.lightObjects or {}) do table.insert(lightSources, source) end
            for _, source in ipairs(session.generatedLightObjects) do table.insert(lightSources, source) end
            if #lightSources > 0 then
                session.currentMapData.runtimeLight = lighting.bake(grid, lightSources)
            end
        end
    else
        -- Procedurally generate floor layout and inject events
        local generatedEvents, generatedLights
        grid, startX, startY, generatedEvents, generatedLights = exploration.generateDungeon(mapData, os.time() + mapIdx, session)
        session.currentMapData.events = generatedEvents
        session.generatedLightObjects = generatedLights
        session.currentMapData.runtimeLight = lighting.bake(grid, generatedLights)
    end
    
    session.mapGrid = grid
    exploration.buildOverrideIndex(session)
    session.playerX = startX
    session.playerY = startY
    session.playerDir = session.loader.system and session.loader.system.spawn and session.loader.system.spawn.dir or "N"
    
    -- Initialize Fog-of-War (visited tiles)
    session.visitedGrid = {}
    local isSafeMap = mapData.safe == true
    for y = 1, #grid do
        session.visitedGrid[y] = {}
        for x = 1, #grid[y] do
            session.visitedGrid[y][x] = isSafeMap
        end
    end
    if not isSafeMap then
        exploration.revealFog(session)
    end
end

function exploration.revealFog(session)
    local x, y = session.playerX, session.playerY
    session.visitedGrid[y][x] = true
    
    -- Reveal adjacent tiles
    for _, dirInfo in pairs(DIRS) do
        local ax, ay = x + dirInfo.dx, y + dirInfo.dy
        if session.mapGrid[ay] and session.mapGrid[ay][ax] then
            session.visitedGrid[ay][ax] = true
        end
    end
end

-- Turn player
function exploration.turnLeft(session)
    local idx = 1
    for i, d in ipairs(DIR_ORDER) do
        if d == session.playerDir then idx = i break end
    end
    idx = (idx - 2) % 4 + 1
    session.playerDir = DIR_ORDER[idx]
end

function exploration.turnRight(session)
    local idx = 1
    for i, d in ipairs(DIR_ORDER) do
        if d == session.playerDir then idx = i break end
    end
    idx = idx % 4 + 1
    session.playerDir = DIR_ORDER[idx]
end

-- Attempts to move the player by a tile delta; drains MP outside safe maps
local function tryMove(session, dx, dy)
    local targetX = session.playerX + dx
    local targetY = session.playerY + dy

    local row = session.mapGrid[targetY]
    local ov = session.overrideIndex and session.overrideIndex[targetX .. "," .. targetY]
    local passable
    if ov and ov.passable ~= nil then
        passable = ov.passable -- illusory wall (true) / one-way wall (false) override the char
    else
        passable = row and row[targetX] and row[targetX] ~= "#"
    end
    if passable then
        session.playerX = targetX
        session.playerY = targetY
        exploration.revealFog(session)

        -- The step's MP cost is charged by the exploration.step flow (the
        -- combined MPD of the living party), not here. It used to be a flat
        -- dungeon.moveMpDrain applied in Lua, which charged the same 1 MP
        -- whether the Summoner was carrying a Pixie or a Bahamut and so hid
        -- the entire expedition economy.
        return true -- Moved successfully
    end
    return false -- Blocked by wall
end

local function dirIndex(session)
    for i, d in ipairs(DIR_ORDER) do
        if d == session.playerDir then return i end
    end
    return 1
end

-- Move player
function exploration.moveForward(session)
    local dirInfo = DIRS[session.playerDir]
    return tryMove(session, dirInfo.dx, dirInfo.dy)
end

function exploration.moveBackward(session)
    local dirInfo = DIRS[session.playerDir]
    return tryMove(session, -dirInfo.dx, -dirInfo.dy)
end

function exploration.strafeLeft(session)
    local leftDir = DIRS[DIR_ORDER[(dirIndex(session) - 2) % 4 + 1]]
    return tryMove(session, leftDir.dx, leftDir.dy)
end

function exploration.strafeRight(session)
    local rightDir = DIRS[DIR_ORDER[dirIndex(session) % 4 + 1]]
    return tryMove(session, rightDir.dx, rightDir.dy)
end

-- Checks what event tile is directly in front of the player
function exploration.getFrontTile(session)
    local dirInfo = DIRS[session.playerDir]
    local tx = session.playerX + dirInfo.dx
    local ty = session.playerY + dirInfo.dy
    local row = session.mapGrid[ty]
    if row then
        return row[tx], tx, ty
    end
    return nil, tx, ty
end

return exploration
