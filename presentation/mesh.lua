-- The one static-mesh representation the world renderer draws.
--
-- Every source of world geometry converges here before reaching the renderer:
-- hand-modelled OBJ kit pieces (presentation/obj_model.lua) and image-authored
-- plane/shell/radial assets (engine/geometry/). The renderer therefore needs no
-- knowledge of where a mesh came from, and there is exactly one place that
-- knows the vertex format, how normals are generated, and how a material binds
-- to a GPU mesh.
--
-- A built model is:
--   { groups = { { material, vertices, mesh, color, texture }, ... },
--     vertexCount = n,
--     bounds = { minX, minY, minZ, maxX, maxY, maxZ } }
--
-- Vertices are flat 12-float records in world axes (Z up, one unit = one map
-- cell): x, y, z, u, v, nx, ny, nz, r, g, b, a.
local mesh = {}

mesh.FORMAT = {
    { "VertexPosition", "float", 3 },
    { "VertexTexCoord", "float", 2 },
    { "VertexNormal", "float", 3 },
    { "VertexColor", "float", 4 },
}

local textureCache = {}

function mesh.dirname(path)
    return path:match("^(.*)/[^/]+$") or ""
end

-- Asset references inside a model may be written relative to the model file or
-- as an ordinary project path; a leading `assets/` marks the latter.
function mesh.joined(base, path)
    if path:match("^assets/") then return path end
    return base == "" and path or (base .. "/" .. path)
end

function mesh.faceNormal(a, b, c)
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length == 0 then error("mesh contains a degenerate face", 0) end
    return { nx / length, ny / length, nz / length }
end

-- Nearest-filtered and shared, so an atlas used by several models -- which is
-- the normal case for image-authored geometry -- is uploaded once.
function mesh.texture(path)
    if textureCache[path] then return textureCache[path] end
    if not love.filesystem.getInfo(path) then
        error("mesh texture missing: " .. path, 0)
    end
    local image = love.graphics.newImage(path)
    image:setFilter("nearest", "nearest")
    textureCache[path] = image
    return image
end

local Builder = {}
Builder.__index = Builder

-- Accumulates triangles into per-material groups. Producers supply geometry in
-- world axes; the builder owns grouping, normal generation and bounds.
function mesh.newBuilder(label)
    return setmetatable({
        label = label or "mesh",
        groups = {}, order = {}, material = "",
        min = { math.huge, math.huge, math.huge },
        max = { -math.huge, -math.huge, -math.huge },
    }, Builder)
end

function Builder:setMaterial(name)
    self.material = name or ""
end

function Builder:group()
    local existing = self.groups[self.material]
    if existing then return existing end
    local created = { material = self.material, vertices = {} }
    self.groups[self.material] = created
    self.order[#self.order + 1] = created
    return created
end

-- Each vertex is { x, y, z, u, v [, nx, ny, nz] }. A vertex without a normal
-- takes the triangle's generated face normal, which is what flat-shaded
-- authored geometry wants.
function Builder:triangle(a, b, c)
    -- Computed even when every vertex carries an authored normal: it is also
    -- the degeneracy check, and a zero-area triangle must fail loudly rather
    -- than reach the renderer as an invisible face.
    local generated = mesh.faceNormal(a, b, c)
    local vertices = self:group().vertices
    for _, vertex in ipairs({ a, b, c }) do
        local nx, ny, nz = vertex[6], vertex[7], vertex[8]
        if not nx then
            nx, ny, nz = generated[1], generated[2], generated[3]
        end
        for axis = 1, 3 do
            if vertex[axis] < self.min[axis] then self.min[axis] = vertex[axis] end
            if vertex[axis] > self.max[axis] then self.max[axis] = vertex[axis] end
        end
        vertices[#vertices + 1] = {
            vertex[1], vertex[2], vertex[3], vertex[4], vertex[5], nx, ny, nz,
            vertex[9] or 1, vertex[10] or 1, vertex[11] or 1, vertex[12] or 1,
        }
    end
end

function Builder:build()
    if #self.order == 0 then error(self.label .. " contains no faces", 0) end
    local count = 0
    for _, group in ipairs(self.order) do count = count + #group.vertices end
    return {
        groups = self.order, vertexCount = count,
        bounds = {
            minX = self.min[1], minY = self.min[2], minZ = self.min[3],
            maxX = self.max[1], maxY = self.max[2], maxZ = self.max[3],
        },
    }
end

-- Bind materials and upload. `materials` maps a material name to
-- { color = {r,g,b,a}, texture = path } or { color, image = <Drawable> };
-- `base` resolves relative texture paths. An `image` is used as-is, which is
-- how a composed surface passes the canvas it baked rather than a file that
-- does not exist on disk.
-- Kept separate from building so a model can be compiled and validated without
-- a graphics device.
function mesh.finalize(model, materials, base)
    for _, group in ipairs(model.groups) do
        local material = (materials or {})[group.material] or { color = { 1, 1, 1, 1 } }
        group.mesh = love.graphics.newMesh(mesh.FORMAT, group.vertices, "triangles", "static")
        group.color = material.color
        if material.image then
            group.texture = material.image
            group.mesh:setTexture(group.texture)
        elseif material.texture then
            group.texture = mesh.texture(mesh.joined(base or "", material.texture))
            group.mesh:setTexture(group.texture)
        end
    end
    return model
end

return mesh
