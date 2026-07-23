local viewport_3d = {}
local ui = require("presentation.ui")
local exploration = require("engine.exploration")
local config = require("engine.config")

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
        local tiles = {}
        if tilesetDef.tiles then
            for k, v in pairs(tilesetDef.tiles) do tiles[k] = v end
        end
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

local function getCompositeTileCanvas(atlas, originX, originY, leftEdgeSpec, rightEdgeSpec, featureOverlay)
    local key = (atlas.manifest and atlas.manifest.id or "default")
        .. ":" .. originX .. "," .. originY
        .. "|" .. (leftEdgeSpec and (leftEdgeSpec[1] .. "," .. leftEdgeSpec[2] .. "," .. (leftEdgeSpec[3] or 0)) or "")
        .. "|" .. (rightEdgeSpec and (rightEdgeSpec[1] .. "," .. rightEdgeSpec[2] .. "," .. (rightEdgeSpec[3] or 32)) or "")
        .. "|" .. (featureOverlay and featureOverlay.atlas and (featureOverlay.atlas[1] .. "," .. featureOverlay.atlas[2]) or "")

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
local function cellHash(mapX, mapY, saltA, saltB)
    local h = (mapX * saltA + mapY * saltB) % 2147483647
    if h < 0 then h = -h end
    return h
end
local function wallVariant(mapX, mapY, variantCount)
    return cellHash(mapX, mapY, 73856093, 19349663) % variantCount
end
local function doorVariant(mapX, mapY)
    return cellHash(mapX, mapY, 83492791, 39916801) % ATLAS_DOOR_VARIANTS
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
end

-- Resolves which atlas to draw walls/doors/sky from this frame: the map's
-- own `tileset` if it names one, else DEFAULT_TILESET. Returns nil if that
-- atlas file doesn't exist (draw() falls back to flat-shaded lines).
local function resolveTileset(mapData, session)
    local tilesetId = (mapData and mapData.tileset) or "dungeon_default"
    local tilesetDef = (session and session.loader and session.loader.getTileset(tilesetId))
        or (loader and loader.getTileset and loader.getTileset(tilesetId))
    if tilesetDef then
        return getAtlasByDef(tilesetDef.id or tilesetId, tilesetDef)
    end
    return nil
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
    for _, source in ipairs(session.generatedLightObjects or {}) do
        lookup[(source.x + 1) .. "," .. (source.y + 1)] = source.material
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
        local duration = session.transitionDuration or 0.15
        local frac = duration > 0 and (session.transitionTimer / duration) or 1
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

    -- ── 2. Bump nudge (wall collision feedback) ────────────────────────────
    -- When bumpTimer > 0, push the camera into the wall for a brief moment
    -- and then ease back, simulating a half-step into the obstacle.
    -- The nudge direction matches the ATTEMPTED movement direction so
    -- forward/backward bumps nudge forward/backward, and strafe bumps nudge
    -- left/right respectively.  Decays from 0.12 tiles → 0 over 120ms.
    if session.bumpTimer and session.bumpTimer > 0 then
        local bumpDur = (config.ui and config.ui.bumpDuration) or 0.12
        local frac = bumpDur > 0 and (session.bumpTimer / bumpDur) or 1
        local maxNudge = (config.ui and config.ui.bumpNudge) or 0.12
        local nudge = frac * maxNudge
        local dx, dy = 0, 0
        local key = session.bumpNudgeKey
        local fwd = DIRS[pdir]
        if key == "up" or key == "w" then
            dx, dy = fwd.dx, fwd.dy                      -- forward
        elseif key == "down" or key == "s" then
            dx, dy = -fwd.dx, -fwd.dy                    -- backward
        elseif key == "q" then
            local ld = DIRS[turnLeftDir(pdir)]
            dx, dy = ld.dx, ld.dy                         -- strafe left
        elseif key == "e" then
            local rd = DIRS[turnRightDir(pdir)]
            dx, dy = rd.dx, rd.dy                         -- strafe right
        else
            dx, dy = fwd.dx, fwd.dy                       -- fallback: forward
        end
        cx = cx + dx * nudge
        cy = cy + dy * nudge
    end

    -- Camera direction vector + projection plane (orthogonal to camera
    -- direction, 73.74-degree FOV for 1:1 square tile ratio) -- computed
    -- here (rather than just before the wall loop, where this used to live)
    -- because the floor/ceiling shader below needs it too.
    local dirX = math.cos(cAngle)
    local dirY = math.sin(cAngle)
    local fovHalfTan = 0.75
    local planeX = -dirY * fovHalfTan
    local planeY = dirX * fovHalfTan

    local mapData = session.currentMapData

    -- Resolved fog config (preset-aware) -- black fog with no panorama IS
    -- the plain darken-with-distance behavior, so there's exactly one
    -- shading model: draw the fog background, then everything else at
    -- alpha = fogAlpha. See docs/design/fog-presets-and-panorama.md.
    local fog = getFogConfig(session, mapData)

    -- Resolved player light config from system settings
    local sysCfg = session and session.loader and session.loader.system
    local dungeonCfg = sysCfg and sysCfg.dungeon
    local pLightCfg = dungeonCfg and dungeonCfg.playerLight
    local playerLight = {
        enabled = (pLightCfg == nil or pLightCfg.enabled == nil) and true or pLightCfg.enabled,
        radius = (pLightCfg and pLightCfg.radius) or 3.5,
        color = (pLightCfg and pLightCfg.color) or { 0.35, 0.3, 0.22 },
        falloff = (pLightCfg and pLightCfg.falloff) or 1.5,
        onlyInDungeons = (pLightCfg == nil or pLightCfg.onlyInDungeons == nil) and true or pLightCfg.onlyInDungeons,
    }
    local isDungeon = not (mapData and mapData.safe)
    playerLight.active = playerLight.enabled and (not playerLight.onlyInDungeons or isDungeon) and playerLight.radius > 0

    -- ── 2. Draw Floor & Ceiling ───────────────────────────────────────────────
    local halfH = ui.toPx(9) -- exactly 9 tiles (72px)
    local screenWpx = ui.toPx(ui.screenWidthTiles)
    local light = (mapData and mapData.runtimeLight) or (mapData and mapData.light)

    -- Player-cell vertex light, used to tint the gradient FALLBACK as a
    -- single color (the shader path samples the light texture per-pixel
    -- instead). See docs/design/raycaster-tileset-lighting.md.
    local px0, py0 = math.floor(cx + 1), math.floor(cy + 1)
    local ambR, ambG, ambB = sampleLight(light, px0, py0, (cx + 1) - px0, (cy + 1) - py0)
    if playerLight.active then
        ambR = math.min(1.0, ambR + playerLight.color[1])
        ambG = math.min(1.0, ambG + playerLight.color[2])
        ambB = math.min(1.0, ambB + playerLight.color[3])
    end

    -- The active session owns the loaded tileset registry. Omitting it here
    -- makes resolveTileset fall back to a nonexistent module-global loader,
    -- returning nil and rendering the flat black/blue fallback instead.
    local atlas = resolveTileset(mapData, session)
    local lightTex, lightW, lightH = getLightTexture(mapData)

    -- Fog background FIRST: everything drawn after this (shaded floor/
    -- ceiling, walls, sprites) uses alpha = fogAlpha and blends against it.
    -- See docs/design/fog-presets-and-panorama.md.
    drawFogBackground(fog, screenWpx, halfH * 2)

    if mapData and mapData.ceilingStyle == "sky" and atlas and (atlas.skyTiles or atlas.skyRow) then
        local skyTiles = atlas.skyTiles
        if not skyTiles or #skyTiles == 0 then
            skyTiles = { { atlas.skyRow or 0, atlas.skyCol or 0 } }
        end
        local numSkyTiles = #skyTiles
        local scaleY = halfH / ATLAS_TILE
        local scaleX = scaleY
        local tileWpx = ATLAS_TILE * scaleX
        local tileIdx = 1
        local x = 0

        -- Sky is daylight, not torchlight -- deliberately NOT tinted by the
        -- vertex light grid (that models local/indoor light sources).
        love.graphics.setColor(1, 1, 1, 1)
        while x < screenWpx do
            local tile = skyTiles[tileIdx]
            local r, c = tile[1], tile[2]
            skyQuad:setViewport(c * ATLAS_TILE, r * ATLAS_TILE, ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h)
            love.graphics.draw(atlas.img, skyQuad, x, 0, 0, scaleX, scaleY)
            x = x + tileWpx
            tileIdx = (tileIdx % numSkyTiles) + 1
        end
    elseif atlas and atlas.ceilingRow
        and drawShadedPlane(atlas, atlas.ceilingRow, atlas.ceilingCol, 0, halfH, cx, cy, dirX, dirY, planeX, planeY, lightTex, lightW, lightH, fog, playerLight) then
        -- shaded plane drawn; nothing else to do
    else
        -- Ceiling gradient: Moody dark purple/indigo fade
        drawVerticalGradient(0, 0, screenWpx, halfH,
            {0.09 * ambR, 0.06 * ambG, 0.14 * ambB},
            {0.02 * ambR, 0.01 * ambG, 0.04 * ambB})
    end

    if not (atlas and atlas.floorRow
        and drawShadedPlane(atlas, atlas.floorRow, atlas.floorCol, halfH, halfH, cx, cy, dirX, dirY, planeX, planeY, lightTex, lightW, lightH, fog, playerLight)) then
        -- Floor gradient: Cold dark stone grey fade
        drawVerticalGradient(0, halfH, screenWpx, halfH,
            {0.03 * ambR, 0.03 * ambG, 0.03 * ambB},
            {0.14 * ambR, 0.12 * ambG, 0.10 * ambB})
    end

    local doorLookup = buildDoorLookup(session)
    local materialLookup = buildMaterialLookup(session)

    -- ── 3. Perspective Raycasting Loop with Fish-eye Correction ────────────────
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
        local lineHeight = math.floor(170.6667 / perpWallDist)

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

        -- x coordinate on the texture (atlas tiles are always 64px)
        local texX = math.floor(wallX * ATLAS_TILE)
        if side == 0 and rx > 0 then texX = (ATLAS_TILE - 1) - texX end
        if side == 1 and ry < 0 then texX = (ATLAS_TILE - 1) - texX end

        -- Vertex lighting: bilinear-sample the light grid at the actual
        -- continuous world hit position (same perpWallDist used for wallX).
        local hitWX = cx + 1 + perpWallDist * rx
        local hitWY = cy + 1 + perpWallDist * ry
        local vx0, vy0 = math.floor(hitWX), math.floor(hitWY)
        local litR, litG, litB = sampleLight(light, vx0, vy0, hitWX - vx0, hitWY - vy0)

        if playerLight.active then
            local dx = hitWX - (cx + 1)
            local dy = hitWY - (cy + 1)
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < playerLight.radius then
                local strength = (1 - dist / playerLight.radius) ^ playerLight.falloff
                litR = math.min(1.0, litR + playerLight.color[1] * strength)
                litG = math.min(1.0, litG + playerLight.color[2] * strength)
                litB = math.min(1.0, litB + playerLight.color[3] * strength)
            end
        end

        -- Darken Y-facing walls for dynamic corner shadows (once -- this
        -- feeds every branch below, so none of them reapply it)
        if side == 1 then
            litR, litG, litB = litR * 0.76, litG * 0.76, litB * 0.76
        end

        local fogAlpha = calcFogAlpha(perpWallDist, fog)

        -- Walls draw ON TOP of the already-opaque floor/ceiling (which
        -- cover the full screen). Alpha-blending the wall texture directly
        -- would reveal the floor/ceiling behind it on screen -- wrong, a
        -- wall should fade into FOG, not into whatever 2D pixel happens to
        -- sit behind it in draw order. So each wall column repaints the
        -- fog layer (flat color + panorama) for just its own 1px-wide
        -- strip before the texture, using the same continuous sampling as
        -- the full-screen background draw -- the panorama lines up exactly
        -- with what's visible through the floor/ceiling.
        drawFogLayers(fog, x, drawStart, 1, drawEnd - drawStart)

        if atlas then
            local originX, originY
            local material = atlas.tiles[materialLookup[mapX .. "," .. mapY] or ""]
            local featureOverlay = nil

            if material and material.role == "wall_feature" then
                featureOverlay = material
                material = nil -- fall through to draw base wall underneath feature
            end

            if material and material.atlas then
                originY = material.atlas[1] * ATLAS_TILE
                originX = material.atlas[2] * ATLAS_TILE
            elseif doorLookup[mapX .. "," .. mapY] then
                originX = doorVariant(mapX, mapY) * ATLAS_TILE
                originY = (atlas.doorRow or 2) * ATLAS_TILE
            elseif grid[mapY] and grid[mapY][mapX] == "o" then
                -- Structural opening: no dedicated atlas row yet (§3's
                -- weighted/adjacency variant resolution is deferred), so it
                -- borrows the door row as a stand-in arch/gate frame.
                originX = doorVariant(mapX, mapY) * ATLAS_TILE
                originY = (atlas.doorRow or 2) * ATLAS_TILE
            else
                local baseWall = (atlas.manifest and atlas.manifest.base and atlas.manifest.base.walls and atlas.manifest.base.walls[1])
                if baseWall and baseWall.middle then
                    originX = baseWall.middle[2] * ATLAS_TILE
                    originY = baseWall.middle[1] * ATLAS_TILE
                else
                    local variant = wallVariant(mapX, mapY, math.max(1, atlas.wallVariants))
                    originX = (variant % ATLAS_WALL_COLS) * ATLAS_TILE
                    originY = (atlas.wallRows and atlas.wallRows[math.floor(variant / ATLAS_WALL_COLS) + 1] or 1) * ATLAS_TILE
                end
            end

            -- Composite tile layers (base wall + edge autotiling + wall fixture overlay)
            -- into a unified 64x64 canvas texture before applying lighting & fog.
            local hasLeftEdge = (side == 0 and grid[mapY - 1] and grid[mapY - 1][mapX] == ".") or (side == 1 and grid[mapY] and grid[mapY][mapX - 1] == ".")
            local hasRightEdge = (side == 0 and grid[mapY + 1] and grid[mapY + 1][mapX] == ".") or (side == 1 and grid[mapY] and grid[mapY][mapX + 1] == ".")

            local leftEdgeSpec = hasLeftEdge and (atlas.manifest and atlas.manifest.base and atlas.manifest.base.walls and atlas.manifest.base.walls[1] and atlas.manifest.base.walls[1].leftEdge) or nil
            local rightEdgeSpec = hasRightEdge and (atlas.manifest and atlas.manifest.base and atlas.manifest.base.walls and atlas.manifest.base.walls[1] and atlas.manifest.base.walls[1].rightEdge) or nil

            if not leftEdgeSpec and not rightEdgeSpec and not featureOverlay then
                sliceQuad:setViewport(originX + texX, originY, 1, ATLAS_TILE, atlas.w, atlas.h)
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(litR, litG, litB, fogAlpha)
                love.graphics.draw(atlas.img, sliceQuad, x, drawStart, 0, 1, lineHeight / ATLAS_TILE)
            else
                local compositeCanvas = getCompositeTileCanvas(atlas, originX, originY, leftEdgeSpec, rightEdgeSpec, featureOverlay)
                sliceQuad:setViewport(texX, 0, 1, ATLAS_TILE, ATLAS_TILE, ATLAS_TILE)
                love.graphics.setBlendMode("alpha")
                love.graphics.setColor(litR, litG, litB, fogAlpha)
                love.graphics.draw(compositeCanvas, sliceQuad, x, drawStart, 0, 1, lineHeight / ATLAS_TILE)
            end
        else
            -- Retro flat-shaded colors if tileset is missing
            local r = (side == 0) and 0.4 or 0.3
            local g = (side == 0) and 0.45 or 0.35
            local b = (side == 0) and 0.55 or 0.45
            love.graphics.setColor(r * litR, g * litG, b * litB, fogAlpha)
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
            local spriteHeight = math.abs(math.floor(170.6667 / transformY))
            local spriteWidth = spriteHeight
            
            local drawStartY = math.floor(70 - spriteHeight / 2)
            local drawStartX = math.floor(spriteScreenX - spriteWidth / 2)

            -- NOT the same fix as walls: sprites are billboards with a
            -- transparent background (the source PNG's own alpha cuts out
            -- the silhouette), so painting an opaque fog rectangle behind
            -- the whole stripe -- like walls need -- would show a solid
            -- fog-colored box around every sprite instead of true
            -- transparency. What's already on the canvas behind a sprite's
            -- transparent pixels is the correct thing to show: the zBuffer
            -- test above already skips drawing this pixel at all when a
            -- nearer wall occludes it, so whatever's underneath is exactly
            -- the right background, not a draw-order artifact. Plain alpha
            -- fade is correct here.
            local fogAlpha = calcFogAlpha(transformY, fog)

            for stripeX = drawStartX, drawStartX + spriteWidth - 1 do
                if stripeX >= 0 and stripeX < 256 then
                    if transformY < (zBuffer[stripeX + 1] or 0) then
                        local clipY = math.max(0, drawStartY)
                        local clipH = math.min(144, drawStartY + spriteHeight) - clipY

                        if clipH > 0 then
                            love.graphics.setScissor(stripeX, clipY, 1, clipH)

                            local sx, sy = s.x + 0.5, s.y + 0.5
                            local svx0, svy0 = math.floor(sx), math.floor(sy)
                            local sLitR, sLitG, sLitB = sampleLight(light, svx0, svy0, sx - svx0, sy - svy0)
                            if playerLight.active then
                                local dx = sx - (cx + 1)
                                local dy = sy - (cy + 1)
                                local dist = math.sqrt(dx * dx + dy * dy)
                                if dist < playerLight.radius then
                                    local strength = (1 - dist / playerLight.radius) ^ playerLight.falloff
                                    sLitR = math.min(1.0, sLitR + playerLight.color[1] * strength)
                                    sLitG = math.min(1.0, sLitG + playerLight.color[2] * strength)
                                    sLitB = math.min(1.0, sLitB + playerLight.color[3] * strength)
                                end
                            end

                            love.graphics.setColor(sLitR, sLitG, sLitB, fogAlpha)

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
