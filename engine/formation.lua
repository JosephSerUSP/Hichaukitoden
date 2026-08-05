-- Pure formation geometry and group-slot operations.
-- No dependencies on battle state, traits, targeting, or session rules.

local formation = {}

formation.SLOT_COUNT = 4

function formation.isValidSlot(slot)
    return type(slot) == "number" and slot >= 1 and slot <= 4 and math.floor(slot) == slot
end

function formation.rowOf(slot)
    if not formation.isValidSlot(slot) then return nil end
    return (slot <= 2) and "front" or "back"
end

function formation.colOf(slot)
    if not formation.isValidSlot(slot) then return nil end
    return ((slot - 1) % 2) + 1
end

function formation.slotAt(row, col)
    if (row ~= "front" and row ~= "back") or (col ~= 1 and col ~= 2) then return nil end
    return (row == "front") and col or (col + 2)
end

function formation.alignedFrontSlot(slot)
    if not formation.isValidSlot(slot) then return nil end
    return formation.colOf(slot) -- slot 1 or 2 for col 1 or 2
end

function formation.alignedBackSlot(slot)
    if not formation.isValidSlot(slot) then return nil end
    return formation.colOf(slot) + 2 -- slot 3 or 4 for col 1 or 2
end

function formation.occupantAt(group, slot)
    if not group or not formation.isValidSlot(slot) then return nil end
    return group[slot]
end

function formation.rowMembers(group, row)
    local members = {}
    if not group then return members end
    local startSlot = (row == "front") and 1 or (row == "back" and 3 or nil)
    if not startSlot then return members end
    for slot = startSlot, startSlot + 1 do
        local battler = group[slot]
        if battler then
            table.insert(members, battler)
        end
    end
    return members
end

function formation.columnMembers(group, col)
    local members = {}
    if not group or (col ~= 1 and col ~= 2) then return members end
    for _, slot in ipairs({ col, col + 2 }) do
        local battler = group[slot]
        if battler then
            table.insert(members, battler)
        end
    end
    return members
end

function formation.slotOf(group, battler)
    if not group or not battler then return nil end
    for slot = 1, formation.SLOT_COUNT do
        if group[slot] == battler then
            return slot
        end
    end
    return nil
end

function formation.denseMembers(group)
    local list = {}
    if not group then return list end
    for slot = 1, formation.SLOT_COUNT do
        if group[slot] then
            table.insert(list, group[slot])
        end
    end
    return list
end

-- Pack an arbitrary list of battlers into slots 1..maxSlots deterministically.
-- Used ONLY for:
--  - legacy-save migration (v1 -> v2)
--  - fixed members / recruits without an authored or preferred slot
--  - enemy placement without authored slots
function formation.autoPack(list, maxSlots)
    maxSlots = maxSlots or formation.SLOT_COUNT
    local packed = {}
    local slot = 1
    for _, b in ipairs(list or {}) do
        if b and slot <= maxSlots then
            packed[slot] = b
            slot = slot + 1
        end
    end
    return packed
end

return formation
