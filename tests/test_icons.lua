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

-- === Palette shader ===
print("=== Palette Shader ===")

-- The recolor is GLSL, so the ramp maths cannot be asserted from Lua. What CAN
-- be asserted is that the shader compiles on this driver at all -- it used to
-- be pcall'd with the failure swallowed, which would have disabled recoloring
-- for the entire game while looking identical to "no palette was set".
local shaderOk, shaderErr = pcall(ui.initIconShader)
check(shaderOk, "the icon palette shader compiles"
    .. (shaderOk and "" or (": " .. tostring(shaderErr))))

if shaderOk then
    local shader = ui.initIconShader()
    check(shader ~= nil, "compiling the shader yields a shader object")
    -- Every uniform drawIcon feeds must actually exist, or a rename would
    -- silently stop reaching the GPU.
    local sendOk = pcall(function()
        shader:send("u_palette", { 0, 0, 0, 1 }, { 0.3, 0, 0, 1 }, { 0.6, 0, 0, 1 }, { 1, 1, 1, 1 })
        shader:send("u_targetHue", 0.0)
        shader:send("u_hueTolerance", 0.08)
        shader:send("u_minimumSaturation", 0.25)
        shader:send("u_minimumLightness", 0.10)
        shader:send("u_maximumLightness", 0.95)
    end)
    check(sendOk, "every uniform drawIcon sends is declared by the shader")
end

-- === Ramp output through the real shader ===
print("=== Ramp Output (GPU) ===")

-- The ramp lives in GLSL, and the editor keeps a JS copy so its preview can
-- predict the runtime draw. Two implementations of one formula drift unless
-- something checks. This renders known source pixels through the ACTUAL
-- shader and reads them back, so the numbers below are the GPU's, not a Lua
-- re-implementation of what the GPU was supposed to do.
--
-- The four palette entries are control points at 0, 1/3, 2/3, 1 -- not four
-- buckets. Quantizing was discarding most of the shading in icons that are
-- already colour-limited, and with a 0.10-0.95 window the top bucket never
-- fired at all.
if shaderOk then
    local shader = ui.initIconShader()

    -- Four pure-red sources at rising lightness, chosen to land on the ramp's
    -- control points given the window below: L = 0.10, 0.383, 0.667, 0.95.
    local window = { min = 0.10, max = 0.95 }
    local sourceLightness = { 0.10, 0.10 + 0.85 / 3, 0.10 + 0.85 * 2 / 3, 0.95 }

    -- Fully-saturated red at a given lightness (hue 0, S = 1).
    local function redAt(l)
        local c = (1 - math.abs(2 * l - 1))
        local m = l - c / 2
        return math.min(1, c + m), math.max(0, m), math.max(0, m)
    end

    local src = love.image.newImageData(#sourceLightness, 1)
    for i, l in ipairs(sourceLightness) do
        local r, g, b = redAt(l)
        src:setPixel(i - 1, 0, r, g, b, 1)
    end

    local image = love.graphics.newImage(src)
    image:setFilter("nearest", "nearest")

    local canvas = love.graphics.newCanvas(#sourceLightness, 1)
    local palette = {
        { 0.0, 0.0, 0.0, 1 },   -- stop 0: black
        { 1.0, 0.0, 0.0, 1 },   -- stop 1: red
        { 0.0, 1.0, 0.0, 1 },   -- stop 2: green
        { 0.0, 0.0, 1.0, 1 },   -- stop 3: blue
    }

    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace")
    love.graphics.setShader(shader)
    shader:send("u_palette", palette[1], palette[2], palette[3], palette[4])
    shader:send("u_targetHue", 0.0)
    shader:send("u_hueTolerance", 0.08)
    shader:send("u_minimumSaturation", 0.25)
    shader:send("u_minimumLightness", window.min)
    shader:send("u_maximumLightness", window.max)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.pop()

    local out = canvas:newImageData()
    local function channels(i)
        local r, g, b = out:getPixel(i, 0)
        return r, g, b
    end

    -- At each control point the output must BE that stop, exactly.
    local tol = 0.02
    local function near(a, b) return math.abs(a - b) <= tol end

    for i = 1, 4 do
        local r, g, b = channels(i - 1)
        local want = palette[i]
        check(near(r, want[1]) and near(g, want[2]) and near(b, want[3]),
            ("control point %d renders as its own palette stop (got %.2f,%.2f,%.2f)")
                :format(i, r, g, b))
    end

    -- And between them it must actually blend, not snap. Midway between the
    -- red and green stops the output has to carry BOTH channels -- which is
    -- exactly what the old four-bucket version could never produce.
    local midSrc = love.image.newImageData(1, 1)
    local midL = 0.10 + 0.85 * 0.5
    local r0, g0, b0 = redAt(midL)
    midSrc:setPixel(0, 0, r0, g0, b0, 1)
    local midImage = love.graphics.newImage(midSrc)
    midImage:setFilter("nearest", "nearest")
    local midCanvas = love.graphics.newCanvas(1, 1)

    love.graphics.push("all")
    love.graphics.setCanvas(midCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace")
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(midImage, 0, 0)
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.pop()

    local mr, mg, mb = midCanvas:newImageData():getPixel(0, 0)
    check(mr > 0.1 and mg > 0.1,
        ("between two stops the ramp blends rather than snapping (got %.2f,%.2f,%.2f)")
            :format(mr, mg, mb))
    check(mb < 0.1, "a mid-ramp blend does not pull in a stop it sits nowhere near")

    -- A pixel outside the hue key must survive untouched.
    local keepSrc = love.image.newImageData(1, 1)
    keepSrc:setPixel(0, 0, 0.2, 0.8, 0.3, 1)  -- green: nowhere near hue 0
    local keepImage = love.graphics.newImage(keepSrc)
    keepImage:setFilter("nearest", "nearest")
    local keepCanvas = love.graphics.newCanvas(1, 1)

    love.graphics.push("all")
    love.graphics.setCanvas(keepCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace")
    love.graphics.setShader(shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(keepImage, 0, 0)
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.pop()

    local kr, kg, kb = keepCanvas:newImageData():getPixel(0, 0)
    check(near(kr, 0.2) and near(kg, 0.8) and near(kb, 0.3),
        ("an unkeyed pixel passes through untouched (got %.2f,%.2f,%.2f)"):format(kr, kg, kb))
end

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
