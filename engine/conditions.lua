-- Shared condition-string grammar for the "flag:<name>" and "hasItem:<id>"
-- prefixes, used by BOTH engine/director.lua's ROUTER evaluation and
-- engine/interpreter.lua's IF handler. Each caller keeps its OWN fallback
-- for non-prefixed strings (director returns false; interpreter evaluates
-- the string as a formula), so this module owns only the prefix cases —
-- keeping the two grammars from drifting apart.
local conditions = {}

-- Returns (matched, result):
--   matched = true  -> the string used a known prefix; result is the boolean
--                      outcome of that prefix's check
--   matched = false -> not a prefixed condition; the caller applies its own
--                      fallback (result is nil)
function conditions.evalPrefixed(condStr, session)
    if type(condStr) ~= "string" then return false end

    local flag = condStr:match("^flag:(.+)")
    if flag then
        return true, session.flags[flag] == true
    end

    local itemStr = condStr:match("^hasItem:(.+)")
    if itemStr then
        -- Item ids are numeric; the pattern always yields a string, so convert
        -- it back before checking the (numeric-keyed) inventory table.
        return true, session:hasItem(tonumber(itemStr), 1)
    end

    local questId, questStatus = condStr:match("^questStatus:([%w_]+):([%w_]+)")
    if questId then
        -- Quest lifecycle is tracked as two flags ("quest:<id>:active" /
        -- "quest:<id>:completed"), set by the QUEST_OFFER/QUEST_COMPLETE
        -- ACTION handlers in main.lua. "inactive" means neither flag is set
        -- yet (quest never offered).
        local active = session.flags["quest:" .. questId .. ":active"] == true
        local completed = session.flags["quest:" .. questId .. ":completed"] == true
        if questStatus == "active" then return true, active end
        if questStatus == "completed" then return true, completed end
        if questStatus == "inactive" then return true, not (active or completed) end
        return true, false
    end

    -- Comma-separated conditions AND together (e.g. "flag:a, hasItem:5"),
    -- as long as every part resolves through a known prefix above; if any
    -- part doesn't match, the whole string falls through to the caller's
    -- own fallback rather than partially matching.
    if condStr:find(",") then
        local allMatched = true
        local allTrue = true
        for part in condStr:gmatch("[^,]+") do
            local trimmed = part:match("^%s*(.-)%s*$")
            local matched, result = conditions.evalPrefixed(trimmed, session)
            if not matched then
                allMatched = false
                break
            end
            if not result then allTrue = false end
        end
        if allMatched then return true, allTrue end
    end

    return false
end

return conditions
