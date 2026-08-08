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

    -- #179: while a resolved round is still being revealed, draw from a
    -- detached presentation projection. Keep this substitution entirely on
    -- the presentation side: scene_host still owns its real scene state and
    -- knows nothing about BattleView. Only the battle reference is swapped for
    -- the duration of this draw call; Battler/GameSession domain objects are
    -- never rewound or replayed.
    local projectedState = nil
    local realBattle = nil
    if scene_host.getCurrent() == "battle" then
        local battle_view = require("presentation.battle_view")
        local state = scene_host.getCurrentState()
        local projectedSession
        projectedState, projectedSession = battle_view.projectState(state, session)
        if projectedState and projectedSession then
            ctx.session = projectedSession
            ctx.party = projectedSession.party
            if state and state.v then
                realBattle = state.v.battle
                state.v.battle = projectedState.v.battle
            end
        end
    end

    scene_host.draw(ctx)

    -- Restore the scene's real Battle immediately after drawing. This is a
    -- presentation reference substitution only; no domain field is changed.
    if realBattle ~= nil then
        local state = scene_host.getCurrentState()
        if state and state.v then state.v.battle = realBattle end
    end

    if scene_host.getCurrent() == "battle" then
        local bv = projectedState and projectedState.v
            or require("engine.scenes.battle").getState()
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
