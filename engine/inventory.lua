-- The inventory ordering contract.
--
-- session.inventory is a sparse id->qty map, so every consumer that speaks
-- in 1-based indices ("use item 3") has to agree on the order those indices
-- number. The window renderer's 'inventory' list source displays that order;
-- the interpreter and the battle item menus index back into it. If any of
-- them sorted differently the player would pick one item and use another,
-- so the comparator lives here rather than being restated per call site.
--
-- Numeric ids sort numerically and ahead of string ids, which sort
-- lexically -- a plain tostring() sort would put id 10 before id 2.

local inventory = {}

function inventory.compareIds(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na < nb end
    if na then return true end
    if nb then return false end
    return tostring(a) < tostring(b)
end

return inventory
