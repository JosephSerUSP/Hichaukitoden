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
    -- Damage/heal popups attach to the battler through the shared anchor
    -- resolver (presentation/battler_geometry.lua), so ONE spec serves both
    -- the 64px enemy portrait and the 24px party sprite -- the old
    -- enemyPopupOffsetX/enemyPopupY + slotPopupOffsetX/Y pairs were a second
    -- opinion on where a creature is, and drifted from where it was drawn.
    popupAnchorPoint = "center",
    popupAnchorOffsetX = 0,
    popupAnchorOffsetY = 0,
    popupAnchorRelativeX = 0,
    popupAnchorRelativeY = 0,
    -- Default anchor for animation entries that do not author their own
    -- (data/animations.json `anchor`).
    animationAnchorPoint = "center",
    -- consoleTileY/H match engine.json windowLayout.party exactly (y18.5,
    -- h11.5) so the bottom console sits at the SAME position as the shared
    -- declarative "party" window every other converted scene uses (owner
    -- direction 12.07.2026).
    consoleTileY = 18.5,
    headerTileOffset = 1,
    fallbackX = 128,
    fallbackY = 70,
    enemyY = 54,
    enemySpriteSize = 56,
    -- Enemy info block (element icons + name + HP gauge). Positioned RELATIVE
    -- to the creature's feet line, so it follows the sprite instead of sitting
    -- at an absolute row that a taller portrait would collide with. Every
    -- channel can be switched off from data.
    enemyInfoVisible = true,
    enemyInfoWidth = 96,
    enemyInfoClampToSlot = false,
    enemyInfoOffsetY = 4,
    enemyInfoBarOffsetY = 14,
    enemyInfoHpBarHeight = 4,
    enemyInfoShowName = true,
    enemyInfoShowHpBar = true,
    enemyInfoShowElements = true,
    enemyFallbackSize = 50,
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
    partyGridColWidth = 68,
    partyGridRowHeight = 40,
    partyGridSpriteSize = 24,
    partyGridNameXOffset = 1,
    partyGridHpXOffset = 8,
    partyGridHpYOffset = 11,
    partyGridHpBarXOffset = 8,
    partyGridHpBarYOffset = 22,
    partyGridHpBarWidth = 52,
    partyGridHpBarHeight = 3,
    partyGridEmptyYOffset = 8,
    targetIndicatorDistance = 8,
    targetIndicatorBlinkSpeed = 0.25,
    targetIndicatorEnemyOffsetX = 0,
    targetIndicatorEnemyOffsetY = 0,
    targetIndicatorAllyOffsetX = 0,
    targetIndicatorAllyOffsetY = 0
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
