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
local FOG_DEFAULTS = { color = { 0, 0, 0 }, density = 0.35, minFactor = 0.12, panorama = nil }
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

    return {
        color     = fog.color or FOG_DEFAULTS.color,
        density   = fog.density or FOG_DEFAULTS.density,
        minFactor = fog.minFactor or FOG_DEFAULTS.minFactor,
        panorama  = (fog.panorama and #fog.panorama > 0) and fog.panorama or nil,
    }, true
end

-- Panorama images (assets/panorama/<name>.png), lazily loaded/cached like
-- tileset atlases. Repeat-wrapped so a screen-sized viewport quad can be
-- offset over time for a scrolling-mist effect without a shader.
local panoramaCache = {}
local function getPanoramaImage(name)
    if panoramaCache[name] ~= nil then return panoramaCache[name] or nil end
    local path = "assets/panorama/" .. name .. ".png"
    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")
        img:setWrap("repeat", "repeat")
        panoramaCache[name] = img
        return img
    end
    panoramaCache[name] = false
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
        local t = love.timer.getTime()
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
local function loadAtlasManifest(name)
    local path = "assets/tilesets/" .. name .. ".json"
    if not love.filesystem.getInfo(path) then return nil end
    local ok, decoded = pcall(function()
        return require("data.json").decode(love.filesystem.read(path))
    end)
    if ok and type(decoded) == "table" then return decoded end
    return nil
end
local function getAtlas(name)
    if atlasCache[name] ~= nil then
        return atlasCache[name] or nil
    end
    local path = "assets/tilesets/" .. name .. ".png"
    if love.filesystem.getInfo(path) then
        local img = love.graphics.newImage(path)
        img:setFilter("nearest", "nearest")
        local loadedManifest = loadAtlasManifest(name)
        local manifest = loadedManifest or {}
        -- No sidecar at all = the built-in sky/wall/door/floor default. A
        -- present-but-partial manifest (e.g. dungeon_001's no-skyRow) is
        -- taken at face value instead -- its omissions are intentional.
        local wallRows = manifest.wallRows or (not loadedManifest and { 1 }) or nil
        local entry = {
            img = img, w = img:getWidth(), h = img:getHeight(),
            wallRows = wallRows,
            wallVariants = wallRows and (#wallRows * ATLAS_WALL_COLS) or 0,
            doorRow = manifest.doorRow or (not loadedManifest and 2) or nil,
            skyRow = manifest.skyRow or (not loadedManifest and 0) or nil,
            floorRow = manifest.floorRow or (not loadedManifest and 3) or nil,
            ceilingRow = manifest.ceilingRow, -- nil = solid ceiling stays a flat gradient
        }
        atlasCache[name] = entry
        return entry
    end
    atlasCache[name] = false
    return nil
end

local sliceQuad = nil        -- 1px-wide column slice, reused for walls and doors
local skyQuad = nil          -- reused for the sky strip, viewport recomputed per atlas
local spriteSliceQuad = nil

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
-- wall projection constants exactly (center row 70, scale 140 -- see
-- `lineHeight = floor(140 / perpWallDist)` in the wall loop) so the floor
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
    uniform vec2 mapSize;   // (mapW, mapH), light texture covers (mapW+1)x(mapH+1) vertices
    // Fog: rather than mixing toward a fog color in-shader, output alpha =
    // fogAlpha and let ordinary blending reveal whatever drawFogBackground()
    // already drew behind this (flat fill or scrolling panorama) -- see
    // docs/design/fog-presets-and-panorama.md.
    uniform float fogDensity;
    uniform float fogMinFactor;

    vec2 cellVariantOrigin(vec2 cell) {
        float h = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
        float col = floor(h * 4.0);
        return vec2(col, targetRow);
    }

    vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
        float dy = screen_coords.y - 70.0;
        if (abs(dy) < 0.0001) dy = 0.0001;
        float rowDist = 70.0 / abs(dy);

        float cameraX = 2.0 * screen_coords.x / 256.0 - 1.0;
        vec2 rayDir = camDir + camPlane * cameraX;
        vec2 worldPos = camPos + rowDist * rayDir;

        vec2 cell = floor(worldPos);
        vec2 fracPos = fract(worldPos);
        vec2 origin = cellVariantOrigin(cell);

        vec2 uv = vec2((origin.x + fracPos.x) * 64.0 / atlasW, (origin.y + fracPos.y) * 64.0 / atlasH);
        vec4 texColor = Texel(tex, uv);

        // Fog alpha: 1.0 at camera, ramps toward fogMinFactor at distance
        float fogAlpha = max(fogMinFactor, 1.0 / (1.0 + rowDist * fogDensity));
        vec2 lightUV = (worldPos - vec2(1.0)) / mapSize;
        vec3 lightColor = Texel(lightTex, lightUV).rgb;
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
    local light = mapData and mapData.light
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
local function drawShadedPlane(atlas, atlasRow, y0, rectH, cx, cy, dirX, dirY, planeX, planeY, lightTex, lightW, lightH, fog)
    local shader = ensureFloorCeilShader()
    if not shader then return false end

    love.graphics.setShader(shader)
    shader:send("camPos", { cx + 1, cy + 1 })
    shader:send("camDir", { dirX, dirY })
    shader:send("camPlane", { planeX, planeY })
    shader:send("atlasW", atlas.w)
    shader:send("atlasH", atlas.h)
    shader:send("targetRow", atlasRow)
    shader:send("fogDensity", fog.density)
    shader:send("fogMinFactor", fog.minFactor)

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
end

-- Resolves which atlas to draw walls/doors/sky from this frame: the map's
-- own `tileset` if it names one, else DEFAULT_TILESET. Returns nil if that
-- atlas file doesn't exist (draw() falls back to flat-shaded lines).
local function resolveTileset(mapData)
    local name = (mapData and mapData.tileset) or DEFAULT_TILESET
    return getAtlas(name)
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
    -- direction, 60-degree FOV) -- computed here (rather than just before
    -- the wall loop, where this used to live) because the floor/ceiling
    -- shader below needs it too.
    local dirX = math.cos(cAngle)
    local dirY = math.sin(cAngle)
    local fovHalfTan = math.tan(math.pi / 6)
    local planeX = -dirY * fovHalfTan
    local planeY = dirX * fovHalfTan

    local mapData = session.currentMapData

    -- Resolved fog config (preset-aware) -- black fog with no panorama IS
    -- the plain darken-with-distance behavior, so there's exactly one
    -- shading model: draw the fog background, then everything else at
    -- alpha = fogAlpha. See docs/design/fog-presets-and-panorama.md.
    local fog = getFogConfig(session, mapData)

    -- ── 2. Draw Floor & Ceiling ───────────────────────────────────────────────
    local halfH = ui.toPx(9) -- exactly 9 tiles (72px)
    local screenWpx = ui.toPx(ui.screenWidthTiles)
    local light = mapData and mapData.light

    -- Player-cell vertex light, used to tint the gradient FALLBACK as a
    -- single color (the shader path samples the light texture per-pixel
    -- instead). See docs/design/raycaster-tileset-lighting.md.
    local px0, py0 = math.floor(cx + 1), math.floor(cy + 1)
    local ambR, ambG, ambB = sampleLight(light, px0, py0, (cx + 1) - px0, (cy + 1) - py0)

    local atlas = resolveTileset(mapData)
    local lightTex, lightW, lightH = getLightTexture(mapData)

    -- Fog background FIRST: everything drawn after this (shaded floor/
    -- ceiling, walls, sprites) uses alpha = fogAlpha and blends against it.
    -- See docs/design/fog-presets-and-panorama.md.
    drawFogBackground(fog, screenWpx, halfH * 2)

    if mapData and mapData.ceilingStyle == "sky" and atlas and atlas.skyRow then
        skyQuad:setViewport(0, atlas.skyRow * ATLAS_TILE, ATLAS_SKY_COLS * ATLAS_TILE, ATLAS_TILE, atlas.w, atlas.h)
        -- Sky is daylight, not torchlight -- deliberately NOT tinted by the
        -- vertex light grid (that models local/indoor light sources).
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(atlas.img, skyQuad, 0, 0, 0,
            screenWpx / (ATLAS_SKY_COLS * ATLAS_TILE), halfH / ATLAS_TILE)
    elseif atlas and atlas.ceilingRow
        and drawShadedPlane(atlas, atlas.ceilingRow, 0, halfH, cx, cy, dirX, dirY, planeX, planeY, lightTex, lightW, lightH, fog) then
        -- shaded plane drawn; nothing else to do
    else
        -- Ceiling gradient: Moody dark purple/indigo fade
        drawVerticalGradient(0, 0, screenWpx, halfH,
            {0.09 * ambR, 0.06 * ambG, 0.14 * ambB},
            {0.02 * ambR, 0.01 * ambG, 0.04 * ambB})
    end

    if not (atlas and atlas.floorRow
        and drawShadedPlane(atlas, atlas.floorRow, halfH, halfH, cx, cy, dirX, dirY, planeX, planeY, lightTex, lightW, lightH, fog)) then
        -- Floor gradient: Cold dark stone grey fade
        drawVerticalGradient(0, halfH, screenWpx, halfH,
            {0.03 * ambR, 0.03 * ambG, 0.03 * ambB},
            {0.14 * ambR, 0.12 * ambG, 0.10 * ambB})
    end

    local doorLookup = buildDoorLookup(session)

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

        -- Darken Y-facing walls for dynamic corner shadows (once -- this
        -- feeds every branch below, so none of them reapply it)
        if side == 1 then
            litR, litG, litB = litR * 0.76, litG * 0.76, litB * 0.76
        end

        local fogAlpha = math.max(fog.minFactor, 1.0 / (1.0 + perpWallDist * fog.density))

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
            if doorLookup[mapX .. "," .. mapY] then
                originX = doorVariant(mapX, mapY) * ATLAS_TILE
                originY = atlas.doorRow * ATLAS_TILE
            else
                local variant = wallVariant(mapX, mapY, atlas.wallVariants)
                originX = (variant % ATLAS_WALL_COLS) * ATLAS_TILE
                originY = atlas.wallRows[math.floor(variant / ATLAS_WALL_COLS) + 1] * ATLAS_TILE
            end
            sliceQuad:setViewport(originX + texX, originY, 1, ATLAS_TILE, atlas.w, atlas.h)
            love.graphics.setColor(litR, litG, litB, fogAlpha)
            love.graphics.draw(atlas.img, sliceQuad, x, drawStart, 0, 1, lineHeight / ATLAS_TILE)
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
            local spriteHeight = math.abs(math.floor(140 / transformY))
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
            local fogAlpha = math.max(fog.minFactor, 1.0 / (1.0 + transformY * fog.density))

            for stripeX = drawStartX, drawStartX + spriteWidth - 1 do
                if stripeX >= 0 and stripeX < 256 then
                    if transformY < (zBuffer[stripeX + 1] or 0) then
                        local clipY = math.max(0, drawStartY)
                        local clipH = math.min(144, drawStartY + spriteHeight) - clipY

                        if clipH > 0 then
                            love.graphics.setScissor(stripeX, clipY, 1, clipH)
                            love.graphics.setColor(1, 1, 1, fogAlpha)

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
