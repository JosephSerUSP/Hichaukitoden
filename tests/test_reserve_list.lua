-- Regression guard for #145: Reserve is an ordered list, not a formation grid.
-- This is intentionally structural: it pins the declarative scene contract and
-- the swap-source seam without depending on pixel output or G5.

local M = {}

local function findWindow(scene, id)
    for _, win in ipairs((scene and scene.windows) or {}) do
        if win.id == id then return win end
    end
    return nil
end

local function firstList(win)
    for _, entry in ipairs((win and win.content) or {}) do
        if entry.type == "list" then return entry end
    end
    return nil
end

function M.run()
    local loader = require("data.loader")

    local reserve = assert(loader.getScene("reserve"), "reserve scene missing")
    local roster = assert(findWindow(reserve, "reserve_roster"), "reserve_roster window missing")
    local rosterList = assert(firstList(roster), "reserve_roster list content missing")

    assert(roster.style == "list", "dedicated Reserve roster must use list presentation")
    assert(roster.visibleRows == 4, "expedition Reserve list must expose its four ordered rows")
    assert(rosterList.listId == "reserve", "Reserve roster must read the canonical reserve source")
    assert(rosterList.format == "{name}" and rosterList.formatRight == "Lv.{level}",
        "Reserve rows must use the shared name + level list vocabulary")
    assert(rosterList.highlight and rosterList.highlight:find("swapSemanticSourceIndex", 1, true),
        "Reserve swap source must be represented by a list-row highlight")

    local scripts = reserve.scripts or {}
    local up = assert(scripts.navigateReserveUp, "Reserve up-navigation script missing")
    local down = assert(scripts.navigateReserveDown, "Reserve down-navigation script missing")
    assert(up:find("v.cursorIdx > 1", 1, true) and up:find("v.cursorIdx = v.cursorIdx - 1", 1, true),
        "Reserve Up must move one list row at a time")
    assert(down:find("v.cursorIdx < 4", 1, true) and down:find("v.cursorIdx = v.cursorIdx + 1", 1, true),
        "Reserve Down must move one list row at a time")

    local popup = assert(scripts.executeReservePopup, "Reserve popup script missing")
    assert(popup:find("v.swapSemanticSourceIndex = v.popupTargetIndex", 1, true),
        "swap gameplay source must be stored independently from presentation")
    assert(popup:find("v.swapSourceIndex = v.popupTargetIsReserve and nil or v.popupTargetIndex", 1, true),
        "Reserve-origin swaps must not feed the legacy grid ghost coordinate path")
    local swap = assert(scripts.executeSwap, "Reserve swap script missing")
    assert(swap:find("v.swapSemanticSourceIndex or v.swapSourceIndex", 1, true),
        "swap execution must consume the semantic source index")

    -- Recruitment established the vocabulary #145 is standardizing on. Keep
    -- the dedicated Reserve screen and recruitment placement surface aligned.
    local recruit = assert(loader.getScene("recruit"), "recruit scene missing")
    local recruitRoster = assert(findWindow(recruit, "reserve_roster"),
        "recruitment Reserve list missing")
    local recruitList = assert(firstList(recruitRoster), "recruitment Reserve list content missing")
    assert(recruitRoster.style == "list", "recruitment Reserve surface regressed to a grid")
    assert(recruitList.format == rosterList.format and recruitList.formatRight == rosterList.formatRight,
        "Reserve row vocabulary drifted between recruitment and management")

    print("  [PASS] Reserve roster uses list navigation and list-row swap pickup semantics")
end

return M
