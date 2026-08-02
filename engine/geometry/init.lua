-- Image-authored geometry: compile an albedo/height PNG pair plus metadata
-- into the one static-mesh representation the world renderer draws.
--
-- See docs/design/image-authored-geometry.md for the intent, and
-- engine/geometry/schema.lua for the asset contract.
--
-- Two entry points, deliberately separate:
--
--   geometry.check(assetPath)   metadata and pixel validation with no graphics
--                               device, so G1 can reject a broken asset
--   geometry.load(assetPath)    compile and upload, cached by composition key
--
-- The compiler is deterministic: identical inputs produce identical meshes, so
-- a compiled asset is safe to cache and safe for byte-comparing gates.
local schema = require("engine.geometry.schema")
local images = require("engine.geometry.images")
local plane = require("engine.geometry.plane")
local shell = require("engine.geometry.shell")
local radial = require("engine.geometry.radial")
local mesh = require("presentation.mesh")

local geometry = {}

local compiled = {}

-- Warnings are advisory and reported by the validator; they never block a
-- build. Hard problems raise instead, per the project's fail-loud rule.
local function inspect(spec)
    local warnings = {}
    local albedo = images.data(spec.albedoPath)
    local height = images.data(spec.heightPath)
    if not images.dimensionsMatch(albedo, height) then
        error(spec.label .. ": albedo is " .. albedo:getWidth() .. "x" .. albedo:getHeight()
            .. " but height is " .. height:getWidth() .. "x" .. height:getHeight()
            .. "; registration requires identical dimensions", 0)
    end
    if not images.checkGrayscale(height, 0) then
        warnings[#warnings + 1] = spec.label
            .. ": height map is not grayscale; only its red channel is read"
    end
    -- Topology-specific pixel checks belong here rather than at build time, so
    -- geometry.check -- and therefore G1 -- rejects a broken mask without ever
    -- needing a graphics device.
    if spec.topology == "shell" then
        shell.checkMasks(spec, height, spec.meshColumns, spec.meshRows)
        shell.checkSingleComponent(spec, height, spec.meshColumns, spec.meshRows)
        -- Geometry with transparent albedo tears the model apart rather than
        -- merely looking wrong: the shader discards transparent texels, so a
        -- boundary quad interpolating into them punches holes. Coverage is the
        -- HEIGHT alpha's job; the albedo should stay opaque across it.
        if shell.hasTransparentCoverage(spec, albedo, height) then
            warnings[#warnings + 1] = spec.label
                .. ": albedo is transparent inside the coverage mask;"
                .. " covered geometry will be discarded and appear torn"
        end
    end
    -- Mesh density that cannot reproduce the authored field is the most common
    -- cause of "my relief disappeared", so it is worth saying out loud.
    if spec.topology == "plane" then
        if spec.meshColumns * 4 < albedo:getWidth() / 16
            or spec.meshRows * 4 < albedo:getHeight() / 16 then
            warnings[#warnings + 1] = spec.label
                .. ": mesh density is very low for this texture resolution"
        end
        if spec.heightScale == 0 and spec.heightOperation ~= "none" then
            warnings[#warnings + 1] = spec.label
                .. ": heightScale is 0, so this asset carries no geometry"
        end
        -- Same rule the builder enforces, checked here so a cavity that would
        -- break through its own wall is a BUILD failure rather than a hole
        -- someone finds by walking into it.
        if spec.surface == "wall" then
            local layer = { {
                data = height, scale = spec.heightScale, operation = spec.heightOperation,
            } }
            local deepest = math.huge
            for row = 0, spec.sampleRows do
                for column = 0, spec.sampleColumns do
                    local lift = plane.sampleField(layer,
                        column / spec.sampleColumns, row / spec.sampleRows) + spec.offset
                    if lift < deepest then deepest = lift end
                end
            end
            if deepest < -0.5 then
                error(spec.label .. ": displacement reaches "
                    .. string.format("%.4f", deepest)
                    .. " into the wall, which is more than half a cell --"
                    .. " the cavity would break through to the far side."
                    .. " Reduce heightScale or raise 'offset'", 0)
            end
        end
    end
    return albedo, height, warnings
end

-- Validate without compiling. Returns the parsed spec and any warnings; raises
-- on a hard error.
function geometry.check(assetPath)
    local spec = schema.parse(assetPath)
    local _, _, warnings = inspect(spec)
    return spec, warnings
end

-- Bumping this invalidates every cached composition. It belongs in the key for
-- the same reason the source revision does: a compiler change alters the mesh
-- that identical inputs produce.
geometry.COMPILER_VERSION = 1

-- The identity under which a compiled composition is cached, per the design
-- document's cache-key inputs: every layer's source revision, their ORDER, and
-- the compiler version. Source revision is included so editing a PNG or its
-- metadata during authoring invalidates the mesh without a restart.
function geometry.compositionKey(assetPaths)
    if type(assetPaths) == "string" then assetPaths = { assetPaths } end
    local parts = { "v" .. geometry.COMPILER_VERSION,
        require("engine.geometry.quality").key() }
    for index, assetPath in ipairs(assetPaths) do
        parts[#parts + 1] = index .. ":" .. assetPath
        for _, path in ipairs({ schema.paths(assetPath) }) do
            local info = love.filesystem.getInfo(path)
            parts[#parts + 1] = tostring(info and info.modtime or 0)
                .. ":" .. tostring(info and info.size or 0)
        end
    end
    return table.concat(parts, "|")
end

-- Bake the composed albedo. A wall fixture that is conceptually part of its
-- wall must be ONE surface, not a mesh floating over another, so colour is
-- composited before meshing exactly as height is.
--
-- Composited on the CPU, deliberately. The obvious implementation draws the
-- layers into a canvas, but compilation happens lazily during the world draw,
-- and binding a canvas there silently breaks the pass: love.graphics.getCanvas
-- returns the target WITHOUT its depth/stencil attachment, so restoring it
-- leaves the world rendering with no depth buffer. Touching no graphics state
-- also means this works headless, so a validator or a diagnostic can compose
-- without a window.
local function composeAlbedoData(specs)
    local base = images.data(specs[1].albedoPath)
    local width, height = base:getWidth(), base:getHeight()
    local composed = love.image.newImageData(width, height)
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local r, g, b, a = base:getPixel(x, y)
            for index = 2, #specs do
                local sr, sg, sb, sa = images.data(specs[index].albedoPath):getPixel(x, y)
                -- Ordinary source-over: the fixture's alpha is its coverage.
                r = sr * sa + r * (1 - sa)
                g = sg * sa + g * (1 - sa)
                b = sb * sa + b * (1 - sa)
                a = sa + a * (1 - sa)
            end
            composed:setPixel(x, y, r, g, b, a)
        end
    end
    return composed
end

local function composeAlbedo(specs)
    if #specs == 1 then return nil end   -- single layer draws its own texture
    local image = love.graphics.newImage(composeAlbedoData(specs))
    image:setFilter("nearest", "nearest")
    return image
end

-- Compile one or more assets into a single mesh. Passing several composes them:
-- the first is the base surface and the rest are surface fixtures layered onto
-- it, albedo and height together.
function geometry.load(assetPaths)
    if type(assetPaths) == "string" then assetPaths = { assetPaths } end
    local key = geometry.compositionKey(assetPaths)
    if compiled[key] then return compiled[key] end

    local specs = {}
    for index, assetPath in ipairs(assetPaths) do
        local spec = schema.parse(assetPath)
        inspect(spec)
        if index > 1 then
            if spec.topology ~= "plane" then
                error(spec.label .. ": only plane assets compose onto a surface", 0)
            end
            if spec.role ~= "surfaceFixture" then
                error(spec.label .. ": only a surfaceFixture composes onto a surface", 0)
            end
            if spec.surface ~= specs[1].surface then
                error(spec.label .. ": composes onto a '" .. specs[1].surface
                    .. "' surface but declares '" .. spec.surface .. "'", 0)
            end
            -- Registration is the hard invariant: layers that disagree on
            -- dimensions cannot keep albedo and height aligned.
            local baseAlbedo = images.data(specs[1].albedoPath)
            local layerAlbedo = images.data(spec.albedoPath)
            if not images.dimensionsMatch(baseAlbedo, layerAlbedo) then
                error(spec.label .. ": composes onto a surface of different dimensions;"
                    .. " registration requires all layers to agree", 0)
            end
        end
        specs[index] = spec
    end

    local spec = specs[1]
    local model
    if spec.topology == "shell" then
        model = shell.build(spec, images.data(spec.heightPath))
    elseif spec.topology == "radial" then
        model = radial.build(spec, images.data(spec.heightPath))
    else
        local layers = {}
        for index, layer in ipairs(specs) do
            layers[index] = {
                data = images.data(layer.heightPath),
                scale = layer.heightScale,
                operation = layer.heightOperation,
            }
        end
        model = plane.build(spec, layers, function(u, v) return u, v end)
    end

    local composed = spec.topology == "plane" and composeAlbedo(specs) or nil
    mesh.finalize(model, {
        [spec.id] = composed and { color = { 1, 1, 1, 1 }, image = composed }
            or { color = { 1, 1, 1, 1 }, texture = spec.albedoPath },
    }, "")
    model.spec = spec
    model.specs = specs
    model.assetPath = assetPaths[1]
    model.assetPaths = assetPaths
    compiled[key] = model
    return model
end

-- The design document's most important diagnostic: the exact albedo and the
-- exact heightfield being handed to the builder, side by side. Seeing both at
-- once localizes a problem to source art, registration, composition, meshing
-- or rendering, which no single view does.
--
-- Sampled at texture resolution rather than mesh resolution on purpose: this
-- shows what was COMPOSED, before the mesh grid decides what survives.
function geometry.debugFields(assetPaths)
    if type(assetPaths) == "string" then assetPaths = { assetPaths } end
    local specs = {}
    for index, assetPath in ipairs(assetPaths) do
        specs[index] = schema.parse(assetPath)
    end
    local base = images.data(specs[1].albedoPath)
    local width, height = base:getWidth(), base:getHeight()

    local layers, totalScale = {}, 0
    for index, spec in ipairs(specs) do
        layers[index] = {
            data = images.data(spec.heightPath),
            scale = spec.heightScale or 1,
            operation = spec.heightOperation,
        }
        totalScale = totalScale + math.abs(spec.heightScale or 1)
    end

    -- Composed height, remapped so mid-grey is the neutral plane again. The
    -- normalisation is by the summed authored scale, so the picture shows
    -- relative depth rather than clipping whatever exceeds one asset's range.
    -- setPixel rather than mapPixel: the callback would sample OTHER ImageData
    -- while this one is locked for mapping, which is not a thing to rely on.
    local heightField = love.image.newImageData(width, height)
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local value = plane.sampleField(layers, x / (width - 1), y / (height - 1))
            local grey = 0.5 + (totalScale > 0 and (value / totalScale) * 0.5 or 0)
            grey = math.max(0, math.min(1, grey))
            heightField:setPixel(x, y, grey, grey, grey, 1)
        end
    end

    -- Composed albedo: the exact pixels the mesh is textured by.
    local albedoField = #specs > 1 and composeAlbedoData(specs) or base
    return albedoField, heightField
end

function geometry.forget()
    compiled = {}
    images.forget()
end

return geometry
