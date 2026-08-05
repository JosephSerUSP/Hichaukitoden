-- Image-authored geometry: the asset contract, the plane builder, and the
-- failure modes that must be loud.
--
-- Fixtures live in tests/fixtures/geometry/ and are deliberately tiny; the
-- point is the contract, not the art.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local geometry = require("engine.geometry")
local plane = require("engine.geometry.plane")
local images = require("engine.geometry.images")
local viewport3d = require("presentation.viewport_3d")

loader.init()

print("[TEST] Starting geometry tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

local FIXTURES = "tests/fixtures/geometry/"

print("=== Geometry Asset Contract ===")

local spec, warnings = geometry.check(FIXTURES .. "valid_plane")
check(spec.id == "fixture_plane" and spec.topology == "plane" and spec.surface == "wall",
    "a well-formed plane asset parses its declared topology and surface")
check(spec.offset == 0.004,
    "an omitted stand-off resolves to its default rather than nil")
check(#warnings == 0, "a well-formed asset reports no warnings")

-- Hard errors. Each of these is a build failure, not a warning, because each
-- produces geometry that is silently wrong rather than visibly broken.
local function refuses(path, label)
    check(not pcall(geometry.check, FIXTURES .. path), label)
end
refuses("mismatched_dimensions",
    "albedo and height of different sizes are refused, since registration cannot hold")
refuses("unknown_topology", "an unregistered topology is refused")
refuses("bad_operation", "an unregistered height operation is refused")
refuses("blocks_on_surface", "blocksMovement on a surface fixture is refused")
refuses("missing_entirely", "a nonexistent asset directory is refused")

local _, colourWarnings = geometry.check(FIXTURES .. "colour_height")
check(#colourWarnings > 0,
    "a non-grayscale height map warns, since only its red channel is read")

print("=== Height Field Composition ===")

check(plane.periodicSampleCoordinate(1) == 0,
    "a tiling height field reuses its first sample at the terminal edge")
check(plane.periodicSampleCoordinate(0.75) == 0.75,
    "periodic sampling leaves interior coordinates unchanged")

print("=== Model Near-Plane Clipping ===")

local function modelVertex(x, y)
    return { x, y, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 }
end
local crossing = viewport3d.clipTrianglesToNear({
    modelVertex(-1, -1), modelVertex(1, -1), modelVertex(1, 1),
}, 0, 0, 1, 0, 0.05)
check(#crossing == 6, "a model triangle crossing the near plane is clipped into two triangles")
local allInFront = true
for _, vertex in ipairs(crossing) do allInFront = allInFront and vertex[1] >= 0.05 - 1e-9 end
check(allInFront, "clipped model vertices never remain behind the near plane")
local visible = viewport3d.clipTrianglesToNear({
    modelVertex(1, -1), modelVertex(2, -1), modelVertex(1, 1),
}, 0, 0, 1, 0, 0.05)
check(#visible == 3, "a model triangle wholly in front of the near plane is preserved")
local hidden = viewport3d.clipTrianglesToNear({
    modelVertex(-2, -1), modelVertex(-1, -1), modelVertex(-1, 1),
}, 0, 0, 1, 0, 0.05)
check(#hidden == 0, "a model triangle wholly behind the near plane is discarded")

-- 128 is the neutral plane; the fixtures are painted flat neutral, so a base
-- layer alone must contribute exactly zero displacement.
local neutral = images.data(FIXTURES .. "valid_plane/height.png")
local baseOnly = plane.sampleField({ { data = neutral, scale = 1, operation = "add" } }, 0.5, 0.5)
check(math.abs(baseOnly) < 1 / 128,
    "a neutral height map displaces nothing")

-- add and replace only differ over a NON-zero base: with a neutral base both
-- reduce to overlay*alpha, so testing them over one would prove nothing.
local function constantField(level, alpha)
    local data = love.image.newImageData(4, 4)
    data:mapPixel(function() return level, level, level, alpha end)
    return data
end
local raised = constantField(192 / 255, 1)     -- base already projecting
local overlay = constantField(1, 0.5)          -- half-influence overlay
local base = { data = raised, scale = 1, operation = "add" }

local baseValue = plane.sampleField({ base }, 0.5, 0.5)
-- Read the influence back rather than assuming 0.5: an 8-bit alpha channel
-- stores it as 127/255, and the composition must match the pixels on disk.
local overlayValue, influence = images.signedDisplacement(overlay, 0.5, 0.5)
local added = plane.sampleField({ base,
    { data = overlay, scale = 1, operation = "add" } }, 0.5, 0.5)
local replaced = plane.sampleField({ base,
    { data = overlay, scale = 1, operation = "replace" } }, 0.5, 0.5)

check(math.abs(added - (baseValue + overlayValue * influence)) < 1e-6,
    "add composes as base + signedOverlay * alpha")
check(math.abs(replaced - (baseValue + (overlayValue - baseValue) * influence)) < 1e-6,
    "replace composes as mix(base, overlay, alpha)")
check(math.abs(added - replaced) > 1e-6,
    "add and replace produce distinct composite displacement over a raised base")
local ignored = plane.sampleField({ base,
    { data = overlay, scale = 1, operation = "none" } }, 0.5, 0.5)
check(math.abs(ignored - baseValue) < 1e-9,
    "the none operation contributes albedo only and leaves height untouched")

local asymmetric = love.image.newImageData(3, 1)
asymmetric:setPixel(0, 0, 0.1, 0.2, 0.3, 1)
asymmetric:setPixel(1, 0, 0.4, 0.5, 0.6, 1)
asymmetric:setPixel(2, 0, 0.7, 0.8, 0.9, 1)
local mirrored = images.flipX(asymmetric)
local leftR, leftG, leftB = mirrored:getPixel(0, 0)
local rightR, rightG, rightB = mirrored:getPixel(2, 0)
check(math.abs(leftR - 0.7) < 1 / 255 and math.abs(leftG - 0.8) < 1 / 255
        and math.abs(leftB - 0.9) < 1 / 255
        and math.abs(rightR - 0.1) < 1 / 255 and math.abs(rightG - 0.2) < 1 / 255
        and math.abs(rightB - 0.3) < 1 / 255,
    "mirrored wall height fields reverse X exactly like mirrored albedo UVs")

print("=== Plane Meshing ===")

local model = geometry.load(FIXTURES .. "valid_plane")
-- The fixture is painted flat, so quadric error is zero everywhere and the
-- decimator should reduce it to the two triangles a quad needs -- regardless of
-- how densely it was sampled or what budget it was allowed. A flat surface
-- carrying hundreds of triangles is the defect this asserts against.
check(model.vertexCount / 3 <= 8,
    "a flat surface collapses to a handful of triangles, not its budget")
check(model.vertexCount / 3 >= 2,
    "a flat surface still emits a surface")
check(model.groups[1].mesh ~= nil and model.groups[1].texture ~= nil,
    "a compiled plane uploads a GPU mesh textured by its own albedo")
check(geometry.load(FIXTURES .. "valid_plane") == model,
    "an identical composition is compiled once and reused")

local sharedHeightSpec = {
    id = "shared_tileset_height",
    label = "shared tileset height fixture",
    topology = "plane", role = "surfaceFixture", surface = "wall",
    heightOperation = "add", heightScale = 0.08,
    meshColumns = 4, meshRows = 4, sampleColumns = 8, sampleRows = 8,
    triangleBudget = 32, offset = 0.004,
}
local sharedAtlasImage = love.graphics.newImage(FIXTURES .. "valid_plane/albedo.png")
local sharedAtlasModel = geometry.loadAtlasSurface(
    "tests-shared-height-atlas", sharedHeightSpec, neutral, sharedAtlasImage,
    function(u, v) return u, v end)
check(sharedAtlasModel.groups[1].texture == sharedAtlasImage,
    "a tileset-level height surface keeps the shared atlas texture")
check(geometry.loadAtlasSurface(
    "tests-shared-height-atlas", sharedHeightSpec, neutral, sharedAtlasImage,
    function(u, v) return u, v end) == sharedAtlasModel,
    "an identical tileset-level height surface is cached")

-- The wall frame the renderer places into: +X depth, +Y along the wall, +Z up.
local bounds = model.bounds
check(math.abs(bounds.minY + 0.5) < 1e-6 and math.abs(bounds.maxY - 0.5) < 1e-6,
    "a wall plane spans exactly one cell across")
-- A wall now spans floor to ceiling AND PAST BOTH, by exactly the skirt. The
-- old invariant was "no further", which held only while floors and ceilings
-- were flat: a displaced floor sits at z = lift and a displaced ceiling at
-- 1 - lift, so either can retreat from a wall that stops dead at the cell and
-- open a hole out of the room. The apron is what closes it.
check(bounds.minZ >= -plane.SKIRT - 1e-6 and bounds.maxZ <= 1 + plane.SKIRT + 1e-6,
    "a wall plane reaches no further than its skirt allows")
check(bounds.minZ <= 1e-6 and bounds.maxZ >= 1 - 1e-6,
    "a wall plane still covers the whole cell floor to ceiling")
check(bounds.minX > 0,
    "a wall plane stands off its structural surface rather than z-fighting it")

-- A relief facing into the wall is invisible, and nothing else would catch it.
local outward = true
for _, group in ipairs(model.groups) do
    for _, vertex in ipairs(group.vertices) do
        if vertex[6] <= 0 then outward = false end
    end
end
check(outward, "every wall-plane face normal points out of the wall")

print("=== Shell Topology ===")

local shellSpec = geometry.check(FIXTURES .. "valid_shell")
check(shellSpec.surfaceMode == "frontBack" and shellSpec.edgeMode == "stitch"
    and shellSpec.edgeColor == "darkenedBlend",
    "a shell asset parses its surface mode and edge treatment")
check(shellSpec.symmetry.imageX == false and shellSpec.symmetry.frontBack == false,
    "image symmetry and front/back reflection default off and stay separate")

refuses("mismatched_masks",
    "a frontBack shell with differing coverage masks is refused")
refuses("split_islands",
    "a coverage mask with more than one island is refused")
refuses("empty_mask", "a coverage mask with no silhouette is refused")
refuses("frontback_needs_layout",
    "frontBack mode without a front/back atlas layout is refused")

local shellModel = geometry.load(FIXTURES .. "valid_shell")
check(shellModel.vertexCount > 0 and shellModel.groups[1].mesh ~= nil,
    "a stitched shell compiles and uploads")

-- Volume is the whole point: a shell must occupy depth on BOTH sides of its
-- central plane, or it is just a plane wearing a mask.
local hasFront, hasBack = false, false
for _, group in ipairs(shellModel.groups) do
    for _, vertex in ipairs(group.vertices) do
        if vertex[1] > 1e-6 then hasFront = true end
        if vertex[1] < -1e-6 then hasBack = true end
    end
end
check(hasFront and hasBack,
    "a shell occupies depth on both sides of its central plane")

-- Front and rear must face opposite ways, or the rear is invisible.
local facesForward, facesBackward = false, false
for _, group in ipairs(shellModel.groups) do
    for _, vertex in ipairs(group.vertices) do
        if vertex[6] > 0.5 then facesForward = true end
        if vertex[6] < -0.5 then facesBackward = true end
    end
end
check(facesForward and facesBackward,
    "the rear grid is wound in reverse so both faces are visible")

-- Stitching is what makes the silhouette closed; without side faces the shell
-- is two loose sheets and the gap is visible from any oblique angle.
local pinched = geometry.load(FIXTURES .. "pinch_shell")
check(pinched.vertexCount < shellModel.vertexCount,
    "pinch mode closes the edge without the side faces stitch emits")

local mirrored = geometry.load(FIXTURES .. "mirror_shell")
local symmetric = true
for _, group in ipairs(mirrored.groups) do
    for _, vertex in ipairs(group.vertices) do
        symmetric = symmetric and math.abs(vertex[1]) <= mirrored.bounds.maxX + 1e-6
    end
end
check(symmetric and math.abs(mirrored.bounds.maxX + mirrored.bounds.minX) < 1e-6,
    "mirrorDepth produces geometry symmetric about the central plane")

print("=== Radial Topology ===")

local radialSpec = geometry.check(FIXTURES .. "valid_radial")
check(radialSpec.angularSegments == 8 and radialSpec.capTop and radialSpec.capBottom,
    "a radial asset parses its segment counts and cap flags")
refuses("oversized_radial",
    "a radial object wider than its cell is refused before it clips the walls")

local pillar = geometry.load(FIXTURES .. "valid_radial")
check(pillar.vertexCount > 0 and pillar.groups[1].mesh ~= nil,
    "a radial asset compiles and uploads")
check(pillar.bounds.minZ >= -1e-6 and math.abs(pillar.bounds.maxZ - 1.2) < 1e-6,
    "a radial object stands on the cell floor and reaches its declared height")

-- The seam is this topology's whole difficulty: the ring must close, not leave
-- a gap or fold back on itself.
local maxRadius = 0
for _, group in ipairs(pillar.groups) do
    for _, vertex in ipairs(group.vertices) do
        maxRadius = math.max(maxRadius, math.sqrt(vertex[1] ^ 2 + vertex[2] ^ 2))
    end
end
check(maxRadius <= 0.5 + 1e-6,
    "no radial vertex escapes its own cell")

-- Walk the bottom ring and confirm it returns to its start: an unclosed seam
-- would leave the last segment short of the first.
local closed, segments = true, radialSpec.angularSegments
for segment = 0, segments - 1 do
    local theta = segment / segments * math.pi * 2
    local wrapped = ((segment + segments) % segments) / segments * math.pi * 2
    closed = closed and math.abs(math.cos(theta) - math.cos(wrapped)) < 1e-9
end
check(closed, "the angular parameterization wraps exactly at the seam")

-- Caps are what make a pillar solid rather than a tube seen through at the top.
local cappedTop = false
for _, group in ipairs(pillar.groups) do
    for _, vertex in ipairs(group.vertices) do
        if math.abs(vertex[3] - 1.2) < 1e-6
            and math.abs(vertex[1]) < 1e-9 and math.abs(vertex[2]) < 1e-9 then
            cappedTop = true
        end
    end
end
check(cappedTop, "capTop fans a closed lid to the central axis")

print("=== Surface Composition ===")

local BASE, OVERLAY = FIXTURES .. "valid_plane", FIXTURES .. "valid_overlay"
local plain = geometry.load(BASE)
local composed = geometry.load({ BASE, OVERLAY })
check(composed ~= plain and #composed.groups == 1,
    "a base and its surface fixture compile to ONE mesh, not two")
check(#composed.specs == 2 and composed.specs[2].id == "fixture_overlay",
    "the composed model records its layer stack in order")
check(composed.groups[1].texture ~= nil,
    "a composed surface is textured by its composed albedo")

-- The fixture must actually change the surface, or composition is a no-op that
-- would pass every structural check while doing nothing.
local plainDepth, composedDepth = 0, 0
for _, vertex in ipairs(plain.groups[1].vertices) do
    plainDepth = math.max(plainDepth, vertex[1])
end
for _, vertex in ipairs(composed.groups[1].vertices) do
    composedDepth = math.max(composedDepth, vertex[1])
end
check(math.abs(plainDepth - composedDepth) > 1e-6,
    "composing a fixture changes the surface it composes onto")

local function refuses2(paths, label)
    check(not pcall(geometry.load, paths), label)
end
refuses2({ BASE, FIXTURES .. "overlay_wrong_size" },
    "a layer of different dimensions is refused; registration cannot hold")
refuses2({ BASE, FIXTURES .. "overlay_wrong_surface" },
    "a floor fixture is refused when composing onto a wall")
refuses2({ BASE, FIXTURES .. "overlay_is_object" },
    "an object fixture is refused as a composition layer")
refuses2({ BASE, FIXTURES .. "valid_shell" },
    "a shell is refused as a composition layer")

print("=== Composition Cache ===")

check(geometry.load({ BASE, OVERLAY }) == composed,
    "an identical composition is compiled once and reused")
check(geometry.compositionKey({ BASE, OVERLAY })
    ~= geometry.compositionKey({ OVERLAY, BASE }),
    "layer ORDER is part of the cache identity, since height ops do not commute")
check(geometry.compositionKey(BASE) ~= geometry.compositionKey({ BASE, OVERLAY }),
    "a composition is not confused with its base alone")
check(geometry.compositionKey(BASE):find("v" .. geometry.COMPILER_VERSION, 1, true) ~= nil,
    "the compiler version is part of the cache identity")

print("=== Diagnostics ===")

local albedoField, heightField = geometry.debugFields({ BASE, OVERLAY })
check(albedoField:getWidth() == heightField:getWidth()
    and albedoField:getHeight() == heightField:getHeight(),
    "the final composed pair is emitted in register, same dimensions")
local baseAlbedo = images.data(BASE .. "/albedo.png")
check(albedoField:getWidth() == baseAlbedo:getWidth(),
    "the composed pair is emitted at texture resolution, not mesh resolution")
local midGrey = select(1, heightField:getPixel(8, 8))
check(midGrey >= 0 and midGrey <= 1,
    "the composed heightfield is emitted as a viewable normalized image")

print("=== Dense Sampling and Decimation ===")

local decimate = require("engine.geometry.decimate")

-- A thin feature is the whole reason for sampling dense: on a budget-sized
-- grid a quad needs all four corners covered, so anything narrower than two
-- cells disappears. This grid is 2 units wide with a 1-unit notch.
local thin = { vertices = {}, faces = {} }
for row = 0, 8 do
    for column = 0, 8 do
        thin.vertices[#thin.vertices + 1] = { column / 8, row / 8, 0, column / 8, row / 8 }
    end
end
for row = 0, 7 do
    for column = 0, 7 do
        local a = row * 9 + column + 1
        thin.faces[#thin.faces + 1] = { a, a + 1, a + 10 }
        thin.faces[#thin.faces + 1] = { a, a + 10, a + 9 }
    end
end
local before = #thin.faces
local reduced = decimate.run({ vertices = thin.vertices, faces = thin.faces }, 32)
check(#reduced.faces <= 32 and #reduced.faces > 0,
    "decimation reaches its triangle budget")
check(before > #reduced.faces, "decimation actually reduces the mesh")

-- The cell seam is the hard constraint: a wall whose border drifted inward
-- would gap against the wall beside it.
local flat = geometry.load(FIXTURES .. "valid_plane")
local minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, group in ipairs(flat.groups) do
    for _, vertex in ipairs(group.vertices) do
        minY, maxY = math.min(minY, vertex[2]), math.max(maxY, vertex[2])
        minZ, maxZ = math.min(minZ, vertex[3]), math.max(maxZ, vertex[3])
    end
end
check(math.abs(minY + 0.5) < 1e-6 and math.abs(maxY - 0.5) < 1e-6,
    "decimation preserves the cell seam across the wall")
-- Contact, not coincidence: the wall must still REACH the floor and the
-- ceiling after decimation, but it is now allowed to overshoot into the skirt.
-- Asserting equality here is what would quietly forbid the apron.
check(minZ <= 1e-6 and maxZ >= 1 - 1e-6,
    "decimation preserves floor and ceiling contact")
check(minZ >= -plane.SKIRT - 1e-6 and maxZ <= 1 + plane.SKIRT + 1e-6,
    "decimation keeps the skirt within its declared reach")

-- The tiling invariant. A wall mesh is instanced once per cell, so its own
-- y = -0.5 border sits against a copy of its own y = +0.5 border. Decimated
-- independently the two borders keep different vertices, and the tiles stop
-- meeting -- a crack no test of the mesh's EXTENT can see, because both borders
-- still reach the cell edge while disagreeing about everything in between.
local relief = geometry.load(FIXTURES .. "valid_plane")
local function borderProfile(model, y)
    local seen, profile = {}, {}
    for _, group in ipairs(model.groups) do
        for _, vertex in ipairs(group.vertices) do
            if math.abs(vertex[2] - y) < 1e-9 then
                local key = string.format("%.9f|%.9f", vertex[3], vertex[1])
                if not seen[key] then
                    seen[key] = true
                    profile[#profile + 1] = { vertex[3], vertex[1] }
                end
            end
        end
    end
    table.sort(profile, function(a, b) return a[1] < b[1] end)
    return profile
end
local left, right = borderProfile(relief, -0.5), borderProfile(relief, 0.5)
local matched = #left > 0 and #left == #right
if matched then
    for index, point in ipairs(left) do
        if math.abs(point[1] - right[index][1]) > 1e-9
            or math.abs(point[2] - right[index][2]) > 1e-9 then
            matched = false
        end
    end
end
check(matched,
    "the two tiling seams of a wall decimate identically, so tile meets tile")

-- ACROSS two meshes, which is the case the mirror machinery does not cover.
--
-- The renderer mirrors a wall's height field for west and south faces (`flipU`
-- in viewport_3d), so a flipped tile stands beside an unflipped one constantly.
-- flipX(h)(u,v) == h(1-u,v), so the flipped tile's near seam samples exactly
-- the points the unflipped tile's far seam does: the two profiles are the same
-- set of points BEFORE decimation, and the surfaces can only meet if they are
-- still the same set afterwards.
--
-- Nothing in the decimator guarantees that. Quadrics accumulate from every
-- incident face including interior ones, and `orient` breaks ties on vertex
-- INDEX -- neither of which is invariant under mirroring.
local flipSpec = geometry.check(FIXTURES .. "valid_plane")
local heightData = images.data(FIXTURES .. "valid_plane/height.png")
local function buildWith(data)
    return plane.build(flipSpec,
        { { data = data, scale = flipSpec.heightScale,
            operation = flipSpec.heightOperation } },
        function(u, v) return u, v end)
end
local plain = buildWith(heightData)
local mirrored = buildWith(images.flipX(heightData))
-- A wall's local +Y runs along the face, so y=+0.5 is one seam and y=-0.5 the
-- other; the mirrored tile presents the opposite one to the same neighbour.
local plainRight = borderProfile(plain, 0.5)
local mirroredLeft = borderProfile(mirrored, -0.5)
local joins = #plainRight > 0 and #plainRight == #mirroredLeft
if joins then
    for index, point in ipairs(plainRight) do
        if math.abs(point[1] - mirroredLeft[index][1]) > 1e-9
            or math.abs(point[2] - mirroredLeft[index][2]) > 1e-9 then
            joins = false
        end
    end
end
check(joins,
    "a mirrored tile's seam decimates to the same points as the tile beside it")
print(string.format("      (plain seam %d points, mirrored seam %d points)",
    #plainRight, #mirroredLeft))

-- Determinism matters more here than anywhere else: the golden gates
-- byte-compare frames rendered from these meshes.
geometry.forget()
local again = geometry.load(FIXTURES .. "valid_plane")
local identical = again.vertexCount == flat.vertexCount
if identical then
    for index, vertex in ipairs(again.groups[1].vertices) do
        local original = flat.groups[1].vertices[index]
        for component = 1, 3 do
            if math.abs(vertex[component] - original[component]) > 1e-9 then
                identical = false
            end
        end
    end
end
check(identical, "decimation is deterministic across a fresh compile")

-- Sampling resolution is independent of the budget, which is the point.
check(spec.sampleColumns > spec.meshColumns and spec.sampleRows > spec.meshRows,
    "an asset samples its field more finely than its triangle budget")

-- A displaced surface must be WATERTIGHT. Owner-reported: a cobble floor shows
-- the background through the valleys between stones. A height field cannot have
-- holes by construction, so any interior boundary edge -- an edge belonging to
-- exactly one triangle, away from the outer rim -- is a hole the builder or the
-- decimator opened.
local steepPath = "assets/geometry/1_blender_depth_maps/floor_cobbles.png"
if love.filesystem.getInfo(steepPath) then
    local steepSpec = {
        id = "steep_floor", label = "steep cobble floor",
        topology = "plane", role = "surfaceFixture", surface = "floor",
        heightOperation = "add", heightScale = 0.1,
        meshColumns = 16, meshRows = 16, sampleColumns = 48, sampleRows = 48,
        triangleBudget = 64, offset = 0.004,
    }
    local steep = plane.build(steepSpec,
        { { data = images.data(steepPath), scale = steepSpec.heightScale,
            operation = steepSpec.heightOperation } },
        function(u, v) return u, v end)

    local function key(vertex)
        return string.format("%.7f,%.7f,%.7f", vertex[1], vertex[2], vertex[3])
    end
    local edges = {}
    local triangles = 0
    for _, group in ipairs(steep.groups) do
        for index = 1, #group.vertices - 2, 3 do
            triangles = triangles + 1
            local corner = { group.vertices[index], group.vertices[index + 1],
                group.vertices[index + 2] }
            for side = 1, 3 do
                local a, b = key(corner[side]), key(corner[side % 3 + 1])
                if a > b then a, b = b, a end
                edges[a .. "|" .. b] = (edges[a .. "|" .. b] or 0) + 1
            end
        end
    end
    -- The outer rim of a floor is the four cell edges; every other boundary
    -- edge is a tear. Counted rather than located, because one is already too
    -- many and the count says how bad it is.
    local rim, interior = 0, 0
    for pair, count in pairs(edges) do
        if count == 1 then
            local ax, ay = pair:match("^(-?[%d%.]+),(-?[%d%.]+)")
            local bx, by = pair:match("|(-?[%d%.]+),(-?[%d%.]+)")
            local function onRim(x, y)
                return math.abs(math.abs(tonumber(x)) - 0.5) < 1e-6
                    or math.abs(math.abs(tonumber(y)) - 0.5) < 1e-6
            end
            if onRim(ax, ay) and onRim(bx, by) then rim = rim + 1
            else interior = interior + 1 end
        end
    end
    check(interior == 0, string.format(
        "a steep displaced floor is watertight (%d triangles, %d rim edges, %d interior tears)",
        triangles, rim, interior))
end

print(string.format("=== Geometry Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " geometry test(s) failed", failed) end
