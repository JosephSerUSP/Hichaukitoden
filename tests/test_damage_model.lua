-- The relative damage model: the curve, the stat pairing, criticals, and
-- DAMAGE_RATE.
--
-- The golden logs prove the whole battle is stable; they cannot prove the curve
-- is the RIGHT one, because any consistent arithmetic produces a stable log.
-- These tests pin the properties docs/design/creature-parameters.md actually
-- promises, so a future change that keeps G2 green by regenerating it still has
-- to answer to the design.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")

print("[TEST] Starting damage model tests...")

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

-- A battler whose stats we set outright, so the curve is tested against exact
-- numbers rather than whatever the growth model currently produces. paramPlus
-- is folded into every stat read by traits.getParam, and actorData is replaced
-- with a private copy because loader tables are shared by every holder.
local function rig(stats)
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 1)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.traits = {}
    private.elements = {}          -- no affinity, so the curve is unclouded
    private.baseParams = stats
    private.growthMultiplier = 0
    b.actorData = private
    b.level = 1
    b.hp = 99999
    return sess, b
end

-- Criticals roll against math.random. Pin the stream so a test measures the
-- curve rather than luck; 0-crit and always-crit are exercised explicitly.
-- Takes a sequence because one action rolls more than once -- the critical
-- first, then any attached status -- and those two rolls need different
-- answers to tell a guarantee apart from an ordinary success.
local realRandom = math.random
local function withRandom(values, fn)
    if type(values) ~= "table" then values = { values } end
    local i = 0
    math.random = function(...)
        i = i + 1
        return values[math.min(i, #values)]
    end
    local ok, err = pcall(fn)
    math.random = realRandom
    if not ok then error(err, 0) end
end

local NO_CRIT = 1.0    -- never below the 5% base rate
local ALL_CRIT = 0.0   -- always below it
-- A roll that fails any authored chance of 0, so a status that lands anyway
-- landed because it was guaranteed. (ALL_CRIT cannot serve: `roll <= chance`
-- with both at 0 succeeds on its own and would prove nothing.)
local FAILS_ZERO_CHANCE = 0.5

---------------------------------------------------------------- the curve --

-- potency * P^2 / (P + D). The table in creature-parameters.md states the
-- defining property as a share of power, so that is what is asserted.
do
    withRandom(NO_CRIT, function()
        local function hit(power, defense, potency)
            local sess, atk = rig({ atk = power, def = 10, mat = 10, mdf = 10, maxHp = 500 })
            local _, def = rig({ atk = 10, def = defense, mat = 10, mdf = 10, maxHp = 500 })
            def.hp = 5000
            local before = def.hp
            effects.apply({ type = "hp_damage", power = "atk", potency = potency },
                atk, def, sess, {})
            return before - def.hp
        end

        -- traits.getParam floors every parameter at 1, so "no defense" is
        -- defense 1 in practice and the share lands just under the whole.
        check(hit(100, 0, 1.0) == 99,
            "with no meaningful defense, damage is essentially all of power")
        check(hit(100, 100, 1.0) == 50,
            "with defense equal to power, damage is 50% of power")
        check(hit(100, 200, 1.0) == 33,
            "with defense at twice power, damage is 33% of power")
        check(hit(100, 300, 1.0) == 25,
            "with defense at three times power, damage is 25% of power")

        -- Potency is a straight multiplier on the relative result, which is
        -- what lets multi-hit actions divide it without multiplying past flat
        -- defense.
        check(hit(100, 100, 2.0) == 100 and hit(100, 100, 0.5) == 25,
            "potency scales the relative result linearly")

        -- Scratch damage: the Pixie-versus-Golem case the design names.
        local scratch = hit(10, 140, 1.0)
        check(scratch >= 1 and scratch <= 2,
            "a frail attacker against a wall does scratch damage, never zero")
        check(hit(1, 9999, 1.0) == 1, "damage floors at 1, never 0")
    end)
end

------------------------------------------------------------ stat pairing --

do
    withRandom(NO_CRIT, function()
        -- A creature with ruinous MDF and enormous DEF: the Golem promise.
        -- Physical must meet DEF and magical must meet MDF, or the advertised
        -- weakness never appears in play.
        local sess, caster = rig({ atk = 100, def = 10, mat = 100, mdf = 10, maxHp = 500 })
        local _, golem = rig({ atk = 10, def = 300, mat = 10, mdf = 10, maxHp = 9999 })

        local function hit(eff)
            golem.hp = 9000
            local before = golem.hp
            effects.apply(eff, caster, golem, sess, {})
            return before - golem.hp
        end

        local physical = hit({ type = "hp_damage", power = "atk", potency = 1.0 })
        local magical = hit({ type = "hp_damage", power = "mat", potency = 1.0 })
        check(physical == 25, "physical damage is reduced by DEF")
        check(magical == 90, "magical damage is reduced by MDF, not DEF")
        check(magical > physical * 3,
            "a high-DEF low-MDF creature is genuinely vulnerable to magic")

        -- An exceptional skill may author the pairing outright.
        local crossed = hit({ type = "hp_damage", power = "atk", defense = "mdf", potency = 1.0 })
        check(crossed == 90, "an authored `defense` overrides the default pairing")
    end)
end

--------------------------------------------------------------- direct hit --

do
    withRandom(NO_CRIT, function()
        local sess, a = rig({ atk = 100, def = 10, mat = 10, mdf = 10, maxHp = 500 })
        local _, b = rig({ atk = 10, def = 300, mat = 10, mdf = 10, maxHp = 9999 })
        b.hp = 9000
        local before = b.hp
        -- No `power`: an authored number, the shape a trap or a scripted
        -- DAMAGE command uses. It must land as authored -- the old path put it
        -- through a defense divisor, so a trap that said 20 never dealt 20.
        effects.apply({ type = "hp_damage", formula = "20" }, a, b, sess, {})
        check(before - b.hp == 20, "direct damage lands as authored, unreduced")
    end)
end

---------------------------------------------------------------- criticals --

do
    local sess, a = rig({ atk = 100, def = 10, mat = 10, mdf = 10, maxHp = 500 })
    local _, b = rig({ atk = 10, def = 100, mat = 10, mdf = 10, maxHp = 9999 })

    local function hit(ctx)
        b.hp = 9000
        local before = b.hp
        effects.apply({ type = "hp_damage", power = "atk", potency = 1.0 }, a, b, sess, ctx or {})
        return before - b.hp
    end

    local plain, crit
    withRandom(NO_CRIT, function() plain = hit() end)
    withRandom(ALL_CRIT, function() crit = hit() end)

    local mult = ((loader.system and loader.system.combat) or {}).criticalMultiplier or 1.5
    check(plain == 50, "an ordinary hit is the plain relative result")
    check(crit == math.floor(50 * mult), "a critical multiplies the final damage")

    -- The event must say so, or presentation and the golden gate are both blind.
    withRandom(ALL_CRIT, function()
        b.hp = 9000
        local evs = effects.apply({ type = "hp_damage", power = "atk", potency = 1.0 },
            a, b, sess, {})
        local dmg
        for _, ev in ipairs(evs) do if ev.type == "damage" then dmg = ev end end
        check(dmg and dmg.critical == true, "a critical is reported on the damage event")
    end)
    withRandom(NO_CRIT, function()
        b.hp = 9000
        local evs = effects.apply({ type = "hp_damage", power = "atk", potency = 1.0 },
            a, b, sess, {})
        local dmg
        for _, ev in ipairs(evs) do if ev.type == "damage" then dmg = ev end end
        check(dmg and dmg.critical == nil, "an ordinary hit reports no critical")
    end)

    -- Direct damage has no attacker to be skilful: it must not crit.
    withRandom(ALL_CRIT, function()
        b.hp = 9000
        local before = b.hp
        effects.apply({ type = "hp_damage", formula = "20" }, a, b, sess, {})
        check(before - b.hp == 20, "direct damage never criticals")
    end)
end

-- Brigandine's rule: a critical damaging hit carries its attached status
-- through, bypassing the authored chance.
do
    local sess, a = rig({ atk = 100, def = 10, mat = 10, mdf = 10, maxHp = 500 })
    local _, b = rig({ atk = 10, def = 100, mat = 10, mdf = 10, maxHp = 9999 })

    -- chance 0 would never land on its own, so any application is the guarantee.
    local function act(critRoll)
        b.hp = 9000
        b.states = {}
        local actionCtx = {}
        withRandom({ critRoll, FAILS_ZERO_CHANCE }, function()
            effects.apply({ type = "hp_damage", power = "atk", potency = 1.0 },
                a, b, sess, actionCtx)
            effects.apply({ type = "add_status", status = "poison", chance = 0 },
                a, b, sess, actionCtx)
        end)
        for _, st in ipairs(b.states or {}) do
            if st.id == "poison" then return true end
        end
        return false
    end

    check(act(ALL_CRIT), "a critical hit guarantees the status attached to it")
    check(not act(NO_CRIT), "an ordinary hit still rolls the authored chance")

    -- A status action with no damage effect has nothing to crit on.
    do
        b.states = {}
        local actionCtx = {}
        withRandom(FAILS_ZERO_CHANCE, function()
            effects.apply({ type = "add_status", status = "poison", chance = 0 },
                a, b, sess, actionCtx)
        end)
        local got = false
        for _, st in ipairs(b.states or {}) do
            if st.id == "poison" then got = true end
        end
        check(not got, "a non-damaging status action does not critical")
    end
end

-------------------------------------------------------------- DAMAGE_RATE --

do
    withRandom(NO_CRIT, function()
        local sess, a = rig({ atk = 100, def = 10, mat = 100, mdf = 10, maxHp = 500 })
        local _, b = rig({ atk = 10, def = 100, mat = 10, mdf = 100, maxHp = 9999 })

        local function hit(power)
            b.hp = 9000
            local before = b.hp
            effects.apply({ type = "hp_damage", power = power, potency = 1.0 }, a, b, sess, {})
            return before - b.hp
        end

        local basePhysical, baseMagical = hit("atk"), hit("mat")

        b.actorData.traits = { { code = "DAMAGE_RATE", value = 0.5 } }
        check(hit("atk") == math.floor(basePhysical * 0.5),
            "DAMAGE_RATE halves physical damage")
        -- The whole point of replacing Defend's doubled DEF: it has to work
        -- against magic too.
        check(hit("mat") == math.floor(baseMagical * 0.5),
            "DAMAGE_RATE halves magical damage as well")

        -- Multiplicative, so two independent protections compound instead of
        -- summing past zero into a heal.
        b.actorData.traits = {
            { code = "DAMAGE_RATE", value = 0.5 },
            { code = "DAMAGE_RATE", value = 0.5 },
        }
        check(hit("atk") == math.floor(basePhysical * 0.25),
            "two DAMAGE_RATE sources multiply rather than sum")

        -- Authored indirect damage is explicitly outside its protection.
        b.actorData.traits = { { code = "DAMAGE_RATE", value = 0.5 } }
        b.hp = 9000
        local before = b.hp
        effects.apply({ type = "hp_damage", formula = "20" }, a, b, sess, {})
        check(before - b.hp == 20, "DAMAGE_RATE does not blunt direct authored damage")
    end)
end

-- The live Defend state must actually carry the new protection.
do
    local defending = loader.getState("defending")
    local hasRate = false
    for _, t in ipairs((defending and defending.traits) or {}) do
        if t.code == "DAMAGE_RATE" then hasRate = true end
    end
    check(hasRate, "the Defending state protects through DAMAGE_RATE, not doubled DEF")
end

-- Every authored damaging skill must speak the relative vocabulary: a skill
-- left on a raw formula would quietly become unreduced direct damage.
do
    local strays = {}
    for id, sk in pairs(loader.skills or {}) do
        for _, eff in ipairs(sk.effects or {}) do
            if (eff.type == "hp_damage" or eff.type == "hp_drain") and eff.power == nil then
                table.insert(strays, id)
            end
        end
    end
    check(#strays == 0,
        "every damaging skill authors a power source (" .. #strays .. " do not)")
end

print(("=== Damage Model Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then error("damage model tests failed") end
