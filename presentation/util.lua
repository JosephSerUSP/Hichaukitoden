-- Small helpers shared by more than one presentation module. Nothing here is
-- specific to any single renderer.
local util = {}

function util.copy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

function util.easeLinear(t)
    return t
end

function util.easeOut(t)
    -- Quadratic ease-out: fast start, slow end
    return 1 - (1 - t) * (1 - t)
end

function util.easeInCubic(t)
    return t * t * t
end

function util.easeOutCubic(t)
    return 1 - (1 - t) * (1 - t) * (1 - t)
end

function util.smoothstep(t)
    return t * t * (3 - 2 * t)
end

function util.clamp01(x)
    return math.max(0, math.min(1, x))
end

return util
