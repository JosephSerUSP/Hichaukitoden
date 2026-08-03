-- Centralized icon rendering: resolution, palette lookup, key profiles.
--
-- The bugs these pin, all three of the same shape -- code reaching for a
-- global that does not exist, and failing silently rather than loudly:
--
--   * ui.lua resolved the registries via `rawget(_G, "loader")`. `loader` is
--     not a global anywhere in this repo (every other module does
--     `require("data.loader")`), so resolveIconPalette returned nil for every
--     palette and NOTHING was ever recolored in game. 190 of 198 items carry
--     an iconPalette; all of them rendered in their original colors.
--   * The editor had the same bug via `window.dbPayload` (a `let`, so never on
--     window) and papered over it with a hardcoded palette table that had
--     already drifted from data/iconPalettes.json.
--
-- G1 cannot catch this: it only proves the JSON parses and that every
-- iconPalette names a registered palette. It never exercises resolution, which
-- is where the whole feature lived. Hence this suite.
--
-- Everything here is deliberately draw-free. ui.drawIcon needs a graphics
-- context and a loaded iconset; the resolution rules above it are pure data,
-- and that is the seam these tests use.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local ui = require("presentation.ui")

print("[TEST] Starting icon tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

local function approx(a, b)
    return a and b and math.abs(a - b) < 0.001
end

loader.init()

-- === Icon reference resolution ===
print("=== Icon Reference Resolution ===")

local r = ui.resolveIcon(51)
check(r.id == 51 and r.palette == nil, "a bare integer resolves to that id with original colors")

r = ui.resolveIcon({ icon = 51 })
check(r.id == 51 and r.palette == nil, "an entity table reads its `icon` field")

r = ui.resolveIcon({ icon = 51, iconPalette = "sapphire" })
check(r.id == 51 and r.palette == "sapphire", "an entity table reads its `iconPalette` field")

r = ui.resolveIcon({ icon = 51, iconPalette = "sapphire" }, "ruby")
check(r.palette == "ruby", "an explicit palette override beats the entity's own")

r = ui.resolveIcon({ icon = 51 }, "ruby")
check(r.palette == "ruby", "an override applies to an entity that declares no palette")

r = ui.resolveIcon({ icon = 51, iconPalette = "" })
check(r.palette == nil, "an empty palette string means original colors, not a lookup miss")

r = ui.resolveIcon({ id = 51 })
check(r.id == 51, "a list row may carry its icon as `id`")

r = ui.resolveIcon({ icon = { id = 51, palette = "gold" } })
check(r.id == 51 and r.palette == "gold", "a normalized nested icon reference resolves")

check(ui.resolveIcon(nil).id == 0, "a nil source resolves to the empty icon")
check(ui.resolveIcon(0).id == 0, "icon 0 resolves to the empty icon")
check(ui.resolveIcon(-3).id == -3, "a negative id stays non-positive so drawIcon rejects it")
check(ui.resolveIcon({}).id == 0, "a table with no icon field resolves to the empty icon")
check(ui.resolveIcon("nonsense").id == 0, "a non-numeric, non-table source resolves to the empty icon")

-- === Palette registry ===
print("=== Palette Registry ===")

check(next(loader.iconPalettes or {}) ~= nil, "data/iconPalettes.json is loaded onto the loader")

-- The load-bearing one. `sapphire` exists ONLY in data/iconPalettes.json; if
-- resolution ever falls back to a hardcoded table again, pick a palette the
-- data file has and the fallback does not and this still fails.
local sapphire = ui.resolveIconPalette("sapphire")
check(sapphire ~= nil, "a palette resolves through the loader, not a hardcoded fallback")
check(sapphire and #sapphire == 4, "a resolved palette is a four-entry ramp")

if sapphire then
    -- "#051428" -> shadow entry, normalized to 0..1 RGBA.
    check(approx(sapphire[1][1], 0x05 / 255)
            and approx(sapphire[1][2], 0x14 / 255)
            and approx(sapphire[1][3], 0x28 / 255),
        "hex ramp colors are parsed into normalized 0..1 components")
    check(sapphire[1][4] == 1, "ramp colors are opaque")
end

-- Every registered palette must survive resolution, so a malformed entry that
-- G1 lets through still fails here rather than at draw time.
local allResolve, badPalette = true, nil
for paletteId in pairs(loader.iconPalettes or {}) do
    local resolved = ui.resolveIconPalette(paletteId)
    if not resolved or #resolved ~= 4 then
        allResolve, badPalette = false, paletteId
    end
end
check(allResolve, "every registered palette resolves to a four-entry ramp"
    .. (badPalette and (" (failed on '" .. badPalette .. "')") or ""))

check(ui.resolveIconPalette(nil) == nil, "no palette means no recolor")
check(ui.resolveIconPalette("no_such_palette") == nil, "an unregistered palette resolves to nil")

-- Resolution is cached; the cache must not corrupt the second read.
local first = ui.resolveIconPalette("ruby")
local second = ui.resolveIconPalette("ruby")
check(first ~= nil and first == second, "a resolved palette is cached and returned identically")

-- === Key profiles ===
print("=== Key Profiles ===")

check((loader.iconKeyProfiles or {})["default"] ~= nil,
    "data/iconKeyProfiles.json is loaded and carries a default profile")

local prof = ui.resolveIconKeyProfile(51)
check(prof ~= nil, "an icon with no custom profile still resolves a profile")
check(prof and prof.targetHue ~= nil and prof.hueTolerance ~= nil
        and prof.minimumSaturation ~= nil and prof.minimumLightness ~= nil
        and prof.maximumLightness ~= nil,
    "a resolved profile carries all five keying fields")

local defaults = loader.iconKeyProfiles["default"]
check(prof and approx(prof.hueTolerance, defaults.hueTolerance),
    "an uncalibrated icon inherits the default profile from data")
check(prof and prof.minimumLightness <= prof.maximumLightness,
    "the resolved lightness window is well-ordered")

-- Inheritance: a custom profile supplies some fields and inherits the rest.
local savedProfiles = loader.iconKeyProfiles
loader.iconKeyProfiles = {
    default = {
        targetHue = 0.0, hueTolerance = 0.08, minimumSaturation = 0.25,
        minimumLightness = 0.10, maximumLightness = 0.95,
    },
    ["84"] = { targetHue = 0.94, hueTolerance = 0.10 },
}

local custom = ui.resolveIconKeyProfile(84)
check(approx(custom.targetHue, 0.94), "a custom profile overrides the field it declares")
check(approx(custom.hueTolerance, 0.10), "a custom profile overrides every field it declares")
check(approx(custom.minimumSaturation, 0.25), "a custom profile inherits the fields it omits")
check(approx(custom.maximumLightness, 0.95), "inheritance covers the whole lightness window")

local uncalibrated = ui.resolveIconKeyProfile(85)
check(approx(uncalibrated.targetHue, 0.0),
    "a neighbouring icon is unaffected by another icon's calibration")

-- Profiles are keyed by string, but callers pass numeric ids.
check(approx(ui.resolveIconKeyProfile("84").targetHue, 0.94),
    "a profile resolves the same whether the id arrives as number or string")

loader.iconKeyProfiles = savedProfiles

-- === Authored data ===
print("=== Authored Data ===")

-- Every palette actually referenced by content must resolve. G1 checks the
-- name is registered; this checks the registration is usable.
local referenced, unresolvable = 0, nil
for _, item in ipairs(loader.items or {}) do
    if item.iconPalette and item.iconPalette ~= "" then
        referenced = referenced + 1
        if not ui.resolveIconPalette(item.iconPalette) then
            unresolvable = item.iconPalette
        end
    end
end
check(referenced > 0, "content actually authors palettes (" .. referenced .. " items)")
check(unresolvable == nil, "every palette referenced by an item resolves"
    .. (unresolvable and (" (failed on '" .. unresolvable .. "')") or ""))

print("=== Icon Tests: " .. passed .. " passed, " .. failed .. " failed ===")
if failed > 0 then require("tests.fail_fast")("icon tests failed", failed) end
