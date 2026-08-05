-- Reusable 3D item-model viewer for UI windows.
-- Displays low-poly OBJ item models in an orthographic turntable viewport with
-- retro vertex snapping, affine UV mapping, dithering, and fixed directional lighting.

local obj_model = require("presentation.obj_model")
local retro_mesh_shader = require("presentation.retro_mesh_shader")

local item_model_view = {}

local FALLBACK_PATH = "assets/models/items/placeholder_question.obj"
local ITEM_PRESENTATION_TILT = math.rad(10)

item_model_view.FALLBACK_PATH = FALLBACK_PATH
item_model_view.ITEM_PRESENTATION_TILT = ITEM_PRESENTATION_TILT

local itemShader = nil
local itemShaderError = nil

local canvasCache = {}        -- Keyed by "w,h" -> { color, depth }
local warnCache = {}          -- Keeps track of paths warned about once
local errorCache = {}         -- Keeps track of severe errors logged once
local rotationStates = {}     -- Keyed by stateKey, stores { selKey, angle }
local resolvedModelCache = {} -- Keyed by requestedPathKey -> { model, resolvedPath, usedFallback }

function item_model_view.clearCache()
    canvasCache = {}
    warnCache = {}
    errorCache = {}
    rotationStates = {}
    resolvedModelCache = {}
end

local function ensureItemShader()
    if itemShader ~= nil then return itemShader or nil end
    local ok, shaderOrErr = pcall(love.graphics.newShader, retro_mesh_shader.buildItemShader())
    if ok then
        itemShader = shaderOrErr
    else
        itemShaderError = tostring(shaderOrErr)
        itemShader = false
        print("[item_model_view] shader failed to compile: " .. itemShaderError)
    end
    return itemShader or nil
end

local function getCanvasBuffers(w, h)
    local key = math.floor(w) .. "," .. math.floor(h)
    if canvasCache[key] then return canvasCache[key] end
    local bw, bh = math.max(1, math.floor(w)), math.max(1, math.floor(h))
    local ok1, colorCanvas = pcall(love.graphics.newCanvas, bw, bh)
    local ok2, depthCanvas = pcall(love.graphics.newCanvas, bw, bh, { format = "depth24stencil8" })
    if not ok2 then
        ok2, depthCanvas = pcall(love.graphics.newCanvas, bw, bh, { format = "depth16" })
    end

    if not ok1 or not colorCanvas or not ok2 or not depthCanvas then
        return nil
    end

    colorCanvas:setFilter("nearest", "nearest")
    local entry = { color = colorCanvas, depth = depthCanvas }
    canvasCache[key] = entry
    return entry
end

function item_model_view.getRotationState(stateKey, selKey, dt)
    stateKey = stateKey or "default"
    selKey = selKey or ""
    local st = rotationStates[stateKey]
    if not st or st.selKey ~= selKey then
        st = { selKey = selKey, angle = 0 }
        rotationStates[stateKey] = st
    else
        dt = dt or love.timer.getDelta()
        st.angle = st.angle + dt * 0.4
    end
    return st.angle
end

function item_model_view.resetState(stateKey)
    if stateKey then rotationStates[stateKey] = nil end
end

function item_model_view.resolveModel(modelPath)
    local isFallbackRequest = not modelPath or type(modelPath) ~= "string" or modelPath == ""
    local requestedKey = isFallbackRequest and "<fallback>" or modelPath

    if resolvedModelCache[requestedKey] ~= nil then
        local entry = resolvedModelCache[requestedKey]
        return entry.model, entry.resolvedPath, entry.usedFallback
    end

    local model = nil
    local actualPath = nil

    if not isFallbackRequest then
        if love.filesystem.getInfo(modelPath) then
            local ok, result = pcall(obj_model.load, modelPath)
            if ok and result then
                model = result
                actualPath = modelPath
            else
                if not warnCache[modelPath] then
                    print("[item_model_view] warning: failed to load OBJ model '" .. tostring(modelPath) .. "': " .. tostring(result))
                    warnCache[modelPath] = true
                end
            end
        else
            if not warnCache[modelPath] then
                print("[item_model_view] warning: model file not found '" .. tostring(modelPath) .. "'")
                warnCache[modelPath] = true
            end
        end
    end

    if model then
        local entry = { model = model, resolvedPath = actualPath, usedFallback = false }
        resolvedModelCache[requestedKey] = entry
        return entry.model, entry.resolvedPath, entry.usedFallback
    end

    -- Fallback to placeholder question mark
    if resolvedModelCache[FALLBACK_PATH] ~= nil then
        local fbEntry = resolvedModelCache[FALLBACK_PATH]
        resolvedModelCache[requestedKey] = fbEntry
        return fbEntry.model, fbEntry.resolvedPath, fbEntry.usedFallback
    end

    if love.filesystem.getInfo(FALLBACK_PATH) then
        local ok, fallback = pcall(obj_model.load, FALLBACK_PATH)
        if ok and fallback then
            local fbEntry = { model = fallback, resolvedPath = FALLBACK_PATH, usedFallback = true }
            resolvedModelCache[FALLBACK_PATH] = fbEntry
            resolvedModelCache[requestedKey] = fbEntry
            return fbEntry.model, fbEntry.resolvedPath, fbEntry.usedFallback
        else
            if not errorCache[FALLBACK_PATH] then
                print("[item_model_view] error: fallback model failed to load '" .. FALLBACK_PATH .. "': " .. tostring(fallback))
                errorCache[FALLBACK_PATH] = true
            end
        end
    else
        if not errorCache[FALLBACK_PATH] then
            print("[item_model_view] error: fallback model missing '" .. FALLBACK_PATH .. "'")
            errorCache[FALLBACK_PATH] = true
        end
    end

    local failEntry = { model = nil, resolvedPath = nil, usedFallback = true }
    resolvedModelCache[FALLBACK_PATH] = failEntry
    resolvedModelCache[requestedKey] = failEntry
    return nil, nil, true
end

function item_model_view.calculateFit(bounds, width, height, fillRatio, tiltRadians)
    fillRatio = fillRatio or 0.81
    tiltRadians = tiltRadians or ITEM_PRESENTATION_TILT

    local minX, minY, minZ = bounds.minX or 0, bounds.minY or 0, bounds.minZ or 0
    local maxX, maxY, maxZ = bounds.maxX or 0, bounds.maxY or 0, bounds.maxZ or 0

    local cx = (minX + maxX) * 0.5
    local cy = (minY + maxY) * 0.5
    local cz = (minZ + maxZ) * 0.5

    local rx = math.max(math.abs(minX - cx), math.abs(maxX - cx))
    local ry = math.max(math.abs(minY - cy), math.abs(maxY - cy))
    local rz = math.max(math.abs(minZ - cz), math.abs(maxZ - cz))

    local cosT = math.abs(math.cos(tiltRadians))
    local sinT = math.abs(math.sin(tiltRadians))

    local tiltedX = rx * cosT + rz * sinT
    local tiltedY = ry
    local tiltedZ = rx * sinT + rz * cosT

    local horizontalRadius = math.max(1e-5, math.sqrt(tiltedX * tiltedX + tiltedY * tiltedY))
    local verticalRadius = math.max(1e-5, tiltedZ)

    local aspect = (width > 0 and height > 0) and (width / height) or 1.0
    local halfHeight = math.max(verticalRadius, horizontalRadius / aspect) / fillRatio
    local halfWidth = halfHeight * aspect

    return { cx, cy, cz }, halfWidth, halfHeight
end

function item_model_view.draw(x, y, w, h, modelPath, stateKey, selKey, dt)
    local model = item_model_view.resolveModel(modelPath)
    if not model then return end

    local shader = ensureItemShader()
    if not shader then return end

    local buffers = getCanvasBuffers(w, h)
    if not buffers then return end

    local angle = item_model_view.getRotationState(stateKey, selKey, dt)
    local center, halfWidth, halfHeight = item_model_view.calculateFit(model.bounds, w, h, 0.81, ITEM_PRESENTATION_TILT)

    -- Fixed light direction from upper-front-left in view space
    local lx, ly, lz = 0.4, -0.6, 0.7
    local llen = math.sqrt(lx*lx + ly*ly + lz*lz)
    lx, ly, lz = lx / llen, ly / llen, lz / llen

    local sx, sy, sw, sh = love.graphics.getScissor()

    love.graphics.push("all")

    local prevCanvas = love.graphics.getCanvas()
    love.graphics.setCanvas({ buffers.color, depthstencil = buffers.depth })
    love.graphics.setScissor()
    love.graphics.clear(0, 0, 0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("less", true)
    love.graphics.setShader(shader)

    shader:send("modelCenter", center)
    shader:send("modelTilt", ITEM_PRESENTATION_TILT)
    shader:send("modelAngle", angle)
    shader:send("halfWidth", halfWidth)
    shader:send("halfHeight", halfHeight)
    shader:send("targetWidth", w)
    shader:send("targetHeight", h)
    shader:send("vertexSnapPixels", 1.0)
    shader:send("ditherLevels", 32.0)
    shader:send("lightDir", { lx, ly, lz })

    for _, group in ipairs(model.groups or {}) do
        local col = group.color or { 1, 1, 1, 1 }
        shader:send("materialColor", { col[1] or 1, col[2] or 1, col[3] or 1 })
        if group.texture then
            group.mesh:setTexture(group.texture)
            shader:send("hasTexture", 1.0)
        else
            shader:send("hasTexture", 0.0)
        end
        love.graphics.draw(group.mesh)
    end

    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.setCanvas(prevCanvas)

    if sx ~= nil then
        love.graphics.setScissor(sx, sy, sw, sh)
    else
        love.graphics.setScissor()
    end

    -- Composite canvas to UI panel using white color
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(buffers.color, x, y)

    love.graphics.pop()
end

return item_model_view

