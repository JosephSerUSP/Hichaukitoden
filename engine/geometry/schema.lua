-- Metadata contract for image-authored geometry assets.
--
-- An asset is a directory holding albedo.png, height.png and asset.json. This
-- module parses and checks asset.json alone: it needs no graphics device, so
-- G1 can reject a malformed asset without compiling it. Image-level checks
-- that need pixels (dimension agreement, mask equality) live in images.lua.
--
-- Every closed vocabulary here is declared in data/engine.json rather than
-- hardcoded, so the validator and the editor read the same list.
local json = require("data.json")

local schema = {}

local function registry()
    local loader = require("data.loader")
    local geometry = loader.engine and loader.engine.geometry
    if not geometry then error("engine.json is missing the geometry registry", 0) end
    return geometry
end

local function oneOf(value, allowed, field, label)
    for _, candidate in ipairs(allowed) do
        if candidate.id == value then return candidate end
    end
    local names = {}
    for _, candidate in ipairs(allowed) do names[#names + 1] = candidate.id end
    error(label .. ": unknown " .. field .. " '" .. tostring(value)
        .. "' (expected one of: " .. table.concat(names, ", ") .. ")", 0)
end

local function number(meta, field, label, default, min, max)
    local value = meta[field]
    if value == nil then
        if default == nil then error(label .. ": missing required '" .. field .. "'", 0) end
        return default
    end
    if type(value) ~= "number" or value ~= value then
        error(label .. ": '" .. field .. "' must be a number", 0)
    end
    if min and value < min then
        error(label .. ": '" .. field .. "' must be at least " .. min, 0)
    end
    if max and value > max then
        error(label .. ": '" .. field .. "' must be at most " .. max, 0)
    end
    return value
end

local function integer(meta, field, label, default, min, max)
    local value = number(meta, field, label, default, min, max)
    if value ~= math.floor(value) then
        error(label .. ": '" .. field .. "' must be a whole number", 0)
    end
    return value
end

schema.ALBEDO = "albedo.png"
schema.HEIGHT = "height.png"
schema.METADATA = "asset.json"

function schema.paths(assetPath)
    local base = assetPath:gsub("/+$", "")
    return base .. "/" .. schema.ALBEDO,
        base .. "/" .. schema.HEIGHT,
        base .. "/" .. schema.METADATA
end

-- Parse and fully check one asset's metadata. Returns a normalized table with
-- every optional field resolved, so no consumer repeats a default.
function schema.parse(assetPath)
    local albedoPath, heightPath, metaPath = schema.paths(assetPath)
    local label = "geometry asset '" .. assetPath .. "'"
    local text = love.filesystem.read(metaPath)
    if not text then error(label .. ": missing " .. schema.METADATA, 0) end
    local ok, meta = pcall(json.decode, text)
    if not ok or type(meta) ~= "table" then
        error(label .. ": " .. schema.METADATA .. " is not valid JSON", 0)
    end
    if not love.filesystem.getInfo(albedoPath) then
        error(label .. ": missing " .. schema.ALBEDO, 0)
    end
    if not love.filesystem.getInfo(heightPath) then
        error(label .. ": missing " .. schema.HEIGHT, 0)
    end

    local registered = registry()
    if type(meta.id) ~= "string" or meta.id == "" then
        error(label .. ": missing required 'id'", 0)
    end
    local topology = oneOf(meta.topology, registered.topologies, "topology", label)
    local role = oneOf(meta.role, registered.roles, "role", label)

    local parsed = {
        id = meta.id, assetPath = assetPath, label = label,
        albedoPath = albedoPath, heightPath = heightPath,
        topology = topology.id, role = role.id,
        blocksMovement = meta.blocksMovement == true,
    }

    if meta.blocksMovement ~= nil and role.id ~= "objectFixture" then
        error(label .. ": 'blocksMovement' applies only to an objectFixture", 0)
    end

    if topology.id == "plane" then
        parsed.surface = oneOf(meta.surface, registered.planeSurfaces, "surface", label).id
        parsed.heightOperation =
            oneOf(meta.heightOperation, registered.heightOperations, "heightOperation", label).id
        -- Displacement is expressed in map cells, so a wall relief and a floor
        -- relief are authored against the same physical scale.
        parsed.heightScale = number(meta, "heightScale", label, nil, 0, 1)
        parsed.meshColumns = integer(meta, "meshColumns", label, nil, 1, 64)
        parsed.meshRows = integer(meta, "meshRows", label, nil, 1, 64)
        -- Sampling resolution is independent of the triangle budget: the field
        -- is meshed densely and then decimated, so a joint or a neck narrower
        -- than a budget cell still reaches the decimator instead of being
        -- averaged out of existence. Capped because this runs at load.
        parsed.sampleColumns = integer(meta, "sampleColumns", label,
            math.min(48, parsed.meshColumns * 4), 1, 96)
        parsed.sampleRows = integer(meta, "sampleRows", label,
            math.min(48, parsed.meshRows * 4), 1, 96)
        -- Stand-off keeps a relief from z-fighting the structural surface it
        -- sits on; it is not part of the authored height field.
        parsed.offset = number(meta, "offset", label, 0.004, 0, 0.25)
    elseif topology.id == "shell" then
        parsed.surfaceMode =
            oneOf(meta.surfaceMode, registered.shellModes, "surfaceMode", label).id
        parsed.layout = oneOf(meta.layout or "single", registered.layouts, "layout", label).id
        parsed.edgeMode = oneOf(meta.edgeMode or "stitch", registered.edgeModes, "edgeMode", label).id
        parsed.edgeColor =
            oneOf(meta.edgeColor or "darkenedBlend", registered.edgeColors, "edgeColor", label).id
        parsed.depthScale = number(meta, "depthScale", label, nil, 0, 2)
        parsed.meshColumns = integer(meta, "meshColumns", label, nil, 1, 64)
        parsed.meshRows = integer(meta, "meshRows", label, nil, 1, 64)
        parsed.pinchWidth = number(meta, "pinchWidth", label, 2, 0, 16)
        -- Dense sampling then decimation, same as plane: at the budget
        -- resolution a silhouette narrower than two cells simply disappears.
        parsed.sampleColumns = integer(meta, "sampleColumns", label,
            math.min(56, parsed.meshColumns * 4), 1, 96)
        parsed.sampleRows = integer(meta, "sampleRows", label,
            math.min(56, parsed.meshRows * 4), 1, 96)
        -- Painting front and back independently is a separate decision from
        -- deriving the rear DEPTH from the front, so an asset may mirror its
        -- geometry while still carrying two painted faces.
        parsed.albedoMode = meta.albedoMode == "frontBack" and "frontBack" or "single"
        parsed.requireMatchingMasks = meta.requireMatchingMasks ~= false
        local symmetry = meta.symmetry or {}
        if type(symmetry) ~= "table" then
            error(label .. ": 'symmetry' must be an object", 0)
        end
        -- Image-plane symmetry and front/back reflection are named separately
        -- on purpose; conflating them removes the ability to paint asymmetry.
        parsed.symmetry = {
            imageX = symmetry.imageX == true,
            imageY = symmetry.imageY == true,
            frontBack = symmetry.frontBack == true,
        }
        if parsed.surfaceMode == "frontBack" and parsed.layout == "single" then
            error(label .. ": surfaceMode 'frontBack' needs a front/back atlas layout", 0)
        end
        if parsed.albedoMode == "frontBack" and parsed.layout == "single" then
            error(label .. ": albedoMode 'frontBack' needs a front/back atlas layout", 0)
        end
    elseif topology.id == "radial" then
        parsed.baseRadius = number(meta, "baseRadius", label, nil, 0, 0.5)
        parsed.height = number(meta, "height", label, nil, 0, 4)
        parsed.radiusScale = number(meta, "heightScale", label, nil, 0, 0.5)
        parsed.angularSegments = integer(meta, "angularSegments", label, nil, 3, 64)
        parsed.verticalSegments = integer(meta, "verticalSegments", label, nil, 1, 64)
        parsed.capTop = meta.capTop == true
        parsed.capBottom = meta.capBottom == true
        -- Signed radius reads 128 as the base radius so a profile can cut
        -- inward as well as bulge out; unsigned only ever adds.
        parsed.signedRadius = meta.signedRadius == true
        local symmetry = meta.symmetry or {}
        if type(symmetry) ~= "table" then
            error(label .. ": 'symmetry' must be an object", 0)
        end
        parsed.symmetry = { angular = symmetry.angular == true }
        if parsed.baseRadius + parsed.radiusScale > 0.5 then
            -- A radial fixture wider than its cell pokes through the walls
            -- around it, and nothing downstream would report that.
            error(label .. ": baseRadius plus heightScale exceeds half a cell,"
                .. " so the object would intersect its own walls", 0)
        end
    else
        error(label .. ": topology '" .. topology.id .. "' is declared but not yet compiled", 0)
    end

    return parsed
end

return schema
