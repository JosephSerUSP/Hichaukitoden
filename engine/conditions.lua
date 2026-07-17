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

    return false
end

return conditions
