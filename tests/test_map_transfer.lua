-- Map transfer used to be two things: a hardcoded `TELEPORT` action in
-- main.lua that could only ever descend one floor, and a LOAD_MAP command that
-- was declared interactive without being compiled -- so in a map or common
-- event it produced no node and the event silently stopped. These tests pin
-- the single remaining path.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local exploration = require("engine.exploration")
local formula = require("engine.formula")
local savegame = require("engine.savegame")
local usability = require("engine.usability")
local viewport3d = require("presentation.viewport_3d")
local objModel = require("presentation.obj_model")

print("[TEST] Starting map transfer tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local resolvedEventSprite = viewport3d.resolveEventSpritePath({ sprite = "wisp" })
check(type(resolvedEventSprite) == "string"
        and love.filesystem.getInfo(resolvedEventSprite) ~= nil,
    "3D event sprites resolve small-battler keys to an image path")
check(viewport3d.resolveEventSpritePath({ sprite = "assets/sprites/NPC00.png" })
        == "assets/sprites/NPC00.png",
    "3D event sprites preserve directly authored image paths")

local eastWestOpening = {
    { "#", "#", "#" },
    { ".", "o", "." },
    { "#", "#", "#" },
}
local northSouthOpening = {
    { "#", ".", "#" },
    { "#", "o", "#" },
    { "#", ".", "#" },
}
check(viewport3d.resolveOpeningAxis(eastWestOpening, 2, 2) == "x",
    "3D structural openings align across an east-west passage")
check(viewport3d.resolveOpeningAxis(northSouthOpening, 2, 2) == "y",
    "3D structural openings align across a north-south passage")
check(viewport3d.resolveOpeningAxis({ { "o" } }, 1, 1) == "x",
    "an isolated structural opening resolves deterministically")

local weightedPool = {
    { id = "common", weight = 2 },
    { id = "rare", weight = 1 },
}
check(viewport3d.resolveWeightedVariant(weightedPool, 1, 0, 1, 0).id == "common"
        and viewport3d.resolveWeightedVariant(weightedPool, 2, 0, 1, 0).id == "rare",
    "3D tileset pools resolve authored weights rather than array position")
check(viewport3d.resolveWeightedVariant(weightedPool, 77, 31).id
        == viewport3d.resolveWeightedVariant(weightedPool, 77, 31).id,
    "3D weighted variants are stable for one map cell")
check(viewport3d.resolveWeightedVariant({ { id = "default" } }, 4, 9).id == "default",
    "a tileset variant without an explicit weight defaults to one")

local tilesetResolver = require("engine.tileset_resolver")
local baseDungeonTileset = loader.tilesets.dungeon_default
local overrideMap = {
    tileset = "dungeon_default",
    tilesetOverride = {
        features = {
            { id = "wall_torch", injectProbability = 0.07 },
            { id = "floor_marker", role = "floor_feature", atlas = { 0, 0 },
                injectProbability = 0 },
        },
        doors = { { id = "dungeon_door", remove = true } },
    },
}
local resolvedOverride, overrideCacheKey = tilesetResolver.resolve(loader, overrideMap)
-- Looked up by id rather than by array position: the base tileset gains
-- fixtures over time, and an appended entry's index is not part of the
-- contract -- only "merge by id, append new ids, remove on request" is.
local function featureById(pool, id)
    for _, entry in ipairs(pool or {}) do
        if entry.id == id then return entry end
    end
end
local patchedTorch = featureById(resolvedOverride.features, "wall_torch")
check(patchedTorch and patchedTorch.injectProbability == 0.07
        and patchedTorch.emitsLight ~= nil
        and featureById(resolvedOverride.features, "floor_marker") ~= nil
        and #resolvedOverride.doors == 0,
    "sparse map tileset overrides merge, append and remove pool entries by id")
check(baseDungeonTileset.features[1].injectProbability == 0.33
        and #baseDungeonTileset.doors > 0 and overrideCacheKey ~= "dungeon_default",
    "map tileset overrides preserve immutable loader data and own a cache identity")

loader.tilesets.fixture_injection_test = {
    id = "fixture_injection_test",
    fixturePrefabs = {
        { id = "wall_beside_floor", where = { adjacent = "floor" },
            probability = { min = 0.5, max = 1, default = 1 } },
    },
    features = {
        { id = "wall_fixture", role = "wall_feature", atlas = { 0, 0 },
            prefab = "wall_beside_floor",
            emitsLight = { color = { 1, 0.5, 0.25 }, radius = 3, falloff = 2 } },
        { id = "floor_fixture", role = "floor_feature", atlas = { 0, 1 },
            injectProbability = 1 },
    },
}
local injectionGrid = {
    { "#", "#", "#", "#", "#" },
    { "#", ".", ".", ".", "#" },
    { "#", ".", "#", ".", "#" },
    { "#", ".", ".", ".", "#" },
    { "#", "#", "#", "#", "#" },
}
math.randomseed(2468)
local expectedRandom = math.random()
math.randomseed(2468)
local injectedFeatures, injectedLights = exploration.injectTilesetFeatures(
    injectionGrid, { tileset = "fixture_injection_test" })
local randomAfterInjection = math.random()
local injectedAgain = exploration.injectTilesetFeatures(
    injectionGrid, { tileset = "fixture_injection_test" })
check(#injectedFeatures > #injectedLights and #injectedLights > 0,
    "tileset injection places wall and floor fixtures but lights only emitters")
check(#injectedFeatures == #injectedAgain
        and injectedFeatures[1].x == injectedAgain[1].x
        and injectedFeatures[1].y == injectedAgain[1].y,
    "tileset fixture placement is deterministic per cell")
check(randomAfterInjection == expectedRandom,
    "tileset fixture injection consumes no gameplay RNG")
check(#injectedLights > 0,
    "a fixture prefab supplies its predicate and default injection probability")
local suppressedFixtures = exploration.injectTilesetFeatures(injectionGrid, {
    tileset = "fixture_injection_test",
    tilesetOverride = {
        features = {
            { id = "wall_fixture", injectProbability = 0 },
            { id = "floor_fixture", remove = true },
        },
    },
})
check(#suppressedFixtures == 0,
    "feature injection consumes the same sparse tileset override as rendering")
loader.tilesets.fixture_injection_test = nil

-- Solid fixtures must never cut the map. The danger is not the flag, it is that
-- the predicates placing fixtures know nothing about topology: one barrel in a
-- one-wide corridor strands everything past it.
loader.tilesets.solid_fixture_test = {
    id = "solid_fixture_test",
    features = {
        { id = "barrel", role = "floor_feature", atlas = { 0, 0 },
            injectProbability = 1, blocksMovement = true },
    },
}
-- Two rooms joined by a single one-wide corridor: every corridor cell is a cut
-- vertex, so a correct guard places nothing there and fills the rooms instead.
local pinchGrid = {
    { "#", "#", "#", "#", "#", "#", "#" },
    { "#", ".", ".", "#", ".", ".", "#" },
    { "#", ".", ".", ".", ".", ".", "#" },
    { "#", ".", ".", "#", ".", ".", "#" },
    { "#", "#", "#", "#", "#", "#", "#" },
}
local pinchMap = { tileset = "solid_fixture_test", spawn = { x = 1, y = 1 } }
local solidPlacements = exploration.injectTilesetFeatures(pinchGrid, pinchMap, {})
local blockedKeys, corridorBlocked = {}, false
for _, placement in ipairs(solidPlacements) do
    if placement.blocks then
        blockedKeys[placement.x .. "," .. placement.y] = true
        -- The single cell joining the two rooms: 1-indexed (4,3), stored 0-indexed.
        if placement.x == 3 and placement.y == 2 then corridorBlocked = true end
    end
end
check(not corridorBlocked,
    "a solid fixture is refused on the one-wide corridor joining two rooms")

-- And the invariant itself: with every accepted fixture in place, the map is
-- still fully walkable except for the fixture cells.
local function walkableFrom(grid, blocked, sx, sy)
    local seen, stack = { [sx .. "," .. sy] = true }, { { sx, sy } }
    local n = 1
    while #stack > 0 do
        local cell = table.remove(stack)
        for _, d in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
            local nx, ny = cell[1] + d[1], cell[2] + d[2]
            local key = nx .. "," .. ny
            if not seen[key] and grid[ny] and grid[ny][nx] and grid[ny][nx] ~= "#"
                    and not blocked[(nx - 1) .. "," .. (ny - 1)] then
                seen[key] = true
                n = n + 1
                stack[#stack + 1] = { nx, ny }
            end
        end
    end
    return n
end
local totalFloor = 0
for gy = 1, #pinchGrid do
    for gx = 1, #pinchGrid[gy] do
        if pinchGrid[gy][gx] ~= "#" then totalFloor = totalFloor + 1 end
    end
end
local blockedCount = 0
for _ in pairs(blockedKeys) do blockedCount = blockedCount + 1 end
check(blockedCount > 0
        and walkableFrom(pinchGrid, blockedKeys, 2, 2) == totalFloor - blockedCount,
    "every cell stays reachable except the ones solid fixtures occupy"
        .. " (floor=" .. totalFloor .. ", solid=" .. blockedCount .. ")")
loader.tilesets.solid_fixture_test = nil

-- The fixture map above is a hand-built pinch. Real generated dungeons are the
-- case that actually matters, and they caught a bug the fixture could not: an
-- earlier guard additionally required every PROTECTED cell to be reachable,
-- which silently refused every solid fixture on every real map, because
-- protected cells include event tiles that are walls or sit outside the walkable
-- component and so are never in the reachable set. The fixture map had no such
-- events, so it passed while the real game placed nothing at all.
--
-- Two assertions, and the first is what makes the second meaningful: fixtures
-- must actually BE placed, or "nothing is stranded" is trivially true.
for _, mapIndex in ipairs({ 2, 3, 4 }) do
    local realSession = sessionModule.GameSession.new(loader)
    local loadedReal = pcall(exploration.loadMap, realSession, mapIndex)
    if loadedReal and realSession.mapGrid then
        local realGrid = realSession.mapGrid
        local realBlocked, solidCount = {}, 0
        for _, placement in ipairs(realSession.generatedFeatures or {}) do
            if placement.blocks then
                realBlocked[(placement.x + 1) .. "," .. (placement.y + 1)] = true
                solidCount = solidCount + 1
            end
        end
        local floorCells = 0
        for gy = 1, #realGrid do
            for gx = 1, #realGrid[gy] do
                if realGrid[gy][gx] ~= "#" then floorCells = floorCells + 1 end
            end
        end
        -- Compare SETS, not counts. A count expectation of
        -- `reached - solidCount` silently assumes every solid fixture sits on a
        -- player-reachable cell; one placed in a pocket the player cannot get
        -- to makes the count higher than expected, which is harmless but reads
        -- as a failure. The property that actually matters is one-directional:
        -- nothing that was reachable becomes unreachable except the fixture
        -- cells themselves.
        local function floodSet(blockedSet)
            local seen = { [realSession.playerX .. "," .. realSession.playerY] = true }
            local stack = { { realSession.playerX, realSession.playerY } }
            while #stack > 0 do
                local cell = table.remove(stack)
                for _, d in ipairs({ { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }) do
                    local nx, ny = cell[1] + d[1], cell[2] + d[2]
                    local key = nx .. "," .. ny
                    if not seen[key] and realGrid[ny] and realGrid[ny][nx]
                            and realGrid[ny][nx] ~= "#" and not blockedSet[key] then
                        seen[key] = true
                        stack[#stack + 1] = { nx, ny }
                    end
                end
            end
            return seen
        end
        local before, after = floodSet({}), floodSet(realBlocked)
        local stranded = 0
        for key in pairs(before) do
            if not after[key] and not realBlocked[key] then stranded = stranded + 1 end
        end
        check(solidCount > 0,
            "map " .. mapIndex .. " actually places solid fixtures"
                .. " (solid=" .. solidCount .. " of " .. floorCells .. " floor cells)")
        check(stranded == 0,
            "map " .. mapIndex .. " strands nothing behind its solid fixtures"
                .. " (stranded=" .. stranded .. ")")
    end
end

local fixturePredicates = require("engine.fixture_predicates")
local predicateZones = {
    { id = "flooded", x = 1, y = 1, width = 2, height = 2 },
    { id = "crypt", cells = { { x = 2, y = 2 } } },
}
local generatedZones = {
    { x = 1, y = 1, tags = { "room" } },
    { x = 3, y = 3, tags = { "entrance" } },
}
local predicateContext = fixturePredicates.newContext(
    injectionGrid, { zones = predicateZones }, generatedZones)
fixturePredicates.addFeature(predicateContext, 2, 2, "torch")
check(fixturePredicates.matches({ all = {
        { zone = "flooded" }, { adjacent = "wall" },
        { ["not"] = { zone = "entrance" } },
    } }, predicateContext, 2, 2),
    "fixture predicates compose all/not across authored and generated zones")
check(fixturePredicates.matches({ any = {
        { zone = "missing" }, { adjacent = { feature = "torch", diagonal = true } },
    } }, predicateContext, 3, 3),
    "fixture predicates compose any with diagonal feature adjacency")
check(fixturePredicates.matches({ distance = { zone = "entrance", min = 4, max = 4 } },
        predicateContext, 2, 2)
        and fixturePredicates.matches({ distance = { feature = "torch", max = 2 } },
            predicateContext, 3, 3),
    "fixture distance targets zones and previously placed features")

local parsedKit = objModel.parse(love.filesystem.read("tests/fixtures/kit_piece.obj"), "kit fixture")
check(parsedKit.vertexCount == 6 and #parsedKit.groups == 1,
    "OBJ kit-piece loader triangulates a quad and accepts negative indices")
local loadedKit = objModel.load("tests/fixtures/kit_piece.obj")
check(loadedKit.vertexCount == 6 and loadedKit.groups[1].mesh ~= nil,
    "OBJ kit-piece loader builds a cached GPU mesh with its MTL material")
check(objModel.load("tests/fixtures/kit_piece.obj") == loadedKit,
    "OBJ kit-piece meshes are reused instead of rebuilt")
local malformedObjOk = pcall(objModel.parse, "v 0 0 0\nf 1 2 3\n", "bad fixture")
check(not malformedObjOk, "OBJ kit-piece loader fails loudly on invalid faces")

local baseModelTileset = loader.tilesets.dungeon_default
loader.tilesets.model_render_test = {
    id = "model_render_test",
    texture = baseModelTileset.texture,
    base = baseModelTileset.base,
    doors = { { id = "fixture", role = "door", weight = 1,
        model = "tests/fixtures/kit_piece.obj" } },
    features = {},
}
local modelSession = sessionModule.GameSession.new(loader)
modelSession.mapGrid = eastWestOpening
modelSession.currentMapData = { tileset = "model_render_test", ceilingStyle = "solid", events = {} }
modelSession.playerX, modelSession.playerY, modelSession.playerDir = 0, 1, "E"
local previousCanvas = love.graphics.getCanvas()
local modelCanvas = love.graphics.newCanvas(256, 240)
local modelRenderOk, modelRenderError = pcall(function()
    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(modelSession)
end)
love.graphics.setCanvas(previousCanvas)
local renderedModelDraws = viewport3d.getLastFrameStats().modelDraws or 0
check(modelRenderOk and renderedModelDraws == 1,
    "a model-backed opening renders through the live depth-tested world path"
        .. (modelRenderOk and (" (draws=" .. renderedModelDraws .. ")")
            or (": " .. tostring(modelRenderError))))
viewport3d.invalidateStructure(modelSession)

local wallModelSession = sessionModule.GameSession.new(loader)
wallModelSession.mapGrid = {
    { "#", "#", "#" },
    { ".", "#", "." },
    { "#", "#", "#" },
}
wallModelSession.currentMapData = {
    tileset = "model_render_test", ceilingStyle = "solid",
    events = { { id = 1, x = 1, y = 1, wallEvent = true, trigger = "bump" } },
}
wallModelSession.playerX, wallModelSession.playerY, wallModelSession.playerDir = 0, 1, "E"
local wallModelRenderOk, wallModelRenderError = pcall(function()
    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(wallModelSession)
end)
love.graphics.setCanvas(previousCanvas)
local wallModelDraws = viewport3d.getLastFrameStats().modelDraws or 0
check(wallModelRenderOk and wallModelDraws >= 1,
    "a wall-event door model resolves onto its visible wall face"
        .. (wallModelRenderOk and (" (draws=" .. wallModelDraws .. ")")
            or (": " .. tostring(wallModelRenderError))))
viewport3d.invalidateStructure(wallModelSession)
loader.tilesets.model_render_test = nil

loader.tilesets.model_fixture_render_test = {
    id = "model_fixture_render_test", texture = baseModelTileset.texture,
    base = baseModelTileset.base, doors = baseModelTileset.doors,
    features = {
        { id = "wall_model", role = "wall_feature", model = "tests/fixtures/kit_piece.obj" },
        { id = "floor_model", role = "floor_feature", model = "tests/fixtures/kit_piece.obj" },
        { id = "world_effect", role = "floor_feature", atlas = { 0, 0 },
            effect = "assets/effects/SecondRite/env_mist.efkefc",
            effectHeight = 0.25, effectMagnification = 0.15625 },
    },
}
local fixtureModelSession = sessionModule.GameSession.new(loader)
fixtureModelSession.mapGrid = wallModelSession.mapGrid
fixtureModelSession.currentMapData = {
    tileset = "model_fixture_render_test", ceilingStyle = "solid", events = {},
}
fixtureModelSession.generatedFeatures = {
    { x = 1, y = 1, material = "wall_model" },
    { x = 0, y = 1, material = "floor_model" },
    { x = 2, y = 1, material = "world_effect" },
}
fixtureModelSession.playerX, fixtureModelSession.playerY, fixtureModelSession.playerDir = 0, 1, "E"
local fixtureModelsOk, fixtureModelsError = pcall(function()
    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(fixtureModelSession)
end)
love.graphics.setCanvas(previousCanvas)
local fixtureModelDraws = viewport3d.getLastFrameStats().modelDraws or 0
check(fixtureModelsOk and fixtureModelDraws >= 2,
    "model-backed wall and floor fixtures share the live world model path"
        .. (fixtureModelsOk and (" (draws=" .. fixtureModelDraws .. ")")
            or (": " .. tostring(fixtureModelsError))))
check(fixtureModelsOk and (viewport3d.getLastFrameStats().worldEffectHandles or 0) == 1,
    "an authored fixture effect spawns in the world camera pass")
-- World effects need a view with RECEDING DEPTH to be observable at all. The
-- 3x3 fixture above faces a wall one cell away, so the depth buffer rejects
-- particles behind it and every effect measures as zero pixels no matter how
-- healthily it is emitting -- which is exactly how env_rain came to be recorded
-- as "produces no pixels through the perspective pass" when it does. Look down
-- a corridor instead.
local corridorGrid = {}
for corridorY = 1, 20 do
    corridorGrid[corridorY] = {
        "#", (corridorY == 1 or corridorY == 20) and "#" or ".", "#",
    }
end

-- Each effect is also sampled while it is ALIVE. Both ambient effects are
-- authored endless, so one milestone serves both; a finite effect would need
-- its own, because sampling past the end measures zero instances and reads as
-- a renderer failure rather than a finished effect.
local worldEffectCases = {
    { effect = "assets/effects/SecondRite/env_mist.efkefc", frames = 400, label = "mist" },
    { effect = "assets/effects/SecondRite/env_rain.efkefc", frames = 400, label = "rain" },
}

-- Each case gets its OWN tileset id. Rewriting one shared fixture's `effect`
-- field between cases made the second case reuse the first's cached resolved
-- structure -- so it reported a live handle that was really the previous,
-- already-stopped effect, and measured as one instance emitting nothing. That
-- is the engine's "loader data is shared and immutable" rule biting a test that
-- mutated it in place, not a renderer fault.
for caseIndex, case in ipairs(worldEffectCases) do
    local tilesetId = "world_effect_render_test_" .. caseIndex
    loader.tilesets[tilesetId] = {
        id = tilesetId, texture = baseModelTileset.texture,
        base = baseModelTileset.base, doors = baseModelTileset.doors,
        features = {
            { id = "world_effect", role = "floor_feature", atlas = { 0, 0 },
                effect = case.effect,
                effectHeight = 0.25, effectMagnification = 0.15625 },
        },
    }
    local effectSession = sessionModule.GameSession.new(loader)
    effectSession.mapGrid = corridorGrid
    effectSession.currentMapData = {
        tileset = tilesetId, ceilingStyle = "solid", events = {},
    }
    effectSession.generatedFeatures = { { x = 1, y = 6, material = "world_effect" } }
    effectSession.playerX, effectSession.playerY, effectSession.playerDir = 1, 1, "S"

    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(effectSession)      -- spawn frame: handle exists, nothing emitted
    love.graphics.setCanvas(previousCanvas)

    require("presentation.effekseer").update(case.frames / 60)
    local worldEffectInstances = require("presentation.effekseer").instanceCount()
    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(effectSession)
    love.graphics.setCanvas(previousCanvas)
    local withWorldEffect = modelCanvas:newImageData()

    -- The baseline draws the identical corridor through a distinct tileset that
    -- authors no effect, so the diff isolates the effect's pixels without
    -- editing loader data underneath a live cache.
    viewport3d.invalidateStructure(effectSession)
    require("presentation.effekseer").reset()
    local baselineId = tilesetId .. "_baseline"
    loader.tilesets[baselineId] = {
        id = baselineId, texture = baseModelTileset.texture,
        base = baseModelTileset.base, doors = baseModelTileset.doors,
        features = {
            { id = "world_effect", role = "floor_feature", atlas = { 0, 0 },
                effectHeight = 0.25, effectMagnification = 0.15625 },
        },
    }
    local baselineSession = sessionModule.GameSession.new(loader)
    baselineSession.mapGrid = corridorGrid
    baselineSession.currentMapData = {
        tileset = baselineId, ceilingStyle = "solid", events = {},
    }
    baselineSession.generatedFeatures = { { x = 1, y = 6, material = "world_effect" } }
    baselineSession.playerX, baselineSession.playerY, baselineSession.playerDir = 1, 1, "S"
    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(baselineSession)
    love.graphics.setCanvas(previousCanvas)
    local withoutWorldEffect = modelCanvas:newImageData()

    local effectPixels = 0
    for py = 0, 239 do
        for px = 0, 255 do
            local ar, ag, ab, aa = withWorldEffect:getPixel(px, py)
            local br, bg, bb, ba = withoutWorldEffect:getPixel(px, py)
            if ar ~= br or ag ~= bg or ab ~= bb or aa ~= ba then
                effectPixels = effectPixels + 1
            end
        end
    end
    check(worldEffectInstances > 0 and effectPixels > 0,
        "world-authored " .. case.label .. " is visible down a corridor at frame "
            .. case.frames .. " (instances=" .. worldEffectInstances
            .. ", pixels=" .. effectPixels .. ")")
    viewport3d.invalidateStructure(effectSession)
    viewport3d.invalidateStructure(baselineSession)
    require("presentation.effekseer").reset()
    require("presentation.effekseer").update(1 / 60)
    loader.tilesets[tilesetId] = nil
    loader.tilesets[baselineId] = nil
end

-- Ambient weather is a MAP-level effect, not a cell fixture: one handle for the
-- whole map, kept at the camera. Anchored to a cell it would stay behind the
-- player, and one endless placement costs ~1,900 of a 2,000 instance budget, so
-- a per-cell weather idiom starves every other effect (roadmap 6.5.1g).
loader.tilesets.ambient_render_test = {
    id = "ambient_render_test", texture = baseModelTileset.texture,
    base = baseModelTileset.base, doors = baseModelTileset.doors,
}
local ambientSession = sessionModule.GameSession.new(loader)
ambientSession.mapGrid = corridorGrid
ambientSession.currentMapData = {
    tileset = "ambient_render_test", ceilingStyle = "solid", events = {},
    ambientEffect = {
        effect = "assets/effects/SecondRite/env_rain.efkefc", height = 1.5,
    },
}
ambientSession.generatedFeatures = {}
ambientSession.playerX, ambientSession.playerY, ambientSession.playerDir = 1, 1, "S"
love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
love.graphics.clear(0, 0, 0, 1, true, true)
viewport3d.draw(ambientSession)
love.graphics.setCanvas(previousCanvas)
local ambientStats = viewport3d.getLastFrameStats()
check(ambientStats.ambientEffect == true and (ambientStats.worldEffectHandles or 0) == 0,
    "a map-level ambient effect spawns one handle and no cell fixtures")

-- Walking the corridor must not leave the weather behind. Drawing from a cell
-- 10 further down produces different pixels only because the effect moved with
-- the camera; a cell-anchored effect would simply fall out of view.
require("presentation.effekseer").update(120 / 60)
love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
love.graphics.clear(0, 0, 0, 1, true, true)
viewport3d.draw(ambientSession)
love.graphics.setCanvas(previousCanvas)
ambientSession.playerY = 11
love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
love.graphics.clear(0, 0, 0, 1, true, true)
viewport3d.draw(ambientSession)      -- applies the follow to the effect root
love.graphics.setCanvas(previousCanvas)
-- Particles already in flight are in WORLD space and stay where they were
-- emitted, so the root arriving is not the same as rain arriving: the new
-- location needs time to emit. Ordinary movement is a cell at a time and never
-- notices, but a teleport (a map transfer, a debug warp) leaves a brief gap.
-- Advance far enough here that the assertion measures the steady state.
require("presentation.effekseer").update(60 / 60)
love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
love.graphics.clear(0, 0, 0, 1, true, true)
viewport3d.draw(ambientSession)
love.graphics.setCanvas(previousCanvas)
local ambientFar = modelCanvas:newImageData()
require("presentation.effekseer").reset()
require("presentation.effekseer").update(1 / 60)

-- The comparison that actually separates the two designs: the SAME corridor,
-- the SAME far camera cell, with no ambient effect. A cell-anchored effect
-- spawned back at the start would be behind the camera by now and these two
-- frames would be identical.
local ambientBaselineSession = sessionModule.GameSession.new(loader)
ambientBaselineSession.mapGrid = corridorGrid
ambientBaselineSession.currentMapData = {
    tileset = "ambient_render_test", ceilingStyle = "solid", events = {},
}
ambientBaselineSession.generatedFeatures = {}
ambientBaselineSession.playerX, ambientBaselineSession.playerY = 1, 11
ambientBaselineSession.playerDir = "S"
love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
love.graphics.clear(0, 0, 0, 1, true, true)
viewport3d.draw(ambientBaselineSession)
love.graphics.setCanvas(previousCanvas)
local ambientBaseline = modelCanvas:newImageData()
local ambientFarPixels = 0
for py = 0, 239 do
    for px = 0, 255 do
        local ar, ag, ab, aa = ambientFar:getPixel(px, py)
        local br, bg, bb, ba = ambientBaseline:getPixel(px, py)
        if ar ~= br or ag ~= bg or ab ~= bb or aa ~= ba then
            ambientFarPixels = ambientFarPixels + 1
        end
    end
end
check(ambientFarPixels > 0,
    "ambient weather is still in view ten cells down the corridor"
        .. " (pixels=" .. ambientFarPixels .. ")")

-- The pixel test above proves the effect RENDERS, not that it FOLLOWS: at house
-- magnification the volume is wide enough to cover this corridor from either
-- end, so it passes with the follow removed. (Verified by disabling it -- 93
-- pixels either way.) Assert the seam itself, which nothing can cover for.
local effekseerModule = require("presentation.effekseer")
local originalSetWorldLocation = effekseerModule.setWorldLocation
local followedTo = {}
effekseerModule.setWorldLocation = function(handle, x, y, z)
    followedTo[#followedTo + 1] = { x = x, y = y, z = z }
    return originalSetWorldLocation(handle, x, y, z)
end
for _, cellY in ipairs({ 3, 15 }) do
    ambientSession.playerY = cellY
    love.graphics.setCanvas({ modelCanvas, depth = true, stencil = true })
    love.graphics.clear(0, 0, 0, 1, true, true)
    viewport3d.draw(ambientSession)
    love.graphics.setCanvas(previousCanvas)
end
effekseerModule.setWorldLocation = originalSetWorldLocation
check(#followedTo == 2 and followedTo[1].y ~= followedTo[2].y
        and math.abs(followedTo[2].y - followedTo[1].y - 12) < 0.001
        and followedTo[1].z == 1.5,
    "the ambient handle is moved to the camera cell every frame at its authored height"
        .. " (y " .. tostring(followedTo[1] and followedTo[1].y)
        .. " -> " .. tostring(followedTo[2] and followedTo[2].y) .. ")")
viewport3d.invalidateStructure(ambientSession)
viewport3d.invalidateStructure(ambientBaselineSession)
require("presentation.effekseer").reset()
loader.tilesets.ambient_render_test = nil
loader.tilesets.model_fixture_render_test = nil

local cacheProbe = {
    mapGrid = eastWestOpening,
    currentMapData = { events = {} },
}
local preparedOnce = viewport3d.prepareStructure(cacheProbe)
local preparedTwice = viewport3d.prepareStructure(cacheProbe)
check(preparedOnce == preparedTwice and preparedTwice.hits == 1,
    "3D structural topology is reused while the map is unchanged")
local resolvedStructureOnce, resolvedFacesOnce = viewport3d.prepareResolvedStructure(cacheProbe)
local resolvedStructureTwice, resolvedFacesTwice = viewport3d.prepareResolvedStructure(cacheProbe)
check(resolvedStructureOnce == resolvedStructureTwice
        and resolvedFacesOnce == resolvedFacesTwice and #resolvedFacesOnce > 0,
    "resolved 3D wall descriptors and composites are reused between frames")
exploration.mutateTile(cacheProbe, 1, 1, ".")
local preparedAfterMutation = viewport3d.prepareStructure(cacheProbe)
check(preparedAfterMutation ~= preparedOnce
        and #preparedAfterMutation.openingCells == 0,
    "a structural mutation invalidates cached 3D topology")
local _, resolvedFacesAfterMutation = viewport3d.prepareResolvedStructure(cacheProbe)
check(resolvedFacesAfterMutation ~= resolvedFacesOnce,
    "a structural mutation invalidates resolved 3D wall descriptors")
cacheProbe.mapPresentationRevision = (cacheProbe.mapPresentationRevision or 0) + 1
check(viewport3d.prepareStructure(cacheProbe) ~= preparedAfterMutation,
    "a map presentation revision invalidates cached 3D lookups")

local townDoorCount, interiorDoorCount, labyrinthGateCount = 0, 0, 0
for _, ev in ipairs(loader.maps[1].events or {}) do
    if ev.wallEvent then
        townDoorCount = townDoorCount + 1
        local row = loader.maps[1].layout[ev.y + 1]
        check(row and row:sub(ev.x + 1, ev.x + 1) == "#",
            ev.name .. " door is authored into a wall cell")
        if ev.name == "Labyrinth Gate" then
            labyrinthGateCount = labyrinthGateCount + 1
            check(ev.trigger == "bump"
                    and ev.sprite == "assets/sprites/labyrinth_gate_bellroot.png",
                "the Labyrinth gate uses wall-bump activation and its authored gate plate")
        else
            interiorDoorCount = interiorDoorCount + 1
            check(ev.trigger == "bump" and ev.sprite == "assets/sprites/map_door_001.png",
                ev.name .. " door uses wall-bump activation and the shared composite sprite")
        end
    end
end
check(townDoorCount == 6 and interiorDoorCount == 5 and labyrinthGateCount == 1,
    "St. Maria has five interior doors and one distinct Labyrinth gate")

local doorTransition = require("presentation.door_transition")
local subtractiveFade = require("presentation.subtractive_fade")
local fadeCanvas = love.graphics.newCanvas(8, 8)
local previousCanvas = love.graphics.getCanvas()
local fadeOk = pcall(function()
    love.graphics.setCanvas(fadeCanvas)
    love.graphics.clear(0.75, 0.50, 0.25, 1)
    subtractiveFade.draw(0.25)
end)
love.graphics.setCanvas(previousCanvas)
check(fadeOk, "the shared subtractive fade renders through LÖVE's subtract blend")
local doorCovered = false
check(doorTransition.begin(function() doorCovered = true end),
    "a door threshold transition starts")
doorTransition.update(0.24)
check(not doorCovered, "the event waits until after the door approach")
check(doorTransition.approachProgress() == 1,
    "the door remains fully zoomed while black covers it")
doorTransition.update(0.29)
check(doorTransition.overlayAlpha() > 0 and doorTransition.overlayAlpha() < 1,
    "entry fades progressively to black")
doorTransition.update(0.29)
check(doorCovered, "the event begins only once the screen is covered")
check(doorTransition.overlayAlpha() == 1,
    "entry lingers at full black before revealing the static room")
doorTransition.update(0.16)
doorTransition.update(0.34)
check(doorTransition.overlayAlpha() > 0 and doorTransition.overlayAlpha() < 1,
    "the static room is progressively revealed")
doorTransition.update(0.34)
check(not doorTransition.isActive(), "the interior reveal completes and unlocks input")

local doorExited = false
check(doorTransition.beginExit(function() doorExited = true end),
    "an inverse door threshold transition starts on exit")
doorTransition.update(0.34)
check(doorTransition.overlayAlpha() > 0 and doorTransition.overlayAlpha() < 1,
    "the static room fades to black without changing scale")
doorTransition.update(0.34)
check(doorExited and doorTransition.overlayAlpha() == 1,
    "the map returns only at full black and remains hidden during the exit hold")
doorTransition.update(0.16)
check(doorTransition.approachProgress() == 1,
    "the outside door begins fully zoomed behind black")
doorTransition.update(0.29)
check(doorTransition.approachProgress() > 0 and doorTransition.approachProgress() < 1,
    "the outside door reverses its zoom while the map is revealed")
doorTransition.update(0.29)
check(not doorTransition.isActive(), "the inverse exit reveal completes")

local portalItem = loader.getItem(197)
local safeUseSession = sessionModule.GameSession.new(loader)
safeUseSession.currentMapData = loader.maps[1]
check(not usability.canUseItem(portalItem, nil, { session = safeUseSession, isField = true }),
    "Town Portal is refused in town before it can be consumed")
safeUseSession.currentMapData = loader.maps[2]
check(usability.canUseItem(portalItem, nil, { session = safeUseSession, isField = true }),
    "Town Portal is usable inside the dungeon")

-- LOAD_MAP inside an event compiles to a real node. When it was listed in
-- INTERACTIVE_COMPILE_IDS with no branch, `nodes` came back empty here and the
-- Developer Room's exit tile went nowhere.
local nodes = {}
local first = interpreter.compileTop(nodes, { { cmd = "LOAD_MAP", mapId = 1 } },
    "t", "done", { loader = loader })
check(first ~= nil and nodes[first] ~= nil,
    "LOAD_MAP in an event compiles to a node instead of a dead end")
check(nodes[first] and nodes[first].action == "RUN_IMMEDIATE",
    "and it runs immediately, because a map transfer asks the player nothing")

-- Depth is read off the map, so every transfer keeps it true.
local sess = sessionModule.GameSession.new(loader)
sess:initializeStartingParty()

exploration.loadMap(sess, 2)
check(sess.dungeonFloor == 1, "entering Floor 1 puts the party at depth 1")
local generatedTagCounts = {}
for _, cell in ipairs(sess.generatedZones or {}) do
    for _, tag in ipairs(cell.tags or {}) do
        generatedTagCounts[tag] = (generatedTagCounts[tag] or 0) + 1
    end
end
check((generatedTagCounts.room or 0) > 0 and (generatedTagCounts.corridor or 0) > 0
        and generatedTagCounts.entrance == 1 and generatedTagCounts.exit == 1,
    "dungeon generation tags rooms, corridors, entrance and exit")
local openingMap = {}
for k, v in pairs(loader.maps[2]) do openingMap[k] = v end
check(openingMap.generationProfile == "entry"
        and loader.system.dungeon.generationProfiles.entry.minRooms == 3
        and openingMap.genMinRooms == nil,
    "procedural floors select validated generation profiles instead of legacy fields")
openingMap.generateOpenings = true
local openingGrid = exploration.generateDungeon(openingMap, 97531, sess)
local repeatedOpeningGrid = exploration.generateDungeon(openingMap, 97531, sess)
local openingCount, openingsStable = 0, true
for y, row in ipairs(openingGrid) do
    for x, cell in ipairs(row) do
        if cell == "o" then openingCount = openingCount + 1 end
        if cell ~= repeatedOpeningGrid[y][x] then openingsStable = false end
    end
end
check(openingCount > 0 and openingsStable,
    "procedural maps opt into deterministic room-threshold openings")
check(formula.sessionView(sess).floor == 1,
    "and the `floor` token reports it -- it used to always read 1")

exploration.loadMap(sess, 6)
check(sess.dungeonFloor == 5, "Floor 5 is depth 5")

-- The old counter only ever incremented, so walking back to town left the
-- party "deep" for enemy levels and recruitment.
exploration.loadMap(sess, 1)
check(sess.dungeonFloor == 0, "returning to Town puts the party back at depth 0")

-- Safe maps may be smaller than Town and therefore cannot inherit Town's
-- system spawn. Developer Room authors its own open-tile entry point.
exploration.loadMap(sess, 8)
check(sess.playerX == 8 and sess.playerY == 7 and sess.mapGrid[7][8] == ".",
    "an authored safe-map spawn places the player on its declared open tile")
check(sess.playerDir == "N",
    "an authored safe-map spawn controls the arrival facing")

-- Descending from Floor 5 reached Floor 5 again under the old maxFloor=5 clamp,
-- which made the deepest authored map unreachable.
local function descend(fromMapId)
    local s = sessionModule.GameSession.new(loader)
    s:initializeStartingParty()
    exploration.loadMap(s, fromMapId)
    local ctx = { session = s, loader = loader, events = {}, party = s.party }
    interpreter.runImmediate({ { cmd = "LOAD_MAP", mapId = "session.floor + 2" } }, ctx)
    return s
end
check(descend(2).currentMapIndex == 3, "the stairs on Floor 1 lead to Floor 2")
local sanctum = descend(6)
check(sanctum.currentMapIndex == 7 and sanctum.dungeonFloor == 6,
    "and the stairs on Floor 5 reach the Sanctum, which the old clamp hid")

-- A generated floor is one place for the life of the expedition. Descending
-- away and climbing back must restore its geometry, fog, events, and landmark
-- positions rather than rolling a replacement.
local route = sessionModule.GameSession.new(loader)
route:initializeStartingParty()
exploration.loadMap(route, 2, { arrival = "entrance" })
local originalGrid = route.mapGrid
local originalEvents = route.currentMapData.events
local entranceX, entranceY = route.currentMapData.entranceX, route.currentMapData.entranceY
local exitX, exitY = route.currentMapData.exitX, route.currentMapData.exitY
route.visitedGrid[2][2] = true
exploration.loadMap(route, 3, { arrival = "entrance" })
exploration.loadMap(route, 2, { arrival = "exit" })
check(route.mapGrid == originalGrid and route.currentMapData.events == originalEvents,
    "climbing back restores the exact generated floor instead of regenerating it")
check(route.visitedGrid[2][2] == true,
    "restored floors retain their fog-of-war history")
check(route.currentMapData.entranceX == entranceX and route.currentMapData.entranceY == entranceY
    and route.currentMapData.exitX == exitX and route.currentMapData.exitY == exitY,
    "restored floors retain both staircase landmarks")
check(math.abs(route.playerX - exitX) + math.abs(route.playerY - exitY) == 1,
    "climbing up arrives beside the previous floor's exit")

local hasEntrance = false
for _, ev in ipairs(route.currentMapData.events or {}) do
    if ev.scriptId == 40 then
        hasEntrance = true
        local row = route.mapGrid[ev.y + 1]
        check(ev.wallEvent == true and ev.trigger == "bump"
                and row and row[ev.x + 1] == "#"
                and ev.sprite == "assets/sprites/dungeon_stairs_up.png",
            "generated entrance stairs occupy a wall and use the wall compositor")
    elseif ev.scriptId == 1 then
        local row = route.mapGrid[ev.y + 1]
        check(ev.wallEvent == true and ev.trigger == "bump"
                and row and row[ev.x + 1] == "#"
                and ev.sprite == "assets/sprites/dungeon_stairs_down.png",
            "generated exit stairs occupy a wall and use the wall compositor")
    end
end
check(hasEntrance, "every generated floor has physical stairs back up")

-- A Town Portal is temporary travel, not a new expedition or a regenerated
-- floor. Returning through it restores the exact tile and facing.
route.playerX, route.playerY, route.playerDir = 7, 8, "W"
local expeditionCount = route.party[1].history.expeditions
local portalCtx = { session = route, loader = loader, events = {}, party = route.party }
interpreter.runImmediate({ { cmd = "PORTAL_TO_TOWN" } }, portalCtx)
check(route.currentMapIndex == 1 and route.portalReturn ~= nil and route.flags.portal_open == true,
    "PORTAL_TO_TOWN opens a resumable route and moves the party to safety")
interpreter.runImmediate({ { cmd = "RETURN_TO_PORTAL" } }, portalCtx)
check(route.currentMapIndex == 2 and route.playerX == 7 and route.playerY == 8 and route.playerDir == "W",
    "RETURN_TO_PORTAL restores the exact dungeon tile and facing")
check(route.party[1].history.expeditions == expeditionCount,
    "temporary portal travel does not count as a new expedition")
check(route.portalReturn == nil and route.flags.portal_open == nil,
    "the return trip closes the temporary portal")
local completedRoute = route.mapGrid
exploration.loadMap(route, 1)
exploration.loadMap(route, 2, { arrival = "entrance" })
check(route.mapGrid ~= completedRoute,
    "a new expedition receives a fresh floor instead of reusing the completed route")

-- Off-floor snapshots and an open portal both survive save/load.
exploration.loadMap(route, 3, { arrival = "entrance" })
route.portalReturn = { mapIndex = 2, playerX = 4, playerY = 5, playerDir = "S" }
local restored = savegame.deserialize(savegame.serialize(route, loader, "map"), loader)
check(restored.mapStates[2] and restored.mapStates[2].mapGrid,
    "generated floor snapshots survive save/load")
check(restored.mapStates[2] and #(restored.mapStates[2].generatedZones or {}) > 0,
    "generated structural zones survive off-floor save/load")
check(restored.portalReturn and restored.portalReturn.mapIndex == 2
    and restored.portalReturn.playerX == 4,
    "an open portal destination survives save/load")
-- Town states can replace the whole visual atmosphere without replacing the
-- map or branching presentation code. This is how the Vigil first announces
-- itself: palette, fog, and ambient light change together.
local festivalTown = sessionModule.GameSession.new(loader)
festivalTown:initializeStartingParty()
exploration.loadMap(festivalTown, 1)
local ordinaryLight = festivalTown.currentMapData.runtimeLight
local presentationCtx = {
    session = festivalTown, loader = loader, events = {}, party = festivalTown.party
}
interpreter.runImmediate({ {
    cmd = "SET_MAP_PRESENTATION",
    mapId = 1,
    tileset = "town_003",
    fogPreset = "purple_dusk",
    ambientR = 0.24,
    ambientG = 0.09,
    ambientB = 0.18
} }, presentationCtx)
check(festivalTown.currentMapData.tileset == "town_003"
    and festivalTown.currentMapData.fog.preset == "purple_dusk",
    "SET_MAP_PRESENTATION changes the current map's tileset and fog immediately")
check(festivalTown.currentMapData.runtimeLight ~= ordinaryLight,
    "SET_MAP_PRESENTATION rebakes map lighting immediately")

local restoredFestival = savegame.deserialize(
    savegame.serialize(festivalTown, loader, "town"), loader)
check(restoredFestival.currentMapData.tileset == "town_003"
    and restoredFestival.currentMapData.fog.preset == "purple_dusk",
    "a changed town presentation survives save/load")
check(restoredFestival.mapPresentationOverrides[1].ambient[1] == 0.24,
    "the festival ambient-light state survives save/load")

interpreter.runImmediate({ {
    cmd = "ENTER_LOCATION", image = "st_maria_home.png"
} }, presentationCtx)
check(festivalTown.locationArt == "st_maria_home.png",
    "ENTER_LOCATION selects a static illustrated dialogue backdrop")

local intro = loader.commonEvents["42"]
check(intro and intro.scene == "cinematic",
    "New Game's opening is authored as a cinematic common event")
local introGraph = interpreter.runInteractive(intro.commands, {
    session = festivalTown, loader = loader, party = festivalTown.party,
    eventTitle = intro.name
})
check(introGraph.labels and introGraph.labels.intro_cleanup,
    "the opening exposes an authored cleanup label for skipping")
local actingGraph = interpreter.runInteractive({
    { cmd = "TEXT", text = "Act.", speaker = "Alicia", expression = 4 }
}, {
    session = festivalTown, loader = loader, party = festivalTown.party
})
local actingNode
for _, node in pairs(actingGraph.nodes or {}) do
    if node.type == "TEXT" then actingNode = node break end
end
check(actingNode and actingNode.expression == 4,
    "TEXT preserves the authored 1-5 portrait expression in the event graph")

local alicia
for _, ev in ipairs(loader.maps[1].events or {}) do
    if ev.name == "Alicia" then alicia = ev break end
end
check(alicia and alicia.pages and alicia.pages[1]
    and alicia.pages[1].condition == "flag:vigil_ready",
    "Alicia's Vigil page does not hide her introductory event before the Vigil")

local cancelGraph = interpreter.runInteractive({
    {
        cmd = "CHOICE",
        cancelOption = 2,
        options = {
            { label = "Stay", commands = {} },
            { label = "Leave", commands = {
                { cmd = "SET_FLAG", flag = "choice_cancelled", value = true }
            } }
        }
    }
}, {
    session = festivalTown, loader = loader, party = festivalTown.party
})
local cancelNode = cancelGraph.nodes[cancelGraph.initialNode]
check(cancelNode and cancelNode.cancelOption == 2,
    "CHOICE compiles its authored cancel option")

festivalTown.flags.hide_cancel = true
local hiddenCancelGraph = interpreter.runInteractive({
    {
        cmd = "CHOICE",
        cancelOption = 2,
        options = {
            { label = "Stay", commands = {} },
            {
                label = "Hidden leave",
                condition = "flag:missing_cancel_option",
                commands = {}
            }
        }
    }
}, {
    session = festivalTown, loader = loader, party = festivalTown.party
})
local hiddenCancelNode = hiddenCancelGraph.nodes[hiddenCancelGraph.initialNode]
check(hiddenCancelNode and hiddenCancelNode.cancelOption == nil,
    "CHOICE disables Cancel when its authored cancel option is hidden")
for _, node in pairs(introGraph.nodes or {}) do
    if node.type == "ACTION" and node.action == "RUN_IMMEDIATE" then
        for _, cmd in ipairs(node.commands or {}) do
            if cmd.cmd == "MOVE_IMAGE_PICTURE" then
                check(cmd.scale == nil,
                    "opening cinematic plates crossfade without zooming")
            end
        end
    end
end
local hasWaitNode = false
for _, node in pairs(introGraph.nodes or {}) do
    if node.action == "WAIT_EVENT" then hasWaitNode = true break end
end
check(hasWaitNode,
    "WAIT compiles to a pausing event-graph node instead of a synchronous no-op")
check(loader.getScene("title").backdropImage == "assets/title/st_maria_title_psx.png",
    "the title scene uses the St. Maria labyrinth vista")
local stringPictures = require("presentation.string_picture_renderer")
stringPictures.show({ id = 777, text = "scroll", x = 0, y = 0 })
stringPictures.move({ id = 777, x = 10, duration = 2, easing = "linear" })
stringPictures.update(1)
check(stringPictures.get(777).x == 5,
    "string pictures support constant-speed linear movement for credit-style scrolls")
stringPictures.clear()

stringPictures.show({ id = 780, text = "typewriter", x = 0, y = 0, reveal = true })
stringPictures.update(0.25)
check(stringPictures.get(780).reveal == true
        and stringPictures.get(780).revealElapsed == 0.25,
    "string pictures support the shared SHOW TEXT character reveal")
stringPictures.clear()

local imagePictures = require("presentation.image_picture_renderer")
imagePictures.show({
    id = 778, path = "assets/cinematics/arrival_ride.png",
    x = 128, y = 120, anchor = "center", opacity = 0, scale = 1, blend = "add",
})
imagePictures.move({ id = 778, opacity = 1, scale = 1.1, duration = 2, easing = "linear" })
imagePictures.update(1)
check(imagePictures.get(778).opacity == 0.5
    and imagePictures.get(778).scale == 1.05
    and imagePictures.get(778).blend == "add",
    "image pictures support event-authored crossfades, transforms and additive blend")
imagePictures.clear()

stringPictures.show({
    id = 779, text = "glow", x = 0, y = 0, blend = "add",
})
check(stringPictures.get(779).blend == "add",
    "string pictures support event-authored additive blend")
stringPictures.clear()

local gameOver = loader.getScene("game_over")
for _, cmd in ipairs((gameOver.hooks and gameOver.hooks.on_enter) or {}) do
    if cmd.cmd == "MOVE_IMAGE_PICTURE" then
        check(cmd.scale == nil, "the Game Over sequence never zooms its image")
    end
end

-- The bottom of the dungeon is expressed by authoring no stairs there, not by
-- a number in system.json that has to be kept in step with the map list.
local deepest = loader.maps[7]
local hasStairs = false
for _, ev in ipairs((deepest and deepest.events) or {}) do
    if ev.scriptId == 1 then hasStairs = true end
end
check(not hasStairs, "the deepest floor carries no stairs event")
local bottomSession = sessionModule.GameSession.new(loader)
bottomSession:initializeStartingParty()
exploration.loadMap(bottomSession, 7, { arrival = "entrance" })
local generatedBottomHasStairs = false
for _, ev in ipairs(bottomSession.currentMapData.events or {}) do
    if ev.scriptId == 1 then generatedBottomHasStairs = true end
end
check(not generatedBottomHasStairs,
    "generation respects the deepest floor's missing down-stairs marker")

-- Fail loud rather than dropping the party into an empty world.
check(not pcall(exploration.loadMap, sess, 999),
    "a transfer to a map that does not exist raises")

print(string.format("=== Map Transfer Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " map transfer test(s) failed", failed) end
