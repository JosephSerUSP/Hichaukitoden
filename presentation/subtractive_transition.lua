local fade = require("presentation.subtractive_fade")
local util = require("presentation.util")
local transition = {}
local amount, motion = 0, nil

local function eased(p, method)
    if method == "linear" then return util.easeLinear(p) end
    if method == "in" or method == "burn_in" then return util.easeInCubic(p) end
    if method == "out" then return util.easeOutCubic(p) end
    return util.smoothstep(p)
end

function transition.set(spec)
    local target = util.clamp01(tonumber(spec.amount) or 0)
    local duration = math.max(0, tonumber(spec.duration) or 0)
    if duration == 0 then amount, motion = target, nil return end
    motion = { from = amount, target = target, elapsed = 0, duration = duration,
        easing = spec.easing or (target > amount and "burn_in" or "smooth") }
end

function transition.update(dt)
    if not motion then return end
    motion.elapsed = math.min(motion.duration, motion.elapsed + dt)
    local p = eased(motion.elapsed / motion.duration, motion.easing)
    amount = motion.from + (motion.target - motion.from) * p
    if motion.elapsed >= motion.duration then motion = nil end
end

function transition.draw() fade.draw(amount) end
function transition.clear() amount, motion = 0, nil end
function transition.getAmount() return amount end
return transition
