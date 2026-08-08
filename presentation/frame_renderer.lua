-- Native game-frame compositor shared by live play and screenshot tools.
local frame_renderer = {}
local battle_view = require("presentation.battle_view")

-- The party HUD this file used to draw itself for battle, and briefly for
-- dialogue to cover the transition, is now the persistent dock: both scenes
-- declare `config.dock` in scenes.json and scene_host draws it. What is left
-- here is battle's own chrome, which the dock does not own.
function frame_renderer.draw(scene_host, renderer, session, loader, gameHeight)
    local current = scene_host.getCurrent()
    local drawSession = session
    if current == "battle" then
        drawSession = battle_view.sessionFor(session)
    elseif battle_view.isActive() then
        -- A projection never escapes its battle scene. Once another scene owns
        -- the frame, render authoritative session state directly again.
        battle_view.clear()
    end

    local ctx = {
        session = drawSession,
        loader = loader,
        party = drawSession and drawSession.party or {},
    }
    local stringPictures = require("presentation.string_picture_renderer")
    local imagePictures = require("presentation.image_picture_renderer")
    scene_host.draw(ctx)

    if current == "battle" then
        local bv = require("engine.scenes.battle").getState()
        renderer.drawTargetReticles(
            bv, bv.combatState or "input", bv.selectedIndex or 1,
            bv.skillSelect or false, bv.itemSelect or false,
            bv.livingMembers or {}, bv.activeMemberIdx or 1
        )
        renderer.drawScreenFlashOverlay(bv.battle)
        renderer.drawDefeatFadeOverlay(bv.defeatFinalFade)
    end

    -- Effekseer draws ALL live effects in one call, not per battler: the
    -- runtime owns their lifetime once spawned. Placed here so effects sit
    -- above battlers and reticles but below damage popups and pictures --
    -- a number must stay readable through whatever is going off behind it.
    -- effekseer.draw() flushes LOVE's batch first; without that the effects
    -- land behind everything queued this frame (roadmap 6.5.1c).
    require("presentation.effekseer").draw()

    renderer.drawDamagePopups()
    imagePictures.draw("screen")
    stringPictures.draw("screen")
    imagePictures.draw("top")
    stringPictures.draw("top")

    -- Keep diagnostics above all in-canvas game content. The overlay is off by
    -- default, which preserves deterministic previews and golden captures.
    require("presentation.dev_overlay").draw()
end

return frame_renderer
