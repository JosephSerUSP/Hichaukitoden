-- Radial topology: a cylindrical unwrap.
--
--   P(theta,z) = C + (baseRadius + offset(theta,z))
--                  * (cos(theta)X + sin(theta)Y) + zZ
--
-- The image's horizontal axis is angle, its vertical axis is object height,
-- and the grayscale field is distance from the central axis. Suitable when
-- each angle and height has at most ONE outer radius -- not for branching
-- props, deep undercuts, or several surfaces along the same radial line.
--
-- Emitted cell-centred with +Z up, which is how the renderer places a floor
-- fixture: local (0,0,0) is the centre of the owning cell at floor level.
local mesh = require("presentation.mesh")
local images = require("engine.geometry.images")

local radial = {}

-- The seam is the whole difficulty of this topology. Column `angularSegments`
-- is the SAME ring position as column 0, so it must not be sampled again from
-- the far edge of the image -- that reintroduces the discontinuity the wrap is
-- meant to remove. Vertices are generated once per segment and the last quad
-- closes back onto the first.
function radial.build(spec, height)
    local segments, rings = spec.angularSegments, spec.verticalSegments
    local builder = mesh.newBuilder(spec.label)
    builder:setMaterial(spec.id)

    local function ringRadius(segment, ring)
        local u = segment / segments
        if spec.symmetry and spec.symmetry.angular then
            -- A half unwrap mirrored about the seam: paint one side, get a
            -- bilaterally repeated form.
            u = u < 0.5 and u * 2 or (1 - u) * 2
        end
        local v = ring / rings
        local value = images.sample(height, u, v)
        local offset = spec.signedRadius and (value - 128 / 255) * 2 or value
        return spec.baseRadius + offset * spec.radiusScale
    end

    local function vertex(segment, ring)
        local theta = (segment % segments) / segments * math.pi * 2
        local r = ringRadius(segment % segments, ring)
        local z = (1 - ring / rings) * spec.height
        -- U runs the full turn so the texture wraps once; at the seam the
        -- final column addresses u = 1, which samples the same texels as u = 0
        -- in a wrapped atlas while keeping the quad non-degenerate.
        return { math.cos(theta) * r, math.sin(theta) * r, z,
            segment / segments, ring / rings }
    end

    for ring = 0, rings - 1 do
        for segment = 0, segments - 1 do
            local a = vertex(segment, ring)
            local b = vertex(segment + 1, ring)
            local c = vertex(segment + 1, ring + 1)
            local d = vertex(segment, ring + 1)
            -- Outward-facing winding: the player is outside the cylinder.
            radial.quad(builder, a, b, c, d)
        end
    end

    if spec.capTop then radial.cap(builder, spec, vertex, 0, true) end
    if spec.capBottom then radial.cap(builder, spec, vertex, rings, false) end

    return builder:build()
end

-- Skip degenerate triangles rather than raising: a profile may legitimately
-- taper to zero radius at its top or bottom, and that pinch is intentional --
-- unlike a zero-area face in authored art, which is a mistake.
function radial.triangle(builder, p, q, r)
    local ux, uy, uz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
    local vx, vy, vz = r[1] - p[1], r[2] - p[2], r[3] - p[3]
    local nx = uy * vz - uz * vy
    local ny = uz * vx - ux * vz
    local nz = ux * vy - uy * vx
    if nx * nx + ny * ny + nz * nz > 1e-18 then builder:triangle(p, q, r) end
end

function radial.quad(builder, a, b, c, d)
    radial.triangle(builder, a, b, c)
    radial.triangle(builder, a, c, d)
end

-- A cap is a triangle fan to the axis. Winding differs by end so both face
-- away from the solid interior.
function radial.cap(builder, spec, vertex, ring, top)
    local segments = spec.angularSegments
    local z = (1 - ring / spec.verticalSegments) * spec.height
    local centre = { 0, 0, z, 0.5, 0.5 }
    for segment = 0, segments - 1 do
        local a = vertex(segment, ring)
        local b = vertex(segment + 1, ring)
        if top then
            radial.triangle(builder, centre, a, b)
        else
            radial.triangle(builder, centre, b, a)
        end
    end
end

return radial
