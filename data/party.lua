local party = {}

-- Helper functions
local function randInt(min, max)
    return math.random(min, max)
end

local function shuffleArray(tbl)
    local n = #tbl
    for i = n, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

local function slice(tbl, start_idx, end_idx)
    local res = {}
    for i = start_idx, end_idx do
        if tbl[i] then
            table.insert(res, tbl[i])
        end
    end
    return res
end

function party.getGold()
    return randInt(25, 75)
end

function party.getInventory(allItems)
    local inventory = {}
    local consumables = {}
    local equipment = {}

    for _, item in ipairs(allItems) do
        if item.type == 'consumable' and item.id ~= 1 then -- 1 = HP Tonic
            table.insert(consumables, item)
        elseif item.type == 'equipment' then
            table.insert(equipment, item)
        end
    end

    -- 1-3 HP Tonics
    local hpTonic
    for _, item in ipairs(allItems) do
        if item.id == 1 then -- HP Tonic
            hpTonic = item
            break
        end
    end

    if hpTonic then
        local amount = randInt(1, 3)
        for i = 1, amount do
            table.insert(inventory, hpTonic)
        end
    end

    -- 2 random consumables
    consumables = shuffleArray(consumables)
    local randomConsumables = slice(consumables, 1, 2)
    for _, item in ipairs(randomConsumables) do
        table.insert(inventory, item)
    end

    -- 2 random pieces of equipment
    equipment = shuffleArray(equipment)
    local randomEquipment = slice(equipment, 1, 2)
    for _, item in ipairs(randomEquipment) do
        table.insert(inventory, item)
    end

    return inventory
end

function party.getMembers(allActors)
    local availableCreatures = {}
    for _, creature in ipairs(allActors) do
        if creature.initialParty then
            table.insert(availableCreatures, creature)
        end
    end

    if math.random() < 0.25 then
        -- 2 creatures, one leveled up
        availableCreatures = shuffleArray(availableCreatures)
        local creature1 = availableCreatures[1]
        local creature2 = availableCreatures[2]
        return {
            { id = creature1.id, level = creature1.level },
            { id = creature2.id, level = creature2.level + 3 }
        }
    else
        -- 3 creatures at base level
        availableCreatures = shuffleArray(availableCreatures)
        local res = {}
        for i = 1, math.min(3, #availableCreatures) do
            local data = availableCreatures[i]
            table.insert(res, { id = data.id, level = data.level })
        end
        return res
    end
end

return party
