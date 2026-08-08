-- The ONE answer to "where is this battler on screen".
--
-- WHY THIS EXISTS (29.07.2026): battle placement was computed in four
-- disagreeing places -- renderer.enemyAnchor (sprite draw),
-- renderer.getBattlerCoords (damage popups, via its own
-- enemyPopupOffsetX/enemyPopupY and slotPopupOffsetX/Y), getBattlerRect
-- (target reticles) and drawTargetIndicators (slot numbers). Each carried its
-- own arithmetic, so the game literally did not agree on where a creature was:
-- a popup spawned at a fixed y while the sprite it belonged to was somewhere
-- else, and every layout tweak had to be made in four spots or drift.
--
-- Now there is exactly one function that maps a battler to a rect, and one
-- that turns a rect plus an ANCHOR SPEC into a point. Popups, animations,
-- reticles, slot indicators and the enemy info block all go through them, so
-- "where is this battler" has a single answer and moving a creature moves
-- everything attached to it.
--
-- Anchor spec (SPEC 2.3) -- authored on an animation entry, on the popup
-- config, wherever something needs to attach to a creature:
--   point            "center" (default) | "feet" | "head" | "top_left"
--   offsetX/offsetY  pixels, added after the point is resolved
--   relativeOffsetX  fraction of the battler's OWN width, added likewise --
--   relativeOffsetY  fraction of its own height. This is the "battler
--                    size-based offset": 0.5 on a 64px enemy is 32px, on a
--                    24px party sprite it is 12px, so one authored animation
--                    sits correctly on both.
--
-- No require of actor_status/renderer here on purpose: this module is the
-- bottom of the dependency stack (ui + battle_layout only) so every drawer can
-- read it without a cycle. actor_status.cellSize/gridSlot delegate here.

local ui = require("presentation.ui")
local battle_layout = require("presentation.battle_layout")
local battle_view = require("presentation.battle_view")

local battler_geometry = {}

local function layoutVal(session, key)
    return battle_layout.get(session, key)
end

-- Closed set: an unknown anchor point is an authoring mistake and must fail
-- loud (G1 checks animation entries against this), never silently center.
battler_geometry.ANCHOR_POINTS = {
    center = true, feet = true, head = true, top_left = true,
}

---------------------------------------------------------------------------
-- Rects
---------------------------------------------------------------------------

-- A rect describes a battler's SPRITE box (x, y = top-left, w, h) plus the
-- `frame` box that framing UI (target reticle, slot indicators) should use.
-- For an enemy the two are the same; for a party member the sprite is the
-- 24px creature inside the much larger status cell, and the frame is the cell.
local function makeRect(x, y, w, h, frameX, frameY, frameW, frameH, side, index)
    return {
        x = x, y = y, w = w, h = h,
        frameX = frameX, frameY = frameY, frameW = frameW, frameH = frameH,
        side = side, index = index,
    }
end

-- Horizontal slot arithmetic for the enemy formation grid, shared by the rect and the
-- info block so a wider row can never move one without the other.
function battler_geometry.enemySlot(session, index, count)
    count = count or 4
    local formation = require("engine.formation")
    if formation.isValidSlot(index) then
        local col = formation.colOf(index)
        local row = formation.rowOf(index)
        local totalCols = 2
        local spacing = layoutVal(session, "enemyRowWidth") / totalCols
        local startX = layoutVal(session, "enemyStartX")
        local slotX = startX + (col - 1) * spacing + spacing / 2
        local rowYOffset = (row == "back") and -12 or 8
        return slotX, spacing, rowYOffset
    else
        local spacing = layoutVal(session, "enemyRowWidth") / math.max(1, count)
        local slotX = layoutVal(session, "enemyStartX") + (index - 1) * spacing
        return slotX + spacing / 2, spacing, 0
    end
end

-- `image` is the resolved bigBattler (nil falls back to the authored square).
function battler_geometry.enemyRect(session, index, count, image)
    local centerX, spacing, rowYOffset = battler_geometry.enemySlot(session, index, count)
    local feetY = layoutVal(session, "enemyY") + layoutVal(session, "enemySpriteSize") + (rowYOffset or 0)
    local fallback = layoutVal(session, "enemyFallbackSize")
    local w = image and image:getWidth() or fallback
    local h = image and image:getHeight() or fallback
    local x, y = centerX - w / 2, feetY - h
    return makeRect(x, y, w, h, x, y, w, h, "enemy", index)
end

-- Origin of the party status grid. Read from engine.json windowLayout.party --
-- the SAME layout the dock's partyGrid window draws with -- so cells and
-- everything anchored to them share one origin.
function battler_geometry.partyGridOrigin(session)
    local loaderRef = session and session.loader
    local layouts = loaderRef and loaderRef.engine and loaderRef.engine.windowLayout
    local partyLayout = layouts and layouts.party or {}
    local px = ui.toPx(partyLayout.x or 0)
    local py = ui.toPx(partyLayout.y or 18)
    local gridX, gridY = ui.panelContentOrigin(
        px, py, partyLayout.title, partyLayout.contentX or partyLayout.textX, partyLayout.contentY)
    return gridX, gridY, partyLayout.gridColumns or 2
end

function battler_geometry.cellSize(session)
    return layoutVal(session, "partyGridColWidth"), layoutVal(session, "partyGridRowHeight")
end

-- Top-left of the status cell for 1-based member `index`, wrapping into `cols`.
function battler_geometry.gridSlot(originX, originY, index, session, cols)
    cols = cols or 2
    local colW, rowH = battler_geometry.cellSize(session)
    local col = (index - 1) % cols
    local row = math.floor((index - 1) / cols)
    return originX + col * colW, originY + row * rowH
end

-- The party member's creature sprite inside its status cell. Must match
-- actor_status.draw's own draw call exactly -- it reads the same two layout
-- values rather than repeating the offsets.
function battler_geometry.partyRect(session, index)
    local gridX, gridY, cols = battler_geometry.partyGridOrigin(session)
    local slotX, slotY = battler_geometry.gridSlot(gridX, gridY, index, session, cols)
    local colW, rowH = battler_geometry.cellSize(session)
    local size = layoutVal(session, "partyGridSpriteSize")
    return makeRect(
        slotX, slotY + battler_geometry.partySpriteTopOffset(), size, size,
        slotX - 2, slotY - 2, colW - 2, rowH - 2, "party", index)
end

-- The sprite starts one text line below the cell top (the name owns line 1).
function battler_geometry.partySpriteTopOffset()
    return ui.lineHeight
end

-- THE lookup: battler -> rect, whichever side it is on. `resolveImage` lets
-- the caller supply the enemy's bigBattler resolver (renderer owns the cache);
-- omitted, enemies fall back to the authored square size.
function battler_geometry.rect(battleState, session, target, resolveImage)
    if not target then return nil end
    if battleState then
        local enemies = battleState.enemies or {}
        for idx = 1, 4 do
            local enemy = enemies[idx]
            if enemy == target then
                return battler_geometry.enemyRect(
                    session, idx, 4, resolveImage and resolveImage(enemy) or nil)
            end
        end
    end

    -- Domain roster writes may already be final while a wave/reap card is still
    -- on screen. Geometry is presentation state, so resolve party identities
    -- through the same BattleView session facade as the windows. This preserves
    -- popup/animation anchors for outgoing battlers without undoing GameSession.
    local viewSession = battle_view.sessionFor(session)
    local party = viewSession and viewSession.party or {}
    for idx = 1, 4 do
        local member = party[idx]
        if member == target then
            return battler_geometry.partyRect(viewSession, idx)
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Anchors
---------------------------------------------------------------------------

-- Resolve an anchor spec against a rect. Returns x, y in screen pixels.
-- An unknown `point` raises: a silently-centered animation is exactly the
-- "feature that quietly does nothing" the non-negotiables forbid.
function battler_geometry.anchor(rect, spec)
    if not rect then return nil, nil end
    spec = spec or {}
    local point = spec.point or "center"
    if not battler_geometry.ANCHOR_POINTS[point] then
        error("unknown anchor point '" .. tostring(point) .. "' (expected one of "
            .. "center, feet, head, top_left)", 0)
    end

    local x, y
    if point == "center" then
        x, y = rect.x + rect.w / 2, rect.y + rect.h / 2
    elseif point == "feet" then
        x, y = rect.x + rect.w / 2, rect.y + rect.h
    elseif point == "head" then
        x, y = rect.x + rect.w / 2, rect.y
    else -- top_left
        x, y = rect.x, rect.y
    end

    x = x + (spec.offsetX or 0) + (spec.relativeOffsetX or 0) * rect.w
    y = y + (spec.offsetY or 0) + (spec.relativeOffsetY or 0) * rect.h
    return x, y
end

-- The anchor a battler's damage popups spawn at (engine.json battleLayout
-- popupAnchor*). One spec for both sides -- a popup is attached to the
-- creature, not to a hardcoded row y.
function battler_geometry.popupAnchor(session, rect)
    return battler_geometry.anchor(rect, {
        point = layoutVal(session, "popupAnchorPoint"),
        offsetX = layoutVal(session, "popupAnchorOffsetX"),
        offsetY = layoutVal(session, "popupAnchorOffsetY"),
        relativeOffsetX = layoutVal(session, "popupAnchorRelativeX"),
        relativeOffsetY = layoutVal(session, "popupAnchorRelativeY"),
    })
end

---------------------------------------------------------------------------
-- Enemy info block (name + element icons + HP gauge)
---------------------------------------------------------------------------

-- Where an enemy's info block sits and what it shows, entirely from
-- engine.json battleLayout (`enemyInfo*`). Anchored to the creature's feet,
-- not to an absolute row, so it follows the sprite when the row moves.
-- Returns nil when the whole block is switched off.
function battler_geometry.enemyInfo(session, rect, slotWidth)
    if layoutVal(session, "enemyInfoVisible") == false then return nil end

    local width = layoutVal(session, "enemyInfoWidth")
    if layoutVal(session, "enemyInfoClampToSlot") and slotWidth then
        width = math.min(width, slotWidth)
    end

    local centerX = rect.x + rect.w / 2
    local x = centerX - width / 2
    local nameY = rect.y + rect.h + layoutVal(session, "enemyInfoOffsetY")
    return {
        x = x,
        width = width,
        nameY = nameY,
        barY = nameY + layoutVal(session, "enemyInfoBarOffsetY"),
        showName = layoutVal(session, "enemyInfoShowName") ~= false,
        showHpBar = layoutVal(session, "enemyInfoShowHpBar") ~= false,
        showElements = layoutVal(session, "enemyInfoShowElements") ~= false,
    }
end

return battler_geometry
