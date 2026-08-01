-- Skill costs: charges + Overcast (magic), cooldown/warmup/condition
-- (physical). See docs/design/skill-costs.md.
--
-- These are the rules the golden gates cannot see: G2 diffs a battle log and
-- G3 diffs UI events, but neither can tell you WHY a row was unavailable, that
-- a rest reached the bench, or that a debuff failed to shrink a maximum.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local skill_cost = require("engine.skill_cost")
local usability = require("engine.usability")

print("[TEST] Starting skill cost tests...")

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

local function rig()
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 1)
    b.states = {}
    return sess, b
end

------------------------------------------------------------------- charges --

do
    local sess, caster = rig()

    -- The formula reads BASE mdf, so a promoted or levelled caster gets more
    -- castings without the skill row changing.
    local skill = { id = "testSpell", charges = "4 + b.base.mdf / 4" }
    local max = skill_cost.maxCharges(skill, caster, sess)
    local baseMdf = require("engine.traits").getBaseParam(caster, "mdf")
    check(max == math.floor(4 + baseMdf / 4),
        "charges come from the authored formula against base MDF")

    -- Absent = full. A newly summoned creature, or one loaded from a save
    -- written before charges existed, arrives rested rather than mute.
    local current, m = skill_cost.getCharges(caster, "testSpell", skill, sess)
    check(current == m and current == max, "an unrecorded pool reads as full")

    -- A formula that rounds to nothing still leaves one casting: a spell that
    -- silently could never be cast is worse than a weak one.
    check(skill_cost.maxCharges({ id = "x", charges = "b.base.mdf / 9999" }, caster, sess) == 1,
        "a charge formula floors at 1 rather than 0")

    -- ...but a literal 0 is preserved. That is the Overcast-only shape.
    check(skill_cost.maxCharges({ id = "x", charges = 0 }, caster, sess) == 0,
        "an authored charges:0 stays 0 (the Overcast-only shape)")

    -- No charges key at all = not a magic skill, no pool.
    check(skill_cost.maxCharges({ id = "x" }, caster, sess) == nil,
        "a skill with no charges key has no pool")
end

do
    -- Equipment must not be able to buy castings, and a debuff must not be
    -- able to shrink a maximum while the creature holds spent charges (which
    -- would put current above max, or lose them silently).
    local sess, caster = rig()
    local skill = { id = "testSpell", charges = "4 + b.base.mdf / 4" }
    local before = skill_cost.maxCharges(skill, caster, sess)

    caster.passives = {}
    caster.actorData = setmetatable({ traits = {
        { code = "PARAM_PLUS", dataId = "mdf", value = 40 },
        { code = "PARAM_RATE", dataId = "mdf", value = 0.5 },
    } }, { __index = caster.actorData })

    check(skill_cost.maxCharges(skill, caster, sess) == before,
        "PARAM_PLUS/PARAM_RATE on MDF cannot move max charges")
end

------------------------------------------------------------------ Overcast --

do
    local sess, caster = rig()
    local spell = { id = "spell", charges = 1, overcast = { mp = 100 } }

    check(skill_cost.payment(spell, caster, sess, false) == "charge",
        "a spell with charges left spends a charge")

    skill_cost.spend(spell, caster, sess, false)
    check(select(1, skill_cost.getCharges(caster, "spell", spell, sess)) == 0,
        "spending decrements the pool")

    -- Overcast is offered ONLY at zero, so there is never a choice to optimize.
    sess.mp = 500
    check(skill_cost.payment(spell, caster, sess, false) == "overcast",
        "at zero charges the spell may be Overcast")
    skill_cost.spend(spell, caster, sess, false)
    check(sess.mp == 400, "Overcast is paid out of the Summoner's shared pool")

    sess.mp = 50
    local how, reason = skill_cost.payment(spell, caster, sess, false)
    check(how == nil and reason == "Not enough MP to Overcast",
        "Overcast is refused when the pool is short, with a reason")

    -- Enemies have no Summoner and no pool: out of charges means out of spell.
    sess.mp = 500
    check(skill_cost.payment(spell, caster, sess, true) == nil,
        "an enemy never Overcasts")

    -- No overcast key = some magic is simply unavailable when spent, not
    -- purchasable.
    local finite = { id = "finite", charges = 1 }
    skill_cost.spend(finite, caster, sess, false)
    check(skill_cost.payment(finite, caster, sess, false) == nil,
        "a spell with no overcast cost cannot be cast at zero charges")
end

do
    -- Overcast-only: the pool exists and is permanently empty, so the
    -- zero-charge branch is the only branch the skill ever takes. This is a
    -- dragon Breath.
    local sess, dragon = rig()
    local breath = { id = "breath", charges = 0, overcast = { mp = 400 } }
    sess.mp = 1000

    check(skill_cost.payment(breath, dragon, sess, false) == "overcast",
        "an Overcast-only skill Overcasts from the very first use")
    skill_cost.spend(breath, dragon, sess, false)
    skill_cost.spend(breath, dragon, sess, false)
    check(sess.mp == 200, "each Breath bills the Summoner again")
    check(select(1, skill_cost.getCharges(dragon, "breath", breath, sess)) == 0,
        "and it never accumulates charges to spend instead")
end

--------------------------------------------------------------------- rest --

do
    -- Rest is a location, not an activity: the bench rests too, or swapping in
    -- a reserve creature would hand the player a spent one.
    local sess, active = rig()
    local skill = { id = "spell", charges = 4 }
    local benched = sess:recruitActor(3, 1)
    local stored = sess:recruitActor(3, 1)
    sess.party[1] = active
    sess.reserve[1] = benched
    sess.storage[1] = stored
    for _, b in ipairs({ active, benched, stored }) do
        b.charges = { spell = 0 }
    end

    sess:rest()
    check(select(1, skill_cost.getCharges(active, "spell", skill, sess)) == 4,
        "rest refills the fielded party")
    check(select(1, skill_cost.getCharges(benched, "spell", skill, sess)) == 4,
        "rest reaches the reserve")
    check(select(1, skill_cost.getCharges(stored, "spell", skill, sess)) == 4,
        "rest reaches town storage")
end

do
    -- Partial restore: the item/food channel, sharing skill_cost.restore with
    -- the full refill so "full" cannot mean two different things.
    local sess, caster = rig()
    caster.skills = { "windBlade" }
    local sk = loader.getSkill("windBlade")
    local max = select(2, skill_cost.getCharges(caster, "windBlade", sk, sess))
    caster.charges = { windBlade = 0 }

    check(skill_cost.restore(caster, sess, loader, nil, 2) == 2,
        "a partial restore reports what it actually restored")
    check(select(1, skill_cost.getCharges(caster, "windBlade", sk, sess)) == 2,
        "...and grants exactly that")

    check(skill_cost.restore(caster, sess, loader, nil, "all") == max - 2,
        "amount 'all' tops the pool up")
    check(skill_cost.restore(caster, sess, loader, nil, 5) == 0,
        "restoring a full pool restores nothing, so an item can refuse itself")
end

do
    -- Promotion is a rest (rare, rebuilds the creature, happens in the ritual);
    -- levelling is not.
    local sess, caster = rig()
    caster.charges = { windBlade = 0 }
    local transform = require("engine.transform")
    local newForm = transform.into(sess, caster, caster.actorData, {})
    check(newForm.charges == nil, "promotion rests the creature")

    local leveller = select(2, rig())
    leveller.charges = { windBlade = 0 }
    leveller:gainExp(1, sess)
    check(leveller.charges and leveller.charges.windBlade == 0,
        "levelling does not refill charges")
end

-------------------------------------------------------- availability gates --

do
    local sess, fighter = rig()
    local skill = { id = "smash", cooldown = 2 }
    skill_cost.beginBattle(fighter, loader)

    check(skill_cost.blockedReason(skill, fighter, sess, false) == nil,
        "a cooldown skill is available at the start of a battle")

    skill_cost.startCooldown(skill, fighter)
    check(skill_cost.blockedReason(skill, fighter, sess, false) == "Cooling down (2)",
        "using it starts the cooldown, with a reason to show the player")

    skill_cost.tick(fighter)
    check(skill_cost.cooldownLeft(skill, fighter) == 1, "a round elapses one turn")
    skill_cost.tick(fighter)
    check(skill_cost.blockedReason(skill, fighter, sess, false) == nil,
        "and it comes back when the cooldown runs out")
end

do
    -- Warmup is measured from the start of THIS battle, and is independent of
    -- cooldown: a skill may unlock late and then be usable every round.
    local sess, fighter = rig()
    fighter.skills = { "slowBurn" }
    local realGet = loader.getSkill
    loader.getSkill = function(id)
        if id == "slowBurn" then return { id = "slowBurn", warmup = 2 } end
        return realGet(id)
    end
    local skill = loader.getSkill("slowBurn")

    skill_cost.beginBattle(fighter, loader)
    check(skill_cost.blockedReason(skill, fighter, sess, false) == "Ready in 2 rounds",
        "a warmup skill is unavailable at the start of a battle")
    skill_cost.tick(fighter)
    check(skill_cost.blockedReason(skill, fighter, sess, false) == "Ready in 1 round",
        "the wait counts down and reads naturally at 1")
    skill_cost.tick(fighter)
    check(skill_cost.blockedReason(skill, fighter, sess, false) == nil,
        "then it unlocks for the rest of the fight")

    -- Battle-scoped: a fresh battle re-arms the warmup rather than remembering
    -- that it was already paid.
    skill_cost.beginBattle(fighter, loader)
    check(skill_cost.warmupLeft(skill, fighter) == 2,
        "a new battle re-arms the warmup")
    loader.getSkill = realGet
end

do
    -- Cooldowns do not follow a creature out of the fight.
    local sess, fighter = rig()
    skill_cost.beginBattle(fighter, loader)
    skill_cost.startCooldown({ id = "smash", cooldown = 3 }, fighter)
    skill_cost.endBattle(fighter)
    check(fighter.skillTimers == nil, "battle end discards the timers entirely")
end

do
    local sess, fighter = rig()
    skill_cost.beginBattle(fighter, loader)

    local atFull = { id = "opener", condition = "a.hp >= a.maxHp",
                     conditionText = "Only at full HP" }
    check(skill_cost.blockedReason(atFull, fighter, sess, false) == nil,
        "a formula condition passes when it is satisfied")

    fighter.hp = 1
    check(skill_cost.blockedReason(atFull, fighter, sess, false) == "Only at full HP",
        "...and reports the AUTHORED text when it is not")

    -- The state: prefix goes through engine/conditions.lua, the shared grammar,
    -- rather than a private parser in skill_cost.
    local whileBlind = { id = "grope", condition = "state:blind",
                         conditionText = "Only while Blind" }
    check(skill_cost.blockedReason(whileBlind, fighter, sess, false) == "Only while Blind",
        "a state: condition blocks when the state is absent")
    fighter:addState("blind")
    check(skill_cost.blockedReason(whileBlind, fighter, sess, false) == nil,
        "and passes when it is present")
end

------------------------------------------------------- the single predicate --

do
    -- The player's menu, the AI and the status scene all ask this one function,
    -- so a row the player sees greyed is a row the enemy cannot pick either.
    local sess, caster = rig()
    skill_cost.beginBattle(caster, loader)
    local spell = { id = "spell", target = "enemy-any", charges = 1 }

    check(usability.canUseSkill(spell, caster, nil, { session = sess }),
        "canUseSkill allows a paid-for skill")
    skill_cost.spend(spell, caster, sess, false)
    local ok, reason = usability.canUseSkill(spell, caster, nil, { session = sess })
    check(not ok and reason == "Out of charges",
        "canUseSkill refuses an empty pool, with the reason the menu shows")
end

do
    -- The basic attack must never be gated: there has to always be something
    -- to do, which is also what the AI falls back to.
    local sess, fighter = rig()
    skill_cost.beginBattle(fighter, loader)
    local attack = loader.getSkill((loader.system.combat or {}).attackSkillId or "attack")
    check(attack ~= nil and skill_cost.blockedReason(attack, fighter, sess, false) == nil,
        "the basic attack carries no cost or gate")
end

print(("=== Skill Cost Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("skill cost tests failed", failed) end
