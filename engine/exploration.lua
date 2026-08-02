local config = require("engine.config")
local conditions = require("engine.conditions")
local formulaEngine = require("engine.formula")
local lighting = require("engine.lighting")
local loader = require("data.loader")
local fixturePredicates = require("engine.fixture_predicates")
local tilesetResolver = require("engine.tileset_resolver")

local exploration = {}

-- RPG Maker-style event pages: `ev.pages` is an ordered list of
-- {condition, commands/scriptId, sprite, trigger, name, ...} overrides.
-- `commands` owns a custom command list; `scriptId` links a common-event
-- template whose commands and presentation defaults are inherited. The
-- obsolete `script` field is not supported. The
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

-- Where the player actually stands when they arrive at a staircase. Entrance
-- and exit staircases are WALL events -- they are carved into the rock, so the
-- landmark cell itself is a "#" and nobody ever stands on it. The party arrives
-- on the passable cell beside it, facing the stairs.
--
-- `soft` returns nil instead of raising when the landmark is walled in on all
-- four sides; fixture validation asks speculatively and has a fallback, while
-- map loading genuinely cannot continue.
function exploration.arrivalBeside(grid, landmarkX, landmarkY, soft)
    local candidates = {
        { landmarkX, landmarkY + 1, "N" },
        { landmarkX, landmarkY - 1, "S" },
        { landmarkX + 1, landmarkY, "W" },
        { landmarkX - 1, landmarkY, "E" },
    }
    for _, c in ipairs(candidates) do
        local row = grid[c[2]]
        if row and row[c[1]] and row[c[1]] ~= "#" then
            return c[1], c[2], c[3]
        end
    end
    if soft then return nil end
    error("exploration.loadMap: no passable arrival tile beside staircase")
end

-- Cells reachable on foot from (startX, startY), as a set of "x,y" keys.
-- `blocked` is the set of floor cells occupied by solid fixtures.
local function reachableCells(grid, blocked, startX, startY)
    local seen, stack, count = {}, { { startX, startY } }, 0
    local startKey = startX .. "," .. startY
    seen[startKey] = true
    count = 1
    while #stack > 0 do
        local cell = table.remove(stack)
        for _, dir in ipairs(DIR_ORDER) do
            local d = DIRS[dir]
            local nx, ny = cell[1] + d.dx, cell[2] + d.dy
            local key = nx .. "," .. ny
            local row = grid[ny]
            if not seen[key] and row and row[nx] and row[nx] ~= "#" and not blocked[key] then
                seen[key] = true
                count = count + 1
                stack[#stack + 1] = { nx, ny }
            end
        end
    end
    return seen, count
end

-- Cells a solid fixture must never occupy, whatever the predicates say: the
-- spawn, the entrance/exit staircases, and any cell carrying an event. Blocking
-- one of these does not sever the map, so the reachability rule below would let
-- it through -- it just makes something unusable, which is worse for being
-- subtle. Keys are 1-indexed grid coordinates; the sources are all 0-indexed.
local function protectedFixtureCells(grid, mapData, generatedZones, spawnCell)
    local protected = {}
    local function mark(x, y)
        if x and y then protected[(x + 1) .. "," .. (y + 1)] = true end
    end
    -- The RESOLVED spawn, passed in by the caller, not `mapData.spawn` alone.
    -- Most maps do not author a spawn and fall back to system.json's, so
    -- reading only the map's own field protected nothing on exactly the maps
    -- that needed it -- and a 1.1-cell-tall street lamp landed on the town's
    -- start cell, putting the camera inside the model and filling the screen
    -- with its interior faces. G5 caught it.
    if spawnCell then mark(spawnCell.x, spawnCell.y) end
    local spawn = mapData and mapData.spawn
    if spawn then mark(spawn.x, spawn.y) end
    for _, ev in ipairs((mapData and mapData.events) or {}) do
        mark(ev.x, ev.y)
    end
    for _, zone in ipairs(generatedZones or {}) do
        for _, tag in ipairs(zone.tags or {}) do
            if tag == "entrance" or tag == "exit" or tag == "anchor" then
                mark(zone.x, zone.y)
            end
            -- Marking the staircase cell alone protects nothing usable: a
            -- staircase is a wall event, so no fixture could stand there
            -- anyway. What has to stay clear is the cell the party ARRIVES on
            -- -- sealing that is legal under the one-cell rule (it removes
            -- exactly itself) and still makes the stairs unusable, or, at the
            -- entrance, drops the party into a one-cell tomb.
            if tag == "entrance" or tag == "exit" then
                local ax, ay = exploration.arrivalBeside(grid, zone.x + 1, zone.y + 1, true)
                if ax then mark(ax - 1, ay - 1) end
            end
        end
    end
    return protected
end

-- Is a solid fixture standing on this cell? Coordinates are 0-indexed, matching
-- the placement records.
--
-- The answer is read from the PLACEMENT (`blocks`), not re-resolved from the
-- tileset, so it survives save/load without the tileset having to be resolved
-- again -- and so a map already in a save keeps whatever solidity it was
-- generated with, rather than silently changing under an edited tileset.
function exploration.fixtureBlocksAt(session, x, y)
    local index = session.fixtureBlockIndex
    if index == nil then
        index = {}
        for _, placement in ipairs(session.generatedFeatures or {}) do
            if placement.blocks then index[placement.x .. "," .. placement.y] = true end
        end
        session.fixtureBlockIndex = index
    end
    return index[x .. "," .. y] == true
end

-- Generate random room-based dungeon map
-- Resolve the visual fixtures defined by a tileset into per-map material
-- placements. This applies to authored safe maps as well as generated
-- dungeons, so a fixture configured in Tileset Studio is actually visible
-- when testing a town map.
--
-- A fixture with `blocksMovement` is SOLID -- a barrel stack is two metres of
-- timber and the player should not walk through it. That cannot simply be
-- switched on at movement time, because a solid fixture dropped in a one-wide
-- corridor severs the map and a fixture in an alcove mouth strands whatever is
-- behind it, and the predicates that place fixtures know nothing about
-- topology. So solidity is decided HERE, against one invariant:
--
--   blocking a cell may remove ONLY THAT CELL from the reachable set.
--
-- That single rule covers both failures: a severed corridor loses many cells, a
-- stranded alcove loses a few, and a harmless barrel against a room wall loses
-- exactly one. Placements are validated incrementally in authored order, so
-- fixtures that are each individually safe but jointly a cut are caught too --
-- the second one is tested against a map that already contains the first.
function exploration.injectTilesetFeatures(grid, mapData, generatedZones, spawnCell)
    local tilesetDef = tilesetResolver.resolve(loader, mapData)
    local featureList = (tilesetDef and tilesetDef.features) or {}
    local prefabById = {}
    for _, prefab in ipairs((tilesetDef and tilesetDef.fixturePrefabs) or {}) do
        prefabById[prefab.id] = prefab
    end
    local generated, lights, occupied = {}, {}, {}
    local predicateContext = fixturePredicates.newContext(grid, mapData, generatedZones)
    local height = #grid

    -- Solid-fixture bookkeeping. Built lazily: a tileset with no `blocksMovement`
    -- feature never pays for a flood fill.
    local blocked = {}
    local protected = nil
    local reachStartX, reachStartY, reachCount = nil, nil, nil
    local function ensureReachability()
        if reachCount then return reachCount ~= nil end
        protected = protectedFixtureCells(grid, mapData, generatedZones, spawnCell)
        -- "Reachable" has to mean "reachable BY THE PLAYER", so the flood must
        -- start where the player actually arrives. Getting this wrong is subtle:
        -- flooding from an arbitrary cell validates fixtures against the wrong
        -- component, and a fixture in a region the player cannot reach passes a
        -- check that meant nothing. Prefer the generated entrance, then an
        -- authored spawn, and only then fall back to scan order.
        local function usable(gx, gy)
            return grid[gy] and grid[gy][gx] and grid[gy][gx] ~= "#"
        end
        -- The entrance staircase is a wall event, so the entrance CELL is
        -- normally a "#" and `usable` rejects it. Reading that as "no entrance"
        -- and falling through to scan order was the bug this guard exists to
        -- prevent: validation then ran from an arbitrary far corner, where
        -- sealing the party's own arrival cell removes exactly one cell and so
        -- passes the rule -- a generated floor that starts with the party
        -- bricked into a one-tile pocket. Resolve the arrival cell instead.
        for _, zone in ipairs(generatedZones or {}) do
            for _, tag in ipairs(zone.tags or {}) do
                if tag == "entrance" then
                    if usable(zone.x + 1, zone.y + 1) then
                        reachStartX, reachStartY = zone.x + 1, zone.y + 1
                    else
                        local ax, ay = exploration.arrivalBeside(
                            grid, zone.x + 1, zone.y + 1, true)
                        if ax then reachStartX, reachStartY = ax, ay end
                    end
                end
            end
        end
        local spawn = mapData and mapData.spawn
        if reachStartX then
            -- entrance wins
        elseif spawnCell and usable(spawnCell.x + 1, spawnCell.y + 1) then
            reachStartX, reachStartY = spawnCell.x + 1, spawnCell.y + 1
        elseif spawn and spawn.x and spawn.y and usable(spawn.x + 1, spawn.y + 1) then
            reachStartX, reachStartY = spawn.x + 1, spawn.y + 1
        else
            for zy = 1, height do
                for zx = 1, #grid[zy] do
                    if grid[zy][zx] ~= "#" then
                        reachStartX, reachStartY = zx, zy
                        break
                    end
                end
                if reachStartX then break end
            end
        end
        if not reachStartX then return false end
        local _, count = reachableCells(grid, blocked, reachStartX, reachStartY)
        reachCount = count
        return true
    end

    -- May this cell become solid? See the invariant in the header comment.
    local function mayBlock(x, y)
        if not ensureReachability() then return false end
        local key = x .. "," .. y
        if protected[key] then return false end
        if x == reachStartX and y == reachStartY then return false end
        blocked[key] = true
        local _, count = reachableCells(grid, blocked, reachStartX, reachStartY)
        -- Exactly one cell left the reachable set, and it must be this one --
        -- blocking a cell can only remove cells, and this cell is certainly
        -- gone. So a loss of exactly one proves nothing else was cut off, and
        -- the `protected` early-return above already kept this cell from being
        -- one that matters. No separate protected-reachability sweep is needed.
        --
        -- An earlier version did sweep, requiring every protected cell to be
        -- reachable -- which quietly refused EVERY solid fixture on a real map,
        -- because protected cells include event tiles that are walls or sit
        -- outside the walkable component, and those are never in `seen`.
        -- A cell that was already unreachable also fails here, correctly: the
        -- count would not drop at all.
        local ok = (count == reachCount - 1)
        if ok then
            reachCount = count
        else
            blocked[key] = nil
        end
        return ok
    end
    for featureIndex, feat in ipairs(featureList) do
        local prefab = feat.prefab and prefabById[feat.prefab] or nil
        if feat.prefab and not prefab then
            error("fixture '" .. tostring(feat.id) .. "' references unknown prefab '"
                .. tostring(feat.prefab) .. "'")
        end
        if feat.prefab and feat.where ~= nil then
            error("fixture '" .. tostring(feat.id) .. "' cannot author both prefab and where")
        end
        local probability = prefab and prefab.probability or nil
        local prob = feat.injectProbability
            or (probability and probability.default) or 0.1
        local predicate = prefab and prefab.where or feat.where
        for y = 2, height - 1 do
            local width = #grid[y]
            for x = 2, width - 1 do
                local key = x .. "," .. y
                local wantsWall = feat.role == "wall_feature"
                local eligibleCell = (wantsWall and grid[y][x] == "#")
                    or (feat.role == "floor_feature" and grid[y][x] ~= "#")
                if eligibleCell and not occupied[key] then
                    local roll = exploration.cellHash(x, y,
                        15485863 + featureIndex * 32452843,
                        49979687 + featureIndex * 67867967) / 2147483647
                    -- `blocksMovement` is a floor-fixture property: a wall
                    -- fixture already stands on a "#", which blocks anyway.
                    local wantsSolid = feat.blocksMovement == true and not wantsWall
                    if fixturePredicates.matches(predicate, predicateContext, x, y)
                            and roll < prob
                            -- Topology has the last word. A fixture the
                            -- predicates happily allow is still refused here if
                            -- it would cut the map, and the cell simply stays
                            -- empty -- silently dropping the decoration is much
                            -- cheaper than an unwinnable floor.
                            and (not wantsSolid or mayBlock(x, y)) then
                        local placement = { x = x - 1, y = y - 1, material = feat.id }
                        if wantsSolid then placement.blocks = true end
                        generated[#generated + 1] = placement
                        occupied[key] = true
                        fixturePredicates.addFeature(predicateContext, x, y, feat.id)
                        if feat.emitsLight then
                            lights[#lights + 1] = {
                                x = placement.x, y = placement.y, material = feat.id,
                                color = feat.emitsLight.color,
                                radius = feat.emitsLight.radius,
                                falloff = feat.emitsLight.falloff,
                            }
                        end
                    end
                end
            end
        end
    end
    return generated, lights
end

-- Selects a weighted variant from a variant pool (walls/floors/ceilings)
-- deterministically based on seed key (e.g. "x,y") or randomly.
function exploration.cellHash(mapX, mapY, saltA, saltB)
    local h = (mapX * saltA + mapY * saltB) % 2147483647
    if h < 0 then h = -h end
    return h
end

function exploration.resolveTilesetVariant(pool, mapX, mapY, saltA, saltB)
    if not pool or #pool == 0 then return nil end
    local totalWeight = 0
    for _, item in ipairs(pool) do
        totalWeight = totalWeight + (item.weight or 1)
    end
    if totalWeight <= 0 then error("tileset variant pool has no positive weight", 0) end
    local r = exploration.cellHash(mapX, mapY, saltA, saltB) % totalWeight

    local accumulated = 0
    for _, item in ipairs(pool) do
        accumulated = accumulated + (item.weight or 1)
        if r < accumulated then
            return item
        end
    end
    return pool[#pool]
end

function exploration.generateDungeon(mapData, seed, session)
    if seed then math.randomseed(seed) end
    
    local dungeon = loader.system and loader.system.dungeon or {}
    local profileId = mapData.generationProfile or dungeon.generationProfile
    local profile = dungeon.generationProfiles and dungeon.generationProfiles[profileId]
    if not profile then
        error("generateDungeon: unknown generation profile '" .. tostring(profileId) .. "'")
    end
    local width = mapData.width or 21
    local height = mapData.height or 21
    local genMinRooms, genMaxRooms = profile.minRooms, profile.maxRooms
    local genMinRoomSize, genMaxRoomSize = profile.minRoomSize, profile.maxRoomSize
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
    local numProcedural = math.random(genMinRooms, genMaxRooms)
    local minRoom = genMinRoomSize
    local maxRoom = genMaxRoomSize

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
    local corridorCarved = {}
    local function carveCorridor(x, y)
        if grid[y][x] == "#" then
            grid[y][x] = "."
            corridorCarved[x .. "," .. y] = true
        end
    end
    for i = 1, #rooms - 1 do
        local r1 = rooms[i]
        local r2 = rooms[i+1]
        
        local x1, x2 = math.min(r1.cx, r2.cx), math.max(r1.cx, r2.cx)
        for x = x1, x2 do
            carveCorridor(x, r1.cy)
        end
        
        local y1, y2 = math.min(r1.cy, r2.cy), math.max(r1.cy, r2.cy)
        for y = y1, y2 do
            carveCorridor(r2.cx, y)
        end
    end
    
    -- Wall-bound events use the same geometry as town doors: their sprite is
    -- composited into a solid wall cell, with a passable approach cell beside
    -- it. Pick surviving room-boundary walls after corridors have been carved.
    local function wallSlotsForRoom(room)
        local slots = {}
        local function add(wx, wy, ax, ay)
            if grid[wy] and grid[wy][wx] == "#"
                    and grid[ay] and grid[ay][ax] == "." then
                table.insert(slots, { x = wx, y = wy })
            end
        end
        for x = room.x, room.x + room.w - 1 do
            add(x, room.y - 1, x, room.y)
            add(x, room.y + room.h, x, room.y + room.h - 1)
        end
        for y = room.y, room.y + room.h - 1 do
            add(room.x - 1, y, room.x, y)
            add(room.x + room.w, y, room.x + room.w - 1, y)
        end
        -- A connection can consume every cell on a small room boundary.
        -- Fall back to surviving walls anywhere in the generated structure,
        -- ordered by proximity to the intended room.
        if #slots == 0 then
            for y = 2, height - 1 do
                for x = 2, width - 1 do
                    if grid[y][x] == "#" and (
                            grid[y - 1][x] == "." or grid[y + 1][x] == "."
                            or grid[y][x - 1] == "." or grid[y][x + 1] == ".") then
                        table.insert(slots, { x = x, y = y })
                    end
                end
            end
            table.sort(slots, function(a, b)
                local adx, ady = a.x - room.cx, a.y - room.cy
                local bdx, bdy = b.x - room.cx, b.y - room.cy
                return adx * adx + ady * ady < bdx * bdx + bdy * bdy
            end)
        end
        return slots
    end

    local entranceSlots = wallSlotsForRoom(rooms[1])
    local exitSlots = wallSlotsForRoom(rooms[#rooms])
    if #entranceSlots == 0 or #exitSlots == 0 then
        error("generateDungeon: room has no wall slot for staircase")
    end
    local startX, startY = entranceSlots[1].x, entranceSlots[1].y
    local exitX, exitY = exitSlots[1].x, exitSlots[1].y
    if startX == exitX and startY == exitY and #exitSlots > 1 then
        exitX, exitY = exitSlots[2].x, exitSlots[2].y
    end

    -- Optional structural thresholds. Only cells actually carved out of wall
    -- by the corridor pass qualify; ordinary room floors therefore never turn
    -- into openings. The outside edge of each room is deterministic and an
    -- opening remains an ordinary passable cell to movement/pathing.
    if mapData.generateOpenings == true then
        local marked = {}
        local function mark(x, y)
            local key = x .. "," .. y
            if corridorCarved[key] and not marked[key]
                    and not (x == startX and y == startY)
                    and not (x == exitX and y == exitY) then
                grid[y][x] = "o"
                marked[key] = true
            end
        end
        for _, room in ipairs(rooms) do
            for x = room.x, room.x + room.w - 1 do
                mark(x, room.y - 1)
                mark(x, room.y + room.h)
            end
            for y = room.y, room.y + room.h - 1 do
                mark(room.x - 1, y)
                mark(room.x + room.w, y)
            end
        end
    end
    
    local generatedEvents = {}
    
    -- Gather candidate open tiles, prioritizing ROOM tiles over corridor tiles
    local roomOpenTiles = {}
    local corridorOpenTiles = {}
    local wallOpenTiles = {}
    
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
    
    for _, room in ipairs(rooms) do
        if room.allowRandomEvents then
            for _, tile in ipairs(wallSlotsForRoom(room)) do
                if not (tile.x == startX and tile.y == startY)
                        and not (tile.x == exitX and tile.y == exitY) then
                    table.insert(wallOpenTiles, tile)
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

    for i = #wallOpenTiles, 2, -1 do
        local j = math.random(i)
        wallOpenTiles[i], wallOpenTiles[j] = wallOpenTiles[j], wallOpenTiles[i]
    end

    -- Combined pool: room tiles first, fallback to corridors if rooms run out
    local openTiles = {}
    for _, t in ipairs(roomOpenTiles) do table.insert(openTiles, t) end
    for _, t in ipairs(corridorOpenTiles) do table.insert(openTiles, t) end

    local generatedZones = {}
    local function addZone(x, y, tags)
        generatedZones[#generatedZones + 1] = { x = x - 1, y = y - 1, tags = tags }
    end
    for y = 1, height do
        for x = 1, width do
            if grid[y][x] ~= "#" then
                local tags, roomMatch = {}, nil
                for _, room in ipairs(rooms) do
                    if x >= room.x and x < room.x + room.w
                            and y >= room.y and y < room.y + room.h then
                        roomMatch = room
                        break
                    end
                end
                tags[#tags + 1] = roomMatch and "room" or "corridor"
                if roomMatch and roomMatch.isAnchor then tags[#tags + 1] = "anchor" end
                addZone(x, y, tags)
            end
        end
    end
    addZone(startX, startY, { "entrance" })
    addZone(exitX, exitY, { "exit" })

    local generatedFeatures, generatedLights =
        exploration.injectTilesetFeatures(grid, mapData, generatedZones)
    
    local placedCount = 1
    
    -- An authored stairs marker says this floor has a way down; generation
    -- owns its resolved position. A deepest floor omits the marker and gets no
    -- phantom exit.
    local exitScriptId = dungeonConf("exitScriptId", 1)
    local hasDownStairs = false
    for _, ev in ipairs(mapData.events or {}) do
        if ev.scriptId == exitScriptId then hasDownStairs = true break end
    end
    if hasDownStairs then
        table.insert(generatedEvents, {
            id = 99,
            x = exitX - 1,
            y = exitY - 1,
            scriptId = exitScriptId,
            sprite = dungeonConf("exitSprite", "assets/sprites/NPC00.png"),
            trigger = "bump",
            wallEvent = true
        })
    end

    table.insert(generatedEvents, {
        id = 98,
        x = startX - 1,
        y = startY - 1,
        scriptId = dungeonConf("entranceScriptId", 40),
        sprite = dungeonConf("entranceSprite", "assets/sprites/NPC00.png"),
        trigger = "bump",
        wallEvent = true
    })
    
    -- Process events from mapData.events database
    if mapData.events then
        for _, ev in ipairs(mapData.events) do
            if ev.scriptId ~= exitScriptId then
            local tx, ty
            if ev.spawn == "Fixed" and ev.x and ev.y then
                tx, ty = ev.x + 1, ev.y + 1
            elseif ev.spawn == "Random" or not (ev.x and ev.y) then
                local tile = ev.wallEvent and table.remove(wallOpenTiles)
                    or openTiles[placedCount]
                if tile then
                    tx, ty = tile.x, tile.y
                    if not ev.wallEvent then placedCount = placedCount + 1 end
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
                placed.trigger = ev.wallEvent and "bump" or (ev.trigger or "interact")
                table.insert(generatedEvents, placed)
            end
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
                local spritePath = (actorData and actorData.smallBattler) or "assets/sprites/OBJ_Statue_001.png"
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
    
    return grid, startX, startY, exitX, exitY, generatedEvents,
        generatedFeatures, generatedLights, generatedZones
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
    session.mapStructureRevision = (session.mapStructureRevision or 0) + 1
    local ov = session.overrideIndex and session.overrideIndex[gx .. "," .. gy]
    if ov then ov.mutateTo = nil end -- consumed: already applied to the grid
    return true
end

local function cacheCurrentMap(session)
    local mapData = session.currentMapData
    if not mapData or mapData.safe == true or not session.currentMapIndex then return end
    session.mapStates = session.mapStates or {}
    session.mapStates[session.currentMapIndex] = {
        mapGrid = session.mapGrid,
        visitedGrid = session.visitedGrid,
        events = mapData.events,
        runtimeLight = mapData.runtimeLight,
        generatedLightObjects = session.generatedLightObjects,
        generatedFeatures = session.generatedFeatures,
        generatedZones = session.generatedZones,
        entranceX = mapData.entranceX,
        entranceY = mapData.entranceY,
        exitX = mapData.exitX,
        exitY = mapData.exitY,
        playerX = session.playerX,
        playerY = session.playerY,
        playerDir = session.playerDir,
    }
end

function exploration.applyMapPresentation(session, mapIdx, spec)
    mapIdx = mapIdx or session.currentMapIndex
    if not mapIdx then error("applyMapPresentation: no target map") end
    spec = spec or {}
    session.mapPresentationOverrides = session.mapPresentationOverrides or {}
    local saved = session.mapPresentationOverrides[mapIdx] or {}
    if spec.tileset ~= nil then saved.tileset = spec.tileset end
    if spec.fogPreset ~= nil then saved.fogPreset = spec.fogPreset end
    if spec.ambient ~= nil then saved.ambient = spec.ambient end
    session.mapPresentationOverrides[mapIdx] = saved

    if session.currentMapIndex ~= mapIdx or not session.currentMapData then return end
    local mapData = session.currentMapData
    if saved.tileset then mapData.tileset = saved.tileset end
    if saved.fogPreset then mapData.fog = { preset = saved.fogPreset } end
    if saved.ambient then
        local sources = {}
        for _, source in ipairs(mapData.lightObjects or {}) do table.insert(sources, source) end
        for _, source in ipairs(session.generatedLightObjects or {}) do table.insert(sources, source) end
        mapData.runtimeLight = lighting.bake(session.mapGrid, sources, saved.ambient)
    end
    session.mapPresentationRevision = (session.mapPresentationRevision or 0) + 1
end

local arrivalBeside = exploration.arrivalBeside

-- Initialize or restore map state in GameSession. `arrival` is authored by the
-- transfer command: entrance when descending, exit when climbing, and resume
-- for a temporary town portal.
function exploration.loadMap(session, mapIdx, opts)
    opts = opts or {}
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
    if wasSafe and goingDangerous and opts.arrival ~= "resume" and session.party then
        -- A completed physical return ends the expedition. The next departure
        -- gets a fresh labyrinth, while every transfer within an expedition
        -- restores the cached route. Portal resume is explicitly exempt.
        session.mapStates = {}
        require("engine.flow").run("exploration.expedition_start", { session = session, party = session.party })
    end
    cacheCurrentMap(session)
    session.currentMapIndex = mapIdx
    -- How deep the party is, is a property of the map it is standing on, not a
    -- counter that one command remembers to bump. Deriving it here means every
    -- transfer keeps it true -- including going back up, which the old
    -- increment-only counter never did: returning to Town left the party
    -- "on floor 6" for enemy levels and recruitment.
    session.dungeonFloor = rawMapData.depth or session.dungeonFloor or 0
    local mapData = {}
    for k, v in pairs(rawMapData) do mapData[k] = v end
    local presentationOverride = session.mapPresentationOverrides
        and session.mapPresentationOverrides[mapIdx]
    if presentationOverride then
        if presentationOverride.tileset then mapData.tileset = presentationOverride.tileset end
        if presentationOverride.fogPreset then mapData.fog = { preset = presentationOverride.fogPreset } end
    end
    session.currentMapData = mapData
    session.tempEventOverrides = {}
    
    local grid, startX, startY, startDir
    if mapData.safe then
        -- Load fixed town layout
        grid = {}
        for y, rowStr in ipairs(mapData.layout) do
            grid[y] = {}
            for x = 1, #rowStr do
                grid[y][x] = rowStr:sub(x, x)
            end
        end
        -- An authored safe map owns its own entry point. Maps without one
        -- (Town) retain the campaign-wide system spawn as their fallback.
        -- Both schemas store zero-indexed coordinates; the runtime grid is
        -- one-indexed.
        local systemSpawn = session.loader.system and session.loader.system.spawn or {}
        local authoredSpawn = mapData.spawn or systemSpawn
        local startXDef = authoredSpawn.x ~= nil and authoredSpawn.x or 10
        local startYDef = authoredSpawn.y ~= nil and authoredSpawn.y or 17
        startX, startY = startXDef + 1, startYDef + 1
        startDir = authoredSpawn.dir or "N"

        -- Safe/authored maps use the same tileset fixture rules as generated
        -- maps. Without this, wall fixtures configured in a tileset never
        -- appeared while testing a town.
        session.generatedZones = {}
        session.generatedFeatures, session.generatedLightObjects =
            exploration.injectTilesetFeatures(grid, mapData, session.generatedZones,
                { x = authoredSpawn.x, y = authoredSpawn.y })
        session.fixtureBlockIndex = nil
        if not mapData.light then
            local lightSources = {}
            for _, source in ipairs(mapData.lightObjects or {}) do table.insert(lightSources, source) end
            for _, source in ipairs(session.generatedLightObjects) do table.insert(lightSources, source) end
            if #lightSources > 0 then
                session.currentMapData.runtimeLight = lighting.bake(grid, lightSources)
            end
        end
    else
        local saved = session.mapStates and session.mapStates[mapIdx]
        if saved then
            grid = saved.mapGrid
            session.currentMapData.events = saved.events
            session.generatedFeatures = saved.generatedFeatures
            session.fixtureBlockIndex = nil
            session.generatedLightObjects = saved.generatedLightObjects
            session.generatedZones = saved.generatedZones
            session.currentMapData.runtimeLight = saved.runtimeLight
            session.currentMapData.entranceX = saved.entranceX
            session.currentMapData.entranceY = saved.entranceY
            session.currentMapData.exitX = saved.exitX
            session.currentMapData.exitY = saved.exitY
            session.visitedGrid = saved.visitedGrid
        else
            local entranceX, entranceY, exitX, exitY, generatedEvents,
                generatedFeatures, generatedLights, generatedZones
            grid, entranceX, entranceY, exitX, exitY, generatedEvents,
                generatedFeatures, generatedLights, generatedZones =
                -- `opts.seed` pins the layout. Play never passes one and gets a
                -- fresh labyrinth per expedition; tests pass one so that a
                -- topology assertion is reproducible instead of re-rolling a
                -- different dungeon on every run -- a severing regression that
                -- only some layouts expose must fail the same way every time.
                exploration.generateDungeon(mapData, opts.seed or (os.time() + mapIdx), session)
            session.currentMapData.events = generatedEvents
            session.generatedFeatures = generatedFeatures
            session.fixtureBlockIndex = nil
            session.generatedLightObjects = generatedLights
            session.generatedZones = generatedZones
            session.currentMapData.runtimeLight = lighting.bake(grid, generatedLights)
            session.currentMapData.entranceX = entranceX
            session.currentMapData.entranceY = entranceY
            session.currentMapData.exitX = exitX
            session.currentMapData.exitY = exitY
        end

        if opts.arrival == "resume" and saved then
            startX, startY, startDir = saved.playerX, saved.playerY, saved.playerDir
        elseif opts.arrival == "exit" then
            startX, startY, startDir = arrivalBeside(
                grid, session.currentMapData.exitX, session.currentMapData.exitY)
        else
            startX, startY, startDir = arrivalBeside(
                grid, session.currentMapData.entranceX, session.currentMapData.entranceY)
        end
    end
    
    session.mapGrid = grid
    session.mapStructureRevision = (session.mapStructureRevision or 0) + 1
    exploration.buildOverrideIndex(session)
    session.playerX = startX
    session.playerY = startY
    session.playerDir = startDir or "N"
    
    -- Initialize Fog-of-War (visited tiles)
    local isSafeMap = mapData.safe == true
    local restored = not isSafeMap and session.mapStates and session.mapStates[mapIdx]
    if not restored then
        session.visitedGrid = {}
        for y = 1, #grid do
            session.visitedGrid[y] = {}
            for x = 1, #grid[y] do
                session.visitedGrid[y][x] = isSafeMap
            end
        end
        if presentationOverride and presentationOverride.ambient then
            local lightSources = {}
            for _, source in ipairs(mapData.lightObjects or {}) do table.insert(lightSources, source) end
            for _, source in ipairs(session.generatedLightObjects or {}) do table.insert(lightSources, source) end
            session.currentMapData.runtimeLight =
                lighting.bake(grid, lightSources, presentationOverride.ambient)
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
    -- A solid fixture stands ON a floor cell, so the grid still reads passable.
    -- Injection already proved this cell can be blocked without cutting the map
    -- (see injectTilesetFeatures), so refusing the step here is safe. An
    -- override wins: an authored `passable` is a deliberate statement about
    -- this exact cell and outranks a decoration that happened to land on it.
    if passable and not (ov and ov.passable ~= nil)
            and exploration.fixtureBlocksAt(session, targetX - 1, targetY - 1) then
        passable = false
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
