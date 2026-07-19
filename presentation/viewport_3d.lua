local viewport_3d = {}
local ui = require("presentation.ui")
local exploration = require("engine.exploration")

-- Direction vectors (matching exploration.lua)
local DIRS = {
    N = { dx = 0,  dy = -1 },
    E = { dx = 1,  dy = 0  },
    S = { dx = 0,  dy = 1  },
    W = { dx = -1, dy = 0  },
}

local DIR_ORDER = { "N", "E", "S", "W" }
local DIR_ANGLES = {
    N = -math.pi / 2,
    E = 0,
    S = math.pi / 2,
    W = math.pi
}

-- Direction helpers for turn interpolation
local function turnLeftDir(dir)
    local idx = 1
    for i, d in ipairs(DIR_ORDER) do
        if d == dir then idx = i break end
    end
    return DIR_ORDER[(idx - 2) % 4 + 1]
end

local function turnRightDir(dir)
    local idx = 1
    for i, d in ipairs(DIR_ORDER) do
        if d == dir then idx = i break end
    end
    return DIR_ORDER[idx % 4 + 1]
end

local function lerpAngle(a, b, t)
    local diff = b - a
    while diff < -math.pi do diff = diff + math.pi * 2 end
    while diff > math.pi do diff = diff - math.pi * 2 end
    return a + diff * t
end

-- Tileset atlas configuration. See docs/design/raycaster-tileset-lighting.md.
-- Grid cells are 64x64px; row 0 = wall variants, row 1 = floor variants
-- (reserved; the renderer does not floor-cast textures, only tints the
-- gradient), row 2 col 0 = the standard door, row 3 = a single wide sky
-- strip (4 cells, 256x64) sampled as one static stretch rather than tiled.
local ATLAS_TILE = 64
local ATLAS_WALL_ROW, ATLAS_WALL_VARIANTS = 0, 4
local ATLAS_DOOR_ROW, ATLAS_DOOR_COL = 2, 0
local ATLAS_SKY_ROW, ATLAS_SKY_COLS = 3, 4

local tileset = nil
local sheetW, sheetH = 0, 0
local sliceQuad = nil        -- 1px-wide column slice, reused for walls and doors
local skyQuad = nil          -- the full sky strip, drawn as one stretch
local legacyTileset = false  -- true when falling back to the old single-image texture
local spriteSliceQuad = nil

-- Deterministic per-cell wall variant so ambient wall texture varies without
-- being authored in map data (docs/design/raycaster-tileset-lighting.md).
local function wallVariant(mapX, mapY)
    local h = (mapX * 73856093 + mapY * 19349663) % 2147483647
    if h < 0 then h = -h end
    return h % ATLAS_WALL_VARIANTS
end

-- Bilinear-interpolated vertex brightness. session.currentMapData.light, if
-- present, is a (mapW+1) x (mapH+1) grid of 0..1 floats keyed [row][col]
-- (1-indexed, row = y, col = x) covering the map's grid *corners*. Absent
-- light data (older/generated maps) yields flat full brightness, i.e. no
-- change from current behavior.
local function sampleLight(light, x, y, fx, fy)
    if not light then return 1.0 end
    local r0, r1 = light[y], light[y + 1]
    if not r0 or not r1 then return 1.0 end
    local v00, v10 = r0[x] or 1.0, r0[x + 1] or 1.0
    local v01, v11 = r1[x] or 1.0, r1[x + 1] or 1.0
    local top = v00 + (v10 - v00) * fx
    local bot = v01 + (v11 - v01) * fx
    return top + (bot - top) * fy
end

local spriteImageCache = {}
local function getEventSprite(ev, session)
    if not ev then return nil end
    ev = exploration.resolvePage(ev, session)
    -- Sprite precedence: the map event's own sprite, else the default sprite
    -- of the common event it links to (template-style inheritance).
    local path = ev.sprite
    if (not path or path == "") and ev.scriptId and session and session.loader and session.loader.commonEvents then
        local ce = session.loader.commonEvents[tostring(ev.scriptId)]
        path = ce and ce.sprite or nil
    end
    if not path or path == "" then return nil end
    if spriteImageCache[path] then
        return spriteImageCache[path]
    end

    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")
        spriteImageCache[path] = img
        return img
    end

    return nil
end

function viewport_3d.init()
    spriteSliceQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1)

    if love.filesystem.getInfo("assets/textures/tileset_atlas.png") then
        -- New grid atlas: docs/design/raycaster-tileset-lighting.md.
        tileset = love.graphics.newImage("assets/textures/tileset_atlas.png")
        tileset:setFilter("nearest", "nearest")
        sheetW, sheetH = tileset:getWidth(), tileset:getHeight()
        legacyTileset = false
        sliceQuad = love.graphics.newQuad(0, 0, 1, ATLAS_TILE, sheetW, sheetH)
        skyQuad = love.graphics.newQuad(
            0, ATLAS_SKY_ROW * ATLAS_TILE,
            ATLAS_SKY_COLS * ATLAS_TILE, ATLAS_TILE,
            sheetW, sheetH)
    elseif love.filesystem.getInfo("assets/textures/dungeon_tileset.jpg") then
        -- Legacy single-texture fallback: one wall look, no doors/sky/variants.
        tileset = love.graphics.newImage("assets/textures/dungeon_tileset.jpg")
        tileset:setFilter("nearest", "nearest")
        sheetW, sheetH = 1024, 1024
        legacyTileset = true
        sliceQuad = love.graphics.newQuad(0, 0, 1, 256, sheetW, sheetH)
    end
end

-- Doors are ordinary map events (docs/design/raycaster-tileset-lighting.md)
-- flagged door=true; they render into the wall slice instead of as a
-- billboard, so they're normally left without a sprite. Built once per
-- frame (not per raycast column) keyed by 1-indexed grid cell.
local function buildDoorLookup(session)
    local lookup = {}
    local data = session.currentMapData
    if data and data.events then
        for _, ev in ipairs(data.events) do
            if ev.door then
                lookup[(ev.x + 1) .. "," .. (ev.y + 1)] = true
            end
        end
    end
    return lookup
end

-- Draw a vertical gradient block for ceiling/floor
local function drawVerticalGradient(x, y, w, h, colTop, colBottom)
    local verts = {
        { x,     y,     0,0, colTop[1],    colTop[2],    colTop[3],    colTop[4] or 1 },
        { x + w, y,     0,0, colTop[1],    colTop[2],    colTop[3],    colTop[4] or 1 },
        { x + w, y + h, 0,0, colBottom[1], colBottom[2], colBottom[3], colBottom[4] or 1 },
        { x,     y + h, 0,0, colBottom[1], colBottom[2], colBottom[3], colBottom[4] or 1 }
    }
    local mesh = love.graphics.newMesh(verts, "fan", "dynamic")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
end

function viewport_3d.draw(session)
    local grid  = session.mapGrid
    local px    = session.playerX
    local py    = session.playerY
    local pdir  = session.playerDir
    if not grid then return end

    love.graphics.push("all")
    love.graphics.intersectScissor(0, 0, ui.toPx(ui.screenWidthTiles), ui.toPx(18))

    -- ── 1. Calculate Camera State (Interpolated) ─────────────────────────────
    local cx = px - 0.5
    local cy = py - 0.5
    local cAngle = DIR_ANGLES[pdir]

    if session.transitionTimer and session.transitionTimer > 0 then
        local frac = session.transitionTimer / 0.15
        local df = DIRS[pdir]
        local dr = DIRS[turnRightDir(pdir)]

        if session.transitionDir == "forward" then
            cx = cx - df.dx * frac
            cy = cy - df.dy * frac
        elseif session.transitionDir == "backward" then
            cx = cx + df.dx * frac
            cy = cy + df.dy * frac
        elseif session.transitionDir == "strafe_left" then
            cx = cx + dr.dx * frac
            cy = cy + dr.dy * frac
        elseif session.transitionDir == "strafe_right" then
            cx = cx - dr.dx * frac
            cy = cy - dr.dy * frac
        elseif session.transitionDir == "turn_left" then
            local prevDir = turnRightDir(pdir)
            local prevAngle = DIR_ANGLES[prevDir]
            cAngle = lerpAngle(prevAngle, cAngle, 1.0 - frac)
        elseif session.transitionDir == "turn_right" then
            local prevDir = turnLeftDir(pdir)
            local prevAngle = DIR_ANGLES[prevDir]
            cAngle = lerpAngle(prevAngle, cAngle, 1.0 - frac)
        end
    end

    -- ── 2. Draw Floor & Ceiling ───────────────────────────────────────────────
    local halfH = ui.toPx(9) -- exactly 9 tiles (72px)
    local screenWpx = ui.toPx(ui.screenWidthTiles)
    local mapData = session.currentMapData
    local light = mapData and mapData.light

    -- Player-cell vertex light, used to tint the ceiling/floor as a single
    -- value (the gradients aren't raycast per-pixel, so they can't sample a
    -- per-column light like walls do). See docs/design/raycaster-tileset-lighting.md.
    local px0, py0 = math.floor(cx + 1), math.floor(cy + 1)
    local ambient = sampleLight(light, px0, py0, (cx + 1) - px0, (cy + 1) - py0)

    if mapData and mapData.ceilingStyle == "sky" and tileset and not legacyTileset and skyQuad then
        love.graphics.setColor(ambient, ambient, ambient, 1)
        love.graphics.draw(tileset, skyQuad, 0, 0, 0,
            screenWpx / (ATLAS_SKY_COLS * ATLAS_TILE), halfH / ATLAS_TILE)
    else
        -- Ceiling gradient: Moody dark purple/indigo fade
        drawVerticalGradient(0, 0, screenWpx, halfH,
            {0.09 * ambient, 0.06 * ambient, 0.14 * ambient},
            {0.02 * ambient, 0.01 * ambient, 0.04 * ambient})
    end
    -- Floor gradient: Cold dark stone grey fade
    drawVerticalGradient(0, halfH, screenWpx, halfH,
        {0.03 * ambient, 0.03 * ambient, 0.03 * ambient},
        {0.14 * ambient, 0.12 * ambient, 0.10 * ambient})

    local doorLookup = buildDoorLookup(session)

    -- ── 3. Perspective Raycasting Loop with Fish-eye Correction ────────────────
    -- Camera direction vector
    local dirX = math.cos(cAngle)
    local dirY = math.sin(cAngle)
    
    -- Projection plane (orthogonal to camera direction)
    -- Field of View is 60 degrees (tan(30) = 0.577)
    local fovHalfTan = math.tan(math.pi / 6)
    local planeX = -dirY * fovHalfTan
    local planeY = dirX * fovHalfTan
    
    local zBuffer = {}

    for x = 0, 255 do
        -- x-coordinate in camera space (from -1 to 1)
        local cameraX = 2 * x / 256 - 1
        
        -- Ray direction vector
        local rx = dirX + planeX * cameraX
        local ry = dirY + planeY * cameraX

        -- DDA Setup
        local mapX = math.floor(cx) + 1
        local mapY = math.floor(cy) + 1

        local deltaDistX = (rx == 0) and 1e30 or math.abs(1 / rx)
        local deltaDistY = (ry == 0) and 1e30 or math.abs(1 / ry)

        local stepX, stepY
        local sideDistX, sideDistY

        if rx < 0 then
            stepX = -1
            sideDistX = (cx + 1 - mapX) * deltaDistX
        else
            stepX = 1
            sideDistX = (mapX - cx) * deltaDistX
        end

        if ry < 0 then
            stepY = -1
            sideDistY = (cy + 1 - mapY) * deltaDistY
        else
            stepY = 1
            sideDistY = (mapY - cy) * deltaDistY
        end

        -- DDA Loop
        local hit = false
        local side = 0 -- 0: X-hit, 1: Y-hit
        local depth = 0
        local maxDepth = 16

        while not hit and depth < maxDepth do
            if sideDistX < sideDistY then
                sideDistX = sideDistX + deltaDistX
                mapX = mapX + stepX
                side = 0
            else
                sideDistY = sideDistY + deltaDistY
                mapY = mapY + stepY
                side = 1
            end
            depth = depth + 1

            if not grid[mapY] or not grid[mapY][mapX] then
                hit = true
                break
            elseif grid[mapY][mapX] == "#" then
                hit = true
            end
        end

        -- Calculate perpendicular wall distance (frontal depth)
        local perpWallDist
        if side == 0 then
            perpWallDist = (mapX - (cx + 1) + (1 - stepX) / 2) / rx
        else
            perpWallDist = (mapY - (cy + 1) + (1 - stepY) / 2) / ry
        end

        if perpWallDist < 0.05 then perpWallDist = 0.05 end
        
        -- Store in ZBuffer
        zBuffer[x + 1] = perpWallDist

        -- Calculate height of line to draw on screen
        local lineHeight = math.floor(140 / perpWallDist)

        -- Calculate lowest and highest pixel to fill in current stripe
        local drawStart = 70 - lineHeight / 2
        local drawEnd = 70 + lineHeight / 2

        -- Calculate where wall was hit (for texturing)
        local wallX
        if side == 0 then
            wallX = cy + 1 + perpWallDist * ry
        else
            wallX = cx + 1 + perpWallDist * rx
        end
        wallX = wallX - math.floor(wallX)

        -- x coordinate on the texture (atlas tiles are 64px; the legacy
        -- single-image fallback keeps its original 256px sampling)
        local wallTexSize = legacyTileset and 256 or ATLAS_TILE
        local texX = math.floor(wallX * wallTexSize)
        if side == 0 and rx > 0 then texX = (wallTexSize - 1) - texX end
        if side == 1 and ry < 0 then texX = (wallTexSize - 1) - texX end

        -- Shading / Torchlight effect based on distance
        local brightness = math.max(0.12, 1.0 / (1.0 + perpWallDist * 0.35))

        -- Darken Y-facing walls for dynamic corner shadows
        if side == 1 then
            brightness = brightness * 0.76
        end

        -- Vertex lighting: bilinear-sample the light grid at the actual
        -- continuous world hit position (same perpWallDist used for wallX).
        local hitWX = cx + 1 + perpWallDist * rx
        local hitWY = cy + 1 + perpWallDist * ry
        local vx0, vy0 = math.floor(hitWX), math.floor(hitWY)
        brightness = brightness * sampleLight(light, vx0, vy0, hitWX - vx0, hitWY - vy0)

        -- Render textured slice or fallback color slice
        if tileset and sliceQuad then
            local originX, originY
            if legacyTileset then
                originX, originY = 0, 0
            elseif doorLookup[mapX .. "," .. mapY] then
                originX, originY = ATLAS_DOOR_COL * ATLAS_TILE, ATLAS_DOOR_ROW * ATLAS_TILE
            else
                originX = wallVariant(mapX, mapY) * ATLAS_TILE
                originY = ATLAS_WALL_ROW * ATLAS_TILE
            end
            sliceQuad:setViewport(originX + texX, originY, 1, wallTexSize, sheetW, sheetH)
            love.graphics.setColor(brightness, brightness, brightness, 1)
            love.graphics.draw(tileset, sliceQuad, x, drawStart, 0, 1, lineHeight / wallTexSize)
        else
            -- Retro flat-shaded colors if tileset is missing
            local r = (side == 0) and 0.4 or 0.3
            local g = (side == 0) and 0.45 or 0.35
            local b = (side == 0) and 0.55 or 0.45
            love.graphics.setColor(r * brightness, g * brightness, b * brightness, 1)
            love.graphics.line(x, drawStart, x, drawEnd)
        end
    end

    -- ── 4. Collect and Sort Sprite Objects by Distance ───────────────────
    local spritesToDraw = {}

    -- Add coordinate-based events (from maps.json events list)
    if session.currentMapData and session.currentMapData.events then
        for _, ev in ipairs(session.currentMapData.events) do
            local img = getEventSprite(ev, session)
            if img then
                table.insert(spritesToDraw, {
                    x = ev.x,
                    y = ev.y,
                    img = img
                })
            end
        end
    end



    -- Calculate distance to camera for painter sorting
    for _, s in ipairs(spritesToDraw) do
        local dx = s.x + 0.5 - cx
        local dy = s.y + 0.5 - cy
        s.dist = dx * dx + dy * dy
    end

    table.sort(spritesToDraw, function(a, b)
        return a.dist > b.dist
    end)

    -- ── 5. Render Sprite Billboards with Occlusion ─────────────────────
    for _, s in ipairs(spritesToDraw) do
        local spriteX = s.x + 0.5 - cx
        local spriteY = s.y + 0.5 - cy

        -- Translate relative to camera and project
        local invDet = 1.0 / (planeX * dirY - dirX * planeY)
        local transformX = invDet * (dirY * spriteX - dirX * spriteY)
        local transformY = invDet * (-planeY * spriteX + planeX * spriteY)

        if transformY > 0.1 then
            local spriteScreenX = math.floor((256 / 2) * (1 + transformX / transformY))
            
            -- Calculate billboard height and width
            local spriteHeight = math.abs(math.floor(140 / transformY))
            local spriteWidth = spriteHeight
            
            local drawStartY = math.floor(70 - spriteHeight / 2)
            local drawStartX = math.floor(spriteScreenX - spriteWidth / 2)

            local brightness = math.max(0.12, 1.0 / (1.0 + transformY * 0.35))

            -- Render stripe by stripe
            for stripeX = drawStartX, drawStartX + spriteWidth - 1 do
                if stripeX >= 0 and stripeX < 256 then
                    if transformY < (zBuffer[stripeX + 1] or 0) then
                        local clipY = math.max(0, drawStartY)
                        local clipH = math.min(144, drawStartY + spriteHeight) - clipY
                        
                        if clipH > 0 then
                            love.graphics.setScissor(stripeX, clipY, 1, clipH)
                            love.graphics.setColor(brightness, brightness, brightness, 1)
                            
                            local texCol = math.floor((stripeX - drawStartX) / spriteWidth * s.img:getWidth())
                            spriteSliceQuad:setViewport(texCol, 0, 1, s.img:getHeight(), s.img:getWidth(), s.img:getHeight())
                            love.graphics.draw(s.img, spriteSliceQuad, stripeX, drawStartY, 0, 1, spriteHeight / s.img:getHeight())
                        end
                    end
                end
            end
            -- Restore active viewport scissor
            love.graphics.setScissor(0, 0, 256, 144)
        end
    end

    love.graphics.pop()
end

return viewport_3d
