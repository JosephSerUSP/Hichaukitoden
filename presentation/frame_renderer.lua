-- Native game-frame compositor shared by live play and screenshot tools.
local frame_renderer = {}

local function drawSharedPartyHud(scene_host, session, loader)
    local wr = require("presentation.window_renderer")
    local cursor = 0
    if scene_host.getCurrent() == "battle" then
        local bv = require("engine.scenes.battle").getState()
        if bv and bv.combatState == "input" then
            local memberInfo = bv.livingMembers and bv.livingMembers[bv.activeMemberIdx or 1]
            cursor = memberInfo and memberInfo.index or 0
        end
    end
    wr.draw({
        winState = { party = { open = true, listId = "party", cursor = cursor } },
        windowOrder = { "party" },
    }, nil, { session = session, loader = loader })
end

function frame_renderer.draw(scene_host, renderer, session, loader, gameHeight)
    local ctx = { session = session, loader = loader, party = session and session.party or {} }
    scene_host.draw(ctx)

    if scene_host.getCurrent() == "dialogue" then
        local enterTime = _G.dialogueEnterTime or 0
        if love.timer.getTime() - enterTime < 0.15 then
            drawSharedPartyHud(scene_host, session, loader)
        end
    end

    if scene_host.getCurrent() == "battle" then
        local bv = require("engine.scenes.battle").getState()
        local slideT = bv.defeatSlideT or 0
        if slideT > 0 then
            love.graphics.push()
            love.graphics.translate(0, slideT * gameHeight)
            drawSharedPartyHud(scene_host, session, loader)
            love.graphics.pop()
        else
            drawSharedPartyHud(scene_host, session, loader)
        end
        renderer.drawTargetReticles(
            bv, bv.combatState or "input", bv.selectedIndex or 1,
            bv.skillSelect or false, bv.itemSelect or false,
            bv.livingMembers or {}, bv.activeMemberIdx or 1
        )
        renderer.drawScreenFlashOverlay(bv.battle)
        renderer.drawDefeatFadeOverlay(bv.defeatFinalFade)
    end

    renderer.drawDamagePopups()
end

return frame_renderer
