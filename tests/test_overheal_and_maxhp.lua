-- Overheal and Temporary Max HP Tests
package.path = package.path .. ";./?.lua;./engine/?.lua"

_G.love = {
    filesystem = {
        getInfo = function(p)
            local f = io.open(p, "r")
            if f then f:close(); return true end
            return false
        end,
        read = function(p)
            local f = io.open(p, "r")
            if f then
                local content = f:read("*a")
                f:close()
                return content
            end
            return nil
        end,
    },
    math = {
        getRandomSeed = function() return 12345 end
    }
}

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")
local interpreter = require("engine.interpreter")

print("[TEST] Starting overheal and temporary max HP tests...")

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

-- Helper to quickly rig a battler.
local function rig(maxHp)
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(1, 1)
    local private = {}
    for k, v in pairs(b.actorData) do private[k] = v end
    private.baseParams = private.baseParams or {}
    private.baseParams.maxHp = maxHp
    b.actorData = private
    b.growth = { maxHp = 0 }
    b.hp = maxHp
    b.states = {}
    return sess, b
end

do
    local sess, b = rig(100)
    b.hp = 80

    -- Ordinary heal clamps at Max HP
    effects.apply({ type = "hp_heal", formula = "50", allowOverheal = false }, b, b, sess, {})
    check(b.hp == 100, "ordinary healing clamps at Max HP")

    -- Overheal allows exceeding Max HP up to cap
    effects.apply({ type = "hp_heal", formula = "50", allowOverheal = true }, b, b, sess, {})
    check(b.hp == 150, "allowOverheal raises HP above Max HP")

    -- Overheal cap is enforced
    effects.apply({ type = "hp_heal", formula = "500", allowOverheal = true }, b, b, sess, {})
    check(b.hp == 150, "allowOverheal enforces a cap (1.5x maxHp)")

    -- Ordinary heal on already overhealed character does NOT decrease HP
    effects.apply({ type = "hp_heal", formula = "50", allowOverheal = false }, b, b, sess, {})
    check(b.hp == 150, "ordinary heal on overhealed character does not decrease HP")
end

do
    local sess, b = rig(100)
    local oldGetState = sess.loader.getState
    sess.loader.getState = function(id)
        if id == "test_maxhp_up" then
            return {
                id = "test_maxhp_up",
                duration = 3,
                traits = { { code = "PARAM_PLUS", dataId = "maxHp", value = 25 } }
            }
        end
        return oldGetState(id)
    end

    b.hp = 80
    b:addState("test_maxhp_up", nil, sess)
    print("Actual HP: " .. tostring(b.hp))
    check(b.hp == 105, "temporary Max HP increase immediately grants corresponding current HP")
    check(b:getMaxHp(sess) == 125, "temporary Max HP is 125")

    -- Overheal interaction 1: 130 / 100 -> +25 maxHp -> 130 / 125
    b:removeState("test_maxhp_up", sess) -- reset
    b.hp = 130
    b:addState("test_maxhp_up", nil, sess)
    check(b.hp == 130, "130/100 -> +25 maxHp becomes 130/125 without adding extra HP")

    -- Overheal interaction 2: 110 / 100 -> +25 maxHp -> 125 / 125
    b:removeState("test_maxhp_up", sess) -- reset
    b.hp = 110
    b:addState("test_maxhp_up", nil, sess)
    check(b.hp == 125, "110/100 -> +25 maxHp becomes 125/125 by granting partial HP up to capacity")

    -- Overheal interaction 3: Overheal cap drops
    b.hp = 160 -- Overhealed past 125 (cap 187)
    b:removeState("test_maxhp_up", sess) -- Returns to 100 max HP
    check(b.hp == 150, "160/125 -> -25 maxHp clamps to new overheal cap of 150")

    -- Max HP expiry clamps current HP without damage (tested earlier)
    b.hp = 117
    b:addState("test_maxhp_up", nil, sess) -- max HP 125, hp 117+8 = 125
    b.hp = 117 -- manually adjust
    b:removeState("test_maxhp_up", sess)
    check(b.hp == 100, "117/125 -> -25 maxHp clamps to underlying max HP 100")

    sess.loader.getState = oldGetState
end

print(("=== Overheal Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("overheal tests failed", failed) end
