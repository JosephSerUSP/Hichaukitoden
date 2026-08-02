-- Shell topology: one or two displaced surfaces sharing a two-dimensional
-- parameterization, closed or pinched around their common boundary.
--
-- Both depth fields store NONNEGATIVE distance from a shared central plane:
--
--   z_front(x,y) = +depthFront(x,y)
--   z_back(x,y)  = -depthBack(x,y)
--
-- Front and back therefore cannot cross by construction, and each field is
-- easier to paint than an arbitrary signed coordinate. Height alpha is the
-- coverage mask that defines the silhouette.
--
-- Emitted in the same local frame as plane topology so the renderer places a
-- shell exactly like any other model: +X is depth, +Y runs across, +Z is up.
local mesh = require("presentation.mesh")
local images = require("engine.geometry.images")
local decimate = require("engine.geometry.decimate")

local shell = {}

-- Sample a depth field inside a declared atlas region, so front and back can
-- live side by side in one pair of PNGs without introducing a third texture.
local function region(spec, side)
    if spec.layout == "frontBackHorizontal" then
        return side == "back" and { 0.5, 0, 0.5, 1 } or { 0, 0, 0.5, 1 }
    end
    return { 0, 0, 1, 1 }
end

-- Sample in the region's OWN pixel space. Scaling normalized coordinates
-- against the full image instead lands half a pixel off at the seam, so the
-- left half would run 0..15.5 of a 32px atlas and the right 15.5..31 -- and
-- two identical halves would then disagree about their own mask.
local function sampleRegion(data, area, u, v)
    local width, height = data:getWidth(), data:getHeight()
    local x0 = math.floor(area[1] * width + 0.5)
    local y0 = math.floor(area[2] * height + 0.5)
    local regionWidth = math.floor(area[3] * width + 0.5)
    local regionHeight = math.floor(area[4] * height + 0.5)
    local x = x0 + math.max(0, math.min(regionWidth - 1,
        math.floor(u * (regionWidth - 1) + 0.5)))
    local y = y0 + math.max(0, math.min(regionHeight - 1,
        math.floor(v * (regionHeight - 1) + 0.5)))
    return data:getPixel(x, y)
end

-- Coverage: the height map's alpha channel. Anything at or below the threshold
-- is outside the silhouette and produces no geometry.
local function covered(data, area, u, v)
    local _, _, _, alpha = sampleRegion(data, area, u, v)
    return alpha > 0.5
end

local function depthAt(data, area, u, v)
    local value = sampleRegion(data, area, u, v)
    return value   -- unsigned: 0 is the central plane, 1 is maximum outward
end

-- Masks must agree in frontBack mode. Equal masks do not themselves build the
-- side wall; they guarantee that the same contour and the same holes exist on
-- both sides, which is what lets the compiler stitch deterministically.
function shell.checkMasks(spec, height, columns, rows)
    if spec.surfaceMode ~= "frontBack" or not spec.requireMatchingMasks then return end
    local front, back = region(spec, "front"), region(spec, "back")
    for row = 0, rows do
        for column = 0, columns do
            local u, v = column / columns, row / rows
            if covered(height, front, u, v) ~= covered(height, back, u, v) then
                error(spec.label .. ": front and back coverage masks differ at ("
                    .. string.format("%.3f, %.3f", u, v)
                    .. "); a stitched shell needs one shared silhouette", 0)
            end
        end
    end
end

-- Reject what the first implementation deliberately does not support: several
-- disconnected opaque islands. Compiling each as its own shell is a listed
-- later extension, and silently welding them would produce nonsense edges.
function shell.checkSingleComponent(spec, height, columns, rows)
    local area = region(spec, "front")
    local seen, islands = {}, 0
    local function key(c, r) return r * (columns + 1) + c end
    for row = 0, rows do
        for column = 0, columns do
            if covered(height, area, column / columns, row / rows) and not seen[key(column, row)] then
                islands = islands + 1
                if islands > 1 then
                    error(spec.label .. ": coverage mask has more than one island;"
                        .. " restrict the asset to one component plus holes", 0)
                end
                local stack = { { column, row } }
                seen[key(column, row)] = true
                while #stack > 0 do
                    local cell = table.remove(stack)
                    local neighbours = {
                        { cell[1] + 1, cell[2] }, { cell[1] - 1, cell[2] },
                        { cell[1], cell[2] + 1 }, { cell[1], cell[2] - 1 },
                    }
                    for _, next in ipairs(neighbours) do
                        local c, r = next[1], next[2]
                        if c >= 0 and c <= columns and r >= 0 and r <= rows
                            and not seen[key(c, r)]
                            and covered(height, area, c / columns, r / rows) then
                            seen[key(c, r)] = true
                            stack[#stack + 1] = { c, r }
                        end
                    end
                end
            end
        end
    end
    if islands == 0 then
        error(spec.label .. ": coverage mask is empty; the asset has no silhouette", 0)
    end
end

-- Report albedo that is transparent where the coverage mask says there IS
-- geometry. Sampled on the mesh grid rather than per texel: the failure only
-- matters where a quad's interpolation actually reaches.
function shell.hasTransparentCoverage(spec, albedo, height)
    local columns, rows = spec.meshColumns, spec.meshRows
    local area = region(spec, "front")
    for row = 0, rows do
        for column = 0, columns do
            local u, v = column / columns, row / rows
            if covered(height, area, u, v) then
                local _, _, _, alpha = sampleRegion(albedo, area, u, v)
                if alpha < 0.5 then return true end
            end
        end
    end
    return false
end

-- Build the front and rear grids plus the edge that joins them.
function shell.build(spec, height)
    -- Sample densely, decimate after. On a coarse grid a quad survives only
    -- when all four corners are covered, so anything narrower than two cells
    -- vanishes -- which erased a statue's neck outright and left its head
    -- floating. Sampling fine keeps the silhouette; the decimator then spends
    -- the budget on the form rather than on the grid.
    local columns, rows = spec.sampleColumns, spec.sampleRows
    shell.checkMasks(spec, height, columns, rows)
    shell.checkSingleComponent(spec, height, columns, rows)

    local frontArea = region(spec, "front")
    local backArea = spec.surfaceMode == "frontBack" and region(spec, "back") or frontArea

    local builder = mesh.newBuilder(spec.label)
    builder:setMaterial(spec.id)

    -- Sample once per intersection; adjacent quads must agree exactly.
    local front, back, mask = {}, {}, {}
    for row = 0, rows do
        front[row], back[row], mask[row] = {}, {}, {}
        local v = row / rows
        for column = 0, columns do
            local u = column / columns
            local inside = covered(height, frontArea, u, v)
            local frontDepth = depthAt(height, frontArea, u, v) * spec.depthScale
            -- mirrorDepth derives the rear from the front, which halves what
            -- has to be painted while still allowing independent albedo.
            local backDepth = spec.surfaceMode == "frontBack"
                and depthAt(height, backArea, u, v) * spec.depthScale
                or frontDepth
            if spec.surfaceMode == "frontOnly" then backDepth = 0 end

            if spec.edgeMode == "pinch" then
                -- Force both depths toward the central plane near the
                -- silhouette so the halves meet in an intentional thin edge
                -- instead of a visible open rim.
                local margin = spec.pinchWidth / math.max(columns, rows)
                local toEdge = math.min(u, v, 1 - u, 1 - v)
                if margin > 0 and toEdge < margin then
                    local taper = toEdge / margin
                    frontDepth, backDepth = frontDepth * taper, backDepth * taper
                end
            end

            mask[row][column] = inside
            front[row][column] = { frontDepth, u - 0.5, 1 - v, u * 0.5, v }
            -- Back UVs address the rear atlas region, so each face keeps its
            -- own painted art.
            back[row][column] = { -backDepth, u - 0.5, 1 - v,
                (spec.albedoMode == "frontBack" and 0.5 or 0) + u * 0.5, v }
        end
    end

    local function quadInside(row, column)
        return mask[row][column] and mask[row][column + 1]
            and mask[row + 1][column] and mask[row + 1][column + 1]
    end

    -- Indexed so the decimator can collapse shared vertices. Front and rear
    -- stay separate vertex sets even where they coincide: welding them would
    -- let a collapse pull one face through the other.
    local dense = { vertices = {}, faces = {} }
    local frontIndex, backIndex = {}, {}
    -- Where a tapering field brings both surfaces to the central plane, front
    -- and back are the SAME point. Interning them separately leaves two
    -- coincident sheets that z-fight into a dark seam along the silhouette and
    -- hand the decimator a tangle of zero-thickness slivers. Welding there
    -- closes the shell into one surface instead.
    local SEAM = 1e-4
    local function seamWelded(row, column)
        return math.abs(front[row][column][1]) < SEAM
            and math.abs(back[row][column][1]) < SEAM
    end
    local function intern(store, row, column, vertex)
        -- A welded seam vertex lives in the front store, and the back store
        -- points at the same index.
        if seamWelded(row, column) then store = frontIndex end
        store[row] = store[row] or {}
        if not store[row][column] then
            dense.vertices[#dense.vertices + 1] = vertex
            store[row][column] = #dense.vertices
        end
        return store[row][column]
    end
    local function face(a, b, c) dense.faces[#dense.faces + 1] = { a, b, c } end

    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            if quadInside(row, column) then
                local a = intern(frontIndex, row, column, front[row][column])
                local b = intern(frontIndex, row, column + 1, front[row][column + 1])
                local c = intern(frontIndex, row + 1, column + 1, front[row + 1][column + 1])
                local d = intern(frontIndex, row + 1, column, front[row + 1][column])
                -- Front faces +X.
                face(a, d, c)
                face(a, c, b)
                if spec.surfaceMode ~= "frontOnly" then
                    local e = intern(backIndex, row, column, back[row][column])
                    local f = intern(backIndex, row, column + 1, back[row][column + 1])
                    local g = intern(backIndex, row + 1, column + 1, back[row + 1][column + 1])
                    local h = intern(backIndex, row + 1, column, back[row + 1][column])
                    -- Rear winding is reversed so it faces -X.
                    face(e, g, h)
                    face(e, f, g)
                end
            end
        end
    end

    if spec.surfaceMode ~= "frontOnly" and spec.edgeMode == "stitch" then
        shell.stitch(dense, intern, frontIndex, backIndex, front, back, mask, columns, rows)
    end

    local reduced = decimate.run(dense, spec.meshColumns * spec.meshRows * 2)
    for _, triangle in ipairs(reduced.faces) do
        builder:triangle(reduced.vertices[triangle[1]],
            reduced.vertices[triangle[2]], reduced.vertices[triangle[3]])
    end
    return builder:build()
end

-- Bridge the front and rear contours with explicit side faces. A boundary edge
-- is one where an inside quad meets an outside quad (or the grid border);
-- joining those in order closes the shell around its silhouette and its holes
-- alike, without the artist authoring a side texture.
function shell.stitch(dense, intern, frontIndex, backIndex, front, back, mask, columns, rows)
    local function inside(row, column)
        if row < 0 or column < 0 or row >= rows or column >= columns then return false end
        return mask[row][column] and mask[row][column + 1]
            and mask[row + 1][column] and mask[row + 1][column + 1]
    end
    -- Each inside quad contributes a side face for every neighbour that is
    -- outside, using that shared edge's two grid corners.
    local sides = {
        { dr = -1, dc = 0, a = { 0, 0 }, b = { 0, 1 } },   -- top edge
        { dr = 1, dc = 0, a = { 1, 1 }, b = { 1, 0 } },    -- bottom edge
        { dr = 0, dc = -1, a = { 1, 0 }, b = { 0, 0 } },   -- left edge
        { dr = 0, dc = 1, a = { 0, 1 }, b = { 1, 1 } },    -- right edge
    }
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            if inside(row, column) then
                for _, side in ipairs(sides) do
                    if not inside(row + side.dr, column + side.dc) then
                        local ar, ac = row + side.a[1], column + side.a[2]
                        local br, bc = row + side.b[1], column + side.b[2]
                        local fa, fb = front[ar][ac], front[br][bc]
                        local ba, bb = back[ar][ac], back[br][bc]
                        -- Two triangles bridging front edge to rear edge.
                        -- Degenerate strips (both depths zero at a pinch) are
                        -- skipped rather than raising: a pinched silhouette is
                        -- allowed to close to nothing.
                        if math.abs(fa[1] - ba[1]) > 1e-6 or math.abs(fb[1] - bb[1]) > 1e-6 then
                            local ia = intern(frontIndex, ar, ac, fa)
                            local ib = intern(frontIndex, br, bc, fb)
                            local ja = intern(backIndex, ar, ac, ba)
                            local jb = intern(backIndex, br, bc, bb)
                            dense.faces[#dense.faces + 1] = { ia, ib, jb }
                            dense.faces[#dense.faces + 1] = { ia, jb, ja }
                        end
                    end
                end
            end
        end
    end
end

return shell
