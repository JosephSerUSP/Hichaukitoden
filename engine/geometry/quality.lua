-- Runtime geometry quality: the one place that decides how many triangles a
-- compiled asset is allowed, so the developer menu and the compiler cannot
-- disagree.
--
-- Defaults live in data/engine.json (`geometry.quality`) like every other
-- tunable; this module only holds the live override and the arithmetic.
local quality = {}

-- Set from the developer menu. nil means "use the authored default".
local densityOverride = nil
local errorOverride = nil

local function settings()
    local loader = require("data.loader")
    local geometry = loader.engine and loader.engine.geometry
    return (geometry and geometry.quality) or {}
end

function quality.density()
    if densityOverride then return densityOverride end
    return settings().densityScale or 1.0
end

-- Quadric error under which a collapse is free. Expressed in squared world
-- units, so it is independent of how densely the field was sampled: a flat
-- region collapses completely at any sampling resolution.
function quality.maxError()
    if errorOverride then return errorOverride end
    return settings().maxError or 0.0
end

-- An asset's triangle ceiling, scaled by the live density setting. Never below
-- two: one quad is the smallest thing a surface can be.
function quality.budget(authored)
    return math.max(2, math.floor((authored or 64) * quality.density() + 0.5))
end

-- Segment counts for revolved geometry, which has no decimation step -- its
-- segments ARE its facets, so density has to reach them here instead.
function quality.segments(authored, minimum)
    return math.max(minimum or 3, math.floor(authored * quality.density() + 0.5))
end

-- Part of the composition cache key: changing quality must recompile, or the
-- menu would appear to do nothing until something else invalidated the cache.
function quality.key()
    return string.format("d%.3f:e%.5f", quality.density(), quality.maxError())
end

function quality.setDensity(value)
    densityOverride = value and math.max(0.05, math.min(4.0, value)) or nil
    require("engine.geometry").forget()
end

function quality.setMaxError(value)
    errorOverride = value and math.max(0.0, value) or nil
    require("engine.geometry").forget()
end

-- The presets the developer menu cycles through. Named rather than numeric
-- because the useful question is "how blocky", not "what multiplier".
quality.PRESETS = {
    { id = "coarse", label = "COARSE", density = 0.25, maxError = 0.0008 },
    { id = "low", label = "LOW", density = 0.5, maxError = 0.0003 },
    { id = "normal", label = "NORMAL", density = 1.0, maxError = 0.0001 },
    { id = "fine", label = "FINE", density = 2.0, maxError = 0.00002 },
}

function quality.presetIndex()
    local density, maxError = quality.density(), quality.maxError()
    for index, preset in ipairs(quality.PRESETS) do
        if math.abs(preset.density - density) < 1e-6
            and math.abs(preset.maxError - maxError) < 1e-9 then
            return index
        end
    end
    return nil
end

function quality.applyPreset(index)
    local preset = quality.PRESETS[index]
    if not preset then return nil end
    densityOverride = preset.density
    errorOverride = preset.maxError
    require("engine.geometry").forget()
    return preset
end

function quality.presetLabel()
    local index = quality.presetIndex()
    return index and quality.PRESETS[index].label or "CUSTOM"
end

return quality
