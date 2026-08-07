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

local celestialFossil = loader.getItem(53) -- Celestial Fossil (no model field)
local cfRow = item_presentation.enrich({ id = celestialFossil.id, name = celestialFossil.name }, celestialFossil, loader)
check(cfRow.model == "",
    "Missing-model fallback: Celestial Fossil has empty model field on enriched row")

-------------------------------------------------- 2. Fallback resolution tests --

item_model_view.clearCache()

local originalGetTime = love.timer.getTime
local testClock = 10.0
love.timer.getTime = function() return testClock end

-- Selected item with no model ("" or nil) resolves placeholder_question.obj
local fbModel, fbPath, fbUsed = item_model_view.resolveModel("")
check(fbModel ~= nil and fbPath == item_model_view.FALLBACK_PATH and fbUsed == true,
    "Selected item with no model ('') resolves placeholder_question.obj")

local nilModel, nilPath, nilUsed = item_model_view.resolveModel(nil)
check(nilModel ~= nil and nilPath == item_model_view.FALLBACK_PATH and nilUsed == true,
    "Selected item with nil model resolves placeholder_question.obj")

-- Selected item with invalid model path resolves placeholder_question.obj
local invModel, invPath, invUsed = item_model_view.resolveModel("assets/models/items/invalid_nonexistent_item.obj")
check(invModel ~= nil and invPath == item_model_view.FALLBACK_PATH and invUsed == true,
    "Selected item with invalid model path resolves placeholder_question.obj")

-- Caching test: consecutive call for invalid model path returns cached fallback without throwing
local cModel, cPath, cUsed = item_model_view.resolveModel("assets/models/items/invalid_nonexistent_item.obj")
check(cModel == invModel and cPath == invPath and cUsed == true,
    "Invalid model path resolution is cached rather than retried")

-------------------------------------------------- 3. Selection angle reset (Item Identity) --

item_model_view.clearCache()

local sharedObj = "assets/models/items/wind_charm.obj"
local selKey1 = "wind_charm:" .. sharedObj
local selKey2 = "light_amulet:" .. sharedObj

local a0 = item_model_view.getRotationState("window_test", selKey1)
check(math.abs(a0 - 0.0) < 1e-5, "Initial angle for Wind Charm is 0")

local sameTime = item_model_view.getRotationState("window_test", selKey1)
check(math.abs(sameTime - a0) < 1e-5, "Repeated lookup at the same clock time does not advance rotation")

testClock = 11.0
local a1 = item_model_view.getRotationState("window_test", selKey1)
check(math.abs(a1 - 0.4) < 1e-4, "Wind Charm angle follows one second of clock time at 0.4 rad/s (got " .. tostring(a1) .. ")")

local b0 = item_model_view.getRotationState("window_test", selKey2)
check(math.abs(b0 - 0.0) < 1e-5, "Selection change to Light Amulet (same OBJ) resets angle to 0")

testClock = 12.0
local a2 = item_model_view.getRotationState("window_test", selKey1)
check(math.abs(a2 - 0.0) < 1e-5, "Returning to Wind Charm resets angle to 0 rather than inheriting Light Amulet's angle")

item_model_view.resetRotationStates()
local resetAngle = item_model_view.getRotationState("window_test", selKey1)
check(math.abs(resetAngle - 0.0) < 1e-5, "Resetting rotation states restarts the selection clock")

love.timer.getTime = originalGetTime

-------------------------------------------------- 4. Tilt-fit calculation tests --

local tilt = item_model_view.ITEM_PRESENTATION_TILT
local cosT = math.abs(math.cos(tilt))
local sinT = math.abs(math.sin(tilt))

-- Tall bottle bounds
local bottleBounds = { minX = -1, maxX = 1, minY = -1, maxY = 1, minZ = -5, maxZ = 5 }
local bCenter, bHalfW, bHalfH = item_model_view.calculateFit(bottleBounds, 100, 100, 0.81, tilt)
local bTiltedX = 1 * cosT + 5 * sinT
local bTiltedY = 1
local bTiltedZ = 1 * sinT + 5 * cosT
local bHorizRad = math.sqrt(bTiltedX * bTiltedX + bTiltedY * bTiltedY)
local bVertRad = bTiltedZ
check(bHalfH >= bVertRad / 0.81 - 1e-4 and bHalfW >= bHorizRad / 0.81 - 1e-4,
    "Tall bottle fit includes local-Y tilt in extents")

-- Long horizontal sword bounds
local swordBounds = { minX = -6, maxX = 6, minY = -0.5, maxY = 0.5, minZ = -0.5, maxZ = 0.5 }
local _, sHalfW, sHalfH = item_model_view.calculateFit(swordBounds, 100, 100, 0.81, tilt)
local sTiltedX = 6 * cosT + 0.5 * sinT
local sTiltedY = 0.5
local sHorizRad = math.sqrt(sTiltedX * sTiltedX + sTiltedY * sTiltedY)
check(math.abs(sHalfH - sHorizRad / 0.81) < 1e-4,
    "Long horizontal sword fits tilted rotation-safe horizontal radius")

-- Flat charm bounds
local charmBounds = { minX = -2, maxX = 2, minY = -0.1, maxY = 0.1, minZ = -2, maxZ = 2 }
local _, cHalfW, cHalfH = item_model_view.calculateFit(charmBounds, 100, 100, 0.81, tilt)
check(cHalfH > 0 and cHalfW > 0, "Flat charm bounds fit safely with tilt")

-- Zero-sized bounds
local zeroBounds = { minX = 0, maxX = 0, minY = 0, maxY = 0, minZ = 0, maxZ = 0 }
local _, zHalfW, zHalfH = item_model_view.calculateFit(zeroBounds, 100, 100, 0.81, tilt)
check(zHalfH > 0 and zHalfW > 0, "Zero-sized bounds calculate safely without division by zero")

-- Aspect ratio fitting (square, wide, narrow)
local _, wAspectW, wAspectH = item_model_view.calculateFit(swordBounds, 200, 100, 0.81, tilt) -- aspect 2.0
check(math.abs(wAspectW - sHorizRad / 0.81) < 1e-4, "Wide viewport (aspect 2.0) fits tilted horizontal radius")

local _, nAspectW, nAspectH = item_model_view.calculateFit(swordBounds, 100, 200, 0.81, tilt) -- aspect 0.5
check(math.abs(nAspectH - (sHorizRad / 0.5) / 0.81) < 1e-4, "Narrow viewport (aspect 0.5) fits tilted horizontal radius across height")

local validator = require("engine.validator")

-------------------------------------------------- 5. Real validator tests --

local function validateWithItems(itemsList)
    local mockLoader = {}
    for k, v in pairs(loader) do mockLoader[k] = v end
    mockLoader.items = itemsList
    return pcall(validator.run, mockLoader)
end

-- Valid model
local okValid, errValid = validateWithItems({ { id = "valid_item", model = "assets/models/items/silver_blade.obj" } })
check(okValid == true, "Real validator: valid item model path passes validation")

-- Optional model field (missing model key)
local okNoModel, errNoModel = validateWithItems({ { id = "no_model_item" } })
check(okNoModel == true, "Real validator: item without model field passes validation")

-- Missing file
local okMissing, errMissing = validateWithItems({ { id = "missing_model_item", model = "assets/models/items/definitely_missing.obj" } })
check(okMissing == false and tostring(errMissing):find("resolves to no asset"),
    "Real validator: missing model asset yields 'resolves to no asset' problem")

-- Empty string
local okEmpty, errEmpty = validateWithItems({ { id = "empty_model_item", model = "" } })
check(okEmpty == false and tostring(errEmpty):find("must be a non-empty asset path", 1, true) ~= nil,
    "Real validator: empty model path string yields 'must be a non-empty asset path' problem")

-- Wrong type (number, boolean)
local okNum, errNum = validateWithItems({ { id = "numeric_model_item", model = 42 } })
check(okNum == false and tostring(errNum):find("must be a non-empty asset path", 1, true) ~= nil,
    "Real validator: numeric model path yields 'must be a non-empty asset path' problem without crashing")

local okBool, errBool = validateWithItems({ { id = "bool_model_item", model = true } })
check(okBool == false and tostring(errBool):find("must be a non-empty asset path", 1, true) ~= nil,
    "Real validator: boolean model path yields 'must be a non-empty asset path' problem without crashing")

-------------------------------------------------- 6. Graphics state protection & offset scissor regression test --

if love.graphics and love.graphics.isCreated() then
    love.graphics.setColor(0.8, 0.4, 0.2, 0.5)
    love.graphics.setScissor(150, 40, 80, 100)

    local screenCanvas = love.graphics.newCanvas(300, 300)
    love.graphics.setCanvas(screenCanvas)
    love.graphics.clear(0, 0, 0, 0)

    item_model_view.draw(150, 40, 80, 100, "assets/models/items/silver_blade.obj", "scissor_test_window", "scissor_test_item", 0)

    love.graphics.setCanvas()

    local r, g, b, a = love.graphics.getColor()
    local sx, sy, sw, sh = love.graphics.getScissor()

    check(math.abs(r - 0.8) < 1e-4 and math.abs(g - 0.4) < 1e-4 and math.abs(b - 0.2) < 1e-4 and math.abs(a - 0.5) < 1e-4,
        "Caller graphics color is restored after item_model_view.draw")
    check(sx == 150 and sy == 40 and sw == 80 and sh == 100,
        "Caller offset scissor is restored after item_model_view.draw")

    local imgData = screenCanvas:newImageData()
    local nonZeroAlpha = 0
    for py = 40, 139 do
        for px = 150, 229 do
            local _, _, _, alpha = imgData:getPixel(px, py)
            if alpha > 0 then nonZeroAlpha = nonZeroAlpha + 1 end
        end
    end
    check(nonZeroAlpha > 0, "Offset scissor regression test: model renders into offscreen canvas and composite pixels appear in destination region (" .. nonZeroAlpha .. " px)")
end

print("Item model view tests completed: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("item_model_view tests failed", 0) end
