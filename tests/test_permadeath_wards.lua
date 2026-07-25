-- Death wards (ON_PERMADEATH) and the two creature-customization effect types.
-- Both are end-of-battle / item behaviors that the golden gates can't observe,
-- so they are unit-tested here against the real data registry.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local effects = require("engine.effects")
local traits = require("engine.traits")
local savegame = require("engine.savegame")

print("[TEST] Starting permadeath ward + customization effect tests...")

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

-- A session with one creature in slot 1, killed and swept. Returns the
-- session, the battler, and the events REAP_FALLEN emitted.
local function reapWith(equipItemId, passiveId)
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 5) -- Skeleton, level 5
    if not b then return nil end
    if passiveId then b.passives = { passiveId } end
    if equipItemId then
        b.equipment[3] = loader.getItem(equipItemId)
    end
    b.hp = 0
    b:addState("dead")
    local ctx = { session = sess, events = {} }
    interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, ctx)
    return sess, b, ctx.events
end

local function firstEvent(events, evType)
    for _, ev in ipairs(events or {}) do
        if ev.type == evType then return ev end
    end
    return nil
end

loader.init()

-- 1. No ward: the creature is reaped and its EXP banked (baseline unchanged).
do
    local sess, b, events = reapWith(nil, nil)
    local reap = firstEvent(events, "reap")
    check(reap ~= nil and firstEvent(events, "ward_save") == nil,
        "unwarded creature is reaped, not saved")
    check(reap and reap.exp and reap.exp > 0 and (sess.expBank or 0) > 0,
        "reaping banks EXP")
end

-- 2. ward mode: survives, equipment destroyed.
do
    local sess, b, events = reapWith(42, nil) -- Warding Charm
    local ev = firstEvent(events, "ward_save")
    check(ev ~= nil and firstEvent(events, "reap") == nil,
        "ward-mode charm saves the creature from the sweep")
    check(ev and ev.broke == true and b.equipment[3] == nil,
        "ward-mode charm is destroyed on use")
    check(not b:isDead() and b.hp > 0,
        "warded creature is alive with positive HP")
    check((sess.expBank or 0) == 0,
        "a saved creature banks no EXP")
end

-- 3. revive mode: survives at its configured HP fraction.
do
    local sess, b, events = reapWith(43, nil) -- Vial of Second Breath, 0.35
    local ev = firstEvent(events, "ward_save")
    local maxHp = traits.getParam(b, "maxHp", sess)
    check(ev and ev.mode == "revive", "revive-mode ward reports its mode")
    check(b.hp == math.max(1, math.floor(maxHp * 0.35)),
        "revive restores the trait's hpFraction (0.35)")
end

-- 4. charges mode: spends one per save, survives, breaks only at zero.
do
    local sess, b, events = reapWith(44, nil) -- Thrice-Blessed Bead, 3 charges
    local ev = firstEvent(events, "ward_save")
    check(ev and ev.charges == 2 and ev.broke == false,
        "charge ward spends one charge and does not break")
    check(b.equipment[3] ~= nil, "charge ward survives its first use")

    -- Drain the remaining charges through two more sweeps.
    local lastEv
    for _ = 1, 2 do
        b.hp = 0
        b:addState("dead")
        local ctx = { session = sess, events = {} }
        interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, ctx)
        lastEv = firstEvent(ctx.events, "ward_save")
    end
    check(lastEv and lastEv.charges == 0 and lastEv.broke == true,
        "charge ward breaks as the last charge is spent")
    check(b.equipment[3] == nil, "spent charge ward is removed from its slot")

    -- With the bead gone, the next death is a real death.
    b.hp = 0
    b:addState("dead")
    local ctx = { session = sess, events = {} }
    interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, ctx)
    check(firstEvent(ctx.events, "reap") ~= nil,
        "creature dies once its ward is spent")
end

-- 5. relic mode (the `rebirth` passive): never consumed, costs levels.
do
    local sess, b, events = reapWith(nil, "rebirth")
    local ev = firstEvent(events, "ward_save")
    check(ev and ev.mode == "relic" and ev.broke == false,
        "relic ward saves without being consumed")
    check(b.level == 3 and ev.levelCost == 2,
        "rebirth's levelCost drops the creature 5 -> 3")

    -- Still saved a second time: a relic is unconditional.
    b.hp = 0
    b:addState("dead")
    local ctx = { session = sess, events = {} }
    interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, ctx)
    check(firstEvent(ctx.events, "ward_save") ~= nil,
        "relic ward fires again on a later death")
end

-- 6. Priority: a free relic saves the creature before a consumable breaks.
do
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 5)
    b.passives = { "rebirth" }
    b.equipment[3] = loader.getItem(42) -- Warding Charm too
    b.hp = 0
    b:addState("dead")
    local ctx = { session = sess, events = {} }
    interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, ctx)
    local ev = firstEvent(ctx.events, "ward_save")
    check(ev and ev.mode == "relic" and b.equipment[3] ~= nil,
        "relic is preferred over a consumable ward, which is left intact")
end

-- 7. Ward charges round-trip through a save.
do
    local sess, b = reapWith(44, nil)
    local blob = savegame.serialize(sess, loader, "map")
    local restored = savegame.deserialize(blob, loader)
    local rb = restored.party[1]
    local key = "slot:3"
    check(rb and rb.wardCharges and rb.wardCharges[key] == 2,
        "ward charges survive save/load")
end

-- 8. learn_skill: teaches once, reports when already known.
do
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 3)
    local before = #b.skills
    effects.apply({ type = "learn_skill", skill = "windBlade" }, b, b, sess)
    local learned = false
    for _, s in ipairs(b.skills) do if s == "windBlade" then learned = true end end
    check(learned and #b.skills == before + 1, "learn_skill teaches the skill once")

    local evs = effects.apply({ type = "learn_skill", skill = "windBlade" }, b, b, sess)
    check(#b.skills == before + 1 and evs[1] and evs[1].type == "text",
        "learn_skill on a known skill is a no-op with a message")
end

-- 9. param_plus: permanent stat gain, folded into stat reads.
do
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 3)
    local atkBefore = traits.getParam(b, "atk", sess)
    effects.apply({ type = "param_plus", param = "atk", value = 2 }, b, b, sess)
    check(traits.getParam(b, "atk", sess) == atkBefore + 2,
        "param_plus raises the param permanently")

    local evs = effects.apply({ type = "param_plus", param = "nonsense", value = 2 }, b, b, sess)
    check(evs[1] and evs[1].type == "text" and evs[1].text:match("unknown param"),
        "param_plus rejects an unknown param with a message")
end

-- 10. Usability: a skillbook is offered until the skill is known, then refused.
do
    local usability = require("engine.usability")
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 3)
    local tome = loader.getItem(45)
    local ok = usability.canUseItem(tome, b, { session = sess, isField = true })
    check(ok == true, "skillbook is usable on a creature that lacks the skill")

    effects.apply({ type = "learn_skill", skill = "windBlade" }, b, b, sess)
    local ok2, reason = usability.canUseItem(tome, b, { session = sess, isField = true })
    check(ok2 == false and reason == "Already knows that skill",
        "skillbook is refused once the skill is known")
end

print(string.format("=== Ward/effect tests: %d passed, %d failed ===", passed, failed))
assert(failed == 0, "permadeath ward / effect tests failed")
