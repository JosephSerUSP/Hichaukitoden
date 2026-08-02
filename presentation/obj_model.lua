-- Strict, deliberately small OBJ/MTL loader for static dungeon kit pieces.
-- Supports standard Y-up OBJ positions, UVs, normals, polygon triangulation,
-- negative indices, mtllib/usemtl, Kd and map_Kd. Parsed positions are
-- normalized to the engine's Z-up world coordinates. Unsupported geometry
-- fails at load time.
--
-- This is one producer of presentation/mesh.lua's representation; the geometry
-- compiler is the other. Vertex format, normal generation, material binding and
-- texture caching all live there, not here.
local mesh = require("presentation.mesh")

local obj_model = {}

local cache = {}

local function parseMtl(text)
    local materials, current = {}, nil
    for raw in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
        local line = raw:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        local op, rest = line:match("^(%S+)%s*(.*)$")
        if op == "newmtl" then
            if rest == "" then error("MTL newmtl needs a name", 0) end
            current = { color = { 1, 1, 1, 1 } }
            materials[rest] = current
        elseif op == "Kd" and current then
            local r, g, b = rest:match("^(%S+)%s+(%S+)%s+(%S+)$")
            if not r then error("MTL Kd needs three numbers", 0) end
            current.color = { assert(tonumber(r)), assert(tonumber(g)), assert(tonumber(b)), 1 }
        elseif op == "map_Kd" and current then
            if rest == "" then error("MTL map_Kd needs a path", 0) end
            current.texture = rest
        end
    end
    return materials
end

local function resolveIndex(value, count, label)
    local index = tonumber(value)
    if not index or index == 0 or index ~= math.floor(index) then
        error("OBJ " .. label .. " index is invalid: " .. tostring(value), 0)
    end
    if index < 0 then index = count + index + 1 end
    if index < 1 or index > count then
        error("OBJ " .. label .. " index out of range: " .. tostring(value), 0)
    end
    return index
end

local function objToWorld(x, y, z)
    -- OBJ exporters such as Blender's default preset write Y-up with forward
    -- along -Z. The dungeon world is Z-up with forward in its XY plane.
    return x, -z, y
end

function obj_model.parse(text, label)
    local positions, uvs, normals = {}, {}, {}
    local builder = mesh.newBuilder(label or "OBJ")
    local mtllib = nil
    local lineNumber = 0
    for raw in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]+") do
        lineNumber = lineNumber + 1
        local line = raw:gsub("#.*$", ""):match("^%s*(.-)%s*$")
        local op, rest = line:match("^(%S+)%s*(.*)$")
        if op == "v" then
            local x, y, z = rest:match("^(%S+)%s+(%S+)%s+(%S+)")
            if not x then error((label or "OBJ") .. ":" .. lineNumber .. " malformed vertex", 0) end
            x, y, z = objToWorld(assert(tonumber(x)), assert(tonumber(y)), assert(tonumber(z)))
            positions[#positions + 1] = { x, y, z }
        elseif op == "vt" then
            local u, v = rest:match("^(%S+)%s+(%S+)")
            if not u then error((label or "OBJ") .. ":" .. lineNumber .. " malformed UV", 0) end
            uvs[#uvs + 1] = { assert(tonumber(u)), 1 - assert(tonumber(v)) }
        elseif op == "vn" then
            local x, y, z = rest:match("^(%S+)%s+(%S+)%s+(%S+)")
            if not x then error((label or "OBJ") .. ":" .. lineNumber .. " malformed normal", 0) end
            x, y, z = objToWorld(assert(tonumber(x)), assert(tonumber(y)), assert(tonumber(z)))
            normals[#normals + 1] = { x, y, z }
        elseif op == "mtllib" then
            mtllib = rest
        elseif op == "usemtl" then
            builder:setMaterial(rest)
        elseif op == "f" then
            local refs = {}
            for token in rest:gmatch("%S+") do
                local p, t, n = token:match("^([^/]+)/?([^/]*)/?([^/]*)$")
                refs[#refs + 1] = {
                    p = resolveIndex(p, #positions, "position"),
                    t = t ~= "" and resolveIndex(t, #uvs, "UV") or nil,
                    n = n ~= "" and resolveIndex(n, #normals, "normal") or nil,
                }
            end
            if #refs < 3 then error((label or "OBJ") .. ":" .. lineNumber .. " face needs 3+ vertices", 0) end
            for i = 2, #refs - 1 do
                local tri, corners = { refs[1], refs[i], refs[i + 1] }, {}
                for index, ref in ipairs(tri) do
                    local p, uv, normal = positions[ref.p], uvs[ref.t] or { 0, 0 }, normals[ref.n]
                    corners[index] = {
                        p[1], p[2], p[3], uv[1], uv[2],
                        normal and normal[1], normal and normal[2], normal and normal[3],
                    }
                end
                builder:triangle(corners[1], corners[2], corners[3])
            end
        elseif op and op ~= "o" and op ~= "g" and op ~= "s" then
            error((label or "OBJ") .. ":" .. lineNumber .. " unsupported directive '" .. op .. "'", 0)
        end
    end
    local model = builder:build()
    model.mtllib = mtllib
    return model
end

function obj_model.load(path)
    if cache[path] then return cache[path] end
    local text = love.filesystem.read(path)
    if not text then error("OBJ model missing: " .. tostring(path), 0) end
    local parsed = obj_model.parse(text, path)
    local materials, base = {}, mesh.dirname(path)
    if parsed.mtllib then
        local mtlPath = mesh.joined(base, parsed.mtllib)
        local mtlText = love.filesystem.read(mtlPath)
        if not mtlText then error("OBJ material library missing: " .. mtlPath, 0) end
        materials = parseMtl(mtlText)
    end
    mesh.finalize(parsed, materials, base)
    parsed.path = path
    cache[path] = parsed
    return parsed
end

return obj_model
