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

-- The identity under which a compiled asset is cached. Source revision is part
-- of it so editing either PNG or the metadata during authoring invalidates the
-- mesh without a restart.
function geometry.compositionKey(assetPath)
    local parts = { assetPath }
    for _, path in ipairs({ schema.paths(assetPath) }) do
        local info = love.filesystem.getInfo(path)
        parts[#parts + 1] = path .. ":" .. tostring(info and info.modtime or 0)
            .. ":" .. tostring(info and info.size or 0)
    end
    return table.concat(parts, "|")
end

function geometry.load(assetPath)
    local key = geometry.compositionKey(assetPath)
    if compiled[key] then return compiled[key] end

    local spec = schema.parse(assetPath)
    local albedo = inspect(spec)

    -- One layer for now: the asset's own field. Composing a surface fixture
    -- onto a base wall adds entries here, which is why sampleField already
    -- takes a stack rather than a single map.
    local layers = { { data = images.data(spec.heightPath), scale = 1, operation = spec.heightOperation } }
    local model = plane.build(spec, layers, function(u, v) return u, v end)

    mesh.finalize(model, {
        [spec.id] = { color = { 1, 1, 1, 1 }, texture = spec.albedoPath },
    }, "")
    model.spec = spec
    model.assetPath = assetPath
    compiled[key] = model
    return model
end

function geometry.forget()
    compiled = {}
    images.forget()
end

return geometry
