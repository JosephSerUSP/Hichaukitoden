-- Native game-frame compositor shared by live play and screenshot tools.
local frame_renderer = {}

-- The party HUD this file used to draw itself for battle, and briefly for
-- dialogue to cover the transition, is now the persistent dock: both scenes
-- declare `config.dock` in scenes.json and scene_host draws it. What is left
-- here is battle's own chrome, which the dock does not own.
function frame_renderer.draw(scene_host, renderer, session, loader, gameHeight)
    local ctx = { session = session, loader = loader, party = session and session.party or {} }
    local stringPictures = require("presentation.string_picture_renderer")
    local imagePictures = require("presentation.image_picture_renderer")
    scene_host.draw(ctx)

    if scene_host.getCurrent() == "battle" then
        local bv = require("engine.scenes.battle").getState()
        renderer.drawTargetReticles(
            bv, bv.combatState or "input", bv.selectedIndex or 1,
            bv.skillSelect or false, bv.itemSelect or false,
            bv.livingMembers or {}, bv.activeMemberIdx or 1
        )
        renderer.drawScreenFlashOverlay(bv.battle)
        renderer.drawDefeatFadeOverlay(bv.defeatFinalFade)
    end

    renderer.drawDamagePopups()
    imagePictures.draw("screen")
    stringPictures.draw("screen")
    imagePictures.draw("top")
    stringPictures.draw("top")
end

return frame_renderer
