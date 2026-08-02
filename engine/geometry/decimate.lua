-- Quadric-error mesh decimation.
--
-- The compiler samples a field DENSELY -- fine enough that thin features and
-- true silhouettes survive -- and then reduces the result to a low triangle
-- budget here. That is the opposite of meshing straight onto a coarse grid,
-- which cannot represent anything narrower than two cells: it erased a
-- statue's neck outright and forced wall mortar to be painted thicker than the
-- art wanted.
--
-- Decimating afterwards keeps the retro silhouette while spending triangles
-- where the FORM needs them rather than where the grid happens to fall, so the
-- result reads as deliberate low-poly instead of as a grid.
--
-- Garland & Heckbert's quadric error metric: each vertex accumulates the
-- squared-distance quadric of its incident face planes, and the cheapest edge
-- collapse is applied repeatedly. Deterministic -- equal costs break by index
-- -- because the golden gates byte-compare what this produces.
local decimate = {}

-- A symmetric 4x4 quadric stored as its 10 distinct entries.
local function quadricFromPlane(a, b, c, d)
    return {
        a * a, a * b, a * c, a * d,
        b * b, b * c, b * d,
        c * c, c * d,
        d * d,
    }
end

local function quadricAdd(target, other)
    for index = 1, 10 do target[index] = target[index] + other[index] end
    return target
end

local function quadricError(q, x, y, z)
    -- v^T Q v for v = (x, y, z, 1).
    return q[1] * x * x + 2 * q[2] * x * y + 2 * q[3] * x * z + 2 * q[4] * x
        + q[5] * y * y + 2 * q[6] * y * z + 2 * q[7] * y
        + q[8] * z * z + 2 * q[9] * z
        + q[10]
end

local function facePlane(p, q, r)
    local ux, uy, uz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
    local vx, vy, vz = r[1] - p[1], r[2] - p[2], r[3] - p[3]
    local a = uy * vz - uz * vy
    local b = uz * vx - ux * vz
    local c = ux * vy - uy * vx
    local length = math.sqrt(a * a + b * b + c * c)
    if length < 1e-12 then return nil end
    a, b, c = a / length, b / length, c / length
    return a, b, c, -(a * p[1] + b * p[2] + c * p[3])
end

-- A minimal binary heap with lazy invalidation: a collapse changes the cost of
-- every edge around it, and reinserting is cheaper than repairing in place.
local function heapPush(heap, item)
    heap[#heap + 1] = item
    local index = #heap
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap[parent].cost <= item.cost then break end
        heap[index], heap[parent] = heap[parent], heap[index]
        index = parent
    end
end

local function heapPop(heap)
    local size = #heap
    if size == 0 then return nil end
    local top = heap[1]
    heap[1] = heap[size]
    heap[size] = nil
    size = size - 1
    local index = 1
    while true do
        local left, right = index * 2, index * 2 + 1
        local smallest = index
        if left <= size and heap[left].cost < heap[smallest].cost then smallest = left end
        if right <= size and heap[right].cost < heap[smallest].cost then smallest = right end
        if smallest == index then break end
        heap[index], heap[smallest] = heap[smallest], heap[index]
        index = smallest
    end
    return top
end

-- `mesh` is { vertices = { {x,y,z,u,v}, ... }, faces = { {i,j,k}, ... } }.
-- Returns a new mesh with at most `targetFaces` triangles.
--
-- Boundary edges are the silhouette and the cell seam. They are constrained,
-- not frozen: a virtual plane perpendicular to the face through each boundary
-- edge is added with a heavy weight, so collapsing ALONG a straight boundary
-- stays free while pulling a boundary inward becomes expensive. Freezing them
-- outright would leave a dense rim around a coarse interior, and a wall whose
-- border drifted would gap against its neighbour.
-- `maxError` is the quadric error below which a collapse is considered free.
-- Those collapses happen even when the mesh is already inside its budget, which
-- is what lets a flat wall fall to a handful of triangles instead of sitting at
-- whatever the budget allowed. Without it a coplanar region keeps hundreds of
-- triangles that describe nothing -- the budget is a ceiling, not a target.
--
-- `options` lets a caller that KNOWS its boundary is a tiling seam say so. The
-- quadric constraint above is a soft penalty, and a soft penalty is the wrong
-- tool for a seam: it makes drifting inward expensive, not impossible, so a
-- wall's border still creeps and the copy of that wall in the next cell no
-- longer meets it. A caller supplies:
--
--   options.border[i] = "u0" | "u1" | ...   which seam plane vertex i lives on
--   options.locked[i] = true                a corner: never collapse it
--   options.mirror[i] = j                   i and j are the same point on
--                                           opposite seams of a tiling asset
--
-- Border vertices then collapse only ALONG their own seam (the midpoint of two
-- vertices sharing a seam plane is still in that plane, so the border can never
-- leave it), and a mirrored pair is decimated in lockstep: both sides pay the
-- worse of the two costs and both collapse together. That is what makes tile
-- meet tile -- without it each edge of the SAME mesh reduces differently, and
-- copies of it placed side by side disagree about where their vertices are.
function decimate.run(mesh, targetFaces, maxError, options)
    local vertices, faces = mesh.vertices, mesh.faces
    maxError = maxError or 0
    options = options or {}
    local border, locked, mirror = options.border or {}, options.locked or {}, options.mirror or {}
    if #faces <= targetFaces and maxError <= 0 then return mesh end

    local quadrics = {}
    for index = 1, #vertices do quadrics[index] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } end

    -- Face quadrics.
    local edgeFaces = {}
    local function edgeKey(a, b) return (a < b) and (a .. ":" .. b) or (b .. ":" .. a) end
    for _, face in ipairs(faces) do
        local p, q, r = vertices[face[1]], vertices[face[2]], vertices[face[3]]
        local a, b, c, d = facePlane(p, q, r)
        if a then
            local plane = quadricFromPlane(a, b, c, d)
            for _, vertexIndex in ipairs(face) do
                quadricAdd(quadrics[vertexIndex], plane)
            end
        end
        for corner = 1, 3 do
            local key = edgeKey(face[corner], face[corner % 3 + 1])
            edgeFaces[key] = (edgeFaces[key] or 0) + 1
        end
    end

    -- Boundary constraint planes.
    local BOUNDARY_WEIGHT = 1000
    for _, face in ipairs(faces) do
        local p, q, r = vertices[face[1]], vertices[face[2]], vertices[face[3]]
        local fa, fb, fc = facePlane(p, q, r)
        if fa then
            for corner = 1, 3 do
                local i, j = face[corner], face[corner % 3 + 1]
                if edgeFaces[edgeKey(i, j)] == 1 then
                    local vi, vj = vertices[i], vertices[j]
                    local ex, ey, ez = vj[1] - vi[1], vj[2] - vi[2], vj[3] - vi[3]
                    -- Perpendicular to both the edge and the face normal.
                    local nx = ey * fc - ez * fb
                    local ny = ez * fa - ex * fc
                    local nz = ex * fb - ey * fa
                    local length = math.sqrt(nx * nx + ny * ny + nz * nz)
                    if length > 1e-12 then
                        nx, ny, nz = nx / length, ny / length, nz / length
                        local offset = -(nx * vi[1] + ny * vi[2] + nz * vi[3])
                        -- BOTH endpoints carry the weighted constraint. Giving
                        -- j an unweighted copy made the penalty depend on which
                        -- way the face happened to wind, so half of every
                        -- boundary was a thousand times cheaper to pull inward
                        -- than the other half.
                        for _, index in ipairs({ i, j }) do
                            local plane = quadricFromPlane(nx, ny, nz, offset)
                            for entry = 1, 10 do plane[entry] = plane[entry] * BOUNDARY_WEIGHT end
                            quadricAdd(quadrics[index], plane)
                        end
                    end
                end
            end
        end
    end

    -- Adjacency.
    local vertexFaces = {}
    for index = 1, #vertices do vertexFaces[index] = {} end
    for faceIndex, face in ipairs(faces) do
        for _, vertexIndex in ipairs(face) do
            vertexFaces[vertexIndex][faceIndex] = true
        end
    end

    local alive, faceAlive = {}, {}
    for index = 1, #vertices do alive[index] = true end
    for index = 1, #faces do faceAlive[index] = true end

    -- Collapse to the midpoint: solving for the optimal position gives a
    -- slightly tighter fit but drifts vertices off the authored surface, which
    -- costs more visually here than the error it saves.
    -- How immovable a vertex is: a corner outranks a seam, a seam outranks the
    -- interior. The higher rank always survives a collapse and keeps its exact
    -- position, so the interior can be eaten away against a seam without the
    -- seam itself shifting by a hair. Averaging there is what dragged borders
    -- inward; refusing the collapse outright instead left a dense rim wrapped
    -- around a coarse middle, which is the other half of the same artefact.
    local function rank(index)
        if locked[index] then return 2 elseif border[index] then return 1 end
        return 0
    end

    -- Which of the two survives. Deterministic and symmetric, so edgeCost(i, j)
    -- and edgeCost(j, i) agree -- the lazy-invalidation check compares costs for
    -- equality and would loop forever otherwise.
    local function orient(i, j)
        local ri, rj = rank(i), rank(j)
        if ri ~= rj then
            if ri > rj then return i, j end
            return j, i
        end
        if i <= j then return i, j end
        return j, i
    end

    -- Note the survivor keeps its position for ANY seam collapse, not only a
    -- mixed-rank one: a decimated seam is then a SUBSET of the sample points it
    -- was built from rather than a chain of drifting midpoints, so the profile
    -- stays on the authored surface and the collapse disturbs no face that does
    -- not contain the vertex being removed.
    local function collapseTarget(i, j)
        local vi, vj = vertices[i], vertices[j]
        if rank(i) > 0 then return vi[1], vi[2], vi[3], vi[4], vi[5] end
        return (vi[1] + vj[1]) * 0.5, (vi[2] + vj[2]) * 0.5, (vi[3] + vj[3]) * 0.5,
            (vi[4] + vj[4]) * 0.5, (vi[5] + vj[5]) * 0.5
    end

    local function rawCost(i, j)
        i, j = orient(i, j)
        local x, y, z = collapseTarget(i, j)
        local combined = {}
        for entry = 1, 10 do combined[entry] = quadrics[i][entry] + quadrics[j][entry] end
        return quadricError(combined, x, y, z)
    end

    -- A mirrored pair is one decision, so it is priced as one: the worse of the
    -- two sides. Pricing them separately is how the two seams of a tiling asset
    -- end up choosing different vertices to keep.
    local function edgeCost(i, j)
        local cost = rawCost(i, j)
        local mi, mj = mirror[i], mirror[j]
        if mi and mj and alive[mi] and alive[mj] then
            local partner = rawCost(mi, mj)
            if partner > cost then cost = partner end
        end
        return cost
    end

    -- Two seams never merge into each other, two corners never merge at all,
    -- and a mirrored vertex is only ever removed together with its partner --
    -- so the interior can never eat into a seam, and a seam can never be eaten
    -- from one end only while the tile beside it keeps its copy.
    local function collapsible(i, j)
        if locked[i] and locked[j] then return false end
        local bi, bj = border[i], border[j]
        if bi and bj and bi ~= bj then return false end
        local _, removed = orient(i, j)
        if mirror[removed] and not mirror[i == removed and j or i] then return false end
        return true
    end

    local heap = {}
    local seen = {}

    -- `real` is the collapse's actual quadric error; `cost` is only its heap
    -- priority. They differ for a refused collapse, which is requeued behind
    -- everything else at a large penalty. Keeping the two apart matters: the
    -- termination test asks "is the cheapest remaining collapse worth
    -- refusing?", and a penalty is not an answer to that question.
    local function offer(i, j)
        if not collapsible(i, j) then return end
        local cost = edgeCost(i, j)
        heapPush(heap, { i = i, j = j, cost = cost, real = cost })
    end

    for _, face in ipairs(faces) do
        for corner = 1, 3 do
            local i, j = face[corner], face[corner % 3 + 1]
            local key = edgeKey(i, j)
            if not seen[key] then
                seen[key] = true
                offer(i, j)
            end
        end
    end

    -- Would this collapse flip a triangle over? A fold is far more visible
    -- than the error it saves, so refuse it.
    local function wouldFlip(i, j, x, y, z)
        for faceIndex in pairs(vertexFaces[i]) do
            if faceAlive[faceIndex] then
                local face = faces[faceIndex]
                if face[1] ~= j and face[2] ~= j and face[3] ~= j then
                    local p = {}
                    for corner = 1, 3 do
                        local vertexIndex = face[corner]
                        p[corner] = (vertexIndex == i)
                            and { x, y, z } or vertices[vertexIndex]
                    end
                    local before = { facePlane(vertices[face[1]], vertices[face[2]], vertices[face[3]]) }
                    local after = { facePlane(p[1], p[2], p[3]) }
                    -- Flattening a face to zero area counts as a fold and is
                    -- refused. It looks harmless -- the face draws nothing --
                    -- but it is how a surface loses AREA: allowing it let the
                    -- interior snap onto a seam one vertex at a time until a
                    -- whole side of the tile had been retired as degenerate.
                    if not after[1] then return true end
                    if before[1] then
                        local dot = before[1] * after[1] + before[2] * after[2] + before[3] * after[3]
                        if dot < 0 then return true end
                    end
                end
            end
        end
        return false
    end

    -- Merge j into i and retire the faces that degenerate. Split out because a
    -- mirrored seam performs two of these as one atomic step.
    local liveFaces = #faces
    local function performCollapse(i, j)
        i, j = orient(i, j)
        local x, y, z, u, v = collapseTarget(i, j)
        vertices[i] = { x, y, z, u, v }
        alive[j] = false
        quadricAdd(quadrics[i], quadrics[j])
        for faceIndex in pairs(vertexFaces[j]) do
            if faceAlive[faceIndex] then
                local face = faces[faceIndex]
                local touchesI = face[1] == i or face[2] == i or face[3] == i
                if touchesI then
                    faceAlive[faceIndex] = false
                    liveFaces = liveFaces - 1
                else
                    for corner = 1, 3 do
                        if face[corner] == j then face[corner] = i end
                    end
                    vertexFaces[i][faceIndex] = true
                end
            end
        end
        vertexFaces[j] = {}
        -- Retire whatever the merge flattened. These faces have zero area and
        -- draw nothing; leaving them alive would let the budget be spent on
        -- triangles that are not there.
        for faceIndex in pairs(vertexFaces[i]) do
            if faceAlive[faceIndex] then
                local face = faces[faceIndex]
                if not facePlane(vertices[face[1]], vertices[face[2]], vertices[face[3]]) then
                    faceAlive[faceIndex] = false
                    liveFaces = liveFaces - 1
                end
            end
        end
        -- Requeue the ring around the surviving vertex.
        for faceIndex in pairs(vertexFaces[i]) do
            if faceAlive[faceIndex] then
                local face = faces[faceIndex]
                for corner = 1, 3 do
                    local other = face[corner]
                    if other ~= i and alive[other] then offer(i, other) end
                end
            end
        end
    end

    -- Is this collapse, together with its mirror, safe to apply?
    local function folds(i, j)
        i, j = orient(i, j)
        local x, y, z = collapseTarget(i, j)
        return wouldFlip(i, j, x, y, z) or wouldFlip(j, i, x, y, z)
    end

    -- A backstop, not the termination condition -- the no-progress counter
    -- below is. Generous on purpose: refused collapses are retried at a
    -- penalty, so the pop count legitimately runs to many times the face
    -- count. Set too tight, this silently truncates reduction and every
    -- quality setting produces the same mesh.
    local guard = #faces * 200 + 100000
    -- Pops since the last successful collapse. Once every remaining candidate
    -- has been tried and refused, no amount of further popping helps.
    local sinceProgress, patience = 0, 0
    while true do
        guard = guard - 1
        if guard <= 0 then break end
        local edge = heapPop(heap)
        if not edge then break end
        sinceProgress = sinceProgress + 1
        patience = #heap + 64
        if sinceProgress > patience then break end
        -- Stop only when the mesh is inside budget AND the cheapest remaining
        -- collapse would actually cost something. Flat regions keep collapsing
        -- past the budget because they cost nothing to lose.
        if liveFaces <= targetFaces and edge.real > maxError then break end
        local i, j = edge.i, edge.j
        if alive[i] and alive[j] and i ~= j then
            -- Lazy invalidation: recompute and requeue if this entry is stale.
            local current = edgeCost(i, j)
            if math.abs(current - edge.real) > 1e-12 then
                heapPush(heap, { i = i, j = j, cost = current, real = current })
            else
                local mi, mj = mirror[i], mirror[j]
                local mirrored = mi and mj and alive[mi] and alive[mj] and mi ~= mj
                if folds(i, j) or (mirrored and folds(mi, mj)) then
                    -- Requeue at a penalty so it is retried only after
                    -- everything cheaper: a fold often stops being a fold once
                    -- a neighbour collapses, and simply dropping these stalls
                    -- reduction far above budget. Termination comes from the
                    -- no-progress counter below, NOT from the budget -- relying
                    -- on the budget is what made this loop hang when every
                    -- remaining collapse was refused.
                    heapPush(heap, { i = i, j = j, cost = current + 1e6, real = current })
                else
                    sinceProgress = 0
                    performCollapse(i, j)
                    -- The far seam takes the same step, and takes it now: a
                    -- mirrored pair that reduced at different moments would be
                    -- priced against different neighbourhoods and diverge.
                    if mirrored then performCollapse(mi, mj) end
                end
            end
        end
    end

    -- Compact.
    local remap, outVertices = {}, {}
    for index = 1, #vertices do
        if alive[index] then
            outVertices[#outVertices + 1] = vertices[index]
            remap[index] = #outVertices
        end
    end
    local outFaces = {}
    for faceIndex, face in ipairs(faces) do
        if faceAlive[faceIndex] then
            local a, b, c = remap[face[1]], remap[face[2]], remap[face[3]]
            if a and b and c and a ~= b and b ~= c and a ~= c then
                outFaces[#outFaces + 1] = { a, b, c }
            end
        end
    end
    return { vertices = outVertices, faces = outFaces }
end

return decimate
