-- FORCE_ACTION: a state, passive or item that takes the choice away.
--
-- Berserk is the case this exists for. It has raised ATK since it was written
-- and never once compelled anything, so a creature the player was told had lost
-- control kept following orders precisely. The golden fixtures cannot see this:
-- no fixture applies berserk, and a compelled creature that still obeys
-- produces a perfectly stable log.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local battleSystem = require("engine.battle")

print("[TEST] Starting forced action tests...")

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

-- Skeleton knows more than one skill, so "it used Attack" is a real choice
-- being overridden rather than the only option available.
local function rig()
    local sess = sessionModule.GameSession.new(loader)
    local ally = sess:recruitActor("skeleton", 5)
    local enemy = sessionModule.Battler.new(loader.getUnit("skeleton"), 5)
    enemy.hp = enemy:getMaxHp(sess)
    local b = battleSystem.Battle.new(sess, { enemy })
    return sess, b, sess.party[1] or ally, enemy
end

local function queueFor(b, collected)
    local queue = b:buildTurnQueue(collected)
    local bySlot = {}
    for _, turn in ipairs(queue) do bySlot[turn.actor] = turn end
    return bySlot
end

------------------------------------------------------------------- the trait --

do
    local sess, b, ally = rig()
    -- Baseline: the chosen skill is honoured when nothing compels.
    local turn = queueFor(b, { [1] = { type = "skill", id = "boneRush", target = b.enemies[1] } })[ally]
    check(turn and turn.skill and turn.skill.id == "boneRush",
        "an uncompelled creature performs the skill it was given")
end

do
    local sess, b, ally = rig()
    ally:addState("berserk")
    local turn = queueFor(b, { [1] = { type = "skill", id = "boneRush", target = b.enemies[1] } })[ally]
    check(turn and turn.skill and turn.skill.id == "attack",
        "a berserk creature attacks instead of casting what it was told to")
    check(turn and turn.target ~= nil,
        "the forced action still resolves a target")
end

do
    -- Defend is the dangerous one to leave working: a berserk creature that can
    -- still be told to guard has lost nothing at all.
    local sess, b, ally = rig()
    ally:addState("berserk")
    local turn = queueFor(b, { [1] = { type = "defend" } })[ally]
    check(turn and turn.skill and turn.skill.id == "attack",
        "a berserk creature cannot be told to defend")
end

do
    -- Nor rummage in a bag.
    local sess, b, ally = rig()
    ally:addState("berserk")
    local turn = queueFor(b, { [1] = { type = "item", itemIndex = 1, target = ally } })[ally]
    check(turn and turn.item == nil and turn.skill and turn.skill.id == "attack",
        "a berserk creature cannot use an item")
end

do
    -- The trait, not the state name. Nothing in the engine knows what berserk
    -- is; any source carrying FORCE_ACTION compels, which is the whole point.
    local sess, b, ally = rig()
    local private = {}
    for k, v in pairs(ally.actorData) do private[k] = v end
    private.traits = { { code = "FORCE_ACTION", dataId = "windBlade" } }
    ally.actorData = private
    local turn = queueFor(b, { [1] = { type = "attack", target = b.enemies[1] } })[ally]
    check(turn and turn.skill and turn.skill.id == "windBlade",
        "any source carrying FORCE_ACTION compels, and it names the skill")
end

--------------------------------------------------------------- the enemy side --

do
    -- One rule, both sides: the AI is compelled by the same trait, and the
    -- battle scene is not involved in an enemy's turn at all.
    local sess, b, ally, enemy = rig()
    enemy:addState("berserk")
    local action = b:getAIAction(enemy)
    check(action and action.skill and action.skill.id == "attack",
        "a berserk enemy is compelled by the same trait")
end

do
    -- RNG discipline. The compelled path returns before the AI's skill roll --
    -- choosing a skill and then discarding it would still consume draws and
    -- shift every later roll in the round. It does still draw for TARGET
    -- selection, as any path must, so the property is "fewer draws, because the
    -- skill roll is skipped", not "no draws at all".
    local function drawsFor(compelled)
        local sess, b, ally, enemy = rig()
        if compelled then enemy:addState("berserk") end
        local draws = 0
        local realRandom = math.random
        math.random = function(...) draws = draws + 1 return realRandom(...) end
        local ok = pcall(function() b:getAIAction(enemy) end)
        math.random = realRandom
        return ok and draws or nil
    end

    local free, forced = drawsFor(false), drawsFor(true)
    check(free ~= nil and forced ~= nil and forced < free,
        "a compelled enemy skips the AI skill roll (" .. tostring(forced)
        .. " draws vs " .. tostring(free) .. ")")
end

------------------------------------------------------------------ the state --

do
    -- The live state must actually carry it, or the tags it gained today are
    -- a description of behaviour it does not have.
    local berserk = loader.getState("berserk")
    local forces, raises = nil, false
    for _, t in ipairs((berserk and berserk.traits) or {}) do
        if t.code == "FORCE_ACTION" then forces = t.dataId end
        if t.code == "PARAM_PLUS" and t.dataId == "atk" then raises = true end
    end
    check(forces ~= nil, "the live Berserk state forces an action")
    check(loader.getSkill(forces) ~= nil,
        "the action Berserk forces is a real skill (" .. tostring(forces) .. ")")
    check(raises, "Berserk still raises ATK -- the trade, not just the penalty")
end

print(("=== Forced Action Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("forced action tests failed", failed) end
