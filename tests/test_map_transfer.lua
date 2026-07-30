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
check(formula.sessionView(sess).floor == 1,
    "and the `floor` token reports it -- it used to always read 1")

exploration.loadMap(sess, 6)
check(sess.dungeonFloor == 5, "Floor 5 is depth 5")

-- The old counter only ever incremented, so walking back to town left the
-- party "deep" for enemy levels and recruitment.
exploration.loadMap(sess, 1)
check(sess.dungeonFloor == 0, "returning to Town puts the party back at depth 0")

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
if failed > 0 then error(failed .. " map transfer test(s) failed") end
