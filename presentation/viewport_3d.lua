local viewport_3d = {}
local ui = require("presentation.ui")

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

-- Tileset configuration
local tileset = nil
local tileW, tileH = 256, 256
local sheetW, sheetH = 1024, 1024
local sliceQuad = nil
local wallQx, wallQy = 0, 0

function viewport_3d.init()
    if love.filesystem.getInfo("assets/textures/dungeon_tileset.jpg") then
        tileset = love.graphics.newImage("assets/textures/dungeon_tileset.jpg")
        tileset:setFilter("nearest", "nearest")
        sliceQuad = love.graphics.newQuad(0, 0, 1, 256, sheetW, sheetH)
        -- Col 0, Row 0 is the brick wall face
        wallQx, wallQy = 0, 0
    end
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

    -- ── 2. Draw Floor & Ceiling Gradients ────────────────────────────────────
    local halfH = ui.toPx(9) -- exactly 9 tiles (72px)
    -- Ceiling gradient: Moody dark purple/indigo fade
    drawVerticalGradient(0, 0, ui.toPx(ui.screenWidthTiles), halfH, {0.09, 0.06, 0.14}, {0.02, 0.01, 0.04})
    -- Floor gradient: Cold dark stone grey fade
    drawVerticalGradient(0, halfH, ui.toPx(ui.screenWidthTiles), halfH, {0.03, 0.03, 0.03}, {0.14, 0.12, 0.10})

    -- ── 3. Perspective Raycasting Loop with Fish-eye Correction ────────────────
    -- Camera direction vector
    local dirX = math.cos(cAngle)
    local dirY = math.sin(cAngle)
    
    -- Projection plane (orthogonal to camera direction)
    -- Field of View is 60 degrees (tan(30) = 0.577)
    local fovHalfTan = math.tan(math.pi / 6)
    local planeX = -dirY * fovHalfTan
    local planeY = dirX * fovHalfTan

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

        -- x coordinate on the texture
        local texX = math.floor(wallX * 256)
        if side == 0 and rx > 0 then texX = 255 - texX end
        if side == 1 and ry < 0 then texX = 255 - texX end

        -- Shading / Torchlight effect based on distance
        local brightness = math.max(0.12, 1.0 / (1.0 + perpWallDist * 0.35))
        
        -- Darken Y-facing walls for dynamic corner shadows
        if side == 1 then
            brightness = brightness * 0.76
        end

        -- Render textured slice or fallback color slice
        if tileset and sliceQuad then
            sliceQuad:setViewport(wallQx + texX, wallQy, 1, 256, sheetW, sheetH)
            love.graphics.setColor(brightness, brightness, brightness, 1)
            love.graphics.draw(tileset, sliceQuad, x, drawStart, 0, 1, lineHeight / 256)
        else
            -- Retro flat-shaded colors if tileset is missing
            local r = (side == 0) and 0.4 or 0.3
            local g = (side == 0) and 0.45 or 0.35
            local b = (side == 0) and 0.55 or 0.45
            love.graphics.setColor(r * brightness, g * brightness, b * brightness, 1)
            love.graphics.line(x, drawStart, x, drawEnd)
        end
    end

    love.graphics.pop()
end

return viewport_3d
