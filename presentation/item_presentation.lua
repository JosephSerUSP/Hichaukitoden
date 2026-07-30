-- Shared presentation view for items.
--
-- Item descriptions remain authored flavor.  Mechanical text is derived from
-- the same effect/trait data the engine executes and the registry labels the
-- editor exposes, so shop and inventory can never drift into separate copies.

local item_presentation = {}

local function registryBy(entries, field)
    local out = {}
    for _, entry in ipairs(entries or {}) do out[entry[field]] = entry end
    return out
end

local function prettyId(value)
    local text = tostring(value or ""):gsub("_", " ")
    return text:gsub("(%a)([%w']*)", function(a, b)
        return a:upper() .. b:lower()
    end)
end

local function numberText(value)
    if type(value) ~= "number" then return tostring(value) end
    if value == math.floor(value) then return tostring(math.floor(value)) end
    return tostring(value):gsub("0+$", ""):gsub("%.$", "")
end

local function percentText(value, signed)
    local n = math.floor(math.abs(value) * 100 + 0.5)
    if signed then return (value >= 0 and "+" or "-") .. n .. "%" end
    return n .. "%"
end

local function effectText(effect, def, loader)
    local label = (def and def.label) or prettyId(effect.type)
    local parts = {}
    for _, key in ipairs((def and def.params) or {}) do
        local value = effect[key]
        if value ~= nil and value ~= "" then
            if key == "percent" or key == "chance" then
                table.insert(parts, percentText(tonumber(value) or 0, false))
            elseif key == "status" or (effect.type == "remove_status" and key == "value") then
                local state = loader and loader.getState and loader.getState(value)
                table.insert(parts, (state and state.name) or prettyId(value))
            elseif key == "skill" then
                local skill = loader and loader.getSkill and loader.getSkill(value)
                table.insert(parts, (skill and skill.name) or prettyId(value))
            else
                table.insert(parts, prettyId(key) .. " " .. numberText(value))
            end
        end
    end
    return label .. (#parts > 0 and ": " .. table.concat(parts, ", ") or "")
end

local function traitText(trait, def)
    local label = (def and def.label) or prettyId(trait.code)
    local subject = trait.dataId and prettyId(trait.dataId) or nil
    local value = tonumber(trait.value)
    local valueText
    if value then
        if trait.code == "PARAM_RATE" then
            valueText = percentText(value - 1, true)
        elseif trait.code == "HIT" or trait.code == "EVA" or trait.code == "CRI"
            or trait.code == "HRG" or trait.code:find("_RATE", 1, true) then
            valueText = percentText(value, true)
        else
            valueText = (value >= 0 and "+" or "") .. numberText(value)
        end
    end
    local detail = {}
    if subject then table.insert(detail, subject) end
    if valueText then table.insert(detail, valueText) end
    return label .. (#detail > 0 and ": " .. table.concat(detail, " ") or "")
end

function item_presentation.gameplayText(item, loader)
    if not item then return "" end
    local engine = loader and loader.engine or {}
    local effects = registryBy(engine.effectTypes, "id")
    local traits = registryBy(engine.traitCodes, "code")
    local lines = {}
    for _, effect in ipairs(item.effects or {}) do
        table.insert(lines, effectText(effect, effects[effect.type], loader))
    end
    for _, trait in ipairs(item.traits or {}) do
        table.insert(lines, traitText(trait, traits[trait.code]))
    end
    if item.savor and item.savor.traits then
        for _, trait in ipairs(item.savor.traits) do
            table.insert(lines, "Savor - " .. traitText(trait, traits[trait.code]))
        end
    end
    if #lines == 0 then
        if item.equipType then return item.equipType .. " - no traits." end
        return "No direct effects or traits."
    end
    return table.concat(lines, "\n")
end

function item_presentation.enrich(row, item, loader)
    row.description = item.description or ""
    row.keyArt = item.keyArt or ""
    row.gameplayText = item_presentation.gameplayText(item, loader)
    return row
end

return item_presentation
