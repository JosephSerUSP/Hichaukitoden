-- Immutable sparse tileset deltas for per-map/per-floor presentation.
-- Pool arrays merge by id; ordinary arrays (atlas coordinates, colors) replace.
local resolver = {}

local cache = setmetatable({}, { __mode = "k" })
local POOLS = { "features", "doors", "fixturePrefabs" }
local BASE_POOLS = { "walls", "floors", "ceilings", "skies" }

local function isArray(value)
    return type(value) == "table" and #value > 0
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = copy(v) end
    return out
end

local function mergeObject(base, delta)
    if type(delta) ~= "table" then return delta end
    if isArray(delta) then return copy(delta) end
    local out = type(base) == "table" and copy(base) or {}
    for key, value in pairs(delta) do
        if key ~= "remove" then
            if type(value) == "table" and not isArray(value) then
                out[key] = mergeObject(out[key], value)
            else
                out[key] = copy(value)
            end
        end
    end
    return out
end

local function mergePool(base, delta)
    local out, index = copy(base or {}), {}
    for i, entry in ipairs(out) do index[entry.id] = i end
    for _, patch in ipairs(delta or {}) do
        local at = index[patch.id]
        if patch.remove == true then
            if at then
                table.remove(out, at)
                index = {}
                for i, entry in ipairs(out) do index[entry.id] = i end
            end
        elseif at then
            out[at] = mergeObject(out[at], patch)
        else
            out[#out + 1] = mergeObject(nil, patch)
            index[patch.id] = #out
        end
    end
    return out
end

function resolver.resolve(loader, mapData)
    local id = (mapData and mapData.tileset) or "dungeon_default"
    local base = loader and loader.getTileset and loader.getTileset(id)
    if not base then return nil, id end
    local delta = mapData and mapData.tilesetOverride
    if type(delta) ~= "table" or next(delta) == nil then return base, id end

    local cached = cache[mapData]
    if cached and cached.base == base and cached.delta == delta then
        return cached.value, cached.key
    end

    local value = mergeObject(base, delta)
    for _, pool in ipairs(POOLS) do
        if delta[pool] ~= nil then value[pool] = mergePool(base[pool], delta[pool]) end
    end
    if delta.base ~= nil then
        value.base = mergeObject(base.base or {}, delta.base)
        for _, pool in ipairs(BASE_POOLS) do
            if delta.base[pool] ~= nil then
                value.base[pool] = mergePool(base.base and base.base[pool], delta.base[pool])
            end
        end
    end
    value.id = base.id or id
    local key = id .. "@map:" .. tostring(mapData)
    cache[mapData] = { base = base, delta = delta, value = value, key = key }
    return value, key
end

function resolver.invalidate(mapData)
    if mapData then cache[mapData] = nil end
end

return resolver
