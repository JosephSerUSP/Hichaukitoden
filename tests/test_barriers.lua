package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")
local barriers = require("engine.barriers")
local interpreter = require("engine.interpreter")

print("[TEST] Starting barrier resource tests...")
local passed, failed = 0, 0
local function check(ok, msg)
    if ok then passed = passed + 1; print("  [PASS] " .. msg)
    else failed = failed + 1; print("  [FAIL] " .. msg) end
end

loader.init()
local function rig()
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 1)
    local data = {}
    for k, v in pairs(b.actorData) do data[k] = v end
    data.traits, data.elements = {}, {}
    data.baseParams = { atk = 100, def = 100, mat = 100, mdf = 100, maxHp = 9999 }
    data.growthMultiplier = 0
    b.actorData, b.level, b.hp, b.states = data, 1, 9000, {}
    return sess, b
end

local realRandom = math.random
local function fixedRandom(value, fn)
    math.random = function() return value end
    local ok, err = pcall(fn)
    math.random = realRandom
    if not ok then error(err, 0) end
end

local function grant(sess, b, spec)
    return effects.apply({
        type = "barrier", id = spec.id, match = spec.match, stacks = spec.stacks,
        reduction = spec.reduction, maxStacks = spec.maxStacks,
        duration = spec.duration, mode = spec.mode,
    }, b, b, sess, {})
end

local function hit(sess, a, b, power)
    local before, events = b.hp, nil
    fixedRandom(1, function()
        events = effects.apply({ type = "hp_damage", power = power, potency = 1 }, a, b, sess, {})
    end)
    return before - b.hp, events
end

local function eventOf(events, kind)
    for _, ev in ipairs(events or {}) do if ev.type == kind then return ev end end
end

do
    local sess, a = rig(); local _, b = rig()
    grant(sess, b, { id = "magic_once", match = "magical_damage", stacks = 1, reduction = 1, mode = "set" })
    local d1, e1 = hit(sess, a, b, "mat")
    local d2, e2 = hit(sess, a, b, "mat")
    check(d1 == 0 and d2 > 0, "one magical stack negates hit 1 but not hit 2")
    local used = eventOf(e1, "barrier_consume")
    check(used and used.blocked and used.prevented > 0 and eventOf(e1, "barrier_break"),
        "consumption and break emit structured events")
    check(not eventOf(e2, "barrier_consume"), "spent barrier does not affect later hits")
end

do
    local sess, a = rig(); local _, b = rig()
    grant(sess, b, { id = "magic", match = "magical_damage", stacks = 1, reduction = 1, mode = "set" })
    local physical = hit(sess, a, b, "atk")
    check(physical > 0 and barriers.get(b, "magic"), "magical barrier ignores physical damage")
    check(hit(sess, a, b, "mat") == 0 and not barriers.get(b, "magic"), "magical barrier consumes on magic")
    grant(sess, b, { id = "physical", match = "physical_damage", stacks = 1, reduction = 1, mode = "set" })
    check(hit(sess, a, b, "atk") == 0, "physical barrier consumes on physical damage")
end

do
    local sess, a = rig(); local _, base = rig()
    local baseline = hit(sess, a, base, "mat")
    local _, b = rig()
    grant(sess, b, { id = "soft", match = "magical_damage", stacks = 2, reduction = 0.5, mode = "set" })
    local d1, d2, d3 = hit(sess, a, b, "mat"), hit(sess, a, b, "mat"), hit(sess, a, b, "mat")
    check(d1 == math.floor(baseline * 0.5) and d2 == math.floor(baseline * 0.5) and d3 == baseline,
        "partial two-stack barrier reduces exactly two hits")
end

do
    local sess, b = rig()
    grant(sess, b, { id = "persistent", match = "physical_damage", stacks = 5, reduction = 0.25, mode = "set" })
    for round = 1, 20 do barriers.sync(b, "round_end", sess, { battle = { round = round } }) end
    check(barriers.get(b, "persistent") and barriers.get(b, "persistent").stacks == 5,
        "barrier without duration persists until consumed")
    grant(sess, b, { id = "timed", match = "physical_damage", stacks = 2, reduction = 1, duration = 2, mode = "set" })
    barriers.sync(b, "round_end", sess, { battle = { round = 1 } })
    local expiry = barriers.sync(b, "round_end", sess, { battle = { round = 2 } })
    check(not barriers.get(b, "timed") and eventOf(expiry, "barrier_expire"), "optional duration expires independently")
end

do
    local sess, b = rig()
    grant(sess, b, { id = "renew", match = "magical_damage", stacks = 2, reduction = 1, maxStacks = 3, mode = "set" })
    barriers.consume(b, "magical_damage")
    grant(sess, b, { id = "renew", match = "magical_damage", stacks = 2, reduction = 1, maxStacks = 3, mode = "refresh" })
    grant(sess, b, { id = "renew", match = "magical_damage", stacks = 2, reduction = 1, maxStacks = 3, mode = "refresh" })
    check(barriers.get(b, "renew").stacks == 2, "refresh restores a minimum without stockpiling")
    grant(sess, b, { id = "renew", match = "magical_damage", stacks = 3, reduction = 1, maxStacks = 3, mode = "add" })
    check(barriers.get(b, "renew").stacks == 3, "maxStacks caps additive grants")
end

do
    local sess, a = rig(); local _, b = rig()
    grant(sess, b, { id = "status", match = "hostile_status", stacks = 1, reduction = 1, mode = "set" })
    fixedRandom(0, function()
        local events = effects.apply({ type = "add_status", status = "poison", chance = 1 }, a, b, sess, {})
        check(not eventOf(events, "state_add") and eventOf(events, "barrier_consume"), "would-land hostile status is intercepted")
    end)
    check(not barriers.get(b, "status"), "successful hostile-status match spends one stack")
    grant(sess, b, { id = "wait", match = "hostile_status", stacks = 1, reduction = 1, mode = "set" })
    fixedRandom(1, function()
        effects.apply({ type = "add_status", status = "poison", chance = 0.25 }, a, b, sess, {})
    end)
    check(barriers.get(b, "wait") and barriers.get(b, "wait").stacks == 1, "failed status roll does not spend ward")
end

do
    local sess, b = rig()
    b.actorData.traits = {
        { code = "BARRIER_GRANT", id = "start", match = "magical_damage", stacks = 1, reduction = 1, at = "battle_start", mode = "set" },
        { code = "BARRIER_GRANT", id = "renew", match = "magical_damage", stacks = 1, reduction = 0.5, at = "round_start", mode = "refresh" },
    }
    local ctx = { session = sess, target = b, events = {}, battle = { round = 1 } }
    interpreter.execList({ { cmd = "BARRIER_SYNC", target = "target", trigger = "battle_start" } }, ctx)
    interpreter.execList({ { cmd = "BARRIER_SYNC", target = "target", trigger = "round_start" } }, ctx)
    check(barriers.get(b, "start") and barriers.get(b, "renew"), "trait barriers grant through battle phase hooks")
end

local function rejects(spec) return not pcall(barriers.validateSpec, spec, "fixture") end
check(rejects({ id = "bad", match = "magical_damage", stacks = 0, reduction = 1 }), "schema rejects zero stacks")
check(rejects({ id = "bad", match = "magical_damage", stacks = 1, reduction = 1.5 }), "schema rejects invalid reduction")
check(rejects({ id = "bad", match = "blue_magic", stacks = 1, reduction = 1 }), "schema rejects invalid match kind")

print(("=== Barrier Resource Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("barrier resource tests failed", failed) end
