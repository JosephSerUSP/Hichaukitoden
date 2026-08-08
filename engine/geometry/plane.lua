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
local decimate = require("engine.geometry.decimate")
local quality = require("engine.geometry.quality")
local buildProfiler = require("engine.map_build_profiler")

local plane = {}

-- Height fields tile periodically. The terminal mesh vertex is placed at 1 so
-- the cell still spans its full world-space width, but samples height at 0 so
-- it is exactly identical to the neighbouring cell's first vertex. Albedo UVs
-- remain at 1 and continue to address the texture's far edge normally.
function plane.periodicSampleCoordinate(value)
    if math.abs(value - 1) < 1e-9 then return 0 end
    return value
end

-- PROVISIONAL. How far a wall's apron reaches past the cell in each direction.
--
-- This is a riser with a hardcoded height and no data behind it, and it is a
-- placeholder for the rim-height rule in docs/design/surface-junctions.md --
-- delete it when that lands rather than extending it. Two things it does not
-- do, both measured: it does not fire when heightMapScale.wall is 0, because
-- then the wall is a plain quad and not a plane mesh at all, which is exactly
-- the case that motivated it; and it closes nothing between two adjacent
-- floors, because the crack there is a rim-height disagreement rather than a
-- wall that stops short.
--
-- It is kept because a wall meeting a displaced floor is a real void and this
-- closes it, and because it is harmless: the apron sits behind the floor and
-- ceiling, so over-reaching costs two triangles and hides nothing visible.
local SKIRT = 0.15
plane.SKIRT = SKIRT

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
    -- Sample densely, then decimate to the authored budget. meshColumns and
    -- meshRows now declare how many triangles the asset is WORTH, not where
    -- its vertices must fall -- so relief narrower than a grid cell survives
    -- instead of being averaged away.
    local columns, rows = spec.sampleColumns, spec.sampleRows
    local builder = mesh.newBuilder(spec.label)
    builder:setMaterial(spec.id)

    -- A wall gets a SKIRT: one extra row of geometry past each end, continuing
    -- the edge profile beyond z=0 and z=1.
    --
    -- A wall spans exactly one cell in Z and its top and bottom edges are dead
    -- straight, but a displaced floor is z = lift and a displaced ceiling is
    -- 1 - lift, and displacement is signed around neutral. So any joint darker
    -- than neutral drops the floor below the wall's foot and any ceiling recess
    -- lifts it above the wall's head, and the gap between them is a hole
    -- straight out of the room. This is not intermittent -- it is guaranteed
    -- the moment floor or ceiling displacement is non-zero.
    --
    -- The skirt is part of the SAME grid rather than a strip welded on
    -- afterwards, because a separately built strip meets a decimated edge whose
    -- vertices it cannot predict, which trades the hole for a crack.
    local skirt = (spec.surface == "wall") and (spec.skirt or SKIRT) or 0

    -- Rows as (sample position, surface position) pairs. They differ only on
    -- the skirt rows, which reuse the edge's height so the apron continues the
    -- profile instead of stepping away from it.
    local along = {}
    if skirt > 0 then along[#along + 1] = { 0, -skirt } end
    for row = 0, rows do along[#along + 1] = { row / rows, row / rows } end
    if skirt > 0 then along[#along + 1] = { 1, 1 + skirt } end
    rows = #along - 1

    -- Sample once per intersection rather than per triangle corner: adjacent
    -- quads must agree exactly or the surface develops seams.
    local sampleSpan = buildProfiler.span("geometry.denseSampling", "cpu")
    local grid, deepest = {}, math.huge
    for row = 0, rows do
        grid[row] = {}
        local sample, place = along[row + 1][1], along[row + 1][2]
        for column = 0, columns do
            local u = column / columns
            local sampleU = plane.periodicSampleCoordinate(u)
            local sampleV = spec.surface == "wall"
                and sample or plane.periodicSampleCoordinate(sample)
            local lift = plane.sampleField(layers, sampleU, sampleV) + spec.offset
            if lift < deepest then deepest = lift end
            local x, y, z = position(spec.surface, u, place, lift)
            -- UVs clamp to the edge, so the apron wears the wall's own bottom
            -- pixels rather than sampling outside the tile into its neighbour.
            local tu, tv = uv(u, sample)
            grid[row][column] = { x, y, z, tu, tv }
        end
    end
    sampleSpan()
    -- A recess cuts INTO the wall's own volume, which is fine -- a base-wall
    -- surface suppresses the atlas tile behind it. What is not fine is cutting
    -- clean through: past half a cell the cavity emerges inside whatever is on
    -- the far side of that wall.
    if spec.surface == "wall" and deepest < -0.5 then
        error(spec.label .. ": displacement reaches "
            .. string.format("%.4f", deepest)
            .. " into the wall, which is more than half a cell --"
            .. " the cavity would break through to the far side."
            .. " Reduce heightScale or raise 'offset'", 0)
    end

    -- Indexed, because decimation collapses shared vertices; the mesh builder
    -- takes the soup afterwards.
    local topologySpan = buildProfiler.span("geometry.denseTopology", "cpu")
    local dense = { vertices = {}, faces = {} }
    local indexOf = {}
    for row = 0, rows do
        for column = 0, columns do
            dense.vertices[#dense.vertices + 1] = grid[row][column]
            indexOf[row * (columns + 1) + column] = #dense.vertices
        end
    end
    local function at(row, column) return indexOf[row * (columns + 1) + column] end
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local a, b = at(row, column), at(row, column + 1)
            local c, d = at(row + 1, column + 1), at(row + 1, column)
            -- Alternate the diagonal so the dense grid carries no
            -- single-direction bias into the decimator.
            if (column + row) % 2 == 0 then
                dense.faces[#dense.faces + 1] = { a, b, c }
                dense.faces[#dense.faces + 1] = { a, c, d }
            else
                dense.faces[#dense.faces + 1] = { a, b, d }
                dense.faces[#dense.faces + 1] = { b, c, d }
            end
        end
    end

    topologySpan()
    buildProfiler.add("geometry.denseVertices", #dense.vertices)
    buildProfiler.add("geometry.denseTriangles", #dense.faces)

    -- Seam bookkeeping. A plane is a TILE: the mesh is instanced once per cell,
    -- so its own left border sits against a copy of its own right border. The
    -- decimator therefore has to be told two things it cannot see from the
    -- triangle soup.
    --
    -- Which border a vertex lives on, so it reduces along that border instead
    -- of being averaged inward -- the quadric penalty alone only made drift
    -- expensive, and "expensive" still happens.
    --
    -- And which vertices are the SAME point on the opposite border, so both
    -- sides reduce in lockstep. Even with a perfectly seamless texture the two
    -- borders of one mesh have different neighbourhoods, so decimated
    -- independently they keep different vertices and the tiles stop meeting.
    --
    -- Only the WRAPPING borders are declared. A wall wraps along +u into the
    -- next cell, so its left and right borders are the tiling seam; its top and
    -- bottom meet a ceiling and a floor, whose own borders are straight lines at
    -- a fixed height, and a straight border cannot gap against those wherever
    -- its vertices happen to fall. A floor or ceiling wraps both ways. Declaring
    -- only what actually tiles matters: a declared border cannot be absorbed by
    -- the interior, so declaring all four walls the interior in behind a rim and
    -- leaves a flat surface carrying an order of magnitude more triangles than
    -- it needs.
    local border, locked, mirror = {}, {}, {}
    -- A corner sits on two seams at once and answers to both, so it moves for
    -- neither -- and it is deliberately left unmirrored: on a floor it would
    -- need one partner per axis, and a single wrong partner would collapse two
    -- unrelated vertices together.
    for _, corner in ipairs({ at(0, 0), at(0, columns), at(rows, 0), at(rows, columns) }) do
        locked[corner] = true
    end
    local function seam(a, b, id)
        border[a], border[b] = id .. "0", id .. "1"
        if not locked[a] and not locked[b] then mirror[a], mirror[b] = b, a end
    end
    for row = 0, rows do seam(at(row, 0), at(row, columns), "u") end
    if spec.surface ~= "wall" then
        for column = 0, columns do seam(at(0, column), at(rows, column), "v") end
    end

    local decimateSpan = buildProfiler.span("geometry.qemDecimation", "cpu")
    local reduced = decimate.run(dense, quality.budget(spec.triangleBudget),
        quality.maxError(), { border = border, locked = locked, mirror = mirror })
    decimateSpan()
    buildProfiler.add("geometry.reducedVertices", #reduced.vertices)
    buildProfiler.add("geometry.reducedTriangles", #reduced.faces)

    local finalizeCpuSpan = buildProfiler.span("geometry.localFinalizeCpu", "cpu")
    local flip = SURFACES[spec.surface].flip
    for _, face in ipairs(reduced.faces) do
        local p, q, r = reduced.vertices[face[1]], reduced.vertices[face[2]], reduced.vertices[face[3]]
        if flip then builder:triangle(p, r, q) else builder:triangle(p, q, r) end
    end

    -- A displaced atlas tile replaces its structural quad. Close its exposed
    -- perimeter back into the solid cell volume so independently displaced
    -- neighbours cannot reveal the fog/background between them. These are
    -- genuine side faces, not a screen-space patch: depth, lighting and camera
    -- clipping treat them exactly like the relief itself.
    if spec.sealPerimeter then
        local function copyAt(vertex, x, y, z)
            return { x or vertex[1], y or vertex[2], z or vertex[3], vertex[4], vertex[5] }
        end
        local function curtain(points, backing)
            table.sort(points, backing.sort)
            for i = 1, #points - 1 do
                local a, b = points[i], points[i + 1]
                local c, d = backing.vertex(b), backing.vertex(a)
                builder:triangle(a, b, c)
                builder:triangle(a, c, d)
            end
        end
        local function boundary(predicate)
            local points = {}
            for _, vertex in ipairs(reduced.vertices) do
                if predicate(vertex) then points[#points + 1] = vertex end
            end
            return points
        end
        local eps = 1e-6
        local edgeMin, edgeMax = -0.5, 0.5
        if spec.surface == "floor" or spec.surface == "ceiling" then
            -- Continue horizontal surfaces a half-cell into the solid shell as
            -- well. This overlaps the wall closure volume at feet and crowns,
            -- eliminating sub-pixel T-junction pinholes after projection.
            local backingZ = spec.surface == "floor" and -0.51 or 1.51
            local byY = function(a, b) return a[2] < b[2] end
            local byX = function(a, b) return a[1] < b[1] end
            for _, x in ipairs({ edgeMin, edgeMax }) do
                curtain(boundary(function(v) return math.abs(v[1] - x) < eps end), {
                    sort = byY, vertex = function(v) return copyAt(v, x, nil, backingZ) end,
                })
            end
            for _, y in ipairs({ edgeMin, edgeMax }) do
                curtain(boundary(function(v) return math.abs(v[2] - y) < eps end), {
                    sort = byX, vertex = function(v) return copyAt(v, nil, y, backingZ) end,
                })
            end
            local u0, v0 = uv(0, 0)
            local u1, v1 = uv(1, 1)
            local a, b = { edgeMin, edgeMin, backingZ, u0, v0 }, { edgeMax, edgeMin, backingZ, u1, v0 }
            local c, d = { edgeMax, edgeMax, backingZ, u1, v1 }, { edgeMin, edgeMax, backingZ, u0, v1 }
            builder:triangle(a, b, c)
            builder:triangle(a, c, d)
        else
            -- A wall cell is solid through its half-cell depth. Closing only
            -- by the relief amplitude leaves a wedge between two orthogonal
            -- faces at a corner; carrying both curtains to the cell centre
            -- makes them overlap inside solid volume and resolves the corner
            -- once, regardless of either face's height profile.
            local backingX = -0.51
            local byZ = function(a, b) return a[3] < b[3] end
            for _, y in ipairs({ edgeMin, edgeMax }) do
                curtain(boundary(function(v) return math.abs(v[2] - y) < eps end), {
                    sort = byZ, vertex = function(v) return copyAt(v, backingX, y, nil) end,
                })
            end
            local u0, v0 = uv(0, 0)
            local u1, v1 = uv(1, 1)
            local a, b = { backingX, edgeMin, -0.51, u0, v1 }, { backingX, edgeMax, -0.51, u1, v1 }
            local c, d = { backingX, edgeMax, 1.51, u1, v0 }, { backingX, edgeMin, 1.51, u0, v0 }
            builder:triangle(a, b, c)
            builder:triangle(a, c, d)
        end
    end
    local built = builder:build()
    finalizeCpuSpan()
    return built
end

return plane
