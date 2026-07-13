-- Battle-scene layout defaults shared by renderer.lua and
-- presentation/actor_status.lua (extracted 11.07.2026 so the party-status
-- cell drawer can read the same offsets without a circular require), per
-- the BIBLE rule that coordinate mappings must never be duplicated. Values
-- can be overridden from data/engine.json (battleLayout), editable in the
-- Engine editor.

local battle_layout = {}

local BATTLE_LAYOUT = {
    enemyRowWidth = 220,
    enemyStartX = 18,
    enemyPopupOffsetX = 28, -- centered over the 56x56 enemy sprite
    enemyPopupY = 84,
    partyGridTileX = 15,    -- drawPartyGrid origin inside the console (tiles)
    -- consoleTileY/H match engine.json windowLayout.party exactly (y18.5,
    -- h11.5) so the bottom console sits at the SAME position as the shared
    -- declarative "party" window every other converted scene uses (owner
    -- direction 12.07.2026).
    consoleTileY = 18.5,
    headerTileOffset = 1,
    slotPopupOffsetX = 27,
    slotPopupOffsetY = 10,
    summonerPopupX = 50,
    summonerPopupYOffset = 62,
    fallbackX = 128,
    fallbackY = 70,
    enemyY = 54,
    enemyNameY = 114,
    enemyHpBarY = 128,
    enemyHpBarWidth = 50,
    enemyHpBarHeight = 4,
    enemySpriteSize = 56,
    enemyFallbackSize = 50,
    enemySlideOffset = 280,
    enemyDeathYOffset = 20,
    viewportOverlayW = 256,
    viewportOverlayH = 140,
    -- Log/help panel geometry matches engine.json windowLayout.help exactly
    -- (x0,y0,w32,h4 in tiles -> 0,0,256,32 px) so battle's command-help text
    -- sits in the SAME top window every other converted scene uses (owner
    -- direction 12.07.2026) -- a values sync, not a live engine.json read;
    -- battle's drawing stays fully legacy pending the Summoner rework.
    logPanelX = 0,
    logPanelY = 0,
    logPanelWidth = 256,
    logPanelHeight = 32,
    logTextX = 8,
    logTextY = 8,
    logTextLimit = 240,
    logSpaceX = 216,
    logSpaceY = 17,
    logLineSpacing = 10,        -- B.8: second log line offset
    commandBarTileH = 2.5,      -- B.7: single-line full-width command bar
    commandBarTextYOffset = 6,  --      flush above the status console
    victoryPanelTileX = 6,      -- B.9: victory window
    victoryPanelTileY = 4,
    victoryPanelTileW = 20,
    victoryPanelTileH = 14,
    victoryLineSpacing = 12,
    victoryRowHeight = 18,      -- B.9: per-member EXP gauge rows
    victoryGaugeWidth = 120,    -- nearly full panel interior width
    victoryGaugeHeight = 3,
    consoleTileX = 0,
    consoleTileW = 32,
    consoleTileH = 11.5,
    consoleTextTileX = 1,
    menuChoiceSpacing = 16,
    summonerStatusX = 8,
    summonerNameYOffset = 8,   -- B.6: top-aligned with the party grid front row
    summonerMpTextYOffset = 26,
    summonerMpBarYOffset = 34,
    summonerMpBarWidth = 80,
    summonerMpBarHeight = 4,
    partyGridColWidth = 68,
    partyGridRowHeight = 40,
    partyGridNameXOffset = 1,
    partyGridHpXOffset = 8,
    partyGridHpYOffset = 11,
    partyGridHpBarXOffset = 8,
    partyGridHpBarYOffset = 22,
    partyGridHpBarWidth = 52,
    partyGridHpBarHeight = 3,
    partyGridEmptyYOffset = 8
}

-- Battle layout accessor: engine.json override -> built-in default.
-- session is whichever GameSession is active (renderer.session in
-- renderer.lua; ctx.session in window_renderer.lua) — both carry the same
-- .loader reference, so overrides resolve identically everywhere.
function battle_layout.get(session, key)
    local loaderRef = session and session.loader
    local overrides = loaderRef and loaderRef.engine and loaderRef.engine.battleLayout
    if overrides and overrides[key] ~= nil then return overrides[key] end
    return BATTLE_LAYOUT[key]
end

return battle_layout
