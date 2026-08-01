-- Shared spatial predicate vocabulary for procedural fixture placement.
-- Coordinates are 1-based internally; authored zone coordinates are 0-based.
local predicates = {}

local CARDINAL = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local EIGHT_WAY = {
    { 0, -1 }, { 1, -1 }, { 1, 0 }, { 1, 1 },
    { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 },
}

local function key(x, y) return x .. "," .. y end

local function addTag(index, positions, x, y, tag)
    if type(tag) ~= "string" or tag == "" then return end
    local cell = index[key(x, y)]
    if not cell then cell = {} index[key(x, y)] = cell end
    if not cell[tag] then
        cell[tag] = true
        positions[tag] = positions[tag] or {}
        positions[tag][#positions[tag] + 1] = { x = x, y = y }
    end
end

function predicates.buildZoneIndex(mapData, generatedZones)
    local index, positions = {}, {}
    for _, zone in ipairs((mapData and mapData.zones) or {}) do
        local tags = zone.tags or { zone.id }
        if zone.cells then
            for _, cell in ipairs(zone.cells) do
                for _, tag in ipairs(tags) do addTag(index, positions, cell.x + 1, cell.y + 1, tag) end
            end
        else
            for y = zone.y + 1, zone.y + zone.height do
                for x = zone.x + 1, zone.x + zone.width do
                    for _, tag in ipairs(tags) do addTag(index, positions, x, y, tag) end
                end
            end
        end
    end
    for _, cell in ipairs(generatedZones or {}) do
        for _, tag in ipairs(cell.tags or {}) do
            addTag(index, positions, cell.x + 1, cell.y + 1, tag)
        end
    end
    return index, positions
end

local function tileMatches(grid, x, y, wanted)
    local value = grid[y] and grid[y][x]
    if value == nil then return false end
    if wanted == "wall" then return value == "#" end
    if wanted == "floor" then return value ~= "#" end
    if wanted == "opening" then return value == "o" end
    error("unknown fixture predicate tile class '" .. tostring(wanted) .. "'", 0)
end

local function targetPositions(spec, ctx)
    if spec.zone then return ctx.zonePositions[spec.zone] or {} end
    if spec.feature then return ctx.featurePositions[spec.feature] or {} end
    error("distance predicate requires exactly one of zone or feature", 0)
end

local function matches(where, ctx, x, y)
    if where.all then
        for _, child in ipairs(where.all) do if not matches(child, ctx, x, y) then return false end end
        return true
    elseif where.any then
        for _, child in ipairs(where.any) do if matches(child, ctx, x, y) then return true end end
        return false
    elseif where["not"] then
        return not matches(where["not"], ctx, x, y)
    elseif where.zone then
        local tags = ctx.zoneIndex[key(x, y)]
        return tags and tags[where.zone] or false
    elseif where.adjacent then
        local spec = type(where.adjacent) == "string"
            and { tile = where.adjacent } or where.adjacent
        local offsets = spec.diagonal and EIGHT_WAY or CARDINAL
        for _, offset in ipairs(offsets) do
            local nx, ny = x + offset[1], y + offset[2]
            if spec.tile and tileMatches(ctx.grid, nx, ny, spec.tile) then return true end
            if spec.zone then
                local tags = ctx.zoneIndex[key(nx, ny)]
                if tags and tags[spec.zone] then return true end
            end
            if spec.feature and ctx.featureCells[key(nx, ny)] == spec.feature then return true end
        end
        return false
    elseif where.distance then
        local spec = where.distance
        local nearest = math.huge
        for _, target in ipairs(targetPositions(spec, ctx)) do
            nearest = math.min(nearest, math.abs(target.x - x) + math.abs(target.y - y))
        end
        return nearest >= (spec.min or 0) and nearest <= (spec.max or math.huge)
    end
    error("unknown fixture predicate operator", 0)
end

function predicates.matches(where, ctx, x, y)
    return where == nil or matches(where, ctx, x, y)
end

function predicates.newContext(grid, mapData, generatedZones)
    local zoneIndex, zonePositions = predicates.buildZoneIndex(mapData, generatedZones)
    return {
        grid = grid,
        zoneIndex = zoneIndex,
        zonePositions = zonePositions,
        featureCells = {},
        featurePositions = {},
    }
end

function predicates.addFeature(ctx, x, y, id)
    ctx.featureCells[key(x, y)] = id
    ctx.featurePositions[id] = ctx.featurePositions[id] or {}
    ctx.featurePositions[id][#ctx.featurePositions[id] + 1] = { x = x, y = y }
end

return predicates
