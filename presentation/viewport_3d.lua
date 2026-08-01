local viewport_3d = {}
local ui = require("presentation.ui")
local exploration = require("engine.exploration")
local tilesetResolver = require("engine.tileset_resolver")
local config = require("engine.config")
local small_battlers = require("presentation.small_battlers")

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

local lerpAngle = ui.lerpAngle

-- Tileset atlas configuration. See docs/design/raycaster-tileset-lighting.md.
-- Grid cells are 64x64px, 4 columns wide. Default row layout (no sidecar
-- needed): row 0 = sky/ceiling, row 1 = wall, row 2 = door, row 3 = floor.
-- More wall/door/floor variety comes from a WIDER atlas (more columns),
-- not more rows. Atlases that deviate from this (e.g. no sky strip, extra
-- wall-variant rows) carry a sidecar assets/tilesets/<name>.json manifest
-- overriding whichever fields differ:
--   { "wallRows": [0,1], "doorRow": 2, "skyRow": 3, "floorRow": 4 }
-- skyRow/ceilingRow/floorRow are omitted entirely when the atlas has no
-- such strip (e.g. dungeon_001's ceilingRow instead of skyRow).
-- Fog config: an optional per-map `fog` key (maps.json), either a shared
-- preset reference or inline fields. See docs/design/fog-presets-and-panorama.md.
--   "fog": { "preset": "misty_dusk" }
--   "fog": { "color": [0.5,0.55,0.6], "density": 0.35, "minFactor": 0.12,
--            "panorama": [{ "image": "fog_001", "scrollX": 0.01, "scrollY": 0,
--                            "blendMode": "alpha", "opacity": 1.0 }] }
-- Distance shading is a mix toward the fog color/background; the pre-fog
-- "darken with distance" behavior is EXACTLY this with a black flat-color
-- fog and no panorama, so there is only one shading model -- a map without
-- fog just uses the defaults below. That identity is what keeps the wall
-- loop, the sprite tint, and the floor/ceiling shader on a single code
-- path each instead of branching per feature.
local FOG_DEFAULTS = { color = { 0, 0, 0 }, startDist = 0.0, distance = 8.0, sharpness = 1.0, minFactor = 0.12, panorama = nil }

local function calcFogAlpha(dist, fog)
    local dStart = fog.startDist or FOG_DEFAULTS.startDist
    local dRange = fog.distance or FOG_DEFAULTS.distance
    if dRange <= 0 then dRange = 0.001 end
    local norm = (dist - dStart) / dRange
    if norm < 0 then norm = 0 elseif norm > 1 then norm = 1 end
    local sharpness = fog.sharpness or FOG_DEFAULTS.sharpness
    if sharpness ~= 1.0 then
        norm = norm ^ sharpness
    end
    local minFactor = fog.minFactor or FOG_DEFAULTS.minFactor
    return 1.0 - norm * (1.0 - minFactor)
end

local function getFogConfig(session, mapData)
    local fog = mapData and mapData.fog
    if not fog then return FOG_DEFAULTS, false end

    if fog.preset then
        local presets = session and session.loader and session.loader.engine and session.loader.engine.fogPresets
        local resolved = nil
        if presets then
            for _, p in ipairs(presets) do
                if p.id == fog.preset then resolved = p break end
            end
        end
        -- An unresolvable preset id falls back to no-fog rather than
        -- erroring, matching how missing atlases/light grids degrade
        -- elsewhere in this renderer; the validator catches the typo.
        if not resolved then return FOG_DEFAULTS, false end
        fog = resolved
    end

    local dStart = (fog.startDist ~= nil) and fog.startDist or FOG_DEFAULTS.startDist
    local dDist = fog.distance or (fog.endDist and math.max(0.1, fog.endDist - dStart)) or FOG_DEFAULTS.distance

    return {
        color     = fog.color or FOG_DEFAULTS.color,
        startDist = dStart,
        distance  = dDist,
        sharpness = (fog.sharpness ~= nil) and fog.sharpness or FOG_DEFAULTS.sharpness,
        minFactor = (fog.minFactor ~= nil) and fog.minFactor or FOG_DEFAULTS.minFactor,
        psxBands  = fog.psxBands,
        panorama  = (fog.panorama and #fog.panorama > 0) and fog.panorama or nil,
    }, true
end

-- Panorama images (assets/panorama/<name>.png), lazily loaded/cached like
-- tileset atlases. Repeat-wrapped so a screen-sized viewport quad can be
-- offset over time for a scrolling-mist effect without a shader.
local panoramaCache = {}
local function getPanoramaImage(name)
    if not name or name == "" then return nil end
    local cleanName = tostring(name):gsub("^assets/panorama/", ""):gsub("%.png$", "")
    if panoramaCache[cleanName] ~= nil then return panoramaCache[cleanName] or nil end
    local path = "assets/panorama/" .. cleanName .. ".png"
    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")
        img:setWrap("repeat", "repeat")
        panoramaCache[cleanName] = img
        return img
    end
    panoramaCache[cleanName] = false
    return nil
end

local BLEND_MODES = { alpha = true, add = true, multiply = true, screen = true }
local panoramaQuad = nil -- reused; viewport recomputed per layer/call

-- Draws fog (flat fill + any scrolling panorama layers) into the screen
-- rect (x, y, w, h). Sampling is offset by (x, y) in addition to the
-- scroll, so a small sub-rect (a single wall column, a sprite stripe)
-- samples the exact same continuous image a full-screen call would --
-- redrawing a window into it, not a rescaled copy -- which is what makes
-- the panorama line up seamlessly between the floor/ceiling background
-- and the walls/sprites drawn on top of it. See
-- docs/design/fog-presets-and-panorama.md.
local function drawFogLayers(fog, x, y, w, h)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(fog.color[1], fog.color[2], fog.color[3], 1)
    love.graphics.rectangle("fill", x, y, w, h)

    if fog.panorama then
        local t = (fog.time ~= nil) and fog.time or love.timer.getTime()
        for _, layer in ipairs(fog.panorama) do
            local img = getPanoramaImage(layer.image)
            if img then
                local iw, ih = img:getWidth(), img:getHeight()
                local scrollOx = (t * (layer.scrollX or 0) * iw) % iw
                local scrollOy = (t * (layer.scrollY or 0) * ih) % ih
                if not panoramaQuad then panoramaQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1) end
                panoramaQuad:setViewport(scrollOx + x, scrollOy + y, w, h, iw, ih)
                love.graphics.setBlendMode(BLEND_MODES[layer.blendMode] and layer.blendMode or "alpha")
                love.graphics.setColor(1, 1, 1, layer.opacity or 1.0)
                love.graphics.draw(img, panoramaQuad, x, y)
            end
        end
        -- A layer may have left a non-"alpha" blend mode active; restore it
        -- so callers (wall/sprite loops draw their texture right after
        -- this, without their own push/pop) get normal blending.
        love.graphics.setBlendMode("alpha")
    end
end

-- Draws the fog background ONCE per frame, before floor/ceiling, covering
-- the whole viewport. Floor/ceiling (drawn immediately after) blend
-- against this directly at alpha = fogAlpha. Walls and sprites, which
-- draw on top of the now-opaque floor/ceiling, call drawFogLayers() again
-- themselves per-column/per-stripe (see the wall loop and sprite loop
-- below) rather than reusing this draw -- alpha-blending them against
-- whatever's already on the canvas would reveal floor/ceiling pixels
-- behind their own screen position, not fog.
local function drawFogBackground(fog, screenWpx, screenHpx)
    love.graphics.push("all")
    drawFogLayers(fog, 0, 0, screenWpx, screenHpx)
    love.graphics.pop()
end

local ATLAS_TILE = 64
local ATLAS_WALL_COLS = 4
local ATLAS_DOOR_VARIANTS = 4
local ATLAS_SKY_COLS = 4
local DEFAULT_TILESET = "dungeon_001"

-- Per-map tileset selection (session.currentMapData.tileset, a name under
-- assets/tilesets/<name>.png) lazily loaded and cached here. A map without a
-- `tileset` field uses DEFAULT_TILESET.
local atlasCache = {}
local function getAtlasByDef(id, tilesetDef)
    if not tilesetDef then return nil end
    if atlasCache[id] ~= nil then return atlasCache[id] or nil end
    local path = tilesetDef.texture or ("assets/tilesets/" .. id .. ".png")
    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")
        -- `features[]` is the single source of truth for feature/material ids
        -- (SPEC 1.8); the redundant `tiles{}` mirror was purged 24.07.2026.
        local tiles = {}
        if tilesetDef.features then
            for _, f in ipairs(tilesetDef.features) do
                if f.id then tiles[f.id] = f end
            end
        end
        local floorRow = tilesetDef.floorRow
        local floorCol = tilesetDef.floorCol
        if floorRow == nil and tilesetDef.base and tilesetDef.base.floors and tilesetDef.base.floors[1] and tilesetDef.base.floors[1].atlas then
            floorRow = tilesetDef.base.floors[1].atlas[1]
            floorCol = tilesetDef.base.floors[1].atlas[2]
        end

        local ceilingRow = tilesetDef.ceilingRow
        local ceilingCol = tilesetDef.ceilingCol
        if ceilingRow == nil and tilesetDef.base and tilesetDef.base.ceilings and tilesetDef.base.ceilings[1] and tilesetDef.base.ceilings[1].atlas then
            ceilingRow = tilesetDef.base.ceilings[1].atlas[1]
            ceilingCol = tilesetDef.base.ceilings[1].atlas[2]
        end

        local skyTiles = {}
        if tilesetDef.skyTiles and #tilesetDef.skyTiles > 0 then
            for _, st in ipairs(tilesetDef.skyTiles) do
                if type(st) == "table" then
                    if st.atlas then
                        table.insert(skyTiles, { st.atlas[1], st.atlas[2] })
                    elseif st[1] ~= nil and st[2] ~= nil then
                        table.insert(skyTiles, { st[1], st[2] })
                    end
                end
            end
        elseif tilesetDef.base and tilesetDef.base.skies and #tilesetDef.base.skies > 0 then
            for _, st in ipairs(tilesetDef.base.skies) do
                if type(st) == "table" then
                    if st.atlas then
                        table.insert(skyTiles, { st.atlas[1], st.atlas[2] })
                    elseif st[1] ~= nil and st[2] ~= nil then
                        table.insert(skyTiles, { st[1], st[2] })
                    end
                end
            end
        elseif tilesetDef.base and tilesetDef.base.ceilings and #tilesetDef.base.ceilings > 0 then
            for _, c in ipairs(tilesetDef.base.ceilings) do
                if type(c) == "table" then
                    if c.atlas then
                        table.insert(skyTiles, { c.atlas[1], c.atlas[2] })
                    elseif c[1] ~= nil and c[2] ~= nil then
                        table.insert(skyTiles, { c[1], c[2] })
                    end
                end
            end
        end

        local skyRow = tilesetDef.skyRow
        local skyCol = tilesetDef.skyCol
        if skyRow == nil then
            skyRow, skyCol = ceilingRow, ceilingCol
        end

        if #skyTiles == 0 then
            if skyRow ~= nil then
                if skyCol ~= nil then
                    table.insert(skyTiles, { skyRow, skyCol })
                else
                    for col = 0, ATLAS_SKY_COLS - 1 do
                        table.insert(skyTiles, { skyRow, col })
                    end
                end
            else
                table.insert(skyTiles, { 0, 0 })
            end
        end

        if skyRow == nil then
            skyRow = skyTiles[1][1]
            skyCol = skyTiles[1][2]
        end

        local doorRow = tilesetDef.doorRow
        if doorRow == nil and tilesetDef.doors and tilesetDef.doors[1] and tilesetDef.doors[1].atlas then
            doorRow = tilesetDef.doors[1].atlas[1]
        end

        local wallRows = tilesetDef.wallRows
        if not wallRows and tilesetDef.base and tilesetDef.base.walls and #tilesetDef.base.walls > 0 then
            wallRows = {}
            for _, w in ipairs(tilesetDef.base.walls) do
                if w.middle and w.middle[1] then
                    table.insert(wallRows, w.middle[1])
                end
            end
        end
        if not wallRows or #wallRows == 0 then wallRows = { 1 } end

        local entry = {
            img = img, w = img:getWidth(), h = img:getHeight(),
            wallRows = wallRows,
            wallVariants = #wallRows * ATLAS_WALL_COLS,
            doorRow = doorRow,
            skyRow = skyRow,
            skyCol = skyCol,
            skyTiles = skyTiles,
            floorRow = floorRow,
            floorCol = floorCol,
            ceilingRow = ceilingRow,
            ceilingCol = ceilingCol,
            skyPanorama = tilesetDef.skyPanorama,
            tiles = tiles,
            manifest = tilesetDef,
        }
        atlasCache[id] = entry
        return entry
    end
    atlasCache[id] = false
    return nil
end

local sliceQuad = nil        -- 1px-wide column slice, reused for walls and doors
local skyQuad = nil          -- reused for the sky strip, viewport recomputed per atlas
local spriteSliceQuad = nil
local compositeQuad = nil    -- Quad for baking tile layer composites into a 64x64 canvas
local compositeCache = {}    -- Cached 64x64 composite tile canvases keyed by tile specs
local wallOverlayCache = {}

local function getWallOverlay(path)
    if not path then return nil end
    if wallOverlayCache[path] ~= nil then return wallOverlayCache[path] or nil end
    local ok, image = pcall(love.graphics.newImage, path)
    if not ok then error("wall overlay failed to load: " .. tostring(path), 0) end
    image:setFilter("nearest", "nearest")
    wallOverlayCache[path] = image
    return image
end

-- A dedicated panorama fills the playfield behind world geometry and rotates
-- with the cardinal camera. Atlas sky tiles remain the fallback for existing
-- tilesets which have not authored a panorama yet.
local function drawSkyBackdrop(atlas, screenWpx, screenHpx, cameraAngle)
    if atlas and atlas.skyPanorama then
        local img = getPanoramaImage(atlas.skyPanorama)
        if img then
            local iw, ih = img:getDimensions()
            local backdropH = math.floor(screenHpx * 0.5)
            local scale = backdropH / ih
            local sourceW = screenWpx / scale
            local turn = ((cameraAngle or 0) / (math.pi * 2)) % 1
            local sourceX = turn * iw
            if not panoramaQuad then panoramaQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1) end
            panoramaQuad:setViewport(sourceX, 0, sourceW, ih, iw, ih)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(img, panoramaQuad, 0, 0, 0, scale, scale)
            return true
        end
    end
    if not atlas or not atlas.skyTiles or #atlas.skyTiles == 0 then return false end
    local backdropH = math.floor(screenHpx * 0.5)
    local scale = backdropH / ATLAS_TILE
    local tileW = ATLAS_TILE * scale
    local x = 0
    local tileIndex = 1
    love.graphics.setColor(1, 1, 1, 1)
    while x < screenWpx do
        local tile = atlas.skyTiles[tileIndex]
        skyQuad:setViewport(tile[2] * ATLAS_TILE, tile[1] * ATLAS_TILE,
            ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h)
        love.graphics.draw(atlas.img, skyQuad, x, 0, 0, scale, scale)
        x = x + tileW
        tileIndex = (tileIndex % #atlas.skyTiles) + 1
    end
    return true
end

local function getCompositeTileCanvas(atlas, originX, originY, leftEdgeSpec, rightEdgeSpec, featureOverlay, wallOverlay)
    local key = (atlas.manifest and atlas.manifest.id or "default")
        .. ":" .. originX .. "," .. originY
        .. "|" .. (leftEdgeSpec and (leftEdgeSpec[1] .. "," .. leftEdgeSpec[2] .. "," .. (leftEdgeSpec[3] or 0)) or "")
        .. "|" .. (rightEdgeSpec and (rightEdgeSpec[1] .. "," .. rightEdgeSpec[2] .. "," .. (rightEdgeSpec[3] or 32)) or "")
        .. "|" .. (featureOverlay and featureOverlay.atlas and (featureOverlay.atlas[1] .. "," .. featureOverlay.atlas[2]) or "")
        .. "|" .. tostring(wallOverlay or "")

    if compositeCache[key] then
        return compositeCache[key]
    end

    local canvas = love.graphics.newCanvas(ATLAS_TILE, ATLAS_TILE)
    canvas:setFilter("nearest", "nearest")
    -- Bake in ordinary 2D space. The finished canvas is an opaque wall tile
    -- (the base wall is drawn first), so the raycaster can light and fog it
    -- exactly once like any other wall texture.
    local previousCanvas = love.graphics.getCanvas()
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)

    -- 1. Base Wall
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
    compositeQuad:setViewport(originX, originY, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h)
    love.graphics.draw(atlas.img, compositeQuad, 0, 0)

    -- 2. Left Edge Overlay (32x64)
    love.graphics.setBlendMode("alpha")
    if leftEdgeSpec then
        local eRow, eCol, eOffX = leftEdgeSpec[1], leftEdgeSpec[2], leftEdgeSpec[3] or 0
        compositeQuad:setViewport(eCol * ATLAS_TILE + eOffX, eRow * ATLAS_TILE, 32, ATLAS_TILE, atlas.w, atlas.h)
        love.graphics.draw(atlas.img, compositeQuad, 0, 0)
    end

    -- 3. Right Edge Overlay (32x64)
    if rightEdgeSpec then
        local eRow, eCol, eOffX = rightEdgeSpec[1], rightEdgeSpec[2], rightEdgeSpec[3] or 32
        compositeQuad:setViewport(eCol * ATLAS_TILE + eOffX, eRow * ATLAS_TILE, 32, ATLAS_TILE, atlas.w, atlas.h)
        love.graphics.draw(atlas.img, compositeQuad, 32, 0)
    end

    -- 4. Feature Overlay / Fixture (64x64)
    if featureOverlay and featureOverlay.atlas then
        local fOriginY = featureOverlay.atlas[1] * ATLAS_TILE
        local fOriginX = featureOverlay.atlas[2] * ATLAS_TILE
        compositeQuad:setViewport(fOriginX, fOriginY, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h)
        love.graphics.draw(atlas.img, compositeQuad, 0, 0)
    end

    -- 5. Event-authored wall overlay. Doors use the exact same cached
    -- composite canvas as wall edges and fixtures; they are not billboards.
    local overlayImage = getWallOverlay(wallOverlay)
    if overlayImage then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(overlayImage, 0, 0, 0,
            ATLAS_TILE / overlayImage:getWidth(),
            ATLAS_TILE / overlayImage:getHeight())
    end

    -- Canvas targets are not part of LÖVE's push/pop graphics state. Failing
    -- to restore this explicitly sends the rest of the frame into the 64px
    -- bake canvas, leaving the on-screen world black/untextured.
    love.graphics.setCanvas(previousCanvas)
    love.graphics.pop()

    compositeCache[key] = canvas
    return canvas
end

-- Deterministic per-cell variant picks so ambient wall/door texture varies
-- without being authored in map data (docs/design/raycaster-tileset-lighting.md).
function viewport_3d.resolveWeightedVariant(pool, mapX, mapY, saltA, saltB)
    return exploration.resolveTilesetVariant(pool, mapX, mapY,
        saltA or 73856093, saltB or 19349663)
end
local function wallVariant(mapX, mapY, variantCount)
    return exploration.cellHash(mapX, mapY, 73856093, 19349663) % variantCount
end
local function doorVariant(mapX, mapY)
    return exploration.cellHash(mapX, mapY, 83492791, 39916801) % ATLAS_DOOR_VARIANTS
end

-- Bilinear-interpolated vertex color. session.currentMapData.light, if
-- present, is a (mapW+1) x (mapH+1) grid of [r,g,b] triples (each 0..1)
-- keyed [row][col] (1-indexed, row = y, col = x) covering the map's grid
-- *corners* -- painted via the map editor's Light layer ("vertex colorer",
-- docs/design/raycaster-tileset-lighting.md). Absent light data (older/
-- generated maps, or vertices past the grid edge) yields flat full white,
-- i.e. no tinting at all -- matches pre-lighting behavior exactly.
local DEFAULT_LIGHT = { 1.0, 1.0, 1.0 }
local function lightCellAt(light, x, y)
    local row = light[y]
    return (row and row[x]) or DEFAULT_LIGHT
end
local function sampleLight(light, x, y, fx, fy)
    if not light then return 1.0, 1.0, 1.0 end
    local c00, c10 = lightCellAt(light, x, y), lightCellAt(light, x + 1, y)
    local c01, c11 = lightCellAt(light, x, y + 1), lightCellAt(light, x + 1, y + 1)
    local r = c00[1] + (c10[1] - c00[1]) * fx
    local g = c00[2] + (c10[2] - c00[2]) * fx
    local b = c00[3] + (c10[3] - c00[3]) * fx
    local r2 = c01[1] + (c11[1] - c01[1]) * fx
    local g2 = c01[2] + (c11[2] - c01[2]) * fx
    local b2 = c01[3] + (c11[3] - c01[3]) * fx
    return r + (r2 - r) * fy, g + (g2 - g) * fy, b + (b2 - b) * fy
end

local spriteImageCache = {}
function viewport_3d.resolveEventSpritePath(ev, session)
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

    if love.filesystem.getInfo(path) then return path end
    local resolved = small_battlers.resolveFile(path)
    return resolved and resolved.path or nil
end

local function getEventSprite(ev, session)
    local path = viewport_3d.resolveEventSpritePath(ev, session)
    if not path then return nil end
    if spriteImageCache[path] then
        return spriteImageCache[path]
    end

    local img = love.graphics.newImage(path)
    img:setFilter("nearest", "nearest")
    spriteImageCache[path] = img
    return img
end

-- ---------------------------------------------------------------------------
-- Floor/ceiling shader. See docs/design/floor-ceiling-shader.md.
--
-- Walls are one draw call per screen column (a single distance, so a single
-- texture slice). Floors/ceilings don't have that property -- every pixel
-- within a row is a different world position -- so they're computed as a
-- GPU fragment shader instead of a per-pixel Lua loop. The shader receives
-- the SAME camera vectors (camPos/camDir/camPlane) the wall raycast loop
-- already computes; the per-pixel world position formula below is the
-- classic floor-casting algorithm, derived to match this renderer's own
-- wall projection constants exactly (center row 70, scale 170.6667 -- see
-- `lineHeight = floor(170.6667 / perpWallDist)` in the wall loop) so the floor
-- meets the base of each wall with no seam.
--
-- Per-cell texture variant uses a GLSL-friendly float hash (the CPU wall
-- hash's large integer multiplies aren't reliably precise in GLSL floats
-- across GPUs) -- a different hash family from the wall/door CPU hashes,
-- not the same formula ported; visually it serves the same "engine-random,
-- not authored" purpose.
local FLOOR_CEIL_SHADER_SRC = [[
    uniform vec2 camPos;
    uniform vec2 camDir;
    uniform vec2 camPlane;
    uniform float atlasW;
    uniform float atlasH;
    uniform float targetRow;
    uniform float targetCol; // >= 0 selects one authored cell; -1 keeps legacy row variants
    uniform vec2 mapSize;   // (mapW, mapH), light texture covers (mapW+1)x(mapH+1) vertices
    // Fog: rather than mixing toward a fog color in-shader, output alpha =
    // fogAlpha and let ordinary blending reveal whatever drawFogBackground()
    // already drew behind this (flat fill or scrolling panorama) -- see
    // docs/design/fog-presets-and-panorama.md.    uniform float fogStart;
    uniform float fogDistance;
    uniform float fogSharpness;
    uniform float fogMinFactor;
    uniform vec3 playerLightColor;
    uniform float playerLightRadius;
    uniform float playerLightFalloff;

    vec2 cellVariantOrigin(vec2 cell) {
        if (targetCol >= 0.0) return vec2(targetCol, targetRow);
        float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float col = floor(h * 4.0);
        return vec2(col, targetRow);
    }

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
        float dy = screen_coords.y - 70.0;
        if (abs(dy) < 0.0001) dy = 0.0001;
        float rowDist = 85.3333 / abs(dy);

        float cameraX = 2.0 * screen_coords.x / 256.0 - 1.0;
        vec2 rayDir = camDir + camPlane * cameraX;
        vec2 worldPos = camPos + rowDist * rayDir;

        vec2 cell = floor(worldPos);
        vec2 fracPos = fract(worldPos);
        vec2 origin = cellVariantOrigin(cell);

        vec2 uv = vec2((origin.x + fracPos.x) * 64.0 / atlasW, (origin.y + fracPos.y) * 64.0 / atlasH);
        vec4 texColor = Texel(tex, uv);

        // Fog alpha: 1.0 within fogStart, ramps toward fogMinFactor over fogDistance with sharpness curve
        float span = max(0.001, fogDistance);
        float normDist = clamp((rowDist - fogStart) / span, 0.0, 1.0);
        if (fogSharpness != 1.0) {
            normDist = pow(normDist, fogSharpness);
        }
        float fogAlpha = 1.0 - normDist * (1.0 - fogMinFactor);
        vec2 lightUV = (worldPos - vec2(0.5)) / (mapSize + vec2(1.0));
        vec3 lightColor = Texel(lightTex, lightUV).rgb;

        if (playerLightRadius > 0.0) {
            float playerDist = length(worldPos - camPos);
            if (playerDist < playerLightRadius) {
                float strength = pow(1.0 - playerDist / playerLightRadius, playerLightFalloff);
                lightColor = min(vec3(1.0), lightColor + playerLightColor * strength);
            }
        }

        vec3 shaded = texColor.rgb * lightColor;

        return vec4(shaded, texColor.a * fogAlpha) * color;
    }
]]

local floorCeilShader = nil   -- false once a compile attempt has failed, so we don't retry every frame
local whiteLightTex = nil     -- 1x1 white fallback bound when a map has no light grid
local lightTexCache = { mapData = nil, lightRef = nil, tex = nil, w = 0, h = 0 }

-- Rebuilding love.graphics.Shader source to inject the lightTex sampler
-- (LÖVE requires every declared Image uniform to exist in the source, and
-- there's exactly one caller here, so string-splicing it in once at compile
-- time is simpler than threading a second shader variant through).
local FLOOR_CEIL_SHADER_FULL = FLOOR_CEIL_SHADER_SRC:gsub(
    "uniform vec2 mapSize;",
    "uniform vec2 mapSize;\n    uniform Image lightTex;")

local function ensureFloorCeilShader()
    if floorCeilShader ~= nil then return floorCeilShader or nil end
    local ok, shaderOrErr = pcall(love.graphics.newShader, FLOOR_CEIL_SHADER_FULL)
    if ok then
        floorCeilShader = shaderOrErr
    else
        print("[viewport_3d] floor/ceiling shader failed to compile, falling back to gradients: " .. tostring(shaderOrErr))
        floorCeilShader = false
    end
    return floorCeilShader or nil
end

-- Bakes session.currentMapData.light into a small linear-filtered texture so
-- the shader's bilinear light sampling comes from native GPU texture
-- filtering rather than hand-written interpolation (docs/design/floor-ceiling-shader.md).
-- Cached per map/light-table identity; rebuilt only when either changes
-- (e.g. a fresh map load, or the editor writing new light data).
local function getLightTexture(mapData)
    local light = mapData and (mapData.runtimeLight or mapData.light)
    if not light or #light == 0 then return nil end
    if lightTexCache.mapData == mapData and lightTexCache.lightRef == light then
        return lightTexCache.tex, lightTexCache.w, lightTexCache.h
    end
    local h, w = #light, #light[1]
    local imgData = love.image.newImageData(w, h)
    for y = 0, h - 1 do
        local row = light[y + 1]
        for x = 0, w - 1 do
            local c = row[x + 1] or DEFAULT_LIGHT
            imgData:setPixel(x, y, c[1], c[2], c[3], 1)
        end
    end
    local tex = love.graphics.newImage(imgData)
    tex:setFilter("linear", "linear")
    tex:setWrap("clamp", "clamp")
    lightTexCache = { mapData = mapData, lightRef = light, tex = tex, w = w, h = h }
    return tex, w, h
end

-- Draws one shaded floor/ceiling plane (the screen rows y0..y0+rectH) via
-- the floor-casting shader, sampling atlasRow's variant-column texture and
-- the given light texture (or full white if the map has none). `fog` only
-- supplies density/minFactor here -- the shader outputs alpha, not a mixed
-- color; drawFogBackground() already drew what fog.color/panorama reveals
-- underneath (docs/design/fog-presets-and-panorama.md).
local function drawShadedPlane(atlas, atlasRow, atlasCol, y0, rectH, cx, cy, dirX, dirY, planeX, planeY, lightTex, lightW, lightH, fog, playerLight)
    local shader = ensureFloorCeilShader()
    if not shader then return false end

    love.graphics.setShader(shader)
    shader:send("camPos", { cx + 1, cy + 1 })
    shader:send("camDir", { dirX, dirY })
    shader:send("camPlane", { planeX, planeY })
    shader:send("atlasW", atlas.w)
    shader:send("atlasH", atlas.h)
    shader:send("targetRow", atlasRow)
    shader:send("targetCol", atlasCol or -1)
    shader:send("fogStart", fog.startDist)
    shader:send("fogDistance", fog.distance)
    shader:send("fogSharpness", fog.sharpness)
    shader:send("fogMinFactor", fog.minFactor)

    if playerLight and playerLight.active and playerLight.radius > 0 then
        shader:send("playerLightColor", playerLight.color)
        shader:send("playerLightRadius", playerLight.radius)
        shader:send("playerLightFalloff", playerLight.falloff)
    else
        shader:send("playerLightColor", { 0, 0, 0 })
        shader:send("playerLightRadius", 0.0)
        shader:send("playerLightFalloff", 1.0)
    end

    if lightTex then
        shader:send("lightTex", lightTex)
        shader:send("mapSize", { lightW - 1, lightH - 1 })
    else
        if not whiteLightTex then
            local d = love.image.newImageData(1, 1)
            d:setPixel(0, 0, 1, 1, 1, 1)
            whiteLightTex = love.graphics.newImage(d)
        end
        shader:send("lightTex", whiteLightTex)
        shader:send("mapSize", { 1, 1 })
    end

    love.graphics.setColor(1, 1, 1, 1)
    -- The atlas image is only drawn here to bind it as the sampled texture;
    -- its on-screen stretch is irrelevant since the shader computes its own
    -- UVs from screen_coords, ignoring the default texture_coords entirely.
    love.graphics.draw(atlas.img, 0, y0, 0, 256 / atlas.w, rectH / atlas.h)
    love.graphics.setShader()
    return true
end

function viewport_3d.init()
    spriteSliceQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    -- Viewport dims are set per-draw-call below (they depend on which
    -- atlas is active for the current map).
    sliceQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    skyQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    compositeQuad = love.graphics.newQuad(0, 0, 1, 1, 1, 1)
    compositeCache = {}
    wallOverlayCache = {}
end

-- Resolves which atlas to draw walls/doors/sky from this frame: the map's
-- own `tileset` if it names one, else DEFAULT_TILESET. Returns nil if that
-- atlas file doesn't exist (draw() falls back to flat-shaded lines).
local function resolveTileset(mapData, session)
    local tilesetId = (mapData and mapData.tileset) or "dungeon_default"
    local activeLoader = (session and session.loader) or loader
    local tilesetDef, cacheKey = tilesetResolver.resolve(activeLoader, mapData)
    if tilesetDef then
        return getAtlasByDef(cacheKey or tilesetDef.id or tilesetId, tilesetDef)
    end
    return nil
end

-- Wall fixtures are ordinary map events flagged wallEvent=true. Their sprite
-- renders into the wall composite instead of entering the billboard pass.
-- Built once per
-- frame (not per raycast column) keyed by 1-indexed grid cell.
local function buildWallEventLookup(session)
    local lookup = {}
    local data = session.currentMapData
    if data and data.events then
        for _, ev in ipairs(data.events) do
            if ev.wallEvent then
                lookup[(ev.x + 1) .. "," .. (ev.y + 1)] = ev
            end
        end
    end
    return lookup
end

-- Named materials are sparse map overrides: normal geometry remains in the
-- compact #/. layout, while a material selects a specific atlas cell and its
-- properties.  Runtime procedural light fixtures share this lookup.
local function buildMaterialLookup(session)
    local lookup = {}
    local data = session.currentMapData or {}
    for y, row in ipairs(data.materials or {}) do
        for x, id in ipairs(row) do
            if id and id ~= "" then lookup[x .. "," .. y] = id end
        end
    end
    for _, source in ipairs(data.lightObjects or {}) do
        if source.material then
            lookup[(source.x + 1) .. "," .. (source.y + 1)] = source.material
        end
    end
    for _, source in ipairs(session.generatedFeatures or {}) do
        lookup[(source.x + 1) .. "," .. (source.y + 1)] = source.material
    end
    return lookup
end

-- Camera-independent map topology and its lazily-built GPU wall meshes.
local structuralCache = setmetatable({}, { __mode = "k" })
local structuralCacheBuilds = 0
local lastFrameStats = {}

function viewport_3d.getLastFrameStats()
    return lastFrameStats
end

local function releaseMeshTree(node)
    if not node then return end
    for _, child in ipairs(node.children or {}) do releaseMeshTree(child) end
    if node.mesh and node.mesh.release then node.mesh:release() end
    node.mesh = nil
end

local function releasePreparedStructure(prepared)
    for _, faces in pairs((prepared and prepared.resolvedWallFaces) or {}) do
        for _, face in ipairs(faces) do
            releaseMeshTree(face.meshTree)
            face.meshTree = nil
        end
    end
    for _, cell in ipairs((prepared and prepared.floorCells) or {}) do
        releaseMeshTree(cell.floorSurface and cell.floorSurface.meshTree)
        releaseMeshTree(cell.floorFeatureSurface and cell.floorFeatureSurface.meshTree)
        releaseMeshTree(cell.ceilingSurface and cell.ceilingSurface.meshTree)
        cell.floorSurface, cell.floorFeatureSurface, cell.ceilingSurface = nil, nil, nil
    end
    for _, batch in pairs((prepared and prepared.surfaceBatches) or {}) do
        if batch.mesh and batch.mesh.release then batch.mesh:release() end
        batch.mesh = nil
    end
    for _, texturePool in pairs((prepared and prepared.dynamicMeshPool) or {}) do
        for _, entry in pairs(texturePool) do
            if entry.mesh and entry.mesh.release then entry.mesh:release() end
            entry.mesh = nil
        end
    end
    for _, placedGroups in pairs((prepared and prepared.modelSurfaces) or {}) do
        for _, placed in ipairs(placedGroups) do
            if placed.mesh and placed.mesh.release then placed.mesh:release() end
            placed.mesh = nil
        end
    end
    for _, handle in ipairs((prepared and prepared.worldEffectHandles) or {}) do
        require("presentation.effekseer").stop(handle)
    end
    if prepared then prepared.dynamicMeshPool = nil end
    if prepared then prepared.modelSurfaces = nil end
    if prepared then prepared.worldEffectHandles = nil end
end

function viewport_3d.prepareStructure(session)
    local grid = session and session.mapGrid
    if not grid then return nil end
    local mapData = session.currentMapData
    local structureRevision = session.mapStructureRevision or 0
    local presentationRevision = session.mapPresentationRevision or 0
    local cached = structuralCache[session]
    if cached and cached.grid == grid and cached.mapData == mapData
            and cached.structureRevision == structureRevision
            and cached.presentationRevision == presentationRevision then
        cached.hits = cached.hits + 1
        return cached
    end
    releasePreparedStructure(cached)

    local prepared = {
        grid = grid,
        mapData = mapData,
        structureRevision = structureRevision,
        presentationRevision = presentationRevision,
        floorCells = {}, wallCells = {}, openingCells = {},
        doorLookup = buildWallEventLookup(session),
        materialLookup = buildMaterialLookup(session),
        hits = 0,
    }
    for y, row in ipairs(grid) do
        for x, value in ipairs(row) do
            if value == "#" then
                table.insert(prepared.wallCells, { x = x, y = y })
            else
                table.insert(prepared.floorCells, { x = x, y = y })
                if value == "o" then
                    table.insert(prepared.openingCells, {
                        x = x, y = y,
                        axis = viewport_3d.resolveOpeningAxis(grid, x, y),
                    })
                end
            end
        end
    end
    structuralCacheBuilds = structuralCacheBuilds + 1
    prepared.build = structuralCacheBuilds
    structuralCache[session] = prepared
    return prepared
end

function viewport_3d.invalidateStructure(session)
    if session then
        releasePreparedStructure(structuralCache[session])
        structuralCache[session] = nil
    end
end

-- Strategy B starts with the wall geometry only.  The floor/ceiling shader and
-- billboard code below remain the compatibility surface for this first slice;
-- walls are projected as actual quads and depth-tested by the GPU instead of
-- being painted one screen column at a time.
local WALL_MESH_FORMAT = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "float", 4 },
    { "VertexDepth", "float", 1 },
}

local WALL_MESH_SHADER_SOURCE = [[
    #ifdef VERTEX
    attribute float VertexDepth;
    varying vec2 wallUV;
    varying vec4 wallColor;

    vec4 position(mat4 transform_projection, vec4 vertex_position)
    {
        wallUV = VertexTexCoord.xy;
        wallColor = VertexColor;
        vec4 screenPosition = transform_projection * vec4(VertexPosition.xy, 0.0, 1.0);
        return vec4(screenPosition.xy, VertexDepth * 2.0 - 1.0, screenPosition.w);
    }

    #endif

    #ifdef PIXEL
    varying vec2 wallUV;
    varying vec4 wallColor;
    uniform vec3 fogColor;

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 texel = Texel(texture, wallUV);
        vec3 lit = texel.rgb * wallColor.rgb;
        vec3 fogged = mix(fogColor, lit, wallColor.a);
        return vec4(fogged, texel.a);
    }
    #endif
]]

local wallMeshShader = nil
local wallMeshShaderError = nil
local whiteWallTexture = nil

local function ensureWallMeshShader()
    if wallMeshShader ~= nil then return wallMeshShader or nil end
    local ok, shaderOrErr = pcall(love.graphics.newShader, WALL_MESH_SHADER_SOURCE)
    if ok then
        wallMeshShader = shaderOrErr
    else
        wallMeshShaderError = tostring(shaderOrErr)
        wallMeshShader = false
        print("[viewport_3d] polygonal wall shader failed to compile, keeping raycast walls: " .. wallMeshShaderError)
    end
    return wallMeshShader or nil
end

local function getWhiteWallTexture()
    if whiteWallTexture then return whiteWallTexture end
    local imageData = love.image.newImageData(1, 1)
    imageData:setPixel(0, 0, 1, 1, 1, 1)
    whiteWallTexture = love.graphics.newImage(imageData)
    whiteWallTexture:setFilter("nearest", "nearest")
    return whiteWallTexture
end

local function wallCell(grid, x, y)
    return grid[y] and grid[y][x] == "#"
end

local function floorCell(grid, x, y)
    return grid[y] and grid[y][x] == "."
end

-- An opening spans the corridor between the stronger pair of opposite wall
-- neighbours. Return the plane normal: "x" means travel is east/west and the
-- frame crosses the cell north/south; "y" is the rotated case. Floor
-- connectivity breaks malformed/ambiguous ties, then "x" keeps the result
-- deterministic for an isolated opening authored during a mutation.
function viewport_3d.resolveOpeningAxis(grid, x, y)
    local northSouth = (wallCell(grid, x, y - 1) and 1 or 0)
        + (wallCell(grid, x, y + 1) and 1 or 0)
    local eastWest = (wallCell(grid, x - 1, y) and 1 or 0)
        + (wallCell(grid, x + 1, y) and 1 or 0)
    if northSouth ~= eastWest then return northSouth > eastWest and "x" or "y" end
    local openEastWest = (not wallCell(grid, x - 1, y) and 1 or 0)
        + (not wallCell(grid, x + 1, y) and 1 or 0)
    local openNorthSouth = (not wallCell(grid, x, y - 1) and 1 or 0)
        + (not wallCell(grid, x, y + 1) and 1 or 0)
    if openEastWest ~= openNorthSouth then return openEastWest > openNorthSouth and "x" or "y" end
    return "x"
end

local function projectWallPoint(worldX, worldY, worldZ, cameraX, cameraY, dirX, dirY)
    local dx = worldX - cameraX
    local dy = worldY - cameraY
    local forward = dx * dirX + dy * dirY
    if forward <= 0.05 then return nil end
    local right = dx * -dirY + dy * dirX
    local focal = 170.6667
    return {
        x = 128 + right / forward * focal,
        y = 70 - (worldZ - 0.5) / forward * focal,
        depth = math.min(0.999, math.max(0.001, forward / 32.0)),
        forward = forward,
    }
end

local function addProjectedWallFace(group, points, originX, originY, texW, texH, flipU, litR, litG, litB, fogAlpha)
    local function uv(localX, localY)
        local u = flipU and (1 - localX) or localX
        return (originX + u * ATLAS_TILE) / texW, (originY + localY * ATLAS_TILE) / texH
    end
    local u0, v0 = uv(0, 0)
    local u1, v1 = uv(1, 1)
    local function vertex(point, u, v)
        return { point.x, point.y, u, v, litR, litG, litB, fogAlpha, point.depth }
    end
    -- Counter-clockwise in screen space is not required for the depth buffer,
    -- but keeping a consistent winding makes the eventual culling pass safe.
    table.insert(group.vertices, vertex(points[1], u0, v0))
    table.insert(group.vertices, vertex(points[2], u1, v0))
    table.insert(group.vertices, vertex(points[3], u1, v1))
    table.insert(group.vertices, vertex(points[1], u0, v0))
    table.insert(group.vertices, vertex(points[3], u1, v1))
    table.insert(group.vertices, vertex(points[4], u0, v1))
end

local function raycastDepthBuffer(grid, cx, cy, dirX, dirY, planeX, planeY)
    local zBuffer = {}
    for x = 0, 255 do
        local cameraX = 2 * x / 256 - 1
        local rx = dirX + planeX * cameraX
        local ry = dirY + planeY * cameraX
        local mapX = math.floor(cx) + 1
        local mapY = math.floor(cy) + 1
        local deltaDistX = (rx == 0) and 1e30 or math.abs(1 / rx)
        local deltaDistY = (ry == 0) and 1e30 or math.abs(1 / ry)
        local stepX, stepY, sideDistX, sideDistY
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
        local side = 0
        local depth = 0
        while depth < 16 do
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
            if not grid[mapY] or not grid[mapY][mapX] or grid[mapY][mapX] == "#" then
                break
            end
        end
        local perpendicular
        if side == 0 then
            perpendicular = (mapX - (cx + 1) + (1 - stepX) / 2) / rx
        else
            perpendicular = (mapY - (cy + 1) + (1 - stepY) / 2) / ry
        end
        zBuffer[x + 1] = math.max(0.05, perpendicular)
    end
    return zBuffer
end

local function drawPolygonalWalls(session, grid, cameraX, cameraY, dirX, dirY, atlas, light, fog, playerLight, doorLookup, materialLookup)
    local shader = ensureWallMeshShader()
    if not shader then return nil end

    local groups = {}
    local faces = {}

    local function addFace(mapX, mapY, kind, p1, p2, neighborX, neighborY)
        if wallCell(grid, neighborX, neighborY) then return end
        local centerX = (p1.x + p2.x) * 0.5
        local centerY = (p1.y + p2.y) * 0.5
        local normalX, normalY = 0, 0
        if kind == "north" then normalY = -1
        elseif kind == "south" then normalY = 1
        elseif kind == "west" then normalX = -1
        else normalX = 1 end
        local toCameraX, toCameraY = cameraX - centerX, cameraY - centerY
        if normalX * toCameraX + normalY * toCameraY <= 0 then return end
        local center = projectWallPoint(centerX, centerY, 0.5, cameraX, cameraY, dirX, dirY)
        if not center or center.forward > 16 then return end
        local top1 = projectWallPoint(p1.x, p1.y, 1, cameraX, cameraY, dirX, dirY)
        local top2 = projectWallPoint(p2.x, p2.y, 1, cameraX, cameraY, dirX, dirY)
        local bottom2 = projectWallPoint(p2.x, p2.y, 0, cameraX, cameraY, dirX, dirY)
        local bottom1 = projectWallPoint(p1.x, p1.y, 0, cameraX, cameraY, dirX, dirY)
        if not top1 or not top2 or not bottom1 or not bottom2 then return end

        local side = (kind == "north" or kind == "south") and 1 or 0
        local material = atlas and atlas.tiles[materialLookup[mapX .. "," .. mapY] or ""] or nil
        local featureOverlay = nil
        if material and material.role == "wall_feature" then
            featureOverlay = material
            material = nil
        end
        local event = doorLookup[mapX .. "," .. mapY]
        local originX, originY
        if material and material.atlas then
            originY = material.atlas[1] * ATLAS_TILE
            originX = material.atlas[2] * ATLAS_TILE
        elseif atlas and event and not event.sprite then
            originX = doorVariant(mapX, mapY) * ATLAS_TILE
            originY = (atlas.doorRow or 2) * ATLAS_TILE
        else
            local baseWall = atlas and atlas.manifest and atlas.manifest.base
                and atlas.manifest.base.walls and atlas.manifest.base.walls[1]
            if baseWall and baseWall.middle then
                originX = baseWall.middle[2] * ATLAS_TILE
                originY = baseWall.middle[1] * ATLAS_TILE
            else
                local variant = wallVariant(mapX, mapY, math.max(1, atlas and atlas.wallVariants or 1))
                originX = (variant % ATLAS_WALL_COLS) * ATLAS_TILE
                originY = (atlas and atlas.wallRows and atlas.wallRows[math.floor(variant / ATLAS_WALL_COLS) + 1] or 1) * ATLAS_TILE
            end
        end

        local hasLeftEdge = (side == 0 and floorCell(grid, mapX, mapY - 1)) or (side == 1 and floorCell(grid, mapX - 1, mapY))
        local hasRightEdge = (side == 0 and floorCell(grid, mapX, mapY + 1)) or (side == 1 and floorCell(grid, mapX + 1, mapY))
        local wallSpec = atlas and atlas.manifest and atlas.manifest.base and atlas.manifest.base.walls and atlas.manifest.base.walls[1]
        local leftEdgeSpec = hasLeftEdge and wallSpec and wallSpec.leftEdge or nil
        local rightEdgeSpec = hasRightEdge and wallSpec and wallSpec.rightEdge or nil
        local texture = getWhiteWallTexture()
        local textureOriginX, textureOriginY, textureW, textureH = 0, 0, 1, 1
        if atlas then
            if not leftEdgeSpec and not rightEdgeSpec and not featureOverlay and not (event and event.sprite) then
                texture = atlas.img
                textureOriginX, textureOriginY, textureW, textureH = originX, originY, atlas.w, atlas.h
            else
                texture = getCompositeTileCanvas(atlas, originX, originY, leftEdgeSpec, rightEdgeSpec, featureOverlay, event and event.sprite)
                textureOriginX, textureOriginY, textureW, textureH = 0, 0, ATLAS_TILE, ATLAS_TILE
            end
        end

        local litR, litG, litB = sampleLight(light, math.floor(centerX), math.floor(centerY), centerX - math.floor(centerX), centerY - math.floor(centerY))
        if playerLight.active then
            local dx, dy = centerX - cameraX, centerY - cameraY
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < playerLight.radius then
                local strength = (1 - distance / playerLight.radius) ^ playerLight.falloff
                litR = math.min(1, litR + playerLight.color[1] * strength)
                litG = math.min(1, litG + playerLight.color[2] * strength)
                litB = math.min(1, litB + playerLight.color[3] * strength)
            end
        end
        if side == 1 then litR, litG, litB = litR * 0.76, litG * 0.76, litB * 0.76 end
        local fogAlpha = calcFogAlpha(center.forward, fog)
        local group = groups[texture]
        if not group then
            group = { texture = texture, vertices = {} }
            groups[texture] = group
            table.insert(faces, group)
        end
        local flipU = kind == "west" or kind == "south"
        addProjectedWallFace(group, { top1, top2, bottom2, bottom1 }, textureOriginX, textureOriginY, textureW, textureH, flipU, litR, litG, litB, fogAlpha)
    end

    for mapY, row in ipairs(grid) do
        for mapX, value in ipairs(row) do
            if value == "#" then
                addFace(mapX, mapY, "north", { x = mapX, y = mapY }, { x = mapX + 1, y = mapY }, mapX, mapY - 1)
                addFace(mapX, mapY, "south", { x = mapX + 1, y = mapY + 1 }, { x = mapX, y = mapY + 1 }, mapX, mapY + 1)
                addFace(mapX, mapY, "west", { x = mapX, y = mapY + 1 }, { x = mapX, y = mapY }, mapX - 1, mapY)
                addFace(mapX, mapY, "east", { x = mapX + 1, y = mapY }, { x = mapX + 1, y = mapY + 1 }, mapX + 1, mapY)
            end
        end
    end

    love.graphics.setDepthMode("always", true)
    love.graphics.setShader(shader)
    shader:send("fogColor", fog.color)
    love.graphics.setColor(1, 1, 1, 1)
    for _, group in ipairs(faces) do
        if #group.vertices > 0 then
            local mesh = love.graphics.newMesh(WALL_MESH_FORMAT, group.vertices, "triangles", "stream")
            mesh:setTexture(group.texture)
            love.graphics.draw(mesh)
            mesh:release()
        end
    end
    love.graphics.setShader()
    -- The billboards still use the renderer's explicit zBuffer below.  Turn
    -- the hardware test off before those ordinary 2D draws and before the
    -- scene UI resumes, so a depth-enabled canvas does not hide HUD sprites.
    love.graphics.setDepthMode("always", false)
    return raycastDepthBuffer(grid, cameraX - 1, cameraY - 1, dirX, dirY, -dirY * 0.75, dirX * 0.75)
end

-- Full world-space path. Every visible surface is authored in map/world
-- coordinates and projected by the same perspective shader.
local WORLD_MESH_FORMAT = {
    { "VertexPosition", "float", 2 },
    { "VertexTexCoord", "float", 2 },
    { "VertexColor", "float", 4 },
    { "SurfaceLight", "float", 3 },
    { "FogVisibility", "float", 1 },
    { "WorldHeight", "float", 1 },
}

local WORLD_SHADER_SOURCE = [[
    #ifdef VERTEX
    varying vec2 worldUV;
    varying float affineScale;
    varying vec4 worldColor;
    varying float fogVisibility;
    attribute float WorldHeight;
    attribute float FogVisibility;
    attribute vec3 SurfaceLight;
    uniform vec3 cameraPosition;
    uniform vec2 cameraForward;
    uniform vec2 cameraRight;
    uniform float fovHalfX;
    uniform float fovHalfY;
    uniform float nearPlane;
    uniform float farPlane;
    uniform float baseViewportWidth;
    uniform float baseViewportHeight;
    uniform float targetWidth;
    uniform float targetHeight;
    uniform float viewportCenterY;
    uniform float affineTextures;
    uniform float vertexSnapPixels;
    uniform float fogStart;
    uniform float fogDistance;
    uniform float fogSharpness;
    uniform float fogMinFactor;
    uniform float fogBands;
    uniform vec3 playerLightColor;
    uniform float playerLightRadius;
    uniform float playerLightFalloff;

    vec4 position(mat4 transform_projection, vec4 vertex_position)
    {
        vec3 relative = vec3(VertexPosition.xy, WorldHeight) - cameraPosition;
        float depth = dot(relative.xy, cameraForward);
        float safeDepth = depth;
        worldUV = mix(VertexTexCoord.xy, VertexTexCoord.xy * safeDepth, affineTextures);
        affineScale = mix(1.0, safeDepth, affineTextures);
        vec3 dynamicLight = SurfaceLight;
        if (playerLightRadius > 0.0) {
            float playerDistance = length(relative.xy);
            if (playerDistance < playerLightRadius) {
                float strength = pow(1.0 - playerDistance / playerLightRadius, playerLightFalloff);
                dynamicLight = min(vec3(1.0), dynamicLight + playerLightColor * strength);
            }
        }
        worldColor = vec4(dynamicLight, 1.0);
        float safeFogDistance = max(fogDistance, 0.001);
        float normalizedFog = clamp((max(0.05, depth) - fogStart) / safeFogDistance, 0.0, 1.0);
        if (fogSharpness != 1.0) normalizedFog = pow(normalizedFog, fogSharpness);
        fogVisibility = 1.0 - normalizedFog * (1.0 - fogMinFactor);
        if (fogBands > 1.0) {
            fogVisibility = floor(fogVisibility * fogBands + 0.5) / fogBands;
        }
        float horizontal = dot(relative.xy, cameraRight);
        float vertical = relative.z;
        float ndcDepth = (farPlane + nearPlane) / (farPlane - nearPlane)
            - (2.0 * farPlane * nearPlane)
                / ((farPlane - nearPlane) * safeDepth);
        float viewportTop = (2.0 * viewportCenterY / targetHeight) - 1.0;
        float ndcX = horizontal / (fovHalfX * safeDepth) * (baseViewportWidth / targetWidth);
        float ndcY = viewportTop
            - vertical / (fovHalfY * safeDepth) * (baseViewportHeight / targetHeight);
        if (vertexSnapPixels > 0.0) {
            float pixelX = (ndcX + 1.0) * targetWidth * 0.5;
            float pixelY = (ndcY + 1.0) * targetHeight * 0.5;
            pixelX = floor(pixelX / vertexSnapPixels + 0.5) * vertexSnapPixels;
            pixelY = floor(pixelY / vertexSnapPixels + 0.5) * vertexSnapPixels;
            ndcX = pixelX * 2.0 / targetWidth - 1.0;
            ndcY = pixelY * 2.0 / targetHeight - 1.0;
        }
        return vec4(ndcX * safeDepth, ndcY * safeDepth, ndcDepth * safeDepth, safeDepth);
    }
    #endif

    #ifdef PIXEL
    varying vec2 worldUV;
    varying float affineScale;
    varying vec4 worldColor;
    varying float fogVisibility;
    uniform vec3 fogColor;
    uniform float ditherLevels;

    float orderedDither(vec2 position)
    {
        vec2 cell = mod(floor(position), 4.0);
        float x = cell.x;
        float y = cell.y;
        float row0 = (x < 1.0) ? 0.0 : ((x < 2.0) ? 8.0 : ((x < 3.0) ? 2.0 : 10.0));
        float row1 = (x < 1.0) ? 12.0 : ((x < 2.0) ? 4.0 : ((x < 3.0) ? 14.0 : 6.0));
        float row2 = (x < 1.0) ? 3.0 : ((x < 2.0) ? 11.0 : ((x < 3.0) ? 1.0 : 9.0));
        float row3 = (x < 1.0) ? 15.0 : ((x < 2.0) ? 7.0 : ((x < 3.0) ? 13.0 : 5.0));
        return ((y < 1.0) ? row0 : ((y < 2.0) ? row1 : ((y < 3.0) ? row2 : row3))) / 16.0;
    }

    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
    {
        vec4 texel = Texel(texture, worldUV / affineScale);
        if (texel.a < 0.01) discard;
        vec3 lit = texel.rgb * worldColor.rgb;
        vec3 fogged = mix(fogColor, lit, fogVisibility);
        if (ditherLevels > 1.0) {
            float threshold = orderedDither(screen_coords) - 0.5;
            fogged = floor(clamp(fogged + threshold / ditherLevels, 0.0, 1.0) * ditherLevels + 0.5) / ditherLevels;
        }
        return vec4(fogged, texel.a) * color;
    }
    #endif
]]

local worldShader = nil
local worldShaderError = nil

local function ensureWorldShader()
    if worldShader ~= nil then return worldShader or nil end
    local ok, shaderOrErr = pcall(love.graphics.newShader, WORLD_SHADER_SOURCE)
    if ok then
        worldShader = shaderOrErr
    else
        worldShaderError = tostring(shaderOrErr)
        worldShader = false
        print("[viewport_3d] world shader failed to compile: " .. worldShaderError)
    end
    return worldShader or nil
end

local function atlasUV(originX, originY, width, height, texW, texH, flipU)
    -- Address texel centres, not atlas-cell borders. Exact-border UVs can
    -- resolve to the neighbouring tile under perspective interpolation and
    -- expose a one-pixel seam even with nearest filtering.
    local u0 = (originX + 0.5) / texW
    local u1 = (originX + width - 0.5) / texW
    local v0 = (originY + 0.5) / texH
    local v1 = (originY + height - 0.5) / texH
    if flipU then u0, u1 = u1, u0 end
    return u0, v0, u1, v1
end

local NO_ATLAS_CACHE_KEY = {}

-- Resolves exposed faces, materials, composite canvases and UVs once. Dynamic
-- visibility, light, fog and subdivision are deliberately absent here.
local function prepareResolvedWallFaces(structure, atlas)
    structure.resolvedWallFaces = structure.resolvedWallFaces or {}
    local cacheKey = atlas or NO_ATLAS_CACHE_KEY
    if structure.resolvedWallFaces[cacheKey] then
        return structure.resolvedWallFaces[cacheKey]
    end
    local grid, faces = structure.grid, {}
    local function addFace(mapX, mapY, kind, p1, p2, nx, ny)
        if wallCell(grid, nx, ny) then return end
        local material = atlas and atlas.tiles[structure.materialLookup[mapX .. "," .. mapY] or ""] or nil
        local featureOverlay = nil
        if material and material.role == "wall_feature" then featureOverlay, material = material, nil end
        local event = structure.doorLookup[mapX .. "," .. mapY]
        local originX, originY = 0, 0
        local wallPool = atlas and atlas.manifest and atlas.manifest.base
            and atlas.manifest.base.walls
        local baseWall = viewport_3d.resolveWeightedVariant(
            wallPool, mapX, mapY, 73856093, 19349663)
        local doorSpec = atlas and viewport_3d.resolveWeightedVariant(
            atlas.manifest and atlas.manifest.doors, mapX, mapY, 83492791, 39916801)
        if material and material.atlas then
            originY, originX = material.atlas[1] * ATLAS_TILE, material.atlas[2] * ATLAS_TILE
        elseif atlas and event and not event.sprite and doorSpec and doorSpec.atlas then
            originY, originX = doorSpec.atlas[1] * ATLAS_TILE, doorSpec.atlas[2] * ATLAS_TILE
        elseif atlas and event and not event.sprite then
            originX, originY = doorVariant(mapX, mapY) * ATLAS_TILE, (atlas.doorRow or 2) * ATLAS_TILE
        elseif atlas then
            if baseWall and baseWall.middle then
                originX, originY = baseWall.middle[2] * ATLAS_TILE, baseWall.middle[1] * ATLAS_TILE
            else
                local variant = wallVariant(mapX, mapY, math.max(1, atlas.wallVariants))
                originX = (variant % ATLAS_WALL_COLS) * ATLAS_TILE
                originY = (atlas.wallRows[math.floor(variant / ATLAS_WALL_COLS) + 1] or 1) * ATLAS_TILE
            end
        end
        local side = (kind == "north" or kind == "south") and 1 or 0
        local hasLeft = (side == 0 and floorCell(grid, mapX, mapY - 1))
            or (side == 1 and floorCell(grid, mapX - 1, mapY))
        local hasRight = (side == 0 and floorCell(grid, mapX, mapY + 1))
            or (side == 1 and floorCell(grid, mapX + 1, mapY))
        local leftSpec = hasLeft and baseWall and baseWall.leftEdge or nil
        local rightSpec = hasRight and baseWall and baseWall.rightEdge or nil
        local texture, uv = getWhiteWallTexture(), { 0, 0, 1, 1 }
        if atlas then
            if leftSpec or rightSpec or featureOverlay or (event and event.sprite) then
                texture = getCompositeTileCanvas(
                    atlas, originX, originY, leftSpec, rightSpec, featureOverlay, event and event.sprite)
            else
                texture = atlas.img
                uv = { atlasUV(originX, originY, ATLAS_TILE, ATLAS_TILE,
                    atlas.w, atlas.h, kind == "west" or kind == "south") }
            end
        end
        if not atlas or texture ~= atlas.img then uv = { 0, 0, 1, 1 } end
        uv[2], uv[4] = uv[4], uv[2]
        local normalX, normalY = 0, 0
        if kind == "north" then normalY = -1 elseif kind == "south" then normalY = 1
        elseif kind == "west" then normalX = -1 else normalX = 1 end
        table.insert(faces, {
            p1 = p1, p2 = p2, sideDarken = side == 1,
            normalX = normalX, normalY = normalY,
            centerX = (p1.x + p2.x) * 0.5, centerY = (p1.y + p2.y) * 0.5,
            texture = texture, uv = uv,
            model = (event and doorSpec and doorSpec.model)
                or (featureOverlay and featureOverlay.model) or nil,
            mapX = mapX, mapY = mapY,
        })
    end
    for _, cell in ipairs(structure.wallCells) do
        local x, y = cell.x, cell.y
        addFace(x, y, "north", { x = x, y = y }, { x = x + 1, y = y }, x, y - 1)
        addFace(x, y, "south", { x = x + 1, y = y + 1 }, { x = x, y = y + 1 }, x, y + 1)
        addFace(x, y, "west", { x = x, y = y + 1 }, { x = x, y = y }, x - 1, y)
        addFace(x, y, "east", { x = x + 1, y = y }, { x = x + 1, y = y + 1 }, x + 1, y)
    end
    structure.resolvedWallFaces[cacheKey] = faces
    return faces
end

function viewport_3d.prepareResolvedStructure(session)
    local structure = viewport_3d.prepareStructure(session)
    if not structure then return nil, nil end
    local atlas = resolveTileset(session.currentMapData, session)
    return structure, prepareResolvedWallFaces(structure, atlas)
end

local function addWorldVertex(group, x, y, z, u, v, r, g, b, fogFactor)
    -- VertexColor feeds LÖVE's built-in `color` shader argument. Keep it
    -- neutral and carry authored lighting separately so it is applied once,
    -- before the fog mix rather than again after it.
    table.insert(group.vertices, { x, y, u, v, 1, 1, 1, 1, r, g, b, fogFactor, z })
end

local function addWorldQuad(group, a, b, c, d, uv, colors)
    addWorldVertex(group, a.x, a.y, a.z, uv[1], uv[2], colors[1][1], colors[1][2], colors[1][3], colors[1][4])
    addWorldVertex(group, b.x, b.y, b.z, uv[3], uv[2], colors[2][1], colors[2][2], colors[2][3], colors[2][4])
    addWorldVertex(group, c.x, c.y, c.z, uv[3], uv[4], colors[3][1], colors[3][2], colors[3][3], colors[3][4])
    addWorldVertex(group, a.x, a.y, a.z, uv[1], uv[2], colors[1][1], colors[1][2], colors[1][3], colors[1][4])
    addWorldVertex(group, c.x, c.y, c.z, uv[3], uv[4], colors[3][1], colors[3][2], colors[3][3], colors[3][4])
    addWorldVertex(group, d.x, d.y, d.z, uv[1], uv[4], colors[4][1], colors[4][2], colors[4][3], colors[4][4])
end

local function drawWorldSpace(session)
    if not skyQuad then viewport_3d.init() end
    local grid = session.mapGrid
    if not grid then return end

    local shader = ensureWorldShader()
    if not shader then error("world renderer unavailable: " .. tostring(worldShaderError), 0) end

    -- The world now fills the whole 256x240 canvas rather than stopping at the
    -- old 256x144 playfield (31.07.2026). The windowskin shells are
    -- semitransparent, so the region behind the bottom dock is visible and has
    -- to contain scene rather than nothing.
    --
    -- This is an unclip, not a re-framing. `baseViewportWidth/Height` stay
    -- 256x144: they are the camera's *pixel scale*, and the shader divides
    -- them by the target size, so a taller target extends the view downward at
    -- a fixed scale exactly as a wider one extends it sideways. The horizon
    -- stays pinned at `viewportCenterY`, so existing composition is unchanged
    -- and what appears below y=144 is floor that was already being projected
    -- and then scissored away.
    local targetWidth, targetHeight = 256, 240
    local targetCanvas = love.graphics.getCanvas()
    if targetCanvas then
        targetWidth, targetHeight = targetCanvas:getDimensions()
    end
    local baseViewportWidth, baseViewportHeight = 256, 144
    local viewportWidth = targetWidth
    local viewportHeight = targetHeight
    local viewportCenterY = 70

    local px, py, pdir = session.playerX, session.playerY, session.playerDir
    local cx, cy = px - 0.5, py - 0.5
    local cAngle = DIR_ANGLES[pdir]
    if session.transitionTimer and session.transitionTimer > 0 then
        local duration = session.transitionDuration or 0.15
        local frac = duration > 0 and session.transitionTimer / duration or 1
        local df = DIRS[pdir]
        local dr = DIRS[turnRightDir(pdir)]
        if session.transitionDir == "forward" then
            cx, cy = cx - df.dx * frac, cy - df.dy * frac
        elseif session.transitionDir == "backward" then
            cx, cy = cx + df.dx * frac, cy + df.dy * frac
        elseif session.transitionDir == "strafe_left" then
            cx, cy = cx + dr.dx * frac, cy + dr.dy * frac
        elseif session.transitionDir == "strafe_right" then
            cx, cy = cx - dr.dx * frac, cy - dr.dy * frac
        elseif session.transitionDir == "turn_left" then
            cAngle = lerpAngle(DIR_ANGLES[turnRightDir(pdir)], cAngle, 1 - frac)
        elseif session.transitionDir == "turn_right" then
            cAngle = lerpAngle(DIR_ANGLES[turnLeftDir(pdir)], cAngle, 1 - frac)
        end
    end

    if session.bumpTimer and session.bumpTimer > 0 then
        local bumpDur = (config.ui and config.ui.bumpDuration) or 0.12
        local frac = bumpDur > 0 and session.bumpTimer / bumpDur or 1
        local nudge = frac * ((config.ui and config.ui.bumpNudge) or 0.12)
        local fwd = DIRS[pdir]
        local key = session.bumpNudgeKey
        local nx, ny = fwd.dx, fwd.dy
        if key == "down" or key == "s" then nx, ny = -fwd.dx, -fwd.dy
        elseif key == "q" then local ld = DIRS[turnLeftDir(pdir)]; nx, ny = ld.dx, ld.dy
        elseif key == "e" then local rd = DIRS[turnRightDir(pdir)]; nx, ny = rd.dx, rd.dy end
        cx, cy = cx + nx * nudge, cy + ny * nudge
    end

    local dirX, dirY = math.cos(cAngle), math.sin(cAngle)
    local rightX, rightY = -dirY, dirX
    local doorProgress = require("presentation.door_transition").approachProgress()
    if doorProgress > 0 then
        cx, cy = cx + dirX * doorProgress * 0.22, cy + dirY * doorProgress * 0.22
    end
    local cameraX, cameraY = cx + 1, cy + 1
    local cameraZ = 0.5
    local surfaces = {}
    local pendingFloorModels = {}
    local dynamicGroups = {}
    local persistentBatchDraws, dynamicMeshDraws, modelDraws = 0, 0, 0
    local dynamicByCategory = {}
    local dynamicSourceQuads = {}
    local function quadVisible(a, b, c, d)
        local minDepth, maxDepth = math.huge, -math.huge
        for _, point in ipairs({ a, b, c, d }) do
            local depth = (point.x - cameraX) * dirX + (point.y - cameraY) * dirY
            minDepth = math.min(minDepth, depth)
            maxDepth = math.max(maxDepth, depth)
        end
        return maxDepth > 0.05 and minDepth < 32.0, (minDepth + maxDepth) * 0.5
    end
    local mapData = session.currentMapData
    local fog = getFogConfig(session, mapData)
    local atlas = resolveTileset(mapData, session)
    local structure = viewport_3d.prepareStructure(session)
    if not structure.worldEffectsInitialized then
        structure.worldEffectsInitialized = true
        structure.worldEffectHandles = {}
        local effekseer = require("presentation.effekseer")
        effekseer.init(session.loader)
        local placements = {}
        for _, source in ipairs(mapData and mapData.lightObjects or {}) do placements[#placements + 1] = source end
        for _, source in ipairs(session.generatedFeatures or {}) do placements[#placements + 1] = source end
        for _, placement in ipairs(placements) do
            local spec = atlas and atlas.tiles[placement.material or ""]
            if spec and spec.effect then
                local ex, ey = placement.x + 1.5, placement.y + 1.5
                local ez = tonumber(spec.effectHeight)
                    or (spec.role == "wall_feature" and 0.55 or 0.08)
                if spec.role == "wall_feature" then
                    local gx, gy = placement.x + 1, placement.y + 1
                    for _, delta in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
                        local nx, ny = gx + delta[1], gy + delta[2]
                        if grid[ny] and grid[ny][nx] and grid[ny][nx] ~= "#" then
                            ex = gx + 0.5 + delta[1] * 0.502
                            ey = gy + 0.5 + delta[2] * 0.502
                            break
                        end
                    end
                end
                local handle = effekseer.playWorld(
                    spec.effect, ex, ey, ez, spec.effectMagnification)
                if handle then structure.worldEffectHandles[#structure.worldEffectHandles + 1] = handle end
            end
        end
    end
    for _, batch in pairs(structure.surfaceBatches or {}) do batch.selected = {} end
    local light = (mapData and (mapData.runtimeLight or mapData.light)) or nil
    local pLightCfg = session.loader and session.loader.system and session.loader.system.dungeon
        and session.loader.system.dungeon.playerLight
    local playerLight = {
        enabled = (pLightCfg == nil or pLightCfg.enabled == nil) and true or pLightCfg.enabled,
        radius = (pLightCfg and pLightCfg.radius) or 3.5,
        color = (pLightCfg and pLightCfg.color) or { 0.35, 0.3, 0.22 },
        falloff = (pLightCfg and pLightCfg.falloff) or 1.5,
        onlyInDungeons = (pLightCfg == nil or pLightCfg.onlyInDungeons == nil) and true or pLightCfg.onlyInDungeons,
    }
    playerLight.active = playerLight.enabled and (not playerLight.onlyInDungeons or not (mapData and mapData.safe)) and playerLight.radius > 0
    local psxCfg = session.loader and session.loader.system and session.loader.system.dungeon
        and session.loader.system.dungeon.psxRendering or {}
    local affineTextures = psxCfg.affineTextures ~= false
    local vertexSnapPixels = math.max(0, tonumber(psxCfg.vertexSnapPixels) or 0)
    local fogBands = math.max(0, math.floor(tonumber(fog.psxBands) or tonumber(psxCfg.fogBands) or 0))
    local ditherLevels = math.max(0, tonumber(psxCfg.ditherLevels) or 0)
    local function group(texture, category)
        category = category or "dynamic"
        local textureGroups = dynamicGroups[texture]
        if not textureGroups then
            textureGroups = {}
            dynamicGroups[texture] = textureGroups
        end
        local grp = textureGroups[category]
        if not grp then
            grp = { texture = texture, vertices = {}, category = category }
            textureGroups[category] = grp
        end
        return grp
    end

    local BASE_MIN_SUBDIVISION_AREA = 0.15

    -- Hardware depth testing exposes geometry which crosses the camera plane:
    -- projecting a negative-depth vertex turns the whole quad inside out and
    -- can make a nearby floor tile occlude the room. Clip leaf polygons to the
    -- near plane before they reach the GPU, interpolating every vertex field.
    local function addNearClippedQuad(grp, a, b, c, d, uv, colors)
        local polygon = {
            { p = a, u = uv[1], v = uv[2], color = colors[1] },
            { p = b, u = uv[3], v = uv[2], color = colors[2] },
            { p = c, u = uv[3], v = uv[4], color = colors[3] },
            { p = d, u = uv[1], v = uv[4], color = colors[4] },
        }
        local function depth(vertex)
            return (vertex.p.x - cameraX) * dirX + (vertex.p.y - cameraY) * dirY
        end
        local function intersection(from, to, fromDepth, toDepth)
            local t = (0.05 - fromDepth) / (toDepth - fromDepth)
            local function lerp(x, y) return x + (y - x) * t end
            return {
                p = { x = lerp(from.p.x, to.p.x), y = lerp(from.p.y, to.p.y), z = lerp(from.p.z, to.p.z) },
                u = lerp(from.u, to.u), v = lerp(from.v, to.v),
                color = {
                    lerp(from.color[1], to.color[1]), lerp(from.color[2], to.color[2]),
                    lerp(from.color[3], to.color[3]), lerp(from.color[4], to.color[4]),
                },
            }
        end
        local clipped = {}
        local previous = polygon[#polygon]
        local previousDepth = depth(previous)
        for _, current in ipairs(polygon) do
            local currentDepth = depth(current)
            local previousInside, currentInside = previousDepth >= 0.05, currentDepth >= 0.05
            if previousInside ~= currentInside then
                table.insert(clipped, intersection(previous, current, previousDepth, currentDepth))
            end
            if currentInside then table.insert(clipped, current) end
            previous, previousDepth = current, currentDepth
        end
        if #clipped < 3 then return end
        local first = clipped[1]
        for i = 2, #clipped - 1 do
            for _, vertex in ipairs({ first, clipped[i], clipped[i + 1] }) do
                addWorldVertex(grp, vertex.p.x, vertex.p.y, vertex.p.z, vertex.u, vertex.v,
                    vertex.color[1], vertex.color[2], vertex.color[3], vertex.color[4])
            end
        end
    end

    local function getQuadArea(a, b, c, d)
        local abX, abY, abZ = b.x - a.x, b.y - a.y, b.z - a.z
        local adX, adY, adZ = d.x - a.x, d.y - a.y, d.z - a.z
        local lenAB = math.sqrt(abX * abX + abY * abY + abZ * abZ)
        local lenAD = math.sqrt(adX * adX + adY * adY + adZ * adZ)
        return lenAB * lenAD
    end

    local function addVisibleWorldQuad(grp, a, b, c, d, uv, colors, maxDepth, category)
        maxDepth = maxDepth or 2
        local visible, depth = quadVisible(a, b, c, d)
        if not visible then return end

        local centerX = (a.x + b.x + c.x + d.x) * 0.25
        local centerY = (a.y + b.y + c.y + d.y) * 0.25
        local centerZ = (a.z + b.z + c.z + d.z) * 0.25
        local dx, dy, dz = centerX - cameraX, centerY - cameraY, centerZ - cameraZ
        local distSq = dx * dx + dy * dy + dz * dz
        local area = getQuadArea(a, b, c, d)

        -- Distance-sensitive area threshold: as distance increases, required face area for subdivision increases
        local requiredArea = BASE_MIN_SUBDIVISION_AREA * (1.0 + 0.5 * distSq)

        if affineTextures and area >= requiredArea and maxDepth > 0 then
            local mAB = { x = (a.x + b.x) * 0.5, y = (a.y + b.y) * 0.5, z = (a.z + b.z) * 0.5 }
            local mBC = { x = (b.x + c.x) * 0.5, y = (b.y + c.y) * 0.5, z = (b.z + c.z) * 0.5 }
            local mCD = { x = (c.x + d.x) * 0.5, y = (c.y + d.y) * 0.5, z = (c.z + d.z) * 0.5 }
            local mDA = { x = (d.x + a.x) * 0.5, y = (d.y + a.y) * 0.5, z = (d.z + a.z) * 0.5 }
            local mCenter = { x = centerX, y = centerY, z = centerZ }

            local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
            local uMid = (u0 + u1) * 0.5
            local vMid = (v0 + v1) * 0.5

            local uvTL = { u0, v0, uMid, vMid }
            local uvTR = { uMid, v0, u1, vMid }
            local uvBR = { uMid, vMid, u1, v1 }
            local uvBL = { u0, vMid, uMid, v1 }

            local cA, cB, cC, cD = colors[1], colors[2], colors[3], colors[4]
            local function lerpColor(c1, c2)
                return {
                    (c1[1] + c2[1]) * 0.5,
                    (c1[2] + c2[2]) * 0.5,
                    (c1[3] + c2[3]) * 0.5,
                    (c1[4] + c2[4]) * 0.5,
                }
            end

            local cAB = lerpColor(cA, cB)
            local cBC = lerpColor(cB, cC)
            local cCD = lerpColor(cC, cD)
            local cDA = lerpColor(cD, cA)
            local cCenter = lerpColor(cAB, cCD)

            addVisibleWorldQuad(grp, a, mAB, mCenter, mDA, uvTL, { cA, cAB, cCenter, cDA }, maxDepth - 1, category)
            addVisibleWorldQuad(grp, mAB, b, mBC, mCenter, uvTR, { cAB, cB, cBC, cCenter }, maxDepth - 1, category)
            addVisibleWorldQuad(grp, mCenter, mBC, c, mCD, uvBR, { cCenter, cBC, cC, cCD }, maxDepth - 1, category)
            addVisibleWorldQuad(grp, mDA, mCenter, mCD, d, uvBL, { cDA, cCenter, cCD, cD }, maxDepth - 1, category)
        else
            local quadGrp = group(grp.texture, category)
            local wasEmpty = #quadGrp.vertices == 0
            addNearClippedQuad(quadGrp, a, b, c, d, uv, colors)
            dynamicSourceQuads[quadGrp.category] =
                (dynamicSourceQuads[quadGrp.category] or 0) + 1
            quadGrp.depthTotal = (quadGrp.depthTotal or 0) + depth
            quadGrp.depthCount = (quadGrp.depthCount or 0) + 1
            quadGrp.depth = quadGrp.depthTotal / quadGrp.depthCount
            if wasEmpty and #quadGrp.vertices > 0 then
                quadGrp.sequence = #surfaces + 1
                table.insert(surfaces, quadGrp)
            end
        end
    end
    local function colorAt(x, y, z, sideDarken)
        local ix, iy = math.floor(x), math.floor(y)
        local r, g, b = sampleLight(light, ix, iy, x - ix, y - iy)
        if sideDarken then r, g, b = r * 0.76, g * 0.76, b * 0.76 end
        return { r, g, b, 1 }
    end

    local function ensureSurfaceMeshTree(owner, texture, rootA, rootB, rootC, rootD, rootUV, rootColors)
        if owner.meshTree then return owner.meshTree end
        structure.surfaceBatches = structure.surfaceBatches or {}
        local batch = structure.surfaceBatches[texture]
        if not batch then
            batch = { texture = texture, vertices = {}, selected = {}, dirty = false }
            structure.surfaceBatches[texture] = batch
        end
        local function lerpColor(c1, c2)
            return {
                (c1[1] + c2[1]) * 0.5, (c1[2] + c2[2]) * 0.5,
                (c1[3] + c2[3]) * 0.5, (c1[4] + c2[4]) * 0.5,
            }
        end
        local function build(a, b, c, d, uv, colors, depthLeft)
            local vertices = {}
            addWorldQuad({ vertices = vertices }, a, b, c, d, uv, colors)
            local first = #batch.vertices + 1
            for _, vertex in ipairs(vertices) do table.insert(batch.vertices, vertex) end
            local indices = {}
            for i = first, first + #vertices - 1 do table.insert(indices, i) end
            batch.dirty = true
            local node = {
                a = a, b = b, c = c, d = d, uv = uv, colors = colors,
                batch = batch, indices = indices,
                area = getQuadArea(a, b, c, d), children = nil,
                centerX = (a.x + b.x + c.x + d.x) * 0.25,
                centerY = (a.y + b.y + c.y + d.y) * 0.25,
                centerZ = (a.z + b.z + c.z + d.z) * 0.25,
            }
            if depthLeft > 0 then
                local mAB = { x = (a.x + b.x) * 0.5, y = (a.y + b.y) * 0.5, z = (a.z + b.z) * 0.5 }
                local mBC = { x = (b.x + c.x) * 0.5, y = (b.y + c.y) * 0.5, z = (b.z + c.z) * 0.5 }
                local mCD = { x = (c.x + d.x) * 0.5, y = (c.y + d.y) * 0.5, z = (c.z + d.z) * 0.5 }
                local mDA = { x = (d.x + a.x) * 0.5, y = (d.y + a.y) * 0.5, z = (d.z + a.z) * 0.5 }
                local center = { x = node.centerX, y = node.centerY, z = node.centerZ }
                local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
                local uMid, vMid = (u0 + u1) * 0.5, (v0 + v1) * 0.5
                local cA, cB, cC, cD = colors[1], colors[2], colors[3], colors[4]
                local cAB, cBC = lerpColor(cA, cB), lerpColor(cB, cC)
                local cCD, cDA = lerpColor(cC, cD), lerpColor(cD, cA)
                local cCenter = lerpColor(cAB, cCD)
                node.children = {
                    build(a, mAB, center, mDA, { u0, v0, uMid, vMid }, { cA, cAB, cCenter, cDA }, depthLeft - 1),
                    build(mAB, b, mBC, center, { uMid, v0, u1, vMid }, { cAB, cB, cBC, cCenter }, depthLeft - 1),
                    build(center, mBC, c, mCD, { uMid, vMid, u1, v1 }, { cCenter, cBC, cC, cCD }, depthLeft - 1),
                    build(mDA, center, mCD, d, { u0, vMid, uMid, v1 }, { cDA, cCenter, cCD, cD }, depthLeft - 1),
                }
            end
            return node
        end
        owner.meshTree = build(rootA, rootB, rootC, rootD, rootUV, rootColors, 2)
        return owner.meshTree
    end

    local function queueMeshNodes(node)
        local visible, depth = quadVisible(node.a, node.b, node.c, node.d)
        if not visible then return end
        local minDepth = math.huge
        for _, point in ipairs({ node.a, node.b, node.c, node.d }) do
            minDepth = math.min(minDepth, (point.x - cameraX) * dirX + (point.y - cameraY) * dirY)
        end
        if minDepth < 0.05 then return false end
        local dx, dy, dz = node.centerX - cameraX, node.centerY - cameraY, node.centerZ - cameraZ
        local requiredArea = BASE_MIN_SUBDIVISION_AREA * (1.0 + 0.5 * (dx * dx + dy * dy + dz * dz))
        if affineTextures and node.children and node.area >= requiredArea then
            for _, child in ipairs(node.children) do
                if queueMeshNodes(child) == false then return false end
            end
        else
            node.batch.selected[#node.batch.selected + 1] = node
        end
        return true
    end
    local function textureInfo(originX, originY, texture)
        if texture == atlas.img then return atlasUV(originX, originY, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h, false) end
        return 0, 0, 1, 1
    end

    local floorTexture = atlas and atlas.img or getWhiteWallTexture()
    local floorOriginX = atlas and (atlas.floorCol or 0) * ATLAS_TILE or 0
    local floorOriginY = atlas and (atlas.floorRow or 3) * ATLAS_TILE or 0
    local ceilingTexture = atlas and atlas.img or getWhiteWallTexture()
    local ceilingOriginX = atlas and (atlas.ceilingCol or 0) * ATLAS_TILE or 0
    local ceilingOriginY = atlas and (atlas.ceilingRow or 0) * ATLAS_TILE or 0
    local floorUV = atlas and { atlasUV(floorOriginX, floorOriginY, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h, false) } or { 0, 0, 1, 1 }
    local ceilingUV = atlas and { atlasUV(ceilingOriginX, ceilingOriginY, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h, false) } or { 0, 0, 1, 1 }
    for _, cell in ipairs(structure.floorCells) do
        local x, y = cell.x, cell.y
        if not cell.floorSurface then
            local floorSpec = atlas and viewport_3d.resolveWeightedVariant(
                atlas.manifest and atlas.manifest.base and atlas.manifest.base.floors,
                x, y, 961748927, 982451653)
            local cellFloorUV = floorUV
            if floorSpec and floorSpec.atlas then
                cellFloorUV = { atlasUV(floorSpec.atlas[2] * ATLAS_TILE,
                    floorSpec.atlas[1] * ATLAS_TILE, ATLAS_TILE, ATLAS_TILE,
                    atlas.w, atlas.h, false) }
            end
            cell.floorSurface = {
                a = { x = x, y = y, z = 0 }, b = { x = x + 1, y = y, z = 0 },
                c = { x = x + 1, y = y + 1, z = 0 }, d = { x = x, y = y + 1, z = 0 },
                uv = cellFloorUV,
                colors = { colorAt(x, y, 0, false), colorAt(x + 1, y, 0, false),
                    colorAt(x + 1, y + 1, 0, false), colorAt(x, y + 1, 0, false) },
            }
        end
        local floor = cell.floorSurface
        if queueMeshNodes(ensureSurfaceMeshTree(floor, floorTexture,
                floor.a, floor.b, floor.c, floor.d, floor.uv, floor.colors)) == false then
            addVisibleWorldQuad(group(floorTexture), floor.a, floor.b, floor.c, floor.d,
                floor.uv, floor.colors, nil, "floor_clip")
        end
        local floorFeature = atlas and atlas.tiles[structure.materialLookup[x .. "," .. y] or ""]
        if floorFeature and floorFeature.role == "floor_feature" and floorFeature.model then
            pendingFloorModels[#pendingFloorModels + 1] = {
                spec = floorFeature, x = x + 0.5, y = y + 0.5,
                key = "floor-feature:" .. x .. "," .. y .. ":" .. tostring(floorFeature.model),
            }
        end
        if floorFeature and floorFeature.role == "floor_feature" and floorFeature.atlas then
            if not cell.floorFeatureSurface then
                local featureUV = { atlasUV(floorFeature.atlas[2] * ATLAS_TILE,
                    floorFeature.atlas[1] * ATLAS_TILE, ATLAS_TILE, ATLAS_TILE,
                    atlas.w, atlas.h, false) }
                cell.floorFeatureSurface = {
                    a = { x = x, y = y, z = 0.002 }, b = { x = x + 1, y = y, z = 0.002 },
                    c = { x = x + 1, y = y + 1, z = 0.002 }, d = { x = x, y = y + 1, z = 0.002 },
                    uv = featureUV, colors = floor.colors,
                }
            end
            local feature = cell.floorFeatureSurface
            if queueMeshNodes(ensureSurfaceMeshTree(feature, atlas.img,
                    feature.a, feature.b, feature.c, feature.d, feature.uv, feature.colors)) == false then
                addVisibleWorldQuad(group(atlas.img), feature.a, feature.b, feature.c, feature.d,
                    feature.uv, feature.colors, nil, "floor_feature_clip")
            end
        end
        if not (mapData and mapData.ceilingStyle == "sky") then
            if not cell.ceilingSurface then
                local ceilingSpec = atlas and viewport_3d.resolveWeightedVariant(
                    atlas.manifest and atlas.manifest.base and atlas.manifest.base.ceilings,
                    x, y, 15485863, 32452843)
                local cellCeilingUV = ceilingUV
                if ceilingSpec and ceilingSpec.atlas then
                    cellCeilingUV = { atlasUV(ceilingSpec.atlas[2] * ATLAS_TILE,
                        ceilingSpec.atlas[1] * ATLAS_TILE, ATLAS_TILE, ATLAS_TILE,
                        atlas.w, atlas.h, false) }
                end
                cell.ceilingSurface = {
                    a = { x = x, y = y + 1, z = 1 }, b = { x = x + 1, y = y + 1, z = 1 },
                    c = { x = x + 1, y = y, z = 1 }, d = { x = x, y = y, z = 1 },
                    uv = cellCeilingUV,
                    colors = { colorAt(x, y + 1, 1, false), colorAt(x + 1, y + 1, 1, false),
                        colorAt(x + 1, y, 1, false), colorAt(x, y, 1, false) },
                }
            end
            local ceiling = cell.ceilingSurface
            if queueMeshNodes(ensureSurfaceMeshTree(ceiling, ceilingTexture,
                    ceiling.a, ceiling.b, ceiling.c, ceiling.d, ceiling.uv, ceiling.colors)) == false then
                addVisibleWorldQuad(group(ceilingTexture),
                    ceiling.a, ceiling.b, ceiling.c, ceiling.d, ceiling.uv, ceiling.colors,
                    nil, "ceiling_clip")
            end
        end
    end

    structure.modelSurfaces = structure.modelSurfaces or {}
    local objModel = require("presentation.obj_model")
    local function ensurePlacedModel(spec, cacheKey, originX, originY, axis)
        if structure.modelSurfaces[cacheKey] then return structure.modelSurfaces[cacheKey] end
        local model, placed = objModel.load(spec.model), {}
        for _, modelGroup in ipairs(model.groups) do
            local vertices = {}
            for _, vertex in ipairs(modelGroup.vertices) do
                local lx, ly, lz = vertex[1], vertex[2], vertex[3]
                local nx, ny, nz = vertex[6], vertex[7], vertex[8]
                if axis == "y" then
                    lx, ly = -ly, lx
                    nx, ny = -ny, nx
                end
                local wx, wy, wz = originX + lx, originY + ly, lz
                local light = colorAt(wx, wy, wz, false)
                local directional = math.max(0.35,
                    0.55 + 0.45 * (nx * -0.4 + ny * -0.6 + nz * 0.7))
                vertices[#vertices + 1] = {
                    wx, wy, vertex[4], vertex[5],
                    modelGroup.color[1], modelGroup.color[2], modelGroup.color[3], modelGroup.color[4],
                    light[1] * directional, light[2] * directional, light[3] * directional,
                    1, wz,
                }
            end
            local mesh = love.graphics.newMesh(WORLD_MESH_FORMAT, vertices, "triangles", "static")
            if modelGroup.texture then mesh:setTexture(modelGroup.texture) end
            placed[#placed + 1] = {
                mesh = mesh, model = true,
                centerX = originX, centerY = originY, centerZ = 0.5,
            }
        end
        structure.modelSurfaces[cacheKey] = placed
        return placed
    end
    local function queuePlacedModels(placedGroups)
        for _, placed in ipairs(placedGroups) do
            placed.depth = (placed.centerX - cameraX) * dirX
                + (placed.centerY - cameraY) * dirY
            placed.sequence = #surfaces + 1
            surfaces[#surfaces + 1] = placed
        end
    end

    for _, placement in ipairs(pendingFloorModels) do
        queuePlacedModels(ensurePlacedModel(placement.spec, placement.key,
            placement.x, placement.y, "x"))
    end

    for _, face in ipairs(prepareResolvedWallFaces(structure, atlas)) do
        if face.normalX * (cameraX - face.centerX)
                + face.normalY * (cameraY - face.centerY) > 0 then
            local p1, p2 = face.p1, face.p2
            if not face.surface then
                face.surface = {
                    a = { x = p1.x, y = p1.y, z = 0 }, b = { x = p2.x, y = p2.y, z = 0 },
                    c = { x = p2.x, y = p2.y, z = 1 }, d = { x = p1.x, y = p1.y, z = 1 },
                    uv = face.uv,
                    colors = { colorAt(p1.x, p1.y, 0, face.sideDarken),
                        colorAt(p2.x, p2.y, 0, face.sideDarken),
                        colorAt(p2.x, p2.y, 1, face.sideDarken),
                        colorAt(p1.x, p1.y, 1, face.sideDarken) },
                }
            end
            local wall = face.surface
            if queueMeshNodes(ensureSurfaceMeshTree(face, face.texture,
                    wall.a, wall.b, wall.c, wall.d, wall.uv, wall.colors)) == false then
                local wallGroup = group(face.texture)
                addVisibleWorldQuad(wallGroup, wall.a, wall.b, wall.c, wall.d,
                    wall.uv, wall.colors, nil, "wall_clip")
            end
            if face.model then
                local axis = face.normalX ~= 0 and "x" or "y"
                local offset = 0.002
                queuePlacedModels(ensurePlacedModel(face,
                    "wall:" .. face.mapX .. "," .. face.mapY .. ":"
                        .. face.centerX .. "," .. face.centerY .. ":"
                        .. axis .. ":" .. tostring(face.model),
                    face.centerX + face.normalX * offset,
                    face.centerY + face.normalY * offset, axis))
            end
        end
    end

    -- A structural opening is passable but not visually empty. Until kit-piece
    -- models land, build a genuine open silhouette from three pieces sampled
    -- from the tileset's door cell: two jambs and a lintel. Unlike the retired
    -- raycaster's opaque door-row wall, this lets the player see and walk
    -- through the space while keeping the authored structural distinction.
    if atlas then
        local function mix(a, b, t) return a + (b - a) * t end
        local function addOpeningPiece(x, y, axis, lo, hi, bottom, top, uv)
            local openingGroup = group(atlas.img)
            local colors
            if axis == "x" then
                local wx = x + 0.5
                colors = {
                    colorAt(wx, y + lo, bottom, false), colorAt(wx, y + hi, bottom, false),
                    colorAt(wx, y + hi, top, false), colorAt(wx, y + lo, top, false),
                }
                addVisibleWorldQuad(openingGroup,
                    { x = wx, y = y + lo, z = bottom }, { x = wx, y = y + hi, z = bottom },
                    { x = wx, y = y + hi, z = top }, { x = wx, y = y + lo, z = top },
                    uv, colors, nil, "opening")
            else
                local wy = y + 0.5
                colors = {
                    colorAt(x + hi, wy, bottom, true), colorAt(x + lo, wy, bottom, true),
                    colorAt(x + lo, wy, top, true), colorAt(x + hi, wy, top, true),
                }
                addVisibleWorldQuad(openingGroup,
                    { x = x + hi, y = wy, z = bottom }, { x = x + lo, y = wy, z = bottom },
                    { x = x + lo, y = wy, z = top }, { x = x + hi, y = wy, z = top },
                    uv, colors, nil, "opening")
            end
        end
        for _, cell in ipairs(structure.openingCells) do
            local x, y, axis = cell.x, cell.y, cell.axis
            local doorSpec = viewport_3d.resolveWeightedVariant(
                atlas.manifest and atlas.manifest.doors, x, y, 83492791, 39916801)
            if doorSpec and doorSpec.model then
                queuePlacedModels(ensurePlacedModel(doorSpec,
                    "opening:" .. x .. "," .. y .. ":" .. axis .. ":" .. tostring(doorSpec.model),
                    x + 0.5, y + 0.5, axis))
            else
                local doorOriginX = doorSpec and doorSpec.atlas and doorSpec.atlas[2] * ATLAS_TILE or 0
                local doorOriginY = doorSpec and doorSpec.atlas and doorSpec.atlas[1] * ATLAS_TILE
                    or (atlas.doorRow or 2) * ATLAS_TILE
                local doorU0, doorV0, doorU1, doorV1 = atlasUV(
                    doorOriginX, doorOriginY, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h, false)
                addOpeningPiece(x, y, axis, 0, 0.18, 0, 1,
                    { doorU0, doorV0, mix(doorU0, doorU1, 0.18), doorV1 })
                addOpeningPiece(x, y, axis, 0.82, 1, 0, 1,
                    { mix(doorU0, doorU1, 0.82), doorV0, doorU1, doorV1 })
                addOpeningPiece(x, y, axis, 0.18, 0.82, 0.82, 1,
                    { mix(doorU0, doorU1, 0.18), doorV0,
                        mix(doorU0, doorU1, 0.82), mix(doorV0, doorV1, 0.18) })
            end
        end
    end

    local function addBillboard(image, x, y)
        local centerX, centerY = x + 1.5, y + 1.5
        local groupForSprite = group(image)
        local u0, v0, u1, v1 = 0, 1, 1, 0
        local function spriteColor(wx, wy, z)
            local c = colorAt(wx, wy, z, false)
            return c
        end
        addVisibleWorldQuad(groupForSprite,
            { x = centerX - rightX * 0.5, y = centerY - rightY * 0.5, z = 0 },
            { x = centerX + rightX * 0.5, y = centerY + rightY * 0.5, z = 0 },
            { x = centerX + rightX * 0.5, y = centerY + rightY * 0.5, z = 1 },
            { x = centerX - rightX * 0.5, y = centerY - rightY * 0.5, z = 1 },
            { u0, v0, u1, v1 },
            { spriteColor(centerX, centerY, 0), spriteColor(centerX, centerY, 0), spriteColor(centerX, centerY, 1), spriteColor(centerX, centerY, 1) },
            nil, "billboard")
    end
    if mapData and mapData.events then
        for _, ev in ipairs(mapData.events) do
            if not ev.wallEvent then
                local image = getEventSprite(ev, session)
                if image then addBillboard(image, ev.x, ev.y) end
            end
        end
    end

    for _, batch in pairs(structure.surfaceBatches or {}) do
        if #batch.selected > 0 then
            if batch.dirty or not batch.mesh then
                if batch.mesh and batch.mesh.release then batch.mesh:release() end
                batch.mesh = love.graphics.newMesh(WORLD_MESH_FORMAT, batch.vertices, "triangles", "static")
                batch.mesh:setTexture(batch.texture)
                batch.dirty = false
            end
            local indices, depthTotal = {}, 0
            for _, node in ipairs(batch.selected) do
                for _, index in ipairs(node.indices) do indices[#indices + 1] = index end
                depthTotal = depthTotal
                    + (node.centerX - cameraX) * dirX + (node.centerY - cameraY) * dirY
            end
            batch.mesh:setVertexMap(indices)
            table.insert(surfaces, {
                mesh = batch.mesh,
                depth = depthTotal / #batch.selected,
                sequence = #surfaces + 1,
            })
            persistentBatchDraws = persistentBatchDraws + 1
        end
    end

    love.graphics.push("all")
    love.graphics.intersectScissor(0, 0, viewportWidth, viewportHeight)
    drawFogBackground(fog, viewportWidth, viewportHeight)
    if mapData and mapData.ceilingStyle == "sky" then
        drawSkyBackdrop(atlas, viewportWidth, viewportHeight, cAngle)
    end
    love.graphics.setShader(shader)
    shader:send("cameraPosition", { cameraX, cameraY, cameraZ })
    shader:send("cameraForward", { dirX, dirY })
    shader:send("cameraRight", { rightX, rightY })
    shader:send("fovHalfX", 0.75)
    shader:send("fovHalfY", 0.421875)
    shader:send("nearPlane", 0.05)
    shader:send("farPlane", 32.0)
    shader:send("baseViewportWidth", baseViewportWidth)
    shader:send("baseViewportHeight", baseViewportHeight)
    shader:send("targetWidth", targetWidth)
    shader:send("targetHeight", targetHeight)
    shader:send("viewportCenterY", viewportCenterY)
    shader:send("affineTextures", affineTextures and 1.0 or 0.0)
    shader:send("vertexSnapPixels", vertexSnapPixels)
    shader:send("fogColor", fog.color)
    shader:send("fogStart", fog.startDist)
    shader:send("fogDistance", fog.distance)
    shader:send("fogSharpness", fog.sharpness)
    shader:send("fogMinFactor", fog.minFactor)
    shader:send("fogBands", fogBands)
    if playerLight.active then
        shader:send("playerLightColor", playerLight.color)
        shader:send("playerLightRadius", playerLight.radius)
        shader:send("playerLightFalloff", playerLight.falloff)
    else
        shader:send("playerLightColor", { 0, 0, 0 })
        shader:send("playerLightRadius", 0.0)
        shader:send("playerLightFalloff", 1.0)
    end
    shader:send("ditherLevels", ditherLevels)
    love.graphics.setColor(1, 1, 1, 1)
    -- Distance fade is a color mix toward the fog/background, never a
    -- translucent polygon. Sort far-to-near for deterministic cutout-edge
    -- ties, while the depth buffer decides actual surface visibility.
    love.graphics.setBlendMode("alpha")
    love.graphics.setDepthMode("less", true)
    table.sort(surfaces, function(a, b)
        if a.depth == b.depth then return a.sequence < b.sequence end
        return a.depth > b.depth
    end)
    for _, g in ipairs(surfaces) do
        if g.mesh then
            if g.model then modelDraws = modelDraws + 1 end
            love.graphics.draw(g.mesh)
        elseif #g.vertices > 0 then
            dynamicMeshDraws = dynamicMeshDraws + 1
            dynamicByCategory[g.category or "dynamic"] =
                (dynamicByCategory[g.category or "dynamic"] or 0) + 1
            structure.dynamicMeshPool = structure.dynamicMeshPool or {}
            local texturePool = structure.dynamicMeshPool[g.texture]
            if not texturePool then
                texturePool = {}
                structure.dynamicMeshPool[g.texture] = texturePool
            end
            local category = g.category or "dynamic"
            local entry = texturePool[category]
            local needed = #g.vertices
            if not entry or entry.capacity < needed then
                if entry and entry.mesh and entry.mesh.release then entry.mesh:release() end
                local capacity = 6
                while capacity < needed do capacity = capacity * 2 end
                entry = {
                    mesh = love.graphics.newMesh(WORLD_MESH_FORMAT, capacity, "triangles", "stream"),
                    capacity = capacity,
                }
                entry.mesh:setTexture(g.texture)
                texturePool[category] = entry
            end
            entry.mesh:setVertices(g.vertices, 1, needed)
            entry.mesh:setDrawRange(1, needed)
            love.graphics.draw(entry.mesh)
        end
    end
    love.graphics.setShader()
    if #(structure.worldEffectHandles or {}) > 0 then
        require("presentation.effekseer").drawWorld({
            x = cameraX, y = cameraY, z = cameraZ,
            dirX = dirX, dirY = dirY, rightX = rightX, rightY = rightY,
            fovHalfX = 0.75, fovHalfY = 0.421875,
            nearPlane = 0.05, farPlane = 32,
            viewportCenterY = viewportCenterY,
            targetHeight = targetHeight,
            viewportWidth = viewportWidth, viewportHeight = viewportHeight,
        })
    end
    love.graphics.setDepthMode()
    love.graphics.pop()
    -- Depth state is canvas-global in LÖVE and is not reliably restored by the
    -- attribute stack on every backend. Presentation sprites and UI are 2D
    -- layers drawn after the world, so explicitly disable testing once more
    -- outside the push/pop boundary.
    love.graphics.setDepthMode()
    love.graphics.setShader()
    love.graphics.clear(false, false, 1)
    local selectedNodes, residentVertices = 0, 0
    for _, batch in pairs(structure.surfaceBatches or {}) do
        selectedNodes = selectedNodes + #(batch.selected or {})
        residentVertices = residentVertices + #(batch.vertices or {})
    end
    lastFrameStats = {
        persistentBatchDraws = persistentBatchDraws,
        dynamicMeshDraws = dynamicMeshDraws,
        modelDraws = modelDraws,
        worldEffectHandles = #(structure.worldEffectHandles or {}),
        queuedSurfaces = #surfaces,
        selectedStructuralNodes = selectedNodes,
        residentStructuralVertices = residentVertices,
        dynamicByCategory = dynamicByCategory,
        dynamicSourceQuads = dynamicSourceQuads,
    }
    require("presentation.door_transition").draw()
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
    -- All world surfaces use one world-space camera and one perspective
    -- shader. The legacy body below is unreachable and retained only as
    -- reference while the remaining presentation details are migrated.
    return drawWorldSpace(session)

end

return viewport_3d
