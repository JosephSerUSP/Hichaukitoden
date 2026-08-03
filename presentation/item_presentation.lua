-- Shared presentation view for items.
--
-- Item descriptions remain authored flavor.  Mechanical text is derived from
-- the same effect/trait data the engine executes and the registry labels the
-- editor exposes, so shop and inventory can never drift into separate copies.
--
-- The vocabulary is DATA (engine.json -> traitCodes[].display /
-- effectTypes[].display), not prose assembled here.  Each row resolves to a
-- short noun phrase and one value, drawn as two columns:
--
--     Pierce              45%
--     ATK                 +23
--     Sleep Risk          70%
--
-- rather than the old sentence form ("Armor Penetration: 45%", "Parameter +:
-- Atk + 23"), which wrapped to two or three lines in the 14-tile info pane and
-- read like a debug dump.  The value carries a TONE -- whether this number is
-- good or bad for the holder -- so the player reads the sign before the word.
-- Tone comes from the registry's `polarity` (does higher help, or hurt?) and
-- the value's own sign, so an author never hand-colours anything.

local item_presentation = {}

-- Value column formats. `neutral` is the value that means "no change", which
-- is 1 for the multiplicative rates and 0 for everything else -- tone is read
-- against it, not against zero, or DAMAGE_RATE 0.82 would read as a penalty.
local FORMATS = {
    signed           = { neutral = 0 },
    percent          = { neutral = 0 },
    percentSigned    = { neutral = 0 },
    multiplier       = { neutral = 1 },
    multiplierSigned = { neutral = 1 },
    subject          = { neutral = 0 },
    none             = { neutral = 0 },
}

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

local function signedText(value)
    return (value >= 0 and "+" or "") .. numberText(value)
end

-- Which way a number points for the holder. `polarity` says whether more of
-- this trait helps ("higher"), hurts ("lower"), or is simply a fact with no
-- direction ("none" -- an element swap is neither).
local function toneFor(polarity, value, neutral)
    if polarity == "none" or polarity == nil then return "neutral" end
    if value == nil then
        -- A flag trait (Rear Guard, Trap Sense): its mere presence is the
        -- statement, so the polarity IS the tone.
        return polarity == "lower" and "bad" or "good"
    end
    if value == neutral then return "neutral" end
    local better = value > neutral
    if polarity == "lower" then better = not better end
    return better and "good" or "bad"
end

-- One registry-declared subject (the trait's dataId, or the named parameter of
-- an effect) rendered as the player's word for it.
local function subjectText(kind, value, loader, engine)
    if value == nil or value == "" then return nil end
    if kind == "param" then
        local labels = (engine and engine.paramLabels) or {}
        return labels[value] or tostring(value):upper()
    elseif kind == "state" then
        local state = loader and loader.getState and loader.getState(value)
        return (state and state.name) or prettyId(value)
    elseif kind == "skill" then
        local skill = loader and loader.getSkill and loader.getSkill(value)
        return (skill and skill.name) or prettyId(value)
    elseif kind == "actor" then
        local actor = loader and loader.getActor and loader.getActor(value)
        return (actor and actor.name) or prettyId(value)
    elseif kind == "element" then
        local element = loader and loader.getElement and loader.getElement(value)
        return (element and element.name) or prettyId(value)
    end
    -- state categories are authored as their own display words
    return prettyId(value)
end

local function applySubject(short, subject)
    if not short then return nil end
    if not short:find("{d}", 1, true) then return short end
    if not subject then
        -- The template needs a subject and has none: fall back to the bare
        -- template minus the slot rather than printing "{d}".
        return (short:gsub("%s*{d}%s*", " "):gsub("^%s+", ""):gsub("%s+$", ""))
    end
    return (short:gsub("{d}", (subject:gsub("%%", "%%%%"))))
end

-- ---------------------------------------------------------------------------
-- Traits
-- ---------------------------------------------------------------------------

local function traitRow(trait, def, loader, engine)
    local display = (def and def.display) or {}
    local format = FORMATS[display.value] and display.value or "signed"
    local neutral = FORMATS[format].neutral
    local subject = subjectText(display.subject, trait.dataId, loader, engine)
    local label = applySubject(display.short, subject)
        or (def and def.label) or prettyId(trait.code)
    local value = tonumber(trait.value)

    local valueText
    if format == "subject" then
        valueText = subject
        value = nil
    elseif format == "none" then
        valueText = nil
        value = nil
    elseif value then
        if format == "percent" then
            valueText = percentText(value, false)
        elseif format == "percentSigned" then
            valueText = percentText(value, true)
        elseif format == "multiplier" then
            valueText = percentText(value, false)
        elseif format == "multiplierSigned" then
            valueText = percentText(value - 1, true)
        else
            valueText = signedText(value)
        end
    end

    return {
        icon = display.icon,
        label = label,
        value = valueText,
        tone = toneFor(display.polarity, value, neutral),
    }
end

-- ---------------------------------------------------------------------------
-- Effects
-- ---------------------------------------------------------------------------

local function contains(list, needle)
    for _, entry in ipairs(list or {}) do
        if entry == needle then return true end
    end
    return false
end

local function effectRow(effect, def, loader, engine)
    local display = (def and def.display) or {}
    local subject = subjectText(display.subject,
        display.subjectParam and effect[display.subjectParam], loader, engine)
    local label = applySubject(display.short, subject)
        or (def and def.label) or prettyId(effect.type)

    local magnitude = (engine and engine.magnitudeKeys) or { "value", "amount" }
    local hidden = (engine and engine.hiddenEffectKeys) or {}
    local parts, signal = {}, nil
    -- `value: "none"` is an effect whose numbers are engine bookkeeping rather
    -- than something the player can act on -- a common event's id is the case
    -- that motivated it.
    for _, key in ipairs(display.value ~= "none" and ((def and def.params) or {}) or {}) do
        local value = effect[key]
        -- The key that names the subject is already IN the label; repeating it
        -- in the value column is what produced "Remove Status: Weakened".
        local named = display.subjectParam == key
        if value ~= nil and value ~= "" and not named and not contains(hidden, key) then
            if key == "percent" or key == "chance" then
                local pct = tonumber(value) or 0
                -- A guaranteed effect is the default; "100%" is noise.
                if pct < 1 then table.insert(parts, percentText(pct, false)) end
            elseif key == "duration" then
                table.insert(parts, numberText(value) .. "t")
            elseif contains(magnitude, key) then
                signal = tonumber(value)
                table.insert(parts, numberText(value))
            else
                table.insert(parts, prettyId(key) .. " " .. numberText(value))
            end
        end
    end

    return {
        icon = display.icon,
        label = label,
        value = #parts > 0 and table.concat(parts, " ") or nil,
        tone = toneFor(display.polarity, signal, 0),
    }
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- The item's mechanics as display rows: { icon, label, value, tone }.
-- `value` may be nil (a flag trait states itself); `tone` is one of
-- "good" / "bad" / "neutral" and is what the renderer colours by.
function item_presentation.rows(item, loader)
    if not item then return {} end
    local engine = (loader and loader.engine) or {}
    local effects = registryBy(engine.effectTypes, "id")
    local traits = registryBy(engine.traitCodes, "code")
    local rows = {}

    for _, effect in ipairs(item.effects or {}) do
        table.insert(rows, effectRow(effect, effects[effect.type], loader, engine))
    end
    for _, trait in ipairs(item.traits or {}) do
        table.insert(rows, traitRow(trait, traits[trait.code], loader, engine))
    end
    if item.savor and item.savor.traits and #item.savor.traits > 0 then
        -- Savor is a temporary, per-creature blessing rather than a property
        -- of the item in your hands, so it gets said ONCE, as a heading, and
        -- its traits indent under it. Repeating the word on every row
        -- ("Savor First Strike +15%") spent six of the pane's twenty
        -- characters restating something the player already read.
        table.insert(rows, { label = "Savor", tone = "neutral", heading = true })
        for _, trait in ipairs(item.savor.traits) do
            local row = traitRow(trait, traits[trait.code], loader, engine)
            row.indent = true
            table.insert(rows, row)
        end
    end

    if #rows == 0 then
        table.insert(rows, {
            label = item.equipType and (item.equipType .. ", plain") or "No effects",
            tone = "neutral",
        })
    end
    return rows
end

-- Flat text form of the same rows, for any surface that can only take a
-- string (traces, tooltips, the editor).  The two-column renderer uses
-- item_presentation.rows directly so it can colour and align.
function item_presentation.gameplayText(item, loader)
    local out = {}
    for _, row in ipairs(item_presentation.rows(item, loader)) do
        local label = row.indent and ("  " .. row.label) or row.label
        table.insert(out, row.value and (label .. " " .. row.value) or label)
    end
    return table.concat(out, "\n")
end

function item_presentation.enrich(row, item, loader)
    row.description = item.description or ""
    row.keyArt = item.keyArt or ""
    row.gameplayRows = item_presentation.rows(item, loader)
    row.gameplayText = item_presentation.gameplayText(item, loader)
    return row
end

return item_presentation
