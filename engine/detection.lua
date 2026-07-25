-- Trap / secret detection (SEE_TRAPS, SEE_WALLS), 24.07.2026.
--
-- Traps are NOT a subsystem: a trap is an ordinary event with a step trigger
-- (SPEC Sec.0 -- anything an event can do, a trap can do). All this module adds
-- is *perception*: which detectable things the current party can notice, so the
-- minimap can mark them and so events can warn the player conditionally.
--
-- Authoring contract (meta keys, registered in data/engine.json):
--   meta.detect      "trap" | "secret" -- what kind of sense notices this
--   meta.detectLevel number (default 1) -- the DIFFICULTY of noticing it
--
-- The trait's value is the party's capability level and is checked against that
-- difficulty (owner rule: "the levels are meant to be difficulty check values
-- against traps and secrets"). So `nightVision` (SEE_TRAPS 2) notices a
-- difficulty-2 trap that plain `seeTraps` (1) walks straight into.
--
-- Capability is the BEST sense in the party, not a sum: two mediocre noses do
-- not add up to one good one.
local traits = require("engine.traits")

local detection = {}

-- Which trait code each `detect` kind is checked against.
local TRAIT_FOR_KIND = {
    trap = "SEE_TRAPS",
    secret = "SEE_WALLS",
}

function detection.kinds()
    local list = {}
    for kind in pairs(TRAIT_FOR_KIND) do table.insert(list, kind) end
    table.sort(list)
    return list
end

-- Highest rate for `traitCode` among living active party members.
function detection.capability(session, traitCode)
    local best = 0
    for i = 1, 4 do
        local b = session and session.party and session.party[i]
        if b and not (b.isDead and b:isDead()) then
            local rate = traits.getRate(b, traitCode, session)
            if rate > best then best = rate end
        end
    end
    return best
end

-- True when the party can notice `entry` (a map event or an override cell).
-- Anything without a `detect` meta key is not detectable at all and returns
-- false -- it is simply a normal event, visible on the usual rules.
function detection.isRevealed(session, entry)
    local meta = entry and entry.meta
    local kind = meta and meta.detect
    if not kind then return false end
    local traitCode = TRAIT_FOR_KIND[kind]
    if not traitCode then return false end
    local difficulty = meta.detectLevel or 1
    return detection.capability(session, traitCode) >= difficulty
end

-- Is this entry detectable at all (regardless of the party's senses)? Used by
-- the minimap to know a marker is even possible here.
function detection.isDetectable(entry)
    local meta = entry and entry.meta
    return (meta and meta.detect and TRAIT_FOR_KIND[meta.detect]) ~= nil
end

return detection
