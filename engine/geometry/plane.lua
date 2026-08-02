-- Plane topology: a displaced rectangular surface.
--
--   P(u,v) = P0 + uT + vB + h(u,v)N
--
-- Emitted in the local frame the world renderer already places models in
-- (presentation/viewport_3d.lua):
--
--   wall            +X is depth out of the wall face, +Y runs along it
--                   (-0.5..0.5), +Z is up (0..1)
--   floor / ceiling +X/+Y are the cell plane (-0.5..0.5), +Z is up, and
--                   displacement runs along Z
--
-- The mesh grid is fixed and declared per asset: texture resolution and
-- geometry density are independent, so a 128px height map does not imply
-- 16,384 vertices.
local mesh = require("presentation.mesh")
local images = require("engine.geometry.images")

local plane = {}

-- Where the undisplaced surface sits, which way displacement points, and
-- whether the natural grid order winds away from the viewer. `flip` is not
-- cosmetic: a back-facing relief is invisible, and the renderer applies no
-- two-sided fallback by design.
local SURFACES = {
    wall = { base = 0, sign = 1, flip = true },
    floor = { base = 0, sign = 1, flip = false },
    ceiling = { base = 1, sign = -1, flip = true },
}

-- Map a grid cell to the asset's local frame. `across` and `along` both run
-- 0..1 over the authored image; `lift` is the displacement along the surface
-- normal in map cells.
local function position(surface, across, along, lift)
    if surface == "wall" then
        -- Image +v runs downward, so a wall's Z is flipped to keep painted
        -- top at world top.
        return lift, across - 0.5, 1 - along
    end
    local placement = SURFACES[surface]
    return across - 0.5, along - 0.5, placement.base + placement.sign * lift
end

-- Sample the composite height field at one grid intersection. `layers` is an
-- ordered list of { data, operation, scale }; the first entry is the base and
-- later entries compose onto it per the design doc's height operations.
--
-- `scale` is ABSOLUTE (in map cells), not relative to the base, because a
-- composed surface mixes layers authored at different depths -- a shrine recess
-- cutting 0.14 into a wall whose own block relief is 0.06.
function plane.sampleField(layers, u, v)
    local value = 0
    for index, layer in ipairs(layers) do
        local displacement, alpha = images.signedDisplacement(layer.data, u, v)
        displacement = displacement * layer.scale
        if index == 1 then
            value = displacement
        elseif layer.operation == "add" then
            value = value + displacement * alpha
        elseif layer.operation == "replace" then
            value = value + (displacement - value) * alpha
        end
        -- "none" contributes albedo only and is deliberately skipped here.
    end
    return value
end

-- Build the displaced grid. `spec` is parsed metadata; `layers` is the height
-- stack described above; `uv` maps a grid position to texture coordinates,
-- letting a caller point the mesh at an atlas region instead of a whole image.
function plane.build(spec, layers, uv)
    if not SURFACES[spec.surface] then
        error(spec.label .. ": unsupported plane surface '" .. tostring(spec.surface) .. "'", 0)
    end
    local columns, rows = spec.meshColumns, spec.meshRows
    local builder = mesh.newBuilder(spec.label)
    builder:setMaterial(spec.id)

    -- Sample once per intersection rather than per triangle corner: adjacent
    -- quads must agree exactly or the surface develops seams.
    local grid, deepest = {}, math.huge
    for row = 0, rows do
        grid[row] = {}
        local v = row / rows
        for column = 0, columns do
            local u = column / columns
            local lift = plane.sampleField(layers, u, v) + spec.offset
            if lift < deepest then deepest = lift end
            local x, y, z = position(spec.surface, u, v, lift)
            local tu, tv = uv(u, v)
            grid[row][column] = { x, y, z, tu, tv }
        end
    end
    -- A wall relief sits IN FRONT of the structural wall, which still renders
    -- behind it. Anything sinking past the wall plane is depth-occluded by it,
    -- and the symptom is the base atlas tile showing through the recessed
    -- parts -- which reads as a broken texture, not as geometry inside a wall.
    -- A true cavity therefore needs the whole surface pushed out, not the
    -- recess pushed in.
    if spec.surface == "wall" and deepest < 0 then
        error(spec.label .. ": displacement reaches "
            .. string.format("%.4f", deepest) .. " behind the wall plane."
            .. " Raise 'offset' to at least "
            .. string.format("%.4f", spec.offset - deepest)
            .. ", or reduce the recessed depth", 0)
    end

    local flip = SURFACES[spec.surface].flip
    local function emit(p, q, r)
        if flip then builder:triangle(p, r, q) else builder:triangle(p, q, r) end
    end
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local a = grid[row][column]
            local b = grid[row][column + 1]
            local c = grid[row + 1][column + 1]
            local d = grid[row + 1][column]
            -- Alternate the diagonal so a coarse grid does not read as a
            -- single-direction sawtooth across the whole panel.
            if (column + row) % 2 == 0 then
                emit(a, b, c)
                emit(a, c, d)
            else
                emit(a, b, d)
                emit(b, c, d)
            end
        end
    end
    return builder:build()
end

return plane
