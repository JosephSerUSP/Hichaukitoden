-- New-game setup rules, driven by the system.newGame block in data/system.json
-- (previously hardcoded in data/party.lua). All quantities, chances and item
-- ids are editable from the editor's System tab.
local newgame = {}

local function ngConf(loader)
    return (loader.system and loader.system.newGame) or {}
end

local function shuffleArray(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

function newgame.rollGold(loader)
    local ng = ngConf(loader)
    return math.random(ng.goldMin or 25, ng.goldMax or 75)
end

-- Returns a list of item ids (repeats allowed) for the starting inventory
function newgame.rollInventory(loader)
    local ng = ngConf(loader)
    local ids = {}

    local guaranteed = ng.guaranteedItem
    local guaranteedId = guaranteed and guaranteed.id or nil

    -- Guaranteed staple (e.g. HP Tonics), random quantity
    if guaranteed and loader.getItem(guaranteedId) then
        local amount = math.random(guaranteed.minQty or 1, guaranteed.maxQty or 1)
        for _ = 1, amount do
            table.insert(ids, guaranteedId)
        end
    end

    -- Pools for the random picks
    local consumables = {}
    local equipment = {}
    for _, item in ipairs(loader.items) do
        if item.type == "consumable" and item.id ~= guaranteedId then
            table.insert(consumables, item.id)
        elseif item.type == "equipment" then
            table.insert(equipment, item.id)
        end
    end

    shuffleArray(consumables)
    for i = 1, math.min(ng.randomConsumables or 0, #consumables) do
        table.insert(ids, consumables[i])
    end

    shuffleArray(equipment)
    for i = 1, math.min(ng.randomEquipment or 0, #equipment) do
        table.insert(ids, equipment[i])
    end

    -- Fixed bonus items (always granted)
    for _, itemId in ipairs(ng.bonusItems or {}) do
        if loader.getItem(itemId) then
            table.insert(ids, itemId)
        end
    end

    return ids
end

-- Returns { { id = actorId, level = n }, ... } for the starting party
function newgame.rollMembers(loader)
    local ng = ngConf(loader)
    local partyRules = ng.party or {}

    local available = {}
    for _, creature in ipairs(loader.actors) do
        if creature.initialParty then
            table.insert(available, creature)
        end
    end
    shuffleArray(available)

    if #available >= 2 and math.random() < (partyRules.twoMemberChance or 0.25) then
        -- Smaller party, but the second member starts with bonus levels
        local bonus = partyRules.twoMemberBonusLevels or 3
        return {
            { id = available[1].id, level = available[1].level },
            { id = available[2].id, level = (available[2].level or 1) + bonus }
        }
    end

    local members = {}
    for i = 1, math.min(partyRules.defaultSize or 3, #available) do
        table.insert(members, { id = available[i].id, level = available[i].level })
    end
    return members
end

return newgame
