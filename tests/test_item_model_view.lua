-- Unit tests for 3D item model viewer (presentation/item_model_view.lua).

package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local item_presentation = require("presentation.item_presentation")
local item_model_view = require("presentation.item_model_view")

print("[TEST] Starting 3D item model viewer tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  [PASS] " .. msg)
    else
        failed = failed + 1
        print("  [FAIL] " .. msg)
    end
end

loader.init()

-------------------------------------------------- 1. Item & Shop row enrichment --

local hpTonic = loader.getItem(1) -- HP Tonic
local hpRow = item_presentation.enrich({ id = hpTonic.id, name = hpTonic.name }, hpTonic, loader)
check(hpRow.model == "assets/models/items/bottle_family__basis.obj",
    "Item scene: valid model path 'bottle_family__basis.obj' enriched on HP Tonic row")

local bonePlate = loader.getItem(6) -- Bone Plate (no model field)
local boneRow = item_presentation.enrich({ id = bonePlate.id, name = bonePlate.name }, bonePlate, loader)
check(boneRow.model == "",
    "Missing-model fallback: Bone Plate has empty model field on enriched row")

-------------------------------------------------- 2. Selection angle reset --

item_model_view.resetState("window_test")
local a0 = item_model_view.getRotationState("window_test", "modelA.obj", 0)
check(math.abs(a0 - 0.0) < 1e-5, "Initial angle for model A is 0")

local a1 = item_model_view.getRotationState("window_test", "modelA.obj", 1.0)
check(math.abs(a1 - 0.4) < 1e-4, "Angle advances by dt * 0.4 (got " .. tostring(a1) .. ")")

local b0 = item_model_view.getRotationState("window_test", "modelB.obj", 0.5)
check(math.abs(b0 - 0.0) < 1e-5, "Selection change to model B immediately resets angle to 0")

local a2 = item_model_view.getRotationState("window_test", "modelA.obj", 0.5)
check(math.abs(a2 - 0.0) < 1e-5, "Returning to model A resets angle to 0 rather than inheriting B's angle")

-------------------------------------------------- 3. Bounds fit calculation --

-- Tall model
local tallBounds = { minX = -1, maxX = 1, minY = -1, maxY = 1, minZ = -5, maxZ = 5 }
local center, halfW, halfH = item_model_view.calculateFit(tallBounds, 100, 100, 0.81)
check(math.abs(center[1] - 0) < 1e-5 and math.abs(center[2] - 0) < 1e-5 and math.abs(center[3] - 0) < 1e-5,
    "Tall model bounds center is at origin (0,0,0)")
local expectedHalfH = 5 / 0.81
check(math.abs(halfH - expectedHalfH) < 1e-4, "Tall model halfHeight fits vertical radius with 0.81 margin")
check(halfH >= 5 and halfW >= math.sqrt(2), "Tall model extents contain 3D bounds")

-- Long horizontal model
local wideBounds = { minX = -6, maxX = 6, minY = -2, maxY = 2, minZ = -1, maxZ = 1 }
local _, wideHalfW, wideHalfH = item_model_view.calculateFit(wideBounds, 100, 100, 0.81)
local horizRadius = math.sqrt(36 + 4) -- sqrt(40) ~ 6.32455
local expectedWideHalfH = horizRadius / 0.81
check(math.abs(wideHalfH - expectedWideHalfH) < 1e-4,
    "Wide horizontal model fits rotation-safe horizontal radius in 1:1 aspect ratio")

-- Wide and narrow viewport aspect ratios
local _, wideAspectW, wideAspectH = item_model_view.calculateFit(wideBounds, 200, 100, 0.81) -- aspect = 2.0
check(math.abs(wideAspectW - horizRadius / 0.81) < 1e-4, "Aspect ratio 2.0 fits horizontal radius across width")

local _, narrowAspectW, narrowAspectH = item_model_view.calculateFit(wideBounds, 100, 200, 0.81) -- aspect = 0.5
check(math.abs(narrowAspectH - (horizRadius / 0.5) / 0.81) < 1e-4, "Aspect ratio 0.5 fits horizontal radius across height")

-- Flat / tiny bounds
local tinyBounds = { minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0 }
local _, tinyHalfW, tinyHalfH = item_model_view.calculateFit(tinyBounds, 100, 100, 0.81)
check(tinyHalfH > 0 and tinyHalfW > 0, "Degenerate zero bounds calculated safely without division by zero")

-------------------------------------------------- 4. Canvas rendering test --
if love.graphics and love.graphics.isCreated() then
    local colorCanvas = love.graphics.newCanvas(100, 100)
    local depthCanvas = love.graphics.newCanvas(100, 100, { format = "depth24stencil8" })
    love.graphics.setCanvas({ colorCanvas, depthstencil = depthCanvas })
    love.graphics.clear(0, 0, 0, 0, 0, 1)
    item_model_view.draw(0, 0, 100, 100, "assets/models/items/silver_blade.obj", "test", 0)
    love.graphics.setCanvas()
    local imgData = colorCanvas:newImageData()
    local nonZeroAlpha = 0
    for py = 0, 99 do
        for px = 0, 99 do
            local r, g, b, a = imgData:getPixel(px, py)
            if a > 0 then nonZeroAlpha = nonZeroAlpha + 1 end
        end
    end
    check(nonZeroAlpha > 0, "Item model view renders non-zero alpha pixels to canvas (got " .. nonZeroAlpha .. " pixels)")
end

print("Item model view tests completed: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("item_model_view tests failed", 0) end
