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

print("=== Plane Meshing ===")

local model = geometry.load(FIXTURES .. "valid_plane")
check(model.vertexCount == 4 * 4 * 2 * 3,
    "a 4x4 grid emits two triangles per cell")
check(model.groups[1].mesh ~= nil and model.groups[1].texture ~= nil,
    "a compiled plane uploads a GPU mesh textured by its own albedo")
check(geometry.load(FIXTURES .. "valid_plane") == model,
    "an identical composition is compiled once and reused")

-- The wall frame the renderer places into: +X depth, +Y along the wall, +Z up.
local bounds = model.bounds
check(math.abs(bounds.minY + 0.5) < 1e-6 and math.abs(bounds.maxY - 0.5) < 1e-6,
    "a wall plane spans exactly one cell across")
check(bounds.minZ >= -1e-6 and bounds.maxZ <= 1 + 1e-6,
    "a wall plane spans floor to ceiling and no further")
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

print(string.format("=== Geometry Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " geometry test(s) failed", failed) end
