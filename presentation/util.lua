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

return util
