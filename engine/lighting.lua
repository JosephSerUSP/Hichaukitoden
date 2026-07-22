-- Shared, deterministic light baking for authored light objects and generated
-- dungeon fixtures.  Values are vertex colours because that is the format the
-- raycaster samples; a source is blocked by walls rather than bleeding through
-- them as a simple painted circle would.
local lighting = {}

local function isWall(grid, x, y)
    return not grid[y] or not grid[y][x] or grid[y][x] == "#"
end

local function visible(grid, x0, y0, x1, y1)
    local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
    local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
    local err, x, y = dx - dy, x0, y0
    while x ~= x1 or y ~= y1 do
        if (x ~= x0 or y ~= y0) and isWall(grid, x, y) then return false end
        local e2 = err * 2
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end
    end
    return true
end

-- `sources` use zero-based cell coordinates, colour 0..1, and a tile radius.
function lighting.bake(grid, sources, ambient)
    local h, w = #grid, #grid[1]
    ambient = ambient or { 0.12, 0.12, 0.12 }
    local out = {}
    for vy = 0, h do
        out[vy + 1] = {}
        for vx = 0, w do out[vy + 1][vx + 1] = { ambient[1], ambient[2], ambient[3] } end
    end
    for _, source in ipairs(sources or {}) do
        local radius = math.max(0.1, source.radius or 4)
        local col = source.color or { 1, 0.65, 0.3 }
        for vy = math.max(0, math.floor(source.y - radius)), math.min(h, math.ceil(source.y + radius)) do
            for vx = math.max(0, math.floor(source.x - radius)), math.min(w, math.ceil(source.x + radius)) do
                local dx, dy = vx - (source.x + 0.5), vy - (source.y + 0.5)
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= radius and visible(grid, source.x + 1, source.y + 1, math.max(1, math.min(w, vx)), math.max(1, math.min(h, vy))) then
                    local strength = (1 - dist / radius) ^ (source.falloff or 2)
                    local dst = out[vy + 1][vx + 1]
                    for c = 1, 3 do dst[c] = math.min(1, dst[c] + col[c] * strength) end
                end
            end
        end
    end
    return out
end

return lighting
