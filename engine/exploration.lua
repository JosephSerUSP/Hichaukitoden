local exploration = {}

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
    
    local width, height = 21, 21
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = "#" -- Solid wall
        end
    end
    
    local rooms = {}
    local numRooms = math.random(4, 6)
    
    for r = 1, numRooms do
        local rw = math.random(3, 5)
        local rh = math.random(3, 5)
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
    
    -- Place Stairs Up in room 1, Stairs Down in last room
    local startX, startY = rooms[1].cx, rooms[1].cy
    grid[startY][startX] = "S"
    
    local exitX, exitY = rooms[#rooms].cx, rooms[#rooms].cy
    grid[exitY][exitX] = "E"
    
    -- Place extra events (recovery, chest, encounter, recruit)
    local openTiles = {}
    for y = 2, height - 1 do
        for x = 2, width - 1 do
            if grid[y][x] == "." then
                table.insert(openTiles, { x = x, y = y })
            end
        end
    end
    
    -- Shuffle open tiles
    for i = #openTiles, 2, -1 do
        local j = math.random(i)
        openTiles[i], openTiles[j] = openTiles[j], openTiles[i]
    end
    
    -- Place events based on counts
    local placedCount = 1
    
    -- Shrines/Recovery sites
    grid[openTiles[placedCount].y][openTiles[placedCount].x] = "R"
    placedCount = placedCount + 1
    
    -- Treasures
    for i = 1, 2 do
        if openTiles[placedCount] then
            grid[openTiles[placedCount].y][openTiles[placedCount].x] = "T"
            placedCount = placedCount + 1
        end
    end
    
    -- Recruits
    if math.random() < 0.7 and openTiles[placedCount] then
        grid[openTiles[placedCount].y][openTiles[placedCount].x] = "U"
        placedCount = placedCount + 1
    end
    
    -- Enemies
    for i = 1, 4 do
        if openTiles[placedCount] then
            grid[openTiles[placedCount].y][openTiles[placedCount].x] = "M"
            placedCount = placedCount + 1
        end
    end
    
    return grid, startX, startY
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
                -- Find starting position (usually near center)
                if grid[y][x] == "." and not startX then
                    startX, startY = x, y
                end
            end
        end
        -- Spawn point configuration from system settings, fallback to center bottom
        local startXDef = session.loader.system and session.loader.system.spawn and session.loader.system.spawn.x or 10
        local startYDef = session.loader.system and session.loader.system.spawn and session.loader.system.spawn.y or 17
        startX, startY = startXDef, startYDef
    else
        -- Procedurally generate floor layout
        grid, startX, startY = exploration.generateDungeon(mapData, os.time() + mapIdx)
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

-- Move player
function exploration.moveForward(session)
    local dirInfo = DIRS[session.playerDir]
    local targetX = session.playerX + dirInfo.dx
    local targetY = session.playerY + dirInfo.dy
    
    local row = session.mapGrid[targetY]
    if row and row[targetX] and row[targetX] ~= "#" then
        session.playerX = targetX
        session.playerY = targetY
        exploration.revealFog(session)
        
        -- Drains MP on move if not on a safe map
        if not session.currentMapData.safe then
            session.mp = math.max(0, session.mp - 1)
        end
        
        return true -- Moved successfully
    end
    return false -- Blocked by wall
end

function exploration.moveBackward(session)
    local dirInfo = DIRS[session.playerDir]
    local targetX = session.playerX - dirInfo.dx
    local targetY = session.playerY - dirInfo.dy
    
    local row = session.mapGrid[targetY]
    if row and row[targetX] and row[targetX] ~= "#" then
        session.playerX = targetX
        session.playerY = targetY
        exploration.revealFog(session)
        
        -- Drains MP on move if not on a safe map
        if not session.currentMapData.safe then
            session.mp = math.max(0, session.mp - 1)
        end
        
        return true
    end
    return false
end

function exploration.strafeLeft(session)
    local idx = 1
    for i, d in ipairs(DIR_ORDER) do
        if d == session.playerDir then idx = i; break end
    end
    local leftDir = DIRS[DIR_ORDER[(idx - 2) % 4 + 1]]
    local targetX = session.playerX + leftDir.dx
    local targetY = session.playerY + leftDir.dy
    local row = session.mapGrid[targetY]
    if row and row[targetX] and row[targetX] ~= "#" then
        session.playerX = targetX
        session.playerY = targetY
        exploration.revealFog(session)
        if not session.currentMapData.safe then
            session.mp = math.max(0, session.mp - 1)
        end
        return true
    end
    return false
end

function exploration.strafeRight(session)
    local idx = 1
    for i, d in ipairs(DIR_ORDER) do
        if d == session.playerDir then idx = i; break end
    end
    local rightDir = DIRS[DIR_ORDER[idx % 4 + 1]]
    local targetX = session.playerX + rightDir.dx
    local targetY = session.playerY + rightDir.dy
    local row = session.mapGrid[targetY]
    if row and row[targetX] and row[targetX] ~= "#" then
        session.playerX = targetX
        session.playerY = targetY
        exploration.revealFog(session)
        if not session.currentMapData.safe then
            session.mp = math.max(0, session.mp - 1)
        end
        return true
    end
    return false
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
