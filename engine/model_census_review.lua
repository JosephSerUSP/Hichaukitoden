-- engine/model_census_review.lua
-- Isolated Lua harness for Second Rite procedural model census in-engine review.
-- Exercises viewport_3d.draw directly using real camera, scale, fog, vertex snapping,
-- affine treatment, dithering, and First Stratum presentation settings.

local model_census_review = {}

local json = require("data.json")
local session = require("engine.session")
local exploration = require("engine.exploration")
local viewport_3d = require("presentation.viewport_3d")
local obj_model = require("presentation.obj_model")

local function getRepoRoot()
    -- Get absolute working directory of current run
    local cwd = love.filesystem.getWorkingDirectory()
    return cwd:gsub("\\", "/")
end

local function ensureDirNative(dirPath)
    -- Normalize slashes
    local normalized = dirPath:gsub("/", "\\")
    os.execute('cmd /c if not exist "' .. normalized .. '" mkdir "' .. normalized .. '"')
end

local function sha256String(str)
    if not str then return nil end
    local hashData = love.data.hash("sha256", str)
    return love.data.encode("string", "hex", hashData)
end

local function sha256File(filePath)
    local info = love.filesystem.getInfo(filePath)
    if not info then
        -- Try reading native file if outside love filesystem
        local f = io.open(filePath, "rb")
        if not f then return nil end
        local content = f:read("*a")
        f:close()
        return sha256String(content)
    end
    local content = love.filesystem.read(filePath)
    if not content then return nil end
    return sha256String(content)
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

local function getGitSha()
    local handle = io.popen("git rev-parse HEAD")
    local result = handle:read("*a") or ""
    handle:close()
    return result:gsub("%s+", "")
end

local function getGitStatus()
    local handle = io.popen("git status -sb")
    local result = handle:read("*a") or ""
    handle:close()
    return result
end

function model_census_review.verifyAndHashDependencies(manifestPath)
    manifestPath = manifestPath or "tools/asset-production/review_manifest.json"
    local manifestText = love.filesystem.read(manifestPath)
    if not manifestText then
        error("[model_census_review] manifest missing: " .. tostring(manifestPath))
    end
    local manifest = json.decode(manifestText)
    if not manifest or not manifest.assets then
        error("[model_census_review] malformed manifest: " .. tostring(manifestPath))
    end

    local fileHashes = {}
    fileHashes[manifestPath] = sha256String(manifestText)
    fileHashes["assets/authoring/second_rite_census/asset-set.json"] = sha256File("assets/authoring/second_rite_census/asset-set.json")
    fileHashes["assets/tilesets/dungeon_default.png"] = sha256File("assets/tilesets/dungeon_default.png")
    fileHashes["data/tilesets.json"] = sha256File("data/tilesets.json")
    fileHashes["presentation/viewport_3d.lua"] = sha256File("presentation/viewport_3d.lua")
    fileHashes["presentation/obj_model.lua"] = sha256File("presentation/obj_model.lua")

    local missingFiles = {}
    local verifiedCount = 0

    for _, asset in ipairs(manifest.assets) do
        for _, st in ipairs(asset.states or {}) do
            local objPath = st.model
            if not love.filesystem.getInfo(objPath) then
                table.insert(missingFiles, objPath)
            else
                fileHashes[objPath] = sha256File(objPath)
                verifiedCount = verifiedCount + 1
                local text = love.filesystem.read(objPath)
                if text then
                    for mtlName in text:gmatch("mtllib%s+([%w_%-%.]+)") do
                        local dir = objPath:match("^(.*)/[^/]+$") or ""
                        local mtlPath = (dir ~= "" and (dir .. "/") or "") .. mtlName
                        if not love.filesystem.getInfo(mtlPath) then
                            table.insert(missingFiles, mtlPath)
                        else
                            fileHashes[mtlPath] = sha256File(mtlPath)
                            local mtlText = love.filesystem.read(mtlPath)
                            if mtlText then
                                for mapKd in mtlText:gmatch("map_Kd%s+([%w_%-%.%/]+)") do
                                    local texPath = (dir ~= "" and (dir .. "/") or "") .. mapKd
                                    if not love.filesystem.getInfo(texPath) then
                                        table.insert(missingFiles, texPath)
                                    else
                                        fileHashes[texPath] = sha256File(texPath)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #missingFiles > 0 then
        error("[model_census_review] Preflight failed! Missing files: " .. table.concat(missingFiles, ", "))
    end

    return manifest, fileHashes, verifiedCount
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

function model_census_review.run(loader, options)
    options = options or {}
    local repoRoot = getRepoRoot()
    local outDirRel = "out/model-census-review"
    local outDirAbs = repoRoot .. "/" .. outDirRel
    ensureDirNative(outDirAbs)

    print("[model_census_review] Starting preflight verification...")
    local manifest, fileHashes, verifiedProducts = model_census_review.verifyAndHashDependencies()
    print("[model_census_review] Preflight OK: " .. verifiedProducts .. " state products verified and hashed.")

    -- Pinned First Stratum presentation source (Map 2)
    local map2 = nil
    for _, m in ipairs(loader.maps or {}) do
        if tonumber(m.id) == 2 then map2 = m; break end
    end
    local sourceCommit = getGitSha()
    local presentationSource = {
        map_id = 2,
        map_title = map2 and map2.title or "Floor 1: Entry Hall",
        tileset_resolution = {
            authored = map2 and map2.tileset or nil,
            effective = "dungeon_default",
            mechanism = "loader fallback",
        },
        fog = {
            color = { 0.05, 0.05, 0.08 },
            startDist = 2.0,
            distance = 10.0,
            sharpness = 1.2,
            minFactor = 0.05,
            bands = 16,
        },
        source_commit = sourceCommit,
    }

    local baseTileset = assert(loader.tilesets.dungeon_default, "dungeon_default tileset missing")
    local gameWidth, gameHeight = 256, 240
    viewport_3d.init()

    local runMetadata = {
        harness_version = "1.0.0",
        branch = "agent/second-rite-100-model-census",
        commit = sourceCommit,
        dirty_working_tree = getGitStatus():find("%f[%w]M%f[%W]") ~= nil or getGitStatus():find("%f[%w]%?%?%f[%W]") ~= nil,
        start_time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        repository_root = repoRoot,
        output_root = outDirAbs,
        resolution = { width = gameWidth, height = gameHeight },
        presentation_source = presentationSource,
        full_matrix_count = manifest.full_matrix_count or 900,
        file_hashes = fileHashes,
        captures_attempted = 0,
        captures_successful = 0,
        captures_failed = 0,
        captures_skipped = 0,
    }

    writeNativeText(outDirAbs .. "/run.json", json.encode(runMetadata))
    local jsonlFile = assert(io.open(outDirAbs .. "/captures.jsonl", "w"))

    local indexEntries = {}
    local capturedSignatures = {} -- For paired camera signature assertions

    local originalGetTime = love.timer.getTime
    local okRun, errRun = xpcall(function()
        -- Freeze timer to 0.0 for deterministic rendering
        love.timer.getTime = function() return 0.0 end

        for _, asset in ipairs(manifest.assets) do
            print(string.format("[model_census_review] Processing asset %s (%s, %s)...", asset.asset_id, asset.display_name, asset.placement_adapter))
            local assetOutDir = outDirAbs .. "/" .. asset.asset_id
            ensureDirNative(assetOutDir)

            -- Compute concept-level max bound span across all states to guarantee identical camera transforms
            local conceptBoundSpan = 0
            for _, st in ipairs(asset.states) do
                local okObj, parsedObj = pcall(obj_model.load, st.model)
                if okObj and parsedObj and parsedObj.bounds then
                    local b = parsedObj.bounds
                    local s = math.max(b.maxX - b.minX, b.maxY - b.minY, b.maxZ - b.minZ)
                    if s > conceptBoundSpan then conceptBoundSpan = s end
                end
            end
            if conceptBoundSpan <= 0 then conceptBoundSpan = 1.0 end

            for _, st in ipairs(asset.states) do
                local modelPath = st.model

                for _, ctxName in ipairs(st.contexts) do
                    for _, distName in ipairs(st.distances) do
                        for _, angleName in ipairs(st.angles) do
                            for _, lightName in ipairs(st.lighting) do
                                runMetadata.captures_attempted = runMetadata.captures_attempted + 1

                                -- Ephemeral tileset & session for this capture
                                local ephemId = "review_" .. asset.asset_id .. "_" .. st.state .. "_" .. ctxName .. "_" .. distName .. "_" .. angleName .. "_" .. lightName
                                loader.tilesets[ephemId] = {
                                    id = ephemId,
                                    texture = baseTileset.texture,
                                    tileWidth = baseTileset.tileWidth,
                                    tileHeight = baseTileset.tileHeight,
                                    base = baseTileset.base,
                                    doors = (asset.placement_adapter == "opening_model") and { { model = modelPath } } or {},
                                    features = {},
                                }

                                if asset.placement_adapter == "floor_feature_model" then
                                    table.insert(loader.tilesets[ephemId].features, {
                                        id = "census_feat", role = "floor_feature", geometry = modelPath,
                                    })
                                elseif asset.placement_adapter == "wall_feature_model" then
                                    table.insert(loader.tilesets[ephemId].features, {
                                        id = "census_feat", role = "wall_feature", geometry = modelPath,
                                    })
                                end

                                local width, height = 12, 12
                                local grid = makeReviewGrid(width, height)

                                -- Setup map layout and placement site
                                local anchorX, anchorY = 6, 6
                                local openingCells = {}
                                local generatedFeatures = {}
                                local events = {}

                                if asset.placement_adapter == "opening_model" then
                                    grid[anchorY][anchorX] = "."
                                    grid[anchorY - 1][anchorX] = "#"
                                    grid[anchorY + 1][anchorX] = "#"
                                    table.insert(openingCells, { x = anchorX - 1, y = anchorY - 1, axis = "y" })
                                elseif asset.placement_adapter == "wall_feature_model" then
                                    table.insert(generatedFeatures, { id = "census_feat", x = anchorX - 1, y = anchorY - 2, side = "north" })
                                elseif asset.placement_adapter == "floor_feature_model" then
                                    table.insert(generatedFeatures, { id = "census_feat", x = anchorX - 1, y = anchorY - 1 })
                                elseif asset.placement_adapter == "event_model" then
                                    table.insert(events, { id = 1, x = anchorX - 1, y = anchorY - 1, model = modelPath })
                                elseif asset.placement_adapter == "large_floor_model" then
                                    table.insert(events, { id = 1, x = anchorX - 1, y = anchorY - 1, model = modelPath })
                                end

                                local reviewSession = session.GameSession.new(loader)
                                reviewSession.mapGrid = grid
                                reviewSession.openingCells = openingCells
                                reviewSession.generatedFeatures = generatedFeatures
                                reviewSession.currentMapData = {
                                    tileset = ephemId,
                                    ceilingStyle = (ctxName == "neutral") and "solid" or (map2 and map2.ceilingStyle or "solid"),
                                    events = events,
                                    fog = (lightName == "dim_fogged") and {
                                        color = { 0.02, 0.02, 0.04 }, startDist = 1.0, distance = 5.0, sharpness = 1.5, minFactor = 0.02, bands = 16,
                                    } or presentationSource.fog,
                                }

                                -- Camera distance calculations using conceptBoundSpan
                                local distOffset = 1.5
                                if distName == "close" then
                                    distOffset = math.max(1.0, conceptBoundSpan * 0.8)
                                elseif distName == "one_cell" then
                                    distOffset = math.max(1.8, conceptBoundSpan * 1.2)
                                elseif distName == "far" then
                                    distOffset = math.max(3.0, conceptBoundSpan * 2.0)
                                end


                                -- Player camera positioning
                                reviewSession.playerX = anchorX + 0.5
                                reviewSession.playerY = anchorY + 0.5 + distOffset
                                reviewSession.playerDir = "N"

                                local effectiveYaw = 0.0
                                if angleName == "oblique" then
                                    reviewSession.transitionDir = "turn_right"
                                    reviewSession.transitionDuration = 1.0
                                    reviewSession.transitionTimer = 0.5
                                    effectiveYaw = 45.0
                                else
                                    reviewSession.transitionDir = nil
                                    reviewSession.transitionDuration = nil
                                    reviewSession.transitionTimer = nil
                                    effectiveYaw = 0.0
                                end

                                local cameraSig = string.format("%.2f:%.2f:%s:%.2f:%.2f:%s:%.2f:%.1f:%s:%s:%s",
                                    reviewSession.playerX, reviewSession.playerY, reviewSession.playerDir,
                                    anchorX + 0.5, anchorY + 0.5,
                                    reviewSession.transitionDir or "none", reviewSession.transitionTimer or 0.0,
                                    effectiveYaw, lightName, ctxName, modelPath)

                                local cameraPairSig = string.format("%.2f:%.2f:%s:%.2f:%.2f:%s:%.2f:%.1f:%s:%s",
                                    reviewSession.playerX, reviewSession.playerY, reviewSession.playerDir,
                                    anchorX + 0.5, anchorY + 0.5,
                                    reviewSession.transitionDir or "none", reviewSession.transitionTimer or 0.0,
                                    effectiveYaw, lightName, ctxName)

                                -- Paired-state camera signature check
                                local pairKey = asset.asset_id .. ":" .. ctxName .. ":" .. distName .. ":" .. angleName .. ":" .. lightName
                                if capturedSignatures[pairKey] then
                                    if capturedSignatures[pairKey] ~= cameraPairSig then
                                        error(string.format("[model_census_review] Paired state camera drift detected for %s! Expected %s, got %s",
                                            pairKey, capturedSignatures[pairKey], cameraPairSig))
                                    end
                                else
                                    capturedSignatures[pairKey] = cameraPairSig
                                end

                                local filename = string.format("%s__%s__%s__%s__%s.png", ctxName, distName, angleName, lightName, st.state)
                                local relPath = outDirRel .. "/" .. asset.asset_id .. "/" .. filename
                                local absPath = repoRoot .. "/" .. relPath

                                local renderOk, renderErr = pcall(function()
                                    local canvas = love.graphics.newCanvas(gameWidth, gameHeight)
                                    love.graphics.setCanvas({ canvas, depth = true, stencil = true })
                                    love.graphics.clear(0, 0, 0, 1, true, true)
                                    viewport_3d.draw(reviewSession)
                                    love.graphics.setCanvas()
                                    local pngBytes = canvas:newImageData():encode("png"):getString()
                                    writeNativeBinary(absPath, pngBytes)
                                end)

                                viewport_3d.invalidateStructure(reviewSession)

                                local record = {
                                    asset_id = asset.asset_id,
                                    display_name = asset.display_name,
                                    state = st.state,
                                    model = modelPath,
                                    context = ctxName,
                                    distance = distName,
                                    angle = angleName,
                                    lighting = lightName,
                                    effective_yaw_deg = effectiveYaw,
                                    camera_position = { reviewSession.playerX, reviewSession.playerY },
                                    camera_signature = cameraSig,
                                    path = relPath,
                                    success = renderOk,
                                    error = renderErr and tostring(renderErr) or nil,
                                }

                                jsonlFile:write(json.encode(record) .. "\n")
                                jsonlFile:flush()

                                if renderOk then
                                    runMetadata.captures_successful = runMetadata.captures_successful + 1
                                    table.insert(indexEntries, record)
                                else
                                    runMetadata.captures_failed = runMetadata.captures_failed + 1
                                    print(string.format("[model_census_review] Render failed for %s (%s): %s", asset.asset_id, filename, tostring(renderErr)))
                                end

                                -- Cleanup ephemeral tileset
                                loader.tilesets[ephemId] = nil
                            end
                        end
                    end
                end
            end
        end
    end, debug.traceback)

    -- Teardown & Global State Protection
    love.timer.getTime = originalGetTime
    love.graphics.setCanvas()
    love.graphics.setShader()
    love.graphics.setWireframe(false)
    viewport_3d.invalidateStructure()
    jsonlFile:close()

    if not okRun then
        print("[model_census_review] CRITICAL ERROR DURING HARNESS RUN:\n" .. tostring(errRun))
    end

    -- Write index.json
    writeNativeText(outDirAbs .. "/index.json", json.encode(indexEntries))

    -- Write blank review.csv template (non-destructive)
    local csvPath = outDirAbs .. "/review.csv"
    if not love.filesystem.getInfo("out/model-census-review/review.csv") and not io.open(csvPath, "r") then
        local csvLines = { "asset_id,recognition,spatialFunction,styleIntegration,materialHierarchy,screenEconomy,emotionalFunction,verdict,notes" }
        for _, asset in ipairs(manifest.assets) do
            table.insert(csvLines, string.format("%s,,,,,,,,", asset.asset_id))
        end
        writeNativeText(csvPath, table.concat(csvLines, "\n") .. "\n")
    end

    -- Update final run.json metadata
    runMetadata.end_time = os.date("!%Y-%m-%dT%H:%M:%SZ")
    runMetadata.required_capture_count = runMetadata.captures_attempted
    runMetadata.complete = okRun and (runMetadata.captures_failed == 0)

    writeNativeText(outDirAbs .. "/run.json", json.encode(runMetadata))

    print(string.format("[model_census_review] Completed. Attempted: %d, Successful: %d, Failed: %d",
        runMetadata.captures_attempted, runMetadata.captures_successful, runMetadata.captures_failed))

    if not okRun or runMetadata.captures_failed > 0 then
        error("[model_census_review] Run completed with errors or failed captures.")
    end

    return runMetadata
end

return model_census_review
