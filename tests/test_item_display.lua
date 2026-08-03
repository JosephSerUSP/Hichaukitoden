-- The item/trait readout vocabulary (presentation/item_presentation.lua).
--
-- Invisible to every golden gate: G2 diffs battle logs, G3 diffs UI *events*,
-- and the two-column pane is drawn from `gameplayRows`, which no trace
-- records. The rules that matter here are exactly the ones that made the old
-- readout unreadable -- a label that is a sentence, a number with no
-- direction, a subject repeated in both columns -- so they get pinned.

package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local item_presentation = require("presentation.item_presentation")

print("[TEST] Starting item display tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  [PASS] " .. msg)
    else
        failed = failed + 1
        print("  [FAIL] " .. msg)
    end
end

loader.init()

local function rowsOf(item)
    return item_presentation.rows(item, loader)
end

local function firstRow(item)
    return rowsOf(item)[1]
end

---------------------------------------------------------------- vocabulary --

local row = firstRow({ traits = { { code = "PENETRATION", value = 0.45 } } })
check(row.label == "Pierce" and row.value == "45%",
    "Armor Penetration reads as 'Pierce 45%', not a sentence")

row = firstRow({ traits = { { code = "PARAM_PLUS", dataId = "atk", value = 23 } } })
check(row.label == "ATK" and row.value == "+23",
    "a parameter bonus is the parameter's own name plus a signed number")

row = firstRow({ traits = { { code = "PARAM_RATE", dataId = "maxHp", value = 1.1 } } })
check(row.label == "HP" and row.value == "+10%",
    "a parameter rate reads as the change, not the multiplier")

row = firstRow({ traits = { { code = "DAMAGE_RATE", value = 0.82 } } })
check(row.label == "Dmg Taken" and row.value == "82%",
    "a multiplicative rate keeps its absolute form")

-- The label is short enough to leave the value room in a 14-tile pane. 11
-- characters is the measured budget: the Savor heading indents its rows, and
-- "Damage Taken 90%" under that indent was the case that truncated on screen.
-- A regression here is a label that WILL be cut off, not one that might be.
for _, def in ipairs(loader.engine.traitCodes) do
    local short = def.display and def.display.short or ""
    if not short:find("{d}", 1, true) then
        check(#short <= 11, "trait '" .. def.code .. "' label fits the info pane: '" .. short .. "'")
    end
end

------------------------------------------------------------------- subject --

row = firstRow({ traits = { { code = "STATE_RATE", dataId = "sleep", value = 0.7 } } })
check(row.label:find("Risk", 1, true) and row.value == "70%",
    "a state rate names the state and states the odds")

row = firstRow({ traits = { { code = "ELEMENT_CHANGE", dataId = "Red" } } })
check(row.label == "Element" and row.value == "Red",
    "a subject-valued trait puts the subject in the value column")

row = firstRow({ effects = { { type = "remove_status", value = "weakened" } } })
check(row.label:find("Cures", 1, true) and row.value == nil,
    "a cure names the status once, in the label, and carries no number")

row = firstRow({ effects = { { type = "add_status", status = "regen", chance = 1, duration = 3 } } })
check(row.value == "3t", "a guaranteed status shows its duration, not '100%'")

row = firstRow({ effects = { { type = "common_event", value = 41 } } })
check(row.value == nil, "a common-event hook does not print its internal id")

----------------------------------------------------------------------- tone --

local function toneOf(trait)
    return firstRow({ traits = { trait } }).tone
end

check(toneOf({ code = "PARAM_PLUS", dataId = "atk", value = 5 }) == "good",
    "a bonus reads as good")
check(toneOf({ code = "HIT", value = -0.15 }) == "bad",
    "a penalty reads as bad")
check(toneOf({ code = "DAMAGE_RATE", value = 0.82 }) == "good",
    "taking LESS damage reads as good, though the number went down")
check(toneOf({ code = "STATE_RATE", dataId = "sleep", value = 1.5 }) == "bad",
    "being MORE susceptible reads as bad, though the number went up")
check(toneOf({ code = "ELEMENT_ADD", dataId = "Red" }) == "neutral",
    "an element change is a fact, not a bonus")
check(toneOf({ code = "REAR_GUARD", value = 1 }) == "good",
    "a flag trait takes its tone from its polarity alone")

------------------------------------------------------------------- registry --

-- Every registered code renders. This is the check that catches a trait added
-- without a display block once the validator's own check is ever relaxed.
for _, def in ipairs(loader.engine.traitCodes) do
    local r = firstRow({ traits = { { code = def.code, dataId = "sleep", value = 1 } } })
    check(r and r.label and r.label ~= "" and r.label:find("{d}", 1, true) == nil,
        "trait '" .. def.code .. "' renders a label")
end
for _, def in ipairs(loader.engine.effectTypes) do
    local r = firstRow({ effects = { { type = def.id, value = 1 } } })
    check(r and r.label and r.label ~= "" and r.label:find("{d}", 1, true) == nil,
        "effect '" .. def.id .. "' renders a label")
end

-- An item with nothing mechanical still says so in one row rather than none,
-- or the pane would draw empty and read as a missing value.
check(#rowsOf({ equipType = "Weapon" }) == 1, "a plain item still gets one row")

------------------------------------------------------------------ real data --

-- Nothing in the shipped atlas produces a row too wide for the pane once the
-- label is truncated: the VALUE must always fit on its own, since it is the
-- column the player scans.
local overlong = {}
for _, item in ipairs(loader.items or {}) do
    for _, r in ipairs(rowsOf(item)) do
        if r.value and #r.value > 8 then
            table.insert(overlong, (item.id or "?") .. ": " .. r.value)
        end
    end
end
check(#overlong == 0, "no authored item produces an overlong value column"
    .. (#overlong > 0 and (" (" .. table.concat(overlong, ", ") .. ")") or ""))

print(("=== Item Display Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("item display tests failed", failed) end
