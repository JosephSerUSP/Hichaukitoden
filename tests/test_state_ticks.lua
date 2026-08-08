-- Existing STATE_TICKS coverage stays intact in the core file. This extension
-- pins issue #166's Overheal and temporary-Max-HP contracts against the public
-- engine surfaces used by gameplay.
require("tests.test_state_ticks_core")

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")
local interpreter = require("engine.interpreter")
local traits = require("engine.traits")
local vitality = require("engine.vitality")
local formula = require("engine.formula")
local savegame = require("engine.savegame")

print("[TEST] Starting combat-state resource tests...")

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

local TEMP_STATE = "__test_temp_max_hp"
local function testLoader(overhealCap)
    local proxy = setmetatable({}, { __index = loader })
    local sys = {}
    for k, v in pairs(loader.system or {}) do sys[k] = v end
    local combat = {}
    for k, v in pairs((loader.system and loader.system.combat) or {}) do combat[k] = v end
    combat.overhealCap = overhealCap or 1.5
    sys.combat = combat
    proxy.system = sys
    proxy.getState = function(id)
        if id == TEMP_STATE then
            return {
                id = TEMP_STATE,
                name = "Test Temporary Max HP",
                categories = { "positive" },
                traits = { { code = "PARAM_PLUS", dataId = "maxHp", value = 25 } },
            }
        end
        return loader.getState(id)
    end
    return proxy
end

local function fresh(cap)
    local ldr = testLoader(cap)
    local sess = sessionModule.GameSession.new(ldr)
    local b = sess:recruitActor("skeleton", 5)
    return sess, b
end

local function hasEvent(events, kind)
    for _, ev in ipairs(events or {}) do if ev.type == kind then return ev end end
end

-------------------------------------------------------------- Overheal --
do
    local sess, b = fresh(1.5)
    local maxHp = traits.getParam(b, "maxHp", sess)
    b.hp = maxHp - 5
    effects.apply({ type = "hp_heal", formula = "999" }, b, b, sess)
    check(b.hp == maxHp, "ordinary formula healing still clamps at Max HP")

    b.hp = maxHp + 10
    local evs = effects.apply({ type = "hp_heal", formula = "999" }, b, b, sess)
    check(b.hp == maxHp + 10 and hasEvent(evs, "heal").value == 0,
        "ordinary healing never deletes existing Overheal")

    b.hp = maxHp - 5
    evs = effects.apply({ type = "hp_heal", formula = "999", overheal = true }, b, b, sess)
    local cap = math.floor(maxHp * 1.5)
    check(b.hp == cap, "an explicit Overheal heal can exceed Max HP up to the system cap")
    check(hasEvent(evs, "heal") and hasEvent(evs, "heal").cap == cap,
        "heal events expose the recovery cap explicitly")

    local beforeDamage = b.hp
    effects.apply({ type = "hp_damage", formula = "5" }, b, b, sess)
    check(b.hp == beforeDamage - 5,
        "damage consumes Overheal as ordinary current HP, with no shield pool")
end

--------------------------------------------------------- percentages --
do
    local sess, b = fresh(1.5)
    local maxHp = traits.getParam(b, "maxHp", sess)
    b.hp = math.floor(maxHp * 1.2)
    check(vitality.hpRatio(b, sess) > 1,
        "HP ratio remains above 1.0 while current HP exceeds effective Max HP")
    local view = formula.battlerView(b, sess)
    check(view.hpRatio > 1 and view.overheal == b.hp - maxHp,
        "formula/UI battler views expose unclamped HP ratio and exact Overheal")
    check(not traits.evaluateCondition("HP < 100%", b, sess)
        and traits.evaluateCondition("HP < 125%", b, sess),
        "authored HP thresholds compare the unclamped currentHP/effectiveMaxHP ratio")
end

----------------------------------------------------- temporary Max HP --
do
    local sess, b = fresh(1.5)
    local beforeMax = traits.getParam(b, "maxHp", sess)
    local beforeParts = vitality.maxHpComponents(b, sess)
    local permanentBefore = b.paramPlus.maxHp
    b.hp = beforeMax - 20

    local evs = effects.apply({
        type = "add_status", status = TEMP_STATE, duration = 1, chance = 1,
    }, b, b, sess)
    local afterMax = traits.getParam(b, "maxHp", sess)
    check(afterMax == beforeMax + 25,
        "a state PARAM_PLUS maxHp raises the actual effective Max HP")
    check(b.hp == beforeMax + 5,
        "raising temporary Max HP immediately grants the new capacity as current HP")
    check(b.paramPlus.maxHp == permanentBefore,
        "temporary Max HP never mutates persistent paramPlus.maxHp")
    local view = formula.battlerView(b, sess)
    check(view.maxHpParts.underlying == beforeParts.underlying
        and view.maxHpParts.active == afterMax
        and view.maxHpParts.activeModifier == beforeParts.activeModifier + 25,
        "formula/UI battler views distinguish underlying and active Max HP")
    local modifier, formulaErr = formula.eval("a.maxHpParts.activeModifier",
        formula.makeContext({ a = b }, sess))
    check(formulaErr == nil and modifier == beforeParts.activeModifier + 25,
        "authored formulas can read the active Max-HP modifier")
    local maxEv = hasEvent(evs, "max_hp_change")
    check(maxEv and maxEv.value == 25 and maxEv.hpGranted == 25,
        "state application emits a structured Max-HP transition")
    local stateEv = hasEvent(evs, "state_add")
    check(stateEv and stateEv.duration == 1,
        "state-add events preserve an authored duration for presentation replay")

    local tickEvents = interpreter.runImmediate({ { cmd = "STATE_TICKS" } }, {
        session = sess, loader = sess.loader, party = sess.party, enemies = {}, events = {},
    })
    check(traits.getParam(b, "maxHp", sess) == beforeMax and b.hp == beforeMax,
        "temporary Max HP expiry restores the underlying cap and clamps current HP")
    check(hasEvent(tickEvents, "max_hp_change") and hasEvent(tickEvents, "hp_clamp"),
        "expiry exposes Max-HP loss and the non-damage HP clamp as structured events")
    check(not hasEvent(tickEvents, "damage") and not hasEvent(tickEvents, "death"),
        "Max-HP expiry clamp emits neither damage nor death")
end

--------------------------------------------- permanent growth + Overheal --
do
    local sess, b = fresh(1.5)
    local maxHp = traits.getParam(b, "maxHp", sess)
    b.hp = maxHp + 20
    local beforeHp = b.hp
    local evs = effects.apply({ type = "maxHp", value = 5 }, b, b, sess)
    local healEv = hasEvent(evs, "heal")
    check(b.hp == beforeHp,
        "permanent Max-HP growth preserves existing Overheal")
    check(healEv and healEv.value == 0,
        "permanent Max-HP growth reports only HP actually granted while Overhealed")
end

---------------------------------------------------------- composition --
do
    local sess, b = fresh(1.5)
    local baseMax = traits.getParam(b, "maxHp", sess)
    b.hp = baseMax
    effects.apply({ type = "hp_heal", formula = "999", overheal = true, overhealCap = 2.0 }, b, b, sess)
    local overHp = b.hp
    effects.apply({ type = "add_status", status = TEMP_STATE, duration = 2, chance = 1 }, b, b, sess)
    check(b.hp == overHp,
        "temporary capacity does not double-count current HP already above the grown cap")

    local sess2, b2 = fresh(1.5)
    local base2 = traits.getParam(b2, "maxHp", sess2)
    b2.hp = base2
    effects.apply({ type = "add_status", status = TEMP_STATE, duration = 2, chance = 1 }, b2, b2, sess2)
    local grownMax = traits.getParam(b2, "maxHp", sess2)
    check(b2.hp == grownMax, "growth-first reaches the grown Max HP normally")
    effects.apply({ type = "hp_heal", formula = "999", overheal = true }, b2, b2, sess2)
    check(b2.hp == math.floor(grownMax * 1.5),
        "Overheal applied after growth uses the grown effective Max HP as its cap base")
end

--------------------------------------------------------------- regen --
do
    local sess, b = fresh(1.5)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.traits = { { code = "HRG", value = 0.1 } }
    b.actorData = private
    local maxHp = traits.getParam(b, "maxHp", sess)
    b.hp = maxHp + 10
    local evs = interpreter.runImmediate({ { cmd = "STATE_TICKS" } }, {
        session = sess, loader = sess.loader, party = sess.party, enemies = {}, events = {},
    })
    check(b.hp == maxHp + 10,
        "ordinary positive regeneration does not erase or refill Overheal")
    check(not hasEvent(evs, "heal"),
        "a regen tick with no legal recovery emits no fake +0 heal event")
end

------------------------------------------------------------- save shape --
do
    local sess, b = fresh(1.5)
    local maxHp = traits.getParam(b, "maxHp", sess)
    b.hp = maxHp + 7
    local data = savegame.serialize(sess, sess.loader, "map")
    local saved
    for _, row in pairs(data.party or {}) do
        if row and row.id == b.id then saved = row break end
    end
    check(saved and saved.hp == maxHp + 7 and saved.overheal == nil,
        "Overheal saves as real current HP rather than a second persistent resource")
end

print(("=== Combat-State Resource Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("combat-state resource tests failed", failed) end
