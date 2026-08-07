-- engine/model_census_review.lua
-- Deterministic in-engine review harness for the Second Rite procedural model census.
--
-- v2 corrects the invalidated 2026-08-06 pass:
--   * production-correct placement adapters (grid 'o', material lookups, real wall cells)
--   * primary neutral-gray diagnostic context + legacy First Stratum context
--   * oblique camera orbits the target instead of turning away from it
--   * pre-matrix model-vs-control smoke gate for every placement adapter
--   * structured skip accounting (functional placement is an invariant, not an art context)
--   * failure/index journals that distinguish declared paths from successfully written PNGs
--
-- The only visual authority is presentation.viewport_3d.draw(session).

local model_census_review = {}

local json = require("data.json")
local session = require("engine.session")
local viewport_3d = require("presentation.viewport_3d")
local obj_model = require("presentation.obj_model")

local REVIEW_WIDTH, REVIEW_HEIGHT = 256, 240
local REVIEW_GRID_W, REVIEW_GRID_H = 13, 13
local ANCHOR_X, ANCHOR_Y = 7, 6 -- 1-based grid cell used for all fixtures
local CENSUS_FEATURE_ID = "census_review_feature"
local SMOKE_CHANGED_PIXELS_MIN = 32
local SMOKE_MEAN_DELTA_MIN = 0.0005

local VALID_ADAPTERS = {
    event_model = true,
    floor_feature_model = true,
    wall_feature_model = true,
    opening_model = true,
    large_floor_model = true,
}

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[deepCopy(k, seen)] = deepCopy(v, seen) end
    return out
end
model_census_review.deepCopy = deepCopy

local function getRepoRoot()
    return (love.filesystem.getWorkingDirectory() or "."):gsub("\\", "/")
end

local function shellQuote(path)
    if package.config:sub(1, 1) == "\\" then
        return '"' .. tostring(path):gsub('"', '""') .. '"'
    end
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function ensureDirNative(dirPath)
    if package.config:sub(1, 1) == "\\" then
        local normalized = dirPath:gsub("/", "\\")
        local ok = os.execute('cmd /c if not exist ' .. shellQuote(normalized) .. ' mkdir ' .. shellQuote(normalized))
        if ok == nil or ok == false then error("failed to create directory: " .. tostring(dirPath), 0) end
    else
        local ok = os.execute("mkdir -p " .. shellQuote(dirPath))
        if ok == nil or ok == false then error("failed to create directory: " .. tostring(dirPath), 0) end
    end
end

local function fileExistsNative(path)
    local f = io.open(path, "rb")
    if not f then return false end
    f:close()
    return true
end

local function writeNativeBinary(fullPath, binaryData)
    local dir = fullPath:match("^(.*)/[^/]+$")
    if dir then ensureDirNative(dir) end
    local f = assert(io.open(fullPath, "wb"), "failed to open native file for writing: " .. tostring(fullPath))
    f:write(binaryData)
    f:close()
end

local function writeNativeText(fullPath, textData)
    local dir = fullPath:match("^(.*)/[^/]+$")
    if dir then ensureDirNative(dir) end
    local f = assert(io.open(fullPath, "w"), "failed to open native file for writing: " .. tostring(fullPath))
    f:write(textData)
    f:close()
end

local function sha256String(str)
    if str == nil then return nil end
    local hashData = love.data.hash("sha256", str)
    return love.data.encode("string", "hex", hashData)
end

local function sha256File(filePath)
    local content = love.filesystem.read(filePath)
    if not content then
        local f = io.open(filePath, "rb")
        if not f then return nil end
        content = f:read("*a")
        f:close()
    end
    return sha256String(content)
end

local function getGitSha()
    local handle = io.popen("git rev-parse HEAD 2>nul")
    if not handle and package.config:sub(1, 1) ~= "\\" then handle = io.popen("git rev-parse HEAD 2>/dev/null") end
    if not handle then return "unknown" end
    local result = handle:read("*a") or ""
    handle:close()
    result = result:gsub("%s+", "")
    return result ~= "" and result or "unknown"
end

local function getGitStatus()
    local handle = io.popen("git status --porcelain 2>nul")
    if not handle and package.config:sub(1, 1) ~= "\\" then handle = io.popen("git status --porcelain 2>/dev/null") end
    if not handle then return "" end
    local result = handle:read("*a") or ""
    handle:close()
    return result
end

local function makeReviewGrid(width, height)
    local grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = (y == 1 or y == height or x == 1 or x == width) and "#" or "."
        end
    end
    return grid
end

local function findAssetState(manifest, assetId, stateName)
    for _, asset in ipairs(manifest.assets or {}) do
        if asset.asset_id == assetId then
            for _, st in ipairs(asset.states or {}) do
                if st.state == stateName then return asset, st end
            end
        end
    end
    return nil, nil
end

local function ruleMatches(rule, fields)
    local match = rule and rule.match or {}
    for key, expected in pairs(match) do
        if fields[key] ~= expected then return false end
    end
    return next(match) ~= nil
end

function model_census_review.skipReason(manifest, fields)
    for _, rule in ipairs(manifest.skip_rules or {}) do
        if ruleMatches(rule, fields) then
            return rule.id or "skip_rule", rule.reason or "explicit manifest exclusion"
        end
    end
    return nil, nil
end

function model_census_review.matrixAccounting(manifest)
    local full, required, skipped = 0, 0, 0
    local byRule = {}
    for _, asset in ipairs(manifest.assets or {}) do
        for _, st in ipairs(asset.states or {}) do
            for _, context in ipairs(st.contexts or {}) do
                for _, distance in ipairs(st.distances or {}) do
                    for _, angle in ipairs(st.angles or {}) do
                        for _, lighting in ipairs(st.lighting or {}) do
                            full = full + 1
                            local fields = {
                                asset_id = asset.asset_id,
                                state = st.state,
                                context = context,
                                distance = distance,
                                angle = angle,
                                lighting = lighting,
                            }
                            local ruleId = model_census_review.skipReason(manifest, fields)
                            if ruleId then
                                skipped = skipped + 1
                                byRule[ruleId] = (byRule[ruleId] or 0) + 1
                            else
                                required = required + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return { full = full, required = required, skipped = skipped, skipped_by_rule = byRule }
end

function model_census_review.validateManifest(manifest)
    assert(type(manifest) == "table" and type(manifest.assets) == "table", "malformed review manifest")
    local stateCount = 0
    local ids = {}
    for _, asset in ipairs(manifest.assets) do
        assert(type(asset.asset_id) == "string" and asset.asset_id ~= "", "asset without asset_id")
        assert(not ids[asset.asset_id], "duplicate asset id: " .. asset.asset_id)
        ids[asset.asset_id] = true
        assert(VALID_ADAPTERS[asset.placement_adapter], "unknown placement adapter for " .. asset.asset_id .. ": " .. tostring(asset.placement_adapter))
        for _, st in ipairs(asset.states or {}) do
            stateCount = stateCount + 1
            assert(type(st.model) == "string" and st.model:match("%.obj$"), "state without OBJ path: " .. asset.asset_id)
        end
    end
    assert(#manifest.assets == 16, "model census must contain 16 concepts")
    assert(stateCount == 25, "model census must contain 25 state products")
    local accounting = model_census_review.matrixAccounting(manifest)
    assert(accounting.full == (manifest.full_matrix_count or accounting.full), "full matrix count does not match manifest")
    assert(accounting.full == accounting.required + accounting.skipped, "matrix accounting invariant failed")
    return accounting
end

function model_census_review.verifyAndHashDependencies(manifestPath)
    manifestPath = manifestPath or "tools/asset-production/review_manifest.json"
    local manifestText = love.filesystem.read(manifestPath)
    if not manifestText then error("[model_census_review] manifest missing: " .. tostring(manifestPath), 0) end
    local manifest = json.decode(manifestText)
    local accounting = model_census_review.validateManifest(manifest)

    local fileHashes = {}
    local missing = {}
    local function requireHash(path)
        local hash = sha256File(path)
        if not hash then missing[#missing + 1] = path else fileHashes[path] = hash end
    end

    requireHash(manifestPath)
    requireHash("assets/authoring/second_rite_census/asset-set.json")
    requireHash("assets/tilesets/dungeon_001.png")
    requireHash("data/tilesets.json")
    requireHash("data/maps.json")
    requireHash("data/engine.json")
    requireHash("presentation/viewport_3d.lua")
    requireHash("presentation/obj_model.lua")
    requireHash("presentation/mesh.lua")

    local verifiedProducts = 0
    for _, asset in ipairs(manifest.assets) do
        for _, st in ipairs(asset.states or {}) do
            local objPath = st.model
            local objText = love.filesystem.read(objPath)
            if not objText then
                missing[#missing + 1] = objPath
            else
                requireHash(objPath)
                verifiedProducts = verifiedProducts + 1
                local objDir = objPath:match("^(.*)/[^/]+$") or ""
                for mtlName in objText:gmatch("mtllib%s+([^%s]+)") do
                    local mtlPath = (objDir ~= "" and (objDir .. "/") or "") .. mtlName
                    local mtlText = love.filesystem.read(mtlPath)
                    if not mtlText then
                        missing[#missing + 1] = mtlPath
                    else
                        requireHash(mtlPath)
                        local mtlDir = mtlPath:match("^(.*)/[^/]+$") or ""
                        for line in mtlText:gmatch("[^\r\n]+") do
                            if line:match("^%s*map_Kd%s+") then
                                -- OBJ/MTL map_Kd may carry options; the texture
                                -- filename is the final token for the census exports.
                                local mapKd = line:match("([^%s]+)%s*$")
                                if mapKd then
                                    local texPath = (mtlDir ~= "" and (mtlDir .. "/") or "") .. mapKd
                                    requireHash(texPath)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #missing > 0 then
        error("[model_census_review] preflight failed; missing dependencies: " .. table.concat(missing, ", "), 0)
    end
    return manifest, fileHashes, verifiedProducts, accounting
end

-- Returns the exact production-facing map inputs for one placement adapter.
-- All x/y fields stored in authored event/generated-feature data are 0-based,
-- while the review grid itself is a 1-based Lua array.
function model_census_review.buildReviewFixture(adapter, modelPath, includeModel)
    assert(VALID_ADAPTERS[adapter], "unknown placement adapter: " .. tostring(adapter))
    if includeModel == nil then includeModel = true end
    local grid = makeReviewGrid(REVIEW_GRID_W, REVIEW_GRID_H)
    local generatedFeatures, events = {}, {}
    local featureSpec = nil

    if adapter == "opening_model" then
        -- Production renderer derives openings ONLY from grid value 'o'.
        -- Left/right walls make this a north-south corridor (opening axis y).
        grid[ANCHOR_Y][ANCHOR_X] = "o"
        grid[ANCHOR_Y][ANCHOR_X - 1] = "#"
        grid[ANCHOR_Y][ANCHOR_X + 1] = "#"
        grid[ANCHOR_Y - 1][ANCHOR_X] = "."
        grid[ANCHOR_Y + 1][ANCHOR_X] = "."
    elseif adapter == "wall_feature_model" then
        -- Material lookup is attached to a REAL wall cell. South face remains
        -- exposed to the camera.
        grid[ANCHOR_Y][ANCHOR_X] = "#"
        grid[ANCHOR_Y + 1][ANCHOR_X] = "."
        featureSpec = { id = CENSUS_FEATURE_ID, role = "wall_feature" }
        if includeModel then featureSpec.model = modelPath end
        generatedFeatures[#generatedFeatures + 1] = {
            material = CENSUS_FEATURE_ID,
            x = ANCHOR_X - 1,
            y = ANCHOR_Y - 1,
        }
    elseif adapter == "floor_feature_model" then
        featureSpec = { id = CENSUS_FEATURE_ID, role = "floor_feature" }
        if includeModel then featureSpec.model = modelPath end
        generatedFeatures[#generatedFeatures + 1] = {
            material = CENSUS_FEATURE_ID,
            x = ANCHOR_X - 1,
            y = ANCHOR_Y - 1,
        }
    elseif adapter == "event_model" or adapter == "large_floor_model" then
        if includeModel then
            events[#events + 1] = {
                id = 900001,
                x = ANCHOR_X - 1,
                y = ANCHOR_Y - 1,
                model = modelPath,
                priority = "same",
            }
        end
    end

    return {
        grid = grid,
        generatedFeatures = generatedFeatures,
        events = events,
        featureSpec = featureSpec,
        anchor_grid_x = ANCHOR_X,
        anchor_grid_y = ANCHOR_Y,
        targetX = ANCHOR_X + 0.5,
        targetY = ANCHOR_Y + 0.5,
    }
end

local function conceptBoundSpan(asset)
    local span = 0
    for _, st in ipairs(asset.states or {}) do
        local ok, parsed = pcall(obj_model.load, st.model)
        if ok and parsed and parsed.bounds then
            local b = parsed.bounds
            span = math.max(span,
                math.abs((b.maxX or 0) - (b.minX or 0)),
                math.abs((b.maxY or 0) - (b.minY or 0)),
                math.abs((b.maxZ or 0) - (b.minZ or 0)))
        end
    end
    return span > 0 and span or 1.0
end

function model_census_review.distanceForFixture(distanceName, boundSpan)
    boundSpan = math.max(0.1, tonumber(boundSpan) or 1.0)
    if distanceName == "close" then return math.max(1.15, boundSpan * 0.9) end
    if distanceName == "one_cell" then return math.max(2.0, boundSpan * 1.35) end
    if distanceName == "far" then return math.max(3.5, boundSpan * 2.1) end
    error("unknown census camera distance: " .. tostring(distanceName), 0)
end

function model_census_review.buildCameraFixture(targetX, targetY, distanceName, angleName, boundSpan)
    local distance = model_census_review.distanceForFixture(distanceName, boundSpan)
    local px, py = targetX, targetY + distance
    local transitionDir, transitionDuration, transitionTimer = nil, nil, nil
    local effectiveYaw = 0.0
    if angleName == "oblique" then
        local d = distance / math.sqrt(2)
        -- Camera moves southwest while heading rotates halfway N -> E. The
        -- target therefore remains on the camera's NE view ray.
        px, py = targetX - d, targetY + d
        transitionDir = "turn_right"
        transitionDuration = 1.0
        transitionTimer = 0.5
        effectiveYaw = 45.0
    elseif angleName ~= "frontal" then
        error("unknown census camera angle: " .. tostring(angleName), 0)
    end
    return {
        playerX = px,
        playerY = py,
        playerDir = "N",
        targetX = targetX,
        targetY = targetY,
        nominalDistance = distanceName,
        actualAnchorDistance = distance,
        transitionDir = transitionDir,
        transitionDuration = transitionDuration,
        transitionTimer = transitionTimer,
        effectiveYawDeg = effectiveYaw,
    }
end

function model_census_review.cameraSignature(fixture, context, lighting, geometryIdentity)
    return table.concat({
        string.format("%.4f,%.4f", fixture.playerX, fixture.playerY),
        fixture.playerDir,
        string.format("%.4f,%.4f", fixture.targetX, fixture.targetY),
        fixture.transitionDir or "none",
        string.format("%.4f", fixture.transitionTimer or 0),
        string.format("%.1f", fixture.effectiveYawDeg or 0),
        fixture.nominalDistance,
        context,
        lighting,
        geometryIdentity or "review-bay-v2",
    }, "|")
end

function model_census_review.withFrozenTime(fn)
    local original = love.timer.getTime
    love.timer.getTime = function() return 0.0 end
    local results = { xpcall(fn, debug.traceback) }
    love.timer.getTime = original
    local ok = table.remove(results, 1)
    if not ok then error(results[1], 0) end
    return unpack(results)
end

local function makeNeutralTexture(baseTileset)
    local tw = baseTileset.tileWidth or 64
    local th = baseTileset.tileHeight or 64
    local data = love.image.newImageData(tw * 4, th * 4)
    data:mapPixel(function(_, y)
        -- Flat diagnostic values only: no pattern. A tiny luminance separation
        -- preserves floor/wall orientation without introducing texture noise.
        local row = math.floor(y / th)
        local v = (row == 3) and 0.40 or ((row == 0) and 0.50 or 0.46)
        return v, v, v, 1
    end)
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

local function makeEphemeralTileset(baseTileset, id, adapter, modelPath, includeModel, context, neutralTexture)
    local out = {
        id = id,
        tileWidth = baseTileset.tileWidth,
        tileHeight = baseTileset.tileHeight,
        base = deepCopy(baseTileset.base),
        doors = {},
        features = {},
    }
    if context == "neutral" then
        out.textureImage = neutralTexture
    else
        out.texture = baseTileset.texture
        out.heightMap = baseTileset.heightMap
        out.heightMapScale = deepCopy(baseTileset.heightMapScale)
        out.heightMapMeshColumns = baseTileset.heightMapMeshColumns
        out.heightMapMeshRows = baseTileset.heightMapMeshRows
        out.heightMapTriangleBudget = baseTileset.heightMapTriangleBudget
    end
    if adapter == "opening_model" then
        local spec = { id = "census_review_door", role = "door" }
        if includeModel then spec.model = modelPath end
        out.doors = { spec }
    elseif adapter == "floor_feature_model" or adapter == "wall_feature_model" then
        local spec = { id = CENSUS_FEATURE_ID, role = adapter == "floor_feature_model" and "floor_feature" or "wall_feature" }
        if includeModel then spec.model = modelPath end
        out.features = { spec }
    end
    return out
end

local function resolvedContextFog(map2, context, lighting)
    if lighting == "dim_fogged" then
        return {
            color = { 0.04, 0.04, 0.055 },
            startDist = 1.2,
            distance = 5.5,
            sharpness = 1.4,
            minFactor = 0.04,
            psxBands = 16,
            time = 0.0,
        }
    end
    if context == "neutral" then
        return {
            color = { 0.18, 0.18, 0.18 },
            startDist = 100.0,
            distance = 1000.0,
            sharpness = 1.0,
            minFactor = 1.0,
            psxBands = 16,
            time = 0.0,
        }
    end
    local fog = map2 and map2.fog and deepCopy(map2.fog) or nil
    if fog then fog.time = 0.0 end
    return fog
end

local function applyCamera(reviewSession, fixture)
    reviewSession.playerX = fixture.playerX
    reviewSession.playerY = fixture.playerY
    reviewSession.playerDir = fixture.playerDir
    reviewSession.transitionDir = fixture.transitionDir
    reviewSession.transitionDuration = fixture.transitionDuration
    reviewSession.transitionTimer = fixture.transitionTimer
end

local function makeReviewSession(loader, tilesetId, fixtureData, camera, context, lighting, map2)
    local s = session.GameSession.new(loader)
    s.mapGrid = fixtureData.grid
    s.generatedFeatures = fixtureData.generatedFeatures
    -- Intentionally NO session.openingCells: openings must come from grid 'o'.
    s.currentMapData = {
        id = -9001,
        title = "Model Census Review Bay",
        tileset = tilesetId,
        ceilingStyle = "solid",
        events = fixtureData.events,
        lightObjects = {},
        fog = resolvedContextFog(map2, context, lighting),
    }
    applyCamera(s, camera)
    return s
end

local function renderToImageData(reviewSession)
    local canvas = love.graphics.newCanvas(REVIEW_WIDTH, REVIEW_HEIGHT)
    local pushed = false
    local ok, result = xpcall(function()
        love.graphics.push("all")
        pushed = true
        love.graphics.setCanvas({ canvas, depth = true, stencil = true })
        love.graphics.clear(0, 0, 0, 1, true, true)
        love.graphics.setColor(1, 1, 1, 1)
        viewport_3d.draw(reviewSession)
        love.graphics.setCanvas()
        return canvas:newImageData()
    end, debug.traceback)
    love.graphics.setCanvas()
    if pushed then love.graphics.pop() end
    viewport_3d.invalidateStructure(reviewSession)
    if not ok then error(result, 0) end
    return result
end

local function writeImageData(path, imageData)
    writeNativeBinary(path, imageData:encode("png"):getString())
end

function model_census_review.imageDifference(a, b)
    assert(a:getWidth() == b:getWidth() and a:getHeight() == b:getHeight(), "image delta dimensions differ")
    local changed, total = 0, 0
    local pixels = a:getWidth() * a:getHeight()
    for y = 0, a:getHeight() - 1 do
        for x = 0, a:getWidth() - 1 do
            local ar, ag, ab, aa = a:getPixel(x, y)
            local br, bg, bb, ba = b:getPixel(x, y)
            local d = math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb) + math.abs(aa - ba)
            total = total + d
            if d > 0.05 then changed = changed + 1 end
        end
    end
    return { changed_pixels = changed, mean_abs_delta = total / (pixels * 4) }
end

local function runAdapterSmokeGate(loader, manifest, baseTileset, neutralTexture, map2, outDirAbs)
    local smoke = { version = 1, threshold = { changed_pixels = SMOKE_CHANGED_PIXELS_MIN, mean_abs_delta = SMOKE_MEAN_DELTA_MIN }, adapters = {} }
    for _, spec in ipairs(manifest.smoke_gate or {}) do
        local asset, st = findAssetState(manifest, spec.asset_id, spec.state)
        assert(asset and st, "smoke gate references unknown asset/state: " .. tostring(spec.asset_id) .. "/" .. tostring(spec.state))
        assert(asset.placement_adapter == spec.adapter, "smoke gate adapter mismatch for " .. spec.asset_id)
        local span = conceptBoundSpan(asset)
        local camera = model_census_review.buildCameraFixture(ANCHOR_X + 0.5, ANCHOR_Y + 0.5, "one_cell", "frontal", span)

        local images = {}
        for _, variant in ipairs({ { name = "control", includeModel = false }, { name = "model", includeModel = true } }) do
            local ephemId = "review_census_smoke_" .. spec.adapter .. "_" .. variant.name
            local fixture = model_census_review.buildReviewFixture(spec.adapter, st.model, variant.includeModel)
            loader.tilesets[ephemId] = makeEphemeralTileset(baseTileset, ephemId, spec.adapter, st.model, variant.includeModel, "neutral", neutralTexture)
            local s = makeReviewSession(loader, ephemId, fixture, camera, "neutral", "normal", map2)
            local ok, imageOrError = xpcall(function() return renderToImageData(s) end, debug.traceback)
            loader.tilesets[ephemId] = nil
            if not ok then error("adapter smoke render failed for " .. spec.adapter .. " (" .. variant.name .. "): " .. tostring(imageOrError), 0) end
            images[variant.name] = imageOrError
            local smokePath = outDirAbs .. "/smoke/" .. spec.adapter .. "__" .. variant.name .. ".png"
            writeImageData(smokePath, imageOrError)
        end

        local delta = model_census_review.imageDifference(images.control, images.model)
        local passed = delta.changed_pixels >= SMOKE_CHANGED_PIXELS_MIN and delta.mean_abs_delta >= SMOKE_MEAN_DELTA_MIN
        smoke.adapters[#smoke.adapters + 1] = {
            adapter = spec.adapter,
            asset_id = spec.asset_id,
            state = spec.state,
            changed_pixels = delta.changed_pixels,
            mean_abs_delta = delta.mean_abs_delta,
            passed = passed,
            control = "smoke/" .. spec.adapter .. "__control.png",
            model = "smoke/" .. spec.adapter .. "__model.png",
        }
        if not passed then
            writeNativeText(outDirAbs .. "/smoke.json", json.encode(smoke))
            error(string.format("CAPTURE INVALID: MODEL NOT VISIBLE for adapter %s (%d changed pixels, mean delta %.6f)",
                spec.adapter, delta.changed_pixels, delta.mean_abs_delta), 0)
        end
    end
    writeNativeText(outDirAbs .. "/smoke.json", json.encode(smoke))
    return smoke
end

local function appendJournal(file, record)
    file:write(json.encode(record) .. "\n")
    file:flush()
end

local function existingReviewCsvOrTemplate(csvPath, manifest)
    if fileExistsNative(csvPath) then return end
    local lines = { "asset_id,recognition,spatialFunction,styleIntegration,materialHierarchy,screenEconomy,emotionalFunction,verdict,notes" }
    for _, asset in ipairs(manifest.assets) do lines[#lines + 1] = asset.asset_id .. ",,,,,,,," end
    writeNativeText(csvPath, table.concat(lines, "\n") .. "\n")
end

function model_census_review.run(loader, options)
    options = options or {}
    local repoRoot = getRepoRoot()
    local outDirRel = options.output_root or "out/model-census-review"
    local outDirAbs = outDirRel:match("^[A-Za-z]:[/\\]") and outDirRel or (repoRoot .. "/" .. outDirRel)
    ensureDirNative(outDirAbs)

    print("[model_census_review] v2 preflight verification...")
    local manifest, fileHashes, verifiedProducts, accounting = model_census_review.verifyAndHashDependencies(options.manifest)
    print(string.format("[model_census_review] preflight OK: %d products; matrix %d full / %d required / %d skipped",
        verifiedProducts, accounting.full, accounting.required, accounting.skipped))

    local map2 = nil
    for _, m in ipairs(loader.maps or {}) do if tonumber(m.id) == 2 then map2 = m; break end end
    assert(map2, "First Stratum source map id 2 is missing")
    local baseTileset = assert(loader.tilesets and loader.tilesets.dungeon_default, "dungeon_default tileset missing")
    local neutralTexture = makeNeutralTexture(baseTileset)
    viewport_3d.init()

    local sourceCommit = getGitSha()
    local runMetadata = {
        harness_version = "2.0.0",
        branch = "agent/second-rite-100-model-census",
        commit = sourceCommit,
        dirty_working_tree = getGitStatus() ~= "",
        start_time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        repository_root = repoRoot,
        output_root = outDirAbs,
        resolution = { width = REVIEW_WIDTH, height = REVIEW_HEIGHT },
        presentation_source = {
            map_id = 2,
            map_title = map2.title,
            tileset_resolution = {
                authored = map2.tileset,
                effective = "dungeon_default",
                mechanism = map2.tileset and "authored" or "loader fallback",
            },
            effective_tileset_texture = baseTileset.texture,
            source_commit = sourceCommit,
            contexts = {
                neutral = "primary diagnostic; runtime-generated unpatterned gray atlas",
                first_stratum = "legacy contextual material pass; current dungeon_default is not target art direction",
            },
            map_fog = deepCopy(map2.fog),
        },
        file_hashes = fileHashes,
        full_matrix_count = accounting.full,
        required_capture_count = accounting.required,
        skipped_capture_count = accounting.skipped,
        skipped_by_rule = accounting.skipped_by_rule,
        captures_attempted = 0,
        captures_successful = 0,
        captures_failed = 0,
        captures_skipped = 0,
        smoke_gate = { status = "pending" },
    }
    writeNativeText(outDirAbs .. "/run.json", json.encode(runMetadata))
    existingReviewCsvOrTemplate(outDirAbs .. "/review.csv", manifest)

    local indexEntries = {}
    local capturedPairSignatures = {}
    local journal = assert(io.open(outDirAbs .. "/captures.jsonl", "w"))
    local originalGetTime = love.timer.getTime
    local okRun, errRun

    local function cleanupGlobalState()
        love.timer.getTime = originalGetTime
        pcall(love.graphics.setCanvas)
        pcall(love.graphics.setShader)
        pcall(love.graphics.setScissor)
        pcall(love.graphics.setBlendMode, "alpha")
        pcall(love.graphics.setWireframe, false)
        for id in pairs(loader.tilesets or {}) do
            if tostring(id):match("^review_census_") then loader.tilesets[id] = nil end
        end
    end

    okRun, errRun = xpcall(function()
        love.timer.getTime = function() return 0.0 end

        print("[model_census_review] running five-adapter model-vs-control smoke gate...")
        local smoke = runAdapterSmokeGate(loader, manifest, baseTileset, neutralTexture, map2, outDirAbs)
        runMetadata.smoke_gate = { status = "passed", adapters = smoke.adapters }
        writeNativeText(outDirAbs .. "/run.json", json.encode(runMetadata))

        for _, asset in ipairs(manifest.assets) do
            local span = conceptBoundSpan(asset)
            print(string.format("[model_census_review] %s (%s, bound span %.3f)", asset.asset_id, asset.placement_adapter, span))
            ensureDirNative(outDirAbs .. "/" .. asset.asset_id)

            for _, st in ipairs(asset.states or {}) do
                for _, context in ipairs(st.contexts or {}) do
                    for _, distance in ipairs(st.distances or {}) do
                        for _, angle in ipairs(st.angles or {}) do
                            for _, lighting in ipairs(st.lighting or {}) do
                                local fields = {
                                    asset_id = asset.asset_id, state = st.state, context = context,
                                    distance = distance, angle = angle, lighting = lighting,
                                }
                                local skipId, skipReason = model_census_review.skipReason(manifest, fields)
                                local filename = string.format("%s__%s__%s__%s__%s.png", context, distance, angle, lighting, st.state)
                                local relPath = outDirRel .. "/" .. asset.asset_id .. "/" .. filename
                                local absPath = outDirAbs .. "/" .. asset.asset_id .. "/" .. filename

                                if skipId then
                                    runMetadata.captures_skipped = runMetadata.captures_skipped + 1
                                    local skipped = {
                                        asset_id = asset.asset_id, display_name = asset.display_name, state = st.state,
                                        model = st.model, context = context, distance = distance, angle = angle, lighting = lighting,
                                        path = relPath, success = false, skipped = true,
                                        skip_rule = skipId, skip_reason = skipReason,
                                    }
                                    indexEntries[#indexEntries + 1] = skipped
                                    appendJournal(journal, skipped)
                                else
                                    runMetadata.captures_attempted = runMetadata.captures_attempted + 1
                                    local ephemId = table.concat({ "review_census", asset.asset_id, st.state, context, distance, angle, lighting }, "_")
                                    local fixtureData = model_census_review.buildReviewFixture(asset.placement_adapter, st.model, true)
                                    loader.tilesets[ephemId] = makeEphemeralTileset(baseTileset, ephemId, asset.placement_adapter, st.model, true, context, neutralTexture)
                                    local camera = model_census_review.buildCameraFixture(fixtureData.targetX, fixtureData.targetY, distance, angle, span)
                                    local s = makeReviewSession(loader, ephemId, fixtureData, camera, context, lighting, map2)
                                    local pairSig = model_census_review.cameraSignature(camera, context, lighting, "review-bay-v2:" .. asset.placement_adapter)
                                    local pairKey = table.concat({ asset.asset_id, context, distance, angle, lighting }, ":")
                                    if capturedPairSignatures[pairKey] then
                                        assert(capturedPairSignatures[pairKey] == pairSig, "paired state camera drift: " .. pairKey)
                                    else
                                        capturedPairSignatures[pairKey] = pairSig
                                    end

                                    local renderOk, imageOrError = xpcall(function() return renderToImageData(s) end, debug.traceback)
                                    loader.tilesets[ephemId] = nil
                                    local record = {
                                        asset_id = asset.asset_id, display_name = asset.display_name, state = st.state,
                                        model = st.model, placement_adapter = asset.placement_adapter,
                                        context = context, distance = distance, angle = angle, lighting = lighting,
                                        camera_fixture = camera, camera_signature = pairSig,
                                        target = { fixtureData.targetX, fixtureData.targetY },
                                        path = relPath, success = renderOk, skipped = false,
                                        error = renderOk and nil or tostring(imageOrError),
                                    }
                                    if renderOk then
                                        writeImageData(absPath, imageOrError)
                                        record.png_sha256 = sha256File(absPath)
                                        runMetadata.captures_successful = runMetadata.captures_successful + 1
                                    else
                                        runMetadata.captures_failed = runMetadata.captures_failed + 1
                                        print("[model_census_review] capture failed: " .. asset.asset_id .. "/" .. filename .. " :: " .. tostring(imageOrError))
                                    end
                                    indexEntries[#indexEntries + 1] = record
                                    appendJournal(journal, record)
                                end
                            end
                        end
                    end
                end
            end
        end
    end, debug.traceback)

    cleanupGlobalState()
    journal:close()

    runMetadata.end_time = os.date("!%Y-%m-%dT%H:%M:%SZ")
    if runMetadata.captures_skipped ~= runMetadata.skipped_capture_count then
        okRun = false
        errRun = (errRun and (tostring(errRun) .. "\n") or "") .. "skipped capture accounting mismatch"
    end
    if runMetadata.required_capture_count ~= runMetadata.captures_successful + runMetadata.captures_failed then
        okRun = false
        errRun = (errRun and (tostring(errRun) .. "\n") or "") .. "required capture accounting mismatch"
    end
    if runMetadata.full_matrix_count ~= runMetadata.required_capture_count + runMetadata.skipped_capture_count then
        okRun = false
        errRun = (errRun and (tostring(errRun) .. "\n") or "") .. "full matrix accounting mismatch"
    end
    runMetadata.complete = okRun and runMetadata.captures_failed == 0
    runMetadata.error = okRun and nil or tostring(errRun)

    writeNativeText(outDirAbs .. "/index.json", json.encode(indexEntries))
    writeNativeText(outDirAbs .. "/run.json", json.encode(runMetadata))

    print(string.format("[model_census_review] done: %d required = %d successful + %d failed; %d explicitly skipped",
        runMetadata.required_capture_count, runMetadata.captures_successful, runMetadata.captures_failed, runMetadata.captures_skipped))

    if not okRun then error("[model_census_review] harness aborted: " .. tostring(errRun), 0) end
    if runMetadata.captures_failed > 0 then error("[model_census_review] review incomplete: one or more required captures failed", 0) end
    return runMetadata
end

return model_census_review
