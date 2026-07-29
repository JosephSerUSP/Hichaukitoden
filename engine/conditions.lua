-- Shared condition-string grammar for the "flag:<name>" and "hasItem:<id>"
-- prefixes, used by BOTH engine/director.lua's ROUTER evaluation and
-- engine/interpreter.lua's IF handler. Each caller keeps its OWN fallback
-- for non-prefixed strings (director returns false; interpreter evaluates
-- the string as a formula), so this module owns only the prefix cases —
-- keeping the two grammars from drifting apart.
local conditions = {}

local s_find = string.find
local s_sub = string.sub
local s_match = string.match
local s_gmatch = string.gmatch
local tonumber = tonumber
local type = type

-- Returns (matched, result):
--   matched = true  -> the string used a known prefix; result is the boolean
--                      outcome of that prefix's check
--   matched = false -> not a prefixed condition; the caller applies its own
--                      fallback (result is nil)
function conditions.evalPrefixed(condStr, session)
    if type(condStr) ~= "string" then return false end

    local firstColon = s_find(condStr, ":", 1, true)

    if firstColon and firstColon < #condStr then
        local prefix = s_sub(condStr, 1, firstColon - 1)

        if prefix == "flag" then
            return true, session.flags[s_sub(condStr, firstColon + 1)] == true
        elseif prefix == "gold" then
            local amt = tonumber(s_sub(condStr, firstColon + 1)) or 0
            return true, (session and (session.gold or 0) >= amt)
        elseif prefix == "hasItem" then
            -- Item ids are numeric; the pattern always yields a string, so convert
            -- it back before checking the (numeric-keyed) inventory table.
            return true, session:hasItem(tonumber(s_sub(condStr, firstColon + 1)), 1)
        elseif prefix == "questStatus" then
            local rest = s_sub(condStr, firstColon + 1)
            local secondColon = s_find(rest, ":", 1, true)
            if secondColon and secondColon > 1 and secondColon < #rest then
                -- Quest lifecycle is tracked as two flags ("quest:<id>:active" /
                -- "quest:<id>:completed"), set by the QUEST_OFFER/QUEST_COMPLETE
                -- ACTION handlers in main.lua. "inactive" means neither flag is set
                -- yet (quest never offered).
                local questId = s_sub(rest, 1, secondColon - 1)
                local questStatus = s_sub(rest, secondColon + 1)
                local active = session.flags["quest:" .. questId .. ":active"] == true
                local completed = session.flags["quest:" .. questId .. ":completed"] == true
                if questStatus == "active" then return true, active end
                if questStatus == "completed" then return true, completed end
                if questStatus == "inactive" then return true, not (active or completed) end
                return true, false
            end
        end
    end

    -- Comma-separated conditions AND together (e.g. "flag:a, hasItem:5"),
    -- as long as every part resolves through a known prefix above; if any
    -- part doesn't match, the whole string falls through to the caller's
    -- own fallback rather than partially matching.
    if s_find(condStr, ",", 1, true) then
        local allMatched = true
        local allTrue = true
        for part in s_gmatch(condStr, "[^,]+") do
            local trimmed = s_match(part, "^%s*(.-)%s*$")
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
