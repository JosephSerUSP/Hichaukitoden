local config = require("engine.config")

local exploration = {}

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
function exploration.generateDungeon(mapData, seed)
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
    local numRooms = math.random(dungeonConf("genMinRooms", 4), dungeonConf("genMaxRooms", 6))
    local minRoom = dungeonConf("genMinRoomSize", 3)
    local maxRoom = dungeonConf("genMaxRoomSize", 5)

    for r = 1, numRooms do
        local rw = math.random(minRoom, maxRoom)
        local rh = math.random(minRoom, maxRoom)
        local rx = math.random(2, width - rw - 1)
        local ry = math.random(2, height - rh - 1)
        
        -- Carve room
        for y = ry, ry + rh - 1 do
            for x = rx, rx + rw - 1 do
                grid[y][x] = "."
            end
        end
        table.insert(rooms, { x = rx, y = ry, w = rw, h = rh, cx = math.floor(rx + rw/2), cy = math.floor(ry + rh/2) })
    end
    
    -- Connect rooms with hallways
    for i = 1, #rooms - 1 do
        local r1 = rooms[i]
        local r2 = rooms[i+1]
        
        -- Horizontal tunnel
        local x1, x2 = math.min(r1.cx, r2.cx), math.max(r1.cx, r2.cx)
        for x = x1, x2 do
            grid[r1.cy][x] = "."
        end
        
        -- Vertical tunnel
        local y1, y2 = math.min(r1.cy, r2.cy), math.max(r1.cy, r2.cy)
        for y = y1, y2 do
            grid[y][r2.cx] = "."
        end
    end
    
    local startX, startY = rooms[1].cx, rooms[1].cy
    local exitX, exitY = rooms[#rooms].cx, rooms[#rooms].cy
    
    local generatedEvents = {}
    
    local openTiles = {}
    for y = 2, height - 1 do
        for x = 2, width - 1 do
            if grid[y][x] == "." and not (x == startX and y == startY) and not (x == exitX and y == exitY) then
                table.insert(openTiles, { x = x, y = y })
            end
        end
    end
    
    -- Shuffle open tiles
    for i = #openTiles, 2, -1 do
        local j = math.random(i)
        openTiles[i], openTiles[j] = openTiles[j], openTiles[i]
    end
    
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
                table.insert(generatedEvents, {
                    id = ev.id,
                    x = tx - 1,
                    y = ty - 1,
                    scriptId = ev.scriptId,
                    sprite = ev.sprite,
                    trigger = ev.trigger or "interact",
                    script = ev.script
                })
            end
        end
    end
    
    return grid, startX, startY, generatedEvents
end

-- Initialize map state in GameSession
function exploration.loadMap(session, mapIdx)
    local mapData = session.loader.maps[mapIdx]
    session.currentMapIndex = mapIdx
    session.currentMapData = mapData
    
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
    else
        -- Procedurally generate floor layout and inject events
        local generatedEvents
        grid, startX, startY, generatedEvents = exploration.generateDungeon(mapData, os.time() + mapIdx)
        session.currentMapData.events = generatedEvents
    end
    
    session.mapGrid = grid
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
    if row and row[targetX] and row[targetX] ~= "#" then
        session.playerX = targetX
        session.playerY = targetY
        exploration.revealFog(session)

        if not session.currentMapData.safe then
            session.mp = math.max(0, session.mp - dungeonConf("moveMpDrain", 1))
        end

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
