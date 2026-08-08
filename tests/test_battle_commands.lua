-- The battle console used to draw a fixed five rows and dispatch on the row
-- number, so every creature could attack, flee and rummage in the bag -- an Egg
-- included, despite its only skill being Wait. The command set is data now.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local battle = require("engine.battle")

print("[TEST] Starting battle command tests...")

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1 print("  [PASS] " .. msg)
    else failed = failed + 1 print("  [FAIL] " .. msg) end
end

loader.init()

local function ids(battler)
    local out = {}
    for _, c in ipairs(battle.commandsFor(battler, loader)) do table.insert(out, c.id) end
    return out
end
local function join(t) return table.concat(t, ",") end

-- An ordinary creature authors nothing and gets the default set, in the order
-- the registry declares -- which is the order the menu has always had.
local ordinary = sessionModule.Battler.new(loader.getActor(3), 1)
check(join(ids(ordinary)) == "attack,skill,defend,item,flee",
    "a creature that authors no list gets the default set, in menu order")

-- The Egg: the whole of "an Egg can do nothing else" is one authored list.
local egg = sessionModule.Battler.new(loader.getActor(15), 1)
check(join(ids(egg)) == "wait", "an Egg can only wait")

-- Registry order wins over the order an actor happens to list them in, so the
-- menu never reshuffles between creatures.
local scrambled = { actorData = { battleCommands = { "flee", "attack", "defend" } } }
check(join(ids(scrambled)) == "attack,defend,flee",
    "an actor's list is drawn in registry order, not authoring order")

-- An unknown id is ignored rather than drawn as a blank row; G1 is what
-- actually rejects it, this only pins that it cannot reach the menu.
local bogus = { actorData = { battleCommands = { "attack", "nonexistent" } } }
check(join(ids(bogus)) == "attack", "an unknown command id never reaches the menu")

-- Every command the registry offers must be dispatchable by the console: it
-- either opens target selection, opens a submenu, or commits outright.
local seen = {}
for _, cmd in ipairs(loader.engine.battleCommands or {}) do
    seen[cmd.id] = true
    check(cmd.resolve == "target" or cmd.resolve == "submenu" or cmd.resolve == "commit",
        "command '" .. tostring(cmd.id) .. "' declares how it resolves")
end
check(seen.wait and seen.flee, "Wait and Flee are registry commands like the rest")

-- Flee is a skill now, so it is authorable the way attack, defend and wait are.
check(loader.getSkill("flee") ~= nil, "Flee is backed by a real skill")
local waitSkill = loader.getSkill("wait")
check(waitSkill and #(waitSkill.effects or {}) == 0,
    "Wait is a genuine no-op -- it spends the turn and does nothing")

-- Escaping is an effect, not a keyword. It used to be `act.type == "flee"`
-- scanned before the round was built, so it preempted the whole round and no
-- item could ever carry it. It resolves in speed order now, which is why the
-- default golden fixture's fleeing Pixie dies to a faster Skeleton first --
-- that fixture no longer covers a SUCCESSFUL escape, so this does.
local effects = require("engine.effects")

local fleeSkill = loader.getSkill("flee")
local escapeEffect
for _, eff in ipairs(fleeSkill.effects or {}) do
    if eff.type == "escape" then escapeEffect = eff end
end
check(escapeEffect ~= nil, "the Flee skill escapes by declaring an effect, not by its id")

local sess = sessionModule.GameSession.new(loader)
sess:initializeStartingParty()
local enemy = sessionModule.Battler.new(loader.getActor(3), 1)
local arena = battle.Battle.new(sess, { enemy })
local actor = sess.party[1]

-- The flow decides, so run it enough times to see both branches rather than
-- reaching past it and asserting the roll.
local sawSuccess, sawFailure = false, false
for _ = 1, 200 do
    local evs = effects.apply(escapeEffect, actor, actor, sess, { battle = arena })
    for _, ev in ipairs(evs) do
        if ev.type == "flee_success" then sawSuccess = true end
        if ev.type == "text" then sawFailure = true end
    end
end
check(sawSuccess, "an escape effect can succeed, emitting flee_success")
check(sawFailure, "and can fail, which is what makes it a gamble")

-- Outside a battle there is nothing to escape from; a menu must not blow up.
local outside = effects.apply(escapeEffect, actor, actor, sess, {})
check(type(outside) == "table" and #outside == 0,
    "an escape effect outside battle does nothing rather than erroring")

---------------------------------------------------------------- #179 authority --

-- A detached battle view may show an earlier frame, but mutating/advancing it
-- must never write back into the real Battler/GameSession graph.
do
    local battleView = require("presentation.battle_view")
    local s = sessionModule.GameSession.new(loader)
    s:initializeStartingParty()
    s.mp, s.maxMp = 100, 100
    local foe = sessionModule.Battler.new(loader.getActor(3), 1)
    local b = battle.Battle.new(s, { foe })
    local member = s.party[1]
    member.hp = math.max(2, member:getMaxHp(s))
    local beforeHp = member.hp

    battleView.beginRound(s, b)
    member.hp = math.max(0, beforeHp - 7)
    s.mp = 63

    local projectedState, projectedSession = battleView.projectState({ v = { battle = b } }, s)
    check(projectedState ~= nil and projectedSession ~= nil,
        "BattleView creates a detached draw projection for an active round")
    check(projectedSession.party[1].hp == beforeHp and projectedSession.mp == 100,
        "the projection keeps the pre-resolution visual HP/MP frame")

    battleView.applyEvent({ type = "damage", target = member, value = 7,
        hpBefore = beforeHp, hpAfter = beforeHp - 7 })
    battleView.applyEvent({ type = "overcast", value = 37, mpBefore = 100, mpAfter = 63 })
    check(projectedSession.party[1].hp == beforeHp - 7 and projectedSession.mp == 63,
        "resolved damage/Overcast facts advance only the presentation projection")
    check(member.hp == beforeHp - 7 and s.mp == 63,
        "advancing BattleView leaves authoritative HP/MP untouched")

    -- The inverse MP transition matters too: Reaper/KILL_MP_RESTORE was also
    -- erased by the old MP rollback because presentation had no replay branch.
    -- Here the engine has already resolved 63 -> 75; the event merely catches
    -- the detached visual pool up to that fact.
    s.mp = 75
    battleView.applyEvent({ type = "kill_mp_restore", value = 12,
        mpBefore = 63, mpAfter = 75 })
    check(projectedSession.mp == 75,
        "KILL_MP_RESTORE advances the projected MP to the engine's resolved value")
    check(s.mp == 75,
        "projecting a Reaper MP reward does not perform the authoritative restore again")

    -- Party membership is the other dangerous clock. A wave/reap visual may
    -- temporarily show a different slot occupant, but the real session is not
    -- a presentation scratchpad and must never move with that projection.
    battleView.applyWaveEntry({ slot = 1, battler = foe, reserveKey = 1 })
    check(projectedSession.party[1].name == foe.name,
        "a wave can advance projected slot membership")
    check(s.party[1] == member,
        "projecting a wave does not rewrite authoritative party membership")
    battleView.applyReap({ slot = 1 })
    check(projectedSession.party[1].name == member.name,
        "reap projection can converge the visual slot to authoritative membership")
    check(s.party[1] == member,
        "converging a reap projection leaves authoritative party membership untouched")
    battleView.clear()
end

-- Regression specimen discovered while investigating #179: Overcast was paid
-- by Battle:resolveRound(), then the live scene wrapper restored the old MP and
-- had no `overcast` replay branch, making the cast free only in live play.
do
    local sceneHost = require("engine.scene_host")
    local battleScene = require("engine.scenes.battle")
    local battleView = require("presentation.battle_view")
    local oldGetSkill = loader.getSkill
    local testSkill = {
        id = "testOvercast179", name = "Test Overcast", target = "enemy",
        speed = 999, effects = {}, charges = 0, overcast = { mp = 37 },
    }
    loader.getSkill = function(id)
        if id == testSkill.id then return testSkill end
        return oldGetSkill(id)
    end

    local s = sessionModule.GameSession.new(loader)
    s:initializeStartingParty()
    s.mp, s.maxMp = 100, 100
    local member = s.party[1]
    member.skills = { testSkill.id }
    local foe = sessionModule.Battler.new(loader.getActor(3), 1)
    foe.hp = foe:getMaxHp(s)
    local b = battle.Battle.new(s, { foe })

    local oldGlobal = _G.activeSession
    _G.activeSession = s
    sceneHost.init()
    sceneHost.push("battle", { session = s, loader = loader, party = s.party })
    local v = battleScene.getState()
    v.battle = b
    v.collectedActions = { [1] = { type = "skill", id = testSkill.id, target = foe } }
    battleScene.resolveRound()

    check(s.mp == 63,
        "live scene resolution preserves the authoritative Overcast MP spend")
    check(battleView.isActive(),
        "live scene resolution starts a presentation projection instead of rolling state back")

    battleView.clear()
    sceneHost.init()
    _G.activeSession = oldGlobal
    loader.getSkill = oldGetSkill
end

-- REAP_FALLEN is the semantic authority on permanent death. By the time its
-- immediate-mode command returns, the real party slot must already reflect the
-- decision; the reap animation is allowed to delay only what is drawn.
do
    local interpreter = require("engine.interpreter")
    local s = sessionModule.GameSession.new(loader)
    s:initializeStartingParty()
    local member = s.party[1]
    -- Isolate one occupied slot so autoFieldIfEmpty has nothing else to refill.
    for i = 2, 4 do s.party[i] = nil end
    s.reserve = {}
    member.hp = 0
    member:addState("dead")
    local b = battle.Battle.new(s, {})
    local evs = interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, {
        session = s, battle = b, party = s.party, enemies = {}, events = {},
    })
    local sawReap = false
    for _, ev in ipairs(evs) do if ev.type == "reap" then sawReap = true end end
    check(sawReap, "REAP_FALLEN emits the presentation fact for a permanent death")
    check(s.party[1] == nil,
        "REAP_FALLEN removes the authoritative party slot before presentation")
end

print(string.format("=== Battle Command Tests: %d passed, %d failed ===", passed, failed))
if failed > 0 then require("tests.fail_fast")(failed .. " battle command test(s) failed", failed) end
