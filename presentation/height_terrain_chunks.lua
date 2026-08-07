local height_terrain_chunks = {}

local NO_TEXTURE = {}

local function checkedChunkSize(chunkSize)
    chunkSize = tonumber(chunkSize)
    assert(chunkSize and chunkSize >= 1 and chunkSize % 1 == 0,
        "height terrain chunk size must be a positive integer")
    return chunkSize
end

function height_terrain_chunks.chunkCoordinate(cellCoordinate, chunkSize)
    chunkSize = checkedChunkSize(chunkSize)
    assert(type(cellCoordinate) == "number",
        "height terrain placement requires numeric cell coordinates")
    return math.floor((cellCoordinate - 1) / chunkSize)
end

local function extendBounds(bucket, placed)
    local bounds = placed.bounds
    if bounds then
        bucket.minX = math.min(bucket.minX, bounds.minX)
        bucket.maxX = math.max(bucket.maxX, bounds.maxX)
        bucket.minY = math.min(bucket.minY, bounds.minY)
        bucket.maxY = math.max(bucket.maxY, bounds.maxY)
        return
    end
    for _, vertex in ipairs(placed.vertices or {}) do
        bucket.minX = math.min(bucket.minX, vertex[1])
        bucket.maxX = math.max(bucket.maxX, vertex[1])
        bucket.minY = math.min(bucket.minY, vertex[2])
        bucket.maxY = math.max(bucket.maxY, vertex[2])
    end
end

-- Aggregate already-compiled world-space height placements into spatially
-- bounded persistent meshes. This intentionally does not weld tile topology:
-- Phase 3 measures the lifecycle/representation win first, while preserving
-- every authored triangle and vertex field exactly. A later stitched-terrain
-- experiment can then isolate topology/hardware clipping as its own variable.
--
-- `compilePlacement` returns the same placed-group representation used by
-- viewport_3d. `meshFactory` owns the LÖVE upload so this planner stays easily
-- unit-testable without a graphics context of its own.
function height_terrain_chunks.build(placements, chunkSize, meshFormat,
        compilePlacement, meshFactory)
    chunkSize = checkedChunkSize(chunkSize)
    assert(type(compilePlacement) == "function",
        "height terrain chunk builder requires compilePlacement")
    assert(type(meshFactory) == "function",
        "height terrain chunk builder requires meshFactory")

    local bucketsByTexture = {}
    local orderedBuckets = {}

    for placementIndex, placement in ipairs(placements or {}) do
        assert(type(placement.cellX) == "number" and type(placement.cellY) == "number",
            "height terrain placement requires cellX/cellY")
        local chunkX = height_terrain_chunks.chunkCoordinate(placement.cellX, chunkSize)
        local chunkY = height_terrain_chunks.chunkCoordinate(placement.cellY, chunkSize)
        local chunkKey = chunkX .. "," .. chunkY
        local placedGroups = compilePlacement(placement) or {}

        for _, placed in ipairs(placedGroups) do
            local textureKey = placed.texture or NO_TEXTURE
            local byChunk = bucketsByTexture[textureKey]
            if not byChunk then
                byChunk = {}
                bucketsByTexture[textureKey] = byChunk
            end
            local bucket = byChunk[chunkKey]
            if not bucket then
                bucket = {
                    chunkX = chunkX, chunkY = chunkY,
                    texture = placed.texture,
                    vertices = {},
                    minX = math.huge, maxX = -math.huge,
                    minY = math.huge, maxY = -math.huge,
                    sourcePlacements = 0,
                    sourceGroups = 0,
                    firstPlacementIndex = placementIndex,
                    lastPlacement = nil,
                }
                byChunk[chunkKey] = bucket
                orderedBuckets[#orderedBuckets + 1] = bucket
            end

            if bucket.lastPlacement ~= placement then
                bucket.sourcePlacements = bucket.sourcePlacements + 1
                bucket.lastPlacement = placement
            end
            bucket.sourceGroups = bucket.sourceGroups + 1
            extendBounds(bucket, placed)
            for _, vertex in ipairs(placed.vertices or {}) do
                bucket.vertices[#bucket.vertices + 1] = vertex
            end
        end
    end

    local chunks = {}
    for _, bucket in ipairs(orderedBuckets) do
        bucket.lastPlacement = nil
        if #bucket.vertices > 0 then
            local mesh = meshFactory(meshFormat, bucket.vertices, bucket.texture)
            chunks[#chunks + 1] = {
                mesh = mesh,
                model = true,
                vertices = bucket.vertices,
                texture = bucket.texture,
                isHeightSurface = true,
                terrainChunk = true,
                terrainChunkSize = chunkSize,
                terrainChunkX = bucket.chunkX,
                terrainChunkY = bucket.chunkY,
                terrainSourcePlacements = bucket.sourcePlacements,
                terrainSourceGroups = bucket.sourceGroups,
                terrainFirstPlacementIndex = bucket.firstPlacementIndex,
                centerX = (bucket.minX + bucket.maxX) * 0.5,
                centerY = (bucket.minY + bucket.maxY) * 0.5,
                centerZ = 0.5,
                bounds = {
                    minX = bucket.minX, maxX = bucket.maxX,
                    minY = bucket.minY, maxY = bucket.maxY,
                },
            }
        end
    end
    return chunks
end

return height_terrain_chunks
