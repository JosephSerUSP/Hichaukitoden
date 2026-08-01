-- The status infliction chain and state categories.
--
--   final chance = skill chance * attacker STATUS_SUCCESS * target state rate
--
-- floored at 0. Target rate is itself the product of every STATE_RATE naming
-- the state and every STATE_CATEGORY_RATE naming one of its categories.
--
-- A rate is a SLOPE, not a switch: driving it to 0 makes a state vanishingly
-- unlikely, but a critical hit still forces it through. Absolute immunity is
-- its own trait (STATE_IMMUNITY / STATE_CATEGORY_IMMUNITY) and is the only
-- thing a critical cannot bypass -- which is also how a Ribbon-style blanket
-- covers a whole family without listing its members.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")

print("[TEST] Starting status infliction tests...")

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

local realRandom = math.random
local function withRandom(value, fn)
    math.random = function() return value end
    local ok, err = pcall(fn)
    math.random = realRandom
    if not ok then error(err, 0) end
end

local function rig(traitList)
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 1)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.traits = traitList or {}
    b.actorData = private
    b.passives = {}
    b.states = {}
    return sess, b
end

local function hasState(b, id)
    for _, st in ipairs(b.states or {}) do
        if st.id == id then return true end
    end
    return false
end

-- Applies `status` at `chance` from `attacker` to `target` on a fixed draw.
local function inflict(sess, attacker, target, status, chance, roll, ctx)
    target.states = {}
    local events
    withRandom(roll, function()
        events = effects.apply({ type = "add_status", status = status, chance = chance },
            attacker, target, sess, ctx or {})
    end)
    return hasState(target, status), events
end

local function firstEvent(events, evType)
    for _, ev in ipairs(events or {}) do if ev.type == evType then return ev end end
    return nil
end

------------------------------------------------------------ the categories --

do
    local registered = {}
    for _, c in ipairs((loader.engine and loader.engine.stateCategories) or {}) do
        registered[c.category] = true
    end
    check(next(registered) ~= nil, "engine.json registers state categories")

    -- Every authored category must be one the registry knows, or a broad
    -- resistance silently fails to cover it. G1 gates this too; asserted here
    -- so the rule is stated where the behaviour is.
    local allKnown, anyCategorised = true, false
    for _, state in pairs(loader.states or {}) do
        for _, c in ipairs(state.categories or {}) do
            anyCategorised = true
            if not registered[c] then allKnown = false end
        end
    end
    check(anyCategorised, "the live states carry categories")
    check(allKnown, "every authored state category is registered")

    -- `common` is earned, never assumed. Death must not carry it, or a
    -- Ribbon-style blanket would make its wearer immune to dying.
    local function isCommon(stateId)
        local state = loader.getState(stateId)
        for _, c in ipairs((state and state.categories) or {}) do
            if c == "common" then return true end
        end
        return false
    end
    check(not isCommon("dead"), "the dead state is not common, so no blanket can reach it")
    check(isCommon("poison") and isCommon("sleep"),
        "ordinary afflictions are tagged common")
end

------------------------------------------------------------------ the chain --

do
    local sess, target = rig()
    local _, attacker = rig()

    -- A plain chance still behaves as authored when neither side modifies it.
    check(inflict(sess, attacker, target, "poison", 0.5, 0.4),
        "a draw under the authored chance lands the state")
    check(not inflict(sess, attacker, target, "poison", 0.5, 0.6),
        "a draw over the authored chance does not")

    -- Boundary: the roll is strictly less-than, so a 0 chance never lands even
    -- on a 0 draw. STATE_RATE 0 as immunity depends on this.
    check(not inflict(sess, attacker, target, "poison", 0, 0.0),
        "an authored chance of 0 never lands, even on a zero draw")
    -- A chance of 1 is certainty only before the target's own resistance. The
    -- stat-derived curve (base DEF against `physical`) shaves a little off
    -- every affliction, so nothing is ever quite 100% against a creature with
    -- a body -- which is the point of giving the defensive stats a second job.
    check(inflict(sess, attacker, target, "poison", 1.0, 0.5),
        "an authored chance of 1 lands on any ordinary draw")
end

do
    -- Defensive stats resist AFFLICTIONS ONLY. `physical` and `magical` are
    -- shape tags, not intent tags: `defending` is positive AND physical, and a
    -- creature whose own VIT resisted its own Defend would brace less reliably
    -- the sturdier it got.
    local sess, tanky = rig()
    local _, attacker = rig()
    check(inflict(sess, attacker, tanky, "defending", 1.0, 0.999),
        "a creature's own defensive stat never resists a positive state")
    check(inflict(sess, attacker, tanky, "regen", 1.0, 0.999),
        "...including a magical one")
end

do
    -- The attacker's half: a control specialist lands more without any skill
    -- being rewritten.
    local sess, target = rig()
    local _, specialist = rig({ { code = "STATUS_SUCCESS", value = 1.0 } })

    -- 0.5 * 2.0 = 1.0, so a draw that failed at base now succeeds.
    check(inflict(sess, specialist, target, "poison", 0.5, 0.9),
        "STATUS_SUCCESS raises the attacker's infliction chance")

    local _, clumsy = rig({ { code = "STATUS_SUCCESS", value = -0.5 } })
    -- 0.5 * 0.5 = 0.25, so a draw that succeeded at base now fails.
    check(not inflict(sess, clumsy, target, "poison", 0.5, 0.4),
        "a negative STATUS_SUCCESS lowers it")
end

do
    -- The target's half, narrow: a rate naming this exact state.
    local sess, resistant = rig({ { code = "STATE_RATE", dataId = "poison", value = 0.5 } })
    local _, attacker = rig()
    check(not inflict(sess, attacker, resistant, "poison", 0.5, 0.4),
        "STATE_RATE lowers the chance of its named state")
    -- ...and only that state. Sleep shares no rate with poison.
    check(inflict(sess, attacker, resistant, "sleep", 0.5, 0.4),
        "STATE_RATE leaves other states alone")
end

do
    -- The Ribbon shape: one trait, a whole family, no state named.
    local sess, ribboned = rig({ { code = "STATE_CATEGORY_IMMUNITY", dataId = "common" } })
    local _, attacker = rig()

    check(not inflict(sess, attacker, ribboned, "poison", 1.0, 0.0),
        "a category immunity blocks a state in that category")
    check(not inflict(sess, attacker, ribboned, "sleep", 1.0, 0.0),
        "the same trait blocks every other state in the family")
    check(not inflict(sess, attacker, ribboned, "poison", 1.0, 0.0, { critical = true }),
        "and a critical hit does not get past it either")

    -- The reason `common` is earned rather than inferred from `negative`.
    -- A blanket on `negative` would have covered death as well and quietly
    -- made its wearer unkillable by any authored death effect. Nothing is
    -- exempted by absence of a tag; death simply never earns the tag a
    -- blanket keys off.
    check(inflict(sess, attacker, ribboned, "dead", 1.0, 0.0),
        "a common-state blanket does not confer immunity to death")

    -- Positive states are not common either: a Ribbon that blocked your own
    -- buffs would be a curse.
    check(inflict(sess, attacker, ribboned, "regen", 1.0, 0.0),
        "a common-state blanket does not block positive states")
end

do
    -- Narrow and broad compound rather than one overriding the other.
    local sess, target = rig({
        { code = "STATE_CATEGORY_RATE", dataId = "negative", value = 0.5 },
        { code = "STATE_RATE", dataId = "poison", value = 0.5 },
    })
    local _, attacker = rig()
    -- 1.0 * 0.5 * 0.5 = 0.25
    check(not inflict(sess, attacker, target, "poison", 1.0, 0.3),
        "STATE_RATE and STATE_CATEGORY_RATE multiply together")
    check(inflict(sess, attacker, target, "poison", 1.0, 0.2),
        "...and the product is the chance, not a floor")
end

do
    -- A state in two resisted categories takes both. Poison is negative AND
    -- physical, which is exactly why categories are a list.
    local sess, target = rig({
        { code = "STATE_CATEGORY_RATE", dataId = "negative", value = 0.5 },
        { code = "STATE_CATEGORY_RATE", dataId = "physical", value = 0.5 },
    })
    local _, attacker = rig()
    check(not inflict(sess, attacker, target, "poison", 1.0, 0.3),
        "a state in two resisted categories takes both rates")
    -- Sleep is negative and mental: only the negative rate applies.
    check(inflict(sess, attacker, target, "sleep", 1.0, 0.3),
        "a state in only one of them takes only that rate")
end

------------------------------------------------------------------- immunity --

do
    -- A rate is a SLOPE, not a switch. Driving it to 0 makes the state
    -- vanishingly unlikely on the ordinary path, but it is NOT immunity: a
    -- critical still forces it through. That separation is what lets the
    -- stat-derived resistance curves reach zero safely.
    local sess, resisted = rig({ { code = "STATE_RATE", dataId = "poison", value = 0 } })
    local _, attacker = rig()

    local landed, events = inflict(sess, attacker, resisted, "poison", 1.0, 0.0)
    check(not landed, "a state rate of 0 never lands on the ordinary path")
    check(firstEvent(events, "state_immune") == nil,
        "a rate of 0 is not immunity, so nothing is announced as immune")

    landed = inflict(sess, attacker, resisted, "poison", 1.0, 0.0, { critical = true })
    check(landed, "a critical hit forces a state through a rate of 0")

    -- Immunity is its own trait, and it is the only thing a critical cannot
    -- get past.
    local isess, immune = rig({ { code = "STATE_IMMUNITY", dataId = "poison" } })
    local _, iattacker = rig()

    local ilanded, ievents = inflict(isess, iattacker, immune, "poison", 1.0, 0.0)
    check(not ilanded, "STATE_IMMUNITY blocks the state outright")
    check(firstEvent(ievents, "state_immune") ~= nil,
        "immunity is announced rather than silently doing nothing")
    check(firstEvent(ievents, "state_add") == nil,
        "an immune target reports no state_add")

    ilanded = inflict(isess, iattacker, immune, "poison", 1.0, 0.0, { critical = true })
    check(not ilanded, "a critical hit cannot force a state past STATE_IMMUNITY")

    -- ...but a critical still guarantees against a merely resistant target.
    local _, resistant = rig({ { code = "STATE_RATE", dataId = "poison", value = 0.01 } })
    landed = inflict(sess, attacker, resistant, "poison", 0.0, 0.99, { critical = true })
    check(landed, "a critical still guarantees a status against heavy resistance")
end

do
    -- Clamping: a chance driven over 1 by a specialist is certainty, not an
    -- overflow that starts wrapping.
    local sess, target = rig()
    local _, specialist = rig({ { code = "STATUS_SUCCESS", value = 5.0 } })
    check(inflict(sess, specialist, target, "poison", 0.9, 0.999),
        "a chance driven over 1 clamps to certainty")
end

print(("=== Status Infliction Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("status infliction tests failed", failed) end
