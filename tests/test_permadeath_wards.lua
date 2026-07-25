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


-- 11. Generic trait access from formulas (engine/formula.lua): any registered
-- code must be readable as x.trait.<CODE>, which is what lets a trait be
-- implemented in data instead of new Lua per trait.
do
    local formula = require("engine.formula")
    local sess = sessionModule.GameSession.new(loader)
    local wisp
    for _, a in ipairs(loader.actors) do if a.name == "Wisp" then wisp = a.id end end
    local b = sess:recruitActor(wisp, 3)
    local view = formula.battlerView(b, sess)
    check(view.trait.MOVE_HEAL > 0,
        "battlerView.trait exposes MOVE_HEAL for a carrier (Wisp)")
    check(view.trait.GOLD_DIGGER == 0,
        "battlerView.trait returns 0 for a code the battler lacks")

    local group = formula.groupView(sess.party, sess)
    check(group.trait.MOVE_HEAL > 0,
        "groupView.trait sums a code across living members")
    check(group.trait.NOT_A_REAL_CODE == 0,
        "groupView.trait is safe for an unknown code")
end

-- 12. MOVE_HEAL actually heals through the exploration.step flow (data-driven,
-- reusing HEAL's trait form) -- the trait had NO carrier and no implementation
-- before 24.07.2026.
do
    local flow = require("engine.flow")
    local sess = sessionModule.GameSession.new(loader)
    local wisp
    for _, a in ipairs(loader.actors) do if a.name == "Wisp" then wisp = a.id end end
    local b = sess:recruitActor(wisp, 3)
    local maxHp = traits.getParam(b, "maxHp", sess)
    b.hp = 1
    flow.run("exploration.step", { session = sess })
    check(b.hp > 1, "exploration.step heals a MOVE_HEAL carrier while walking")
    local healed = b.hp
    b.hp = maxHp
    flow.run("exploration.step", { session = sess })
    check(b.hp == maxHp, "MOVE_HEAL never overheals past maxHp")

    -- A creature without the trait is untouched by the same step.
    local plain = sess:recruitActor(3, 3) -- Skeleton, no MOVE_HEAL
    plain.hp = 1
    flow.run("exploration.step", { session = sess })
    check(plain.hp == 1, "exploration.step leaves non-carriers alone")
    check(healed > 1, "sanity: the carrier did gain HP")
end


-- 13. Adjacency traits (SYMBIOSIS / PARASITE) via FOR_EACH's `neighbor` ref.
do
    local flow = require("engine.flow")
    local function idOf(name)
        for _, a in ipairs(loader.actors) do if a.name == name then return a.id end end
    end
    -- Nurse (symbiosis) in slot 1, a plain Skeleton beside it in slot 2.
    local sess = sessionModule.GameSession.new(loader)
    local nurse = sess:recruitActor(idOf("Nurse"), 3)
    local mate = sess:recruitActor(3, 3)
    mate.hp = 1
    sess.mapSafe = true -- keep MP drain/exhaustion out of this assertion
    flow.run("battle.round_end", { session = sess, party = sess.party })
    check(mate.hp > 1, "SYMBIOSIS heals the creature in the adjacent slot")
    check(nurse.hp == traits.getParam(nurse, "maxHp", sess),
        "SYMBIOSIS does not heal its own carrier")

    -- Larva (parasite) drains its neighbour instead.
    local sess2 = sessionModule.GameSession.new(loader)
    local larva = sess2:recruitActor(idOf("Larva"), 3)
    local victim = sess2:recruitActor(3, 3)
    sess2.mapSafe = true
    local before = victim.hp
    flow.run("battle.round_end", { session = sess2, party = sess2.party })
    check(victim.hp < before, "PARASITE drains the creature in the adjacent slot")

    -- Alone in the party, the same traits must no-op rather than error.
    local solo = sessionModule.GameSession.new(loader)
    local lonely = solo:recruitActor(idOf("Larva"), 3)
    solo.mapSafe = true
    local hp = lonely.hp
    local ok = pcall(flow.run, "battle.round_end", { session = solo, party = solo.party })
    check(ok and lonely.hp == hp,
        "adjacency traits no-op safely with no living neighbour")
end


-- 14. recruit_egg: the hatching item adds a creature (party, then reserve).
do
    local sess = sessionModule.GameSession.new(loader)
    local dummy = sess:recruitActor(3, 1)
    local before = #sess.party
    local evs = effects.apply({ type = "recruit_egg", value = 15 }, dummy, dummy, sess)
    check(#sess.party == before + 1, "recruit_egg recruits into a free party slot")
    local hatched = sess.party[#sess.party]
    check(hatched and hatched.id == 15, "recruit_egg recruits the actor named by `value`")
    local sawRecruit = false
    for _, ev in ipairs(evs) do if ev.type == "recruit" then sawRecruit = true end end
    check(sawRecruit, "recruit_egg emits a recruit event for presentation")

    local evs2 = effects.apply({ type = "recruit_egg", value = 99999 }, dummy, dummy, sess)
    check(evs2[1] and evs2[1].type == "text" and evs2[1].text:match("cannot recruit"),
        "recruit_egg reports an unknown actor instead of failing silently")
end

-- 15. RECOVERY_XP_BONUS at a recovery site (commonEvent 7, shared by every
-- recovery event on every map). The trait had no carrier before 24.07.2026.
do
    local sess = sessionModule.GameSession.new(loader)
    local function idOf(name)
        for _, a in ipairs(loader.actors) do if a.name == name then return a.id end end
    end
    local scholar = sess:recruitActor(idOf("Candle"), 3)
    local plain = sess:recruitActor(3, 3)
    local sxp, pxp = scholar.exp, plain.exp
    -- At runtime a common event compiles to a dialogue graph: interactive
    -- commands (TEXT) render, the rest run through runImmediate. Mirror that
    -- split here rather than pushing TEXT through immediate mode.
    local immediate = {}
    for _, c in ipairs(loader.commonEvents["7"].commands) do
        if not interpreter.INTERACTIVE_IDS[c.cmd] then table.insert(immediate, c) end
    end
    interpreter.runImmediate(immediate,
        { session = sess, loader = loader, party = sess.party, recoverParty = function() end })
    check(scholar.exp > sxp, "recovery site grants bonus XP to a RECOVERY_XP_BONUS carrier")
    check(plain.exp == pxp, "recovery site grants no bonus XP to a non-carrier")
end


-- 16. First strike (INITIATIVE) and its counter (REAR_GUARD) in the turn queue.
do
    local battleSystem = require("engine.battle")
    local function idOf(name)
        for _, a in ipairs(loader.actors) do if a.name == name then return a.id end end
    end

    -- Build a battle whose ONLY initiative carrier is an enemy Bat, then force
    -- the roll to succeed by seeding the RNG until it does.
    local function queueWith(partyNames, enemyName)
        local sess = sessionModule.GameSession.new(loader)
        for _, n in ipairs(partyNames) do sess:recruitActor(idOf(n), 3) end
        local enemy = sessionModule.Battler.new(loader.getActor(idOf(enemyName)), 3)
        local battle = battleSystem.Battle.new(sess, { enemy })
        local queue = battle:buildTurnQueue({})
        return queue, enemy, battle
    end

    -- A carrier can take the front of the queue. INITIATIVE is a 25% roll, so
    -- try a handful of seeds and assert it happens at least once (and that a
    -- non-carrier party never displaces it).
    local sawFirstStrike = false
    for seed = 1, 40 do
        math.randomseed(seed)
        local queue, enemy = queueWith({ "Skeleton" }, "Bat")
        if queue[1] and queue[1].actor == enemy and queue[1].firstStrike then
            sawFirstStrike = true
            break
        end
    end
    check(sawFirstStrike, "an INITIATIVE carrier can win the front of the turn queue")

    -- With a REAR_GUARD holder in the party, the enemy may never first-strike.
    local blocked = true
    for seed = 1, 60 do
        math.randomseed(seed)
        local queue = queueWith({ "Golem" }, "Bat") -- Golem carries rearGuard
        for _, turn in ipairs(queue) do
            if turn.firstStrike then blocked = false end
        end
    end
    check(blocked, "REAR_GUARD negates the opposing side's first strikes entirely")

    -- No carrier anywhere: nobody is flagged, and (critically for G2) the queue
    -- is exactly the speed order.
    math.randomseed(12345)
    local queue = queueWith({ "Skeleton" }, "Skeleton")
    local flagged = false
    for _, turn in ipairs(queue) do if turn.firstStrike then flagged = true end end
    check(not flagged, "no INITIATIVE carrier means no first-strike flags")
end


-- 17. Compiled dialogue graphs must be fully linked. Until 24.07.2026
-- ERASE_EVENT/RECRUIT_ACTOR/RECRUIT sat in INTERACTIVE_COMPILE_IDS with no
-- compile() branch, so every graph containing them (all recruitment scripts,
-- any looted-chest event) linked to node ids that were never created.
do
    local recruitment = require("engine.recruitment")
    local sess = sessionModule.GameSession.new(loader)
    sess.gold = 500
    local dangling = {}
    local function checkLinks(nodes, label)
        for id, node in pairs(nodes) do
            local links = { node.next, node.trueNode, node.falseNode }
            for _, opt in ipairs(node.options or {}) do
                table.insert(links, opt.target)
            end
            for _, target in ipairs(links) do
                if target and not nodes[target] then
                    table.insert(dangling, label .. ": " .. tostring(id)
                        .. " -> missing " .. tostring(target))
                end
            end
        end
    end

    for _, actorData in ipairs(loader.actors) do
        local cmds = recruitment.compile(actorData, 1, { loader = loader, session = sess })
        if cmds and #cmds > 0 then
            local nodes = {}
            interpreter.compileTop(nodes, cmds, "t" .. tostring(actorData.id), nil,
                { loader = loader, session = sess, recoverParty = function() end })
            checkLinks(nodes, "recruit " .. tostring(actorData.name))
        end
    end
    check(#dangling == 0,
        "every recruitment graph is fully linked (" .. tostring(#dangling) .. " dangling)")

    -- Same guarantee for authored map events (the trapped chest erases itself).
    local mapDangling = 0
    for _, mp in ipairs(loader.maps or {}) do
        for _, ev in ipairs(mp.events or {}) do
            if ev.commands and #ev.commands > 0 then
                local nodes = {}
                interpreter.compileTop(nodes, ev.commands, "e" .. tostring(ev.id or "?"), nil,
                    { loader = loader, session = sess, recoverParty = function() end })
                local before = #dangling
                checkLinks(nodes, "map event " .. tostring(ev.id))
                mapDangling = mapDangling + (#dangling - before)
            end
        end
    end
    check(mapDangling == 0, "every authored map event graph is fully linked")
end

-- 18. Trap/secret detection (SEE_TRAPS / SEE_WALLS): the trait value is a
-- capability level checked against each thing's difficulty.
do
    local detection = require("engine.detection")
    local function idOf(name)
        for _, a in ipairs(loader.actors) do if a.name == name then return a.id end end
    end
    local trapEasy = { meta = { detect = "trap", detectLevel = 1 } }
    local trapHard = { meta = { detect = "trap", detectLevel = 2 } }
    local secret   = { meta = { detect = "secret", detectLevel = 1 } }
    local plainEvent = { meta = { tier = 1 } }

    local blind = sessionModule.GameSession.new(loader)
    blind:recruitActor(3, 3) -- Skeleton: no senses
    check(not detection.isRevealed(blind, trapEasy),
        "a party with no senses notices nothing")

    -- Bat's nightVision is SEE_TRAPS level 2: it clears both difficulties.
    local sharp = sessionModule.GameSession.new(loader)
    sharp:recruitActor(idOf("Bat"), 3)
    check(detection.isRevealed(sharp, trapEasy) and detection.isRevealed(sharp, trapHard),
        "a level-2 trap sense notices both difficulty 1 and 2 traps")
    check(not detection.isRevealed(sharp, secret),
        "trap sense does not reveal secrets (that is SEE_WALLS)")

    -- Pixie's `sense` is SEE_WALLS 1: secrets yes, traps no.
    local walls = sessionModule.GameSession.new(loader)
    walls:recruitActor(idOf("Pixie"), 3)
    check(detection.isRevealed(walls, secret) and not detection.isRevealed(walls, trapEasy),
        "SEE_WALLS reveals secrets only")

    check(not detection.isRevealed(sharp, plainEvent) and not detection.isDetectable(plainEvent),
        "an ordinary event is not detectable at all")

    -- Capability is the party's BEST sense, not a sum: two level-1 noses must
    -- not add up to a level-2 one.
    local pair = sessionModule.GameSession.new(loader)
    pair:recruitActor(idOf("Candle"), 3) -- nightVision (2)
    check(detection.capability(pair, "SEE_TRAPS") == 2,
        "capability reports the best sense in the party")

    -- The authored proof content is actually detectable.
    local trapsFound, secretsFound = 0, 0
    for _, mp in ipairs(loader.maps or {}) do
        for _, ev in ipairs(mp.events or {}) do
            if detection.isDetectable(ev) then trapsFound = trapsFound + 1 end
        end
        for _, ov in ipairs(mp.overrides or {}) do
            if detection.isDetectable(ov) then secretsFound = secretsFound + 1 end
        end
    end
    check(trapsFound >= 2, "authored maps carry detectable trap events")
    check(secretsFound >= 1, "authored maps carry a detectable secret wall")
end

-- 19. End-to-end: detection markers reach the minimap. Also guards the map
-- generator's event copying -- it used to rebuild authored events from a
-- six-field whitelist, silently dropping `meta` (so nothing was detectable),
-- `label`, `minimapColor` and `pages`.
do
    local exploration = require("engine.exploration")
    local renderer = require("presentation.renderer")
    local detection = require("engine.detection")
    local function idOf(name)
        for _, a in ipairs(loader.actors) do if a.name == name then return a.id end end
    end
    local sess = sessionModule.GameSession.new(loader)
    sess:recruitActor(idOf("Bat"), 3) -- nightVision: SEE_TRAPS 2
    exploration.loadMap(sess, 2)
    renderer.init(sess)

    local revealed, metaKept = 0, 0
    for _, ev in ipairs(sess.currentMapData.events or {}) do
        if ev.meta then metaKept = metaKept + 1 end
        if detection.isRevealed(sess, ev) then revealed = revealed + 1 end
    end
    check(metaKept >= 3, "map generation preserves authored event `meta`")
    check(revealed >= 2, "authored traps are detectable once the floor is loaded")

    local canvas = love.graphics.newCanvas(256, 240)
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    renderer.drawMap()
    love.graphics.setCanvas()
    local data = canvas:newImageData()
    local orange = 0
    for y = 0, 60 do
        for x = 150, 255 do
            local r, g, b = data:getPixel(x, y)
            if r > 0.85 and g > 0.2 and g < 0.55 and b < 0.25 then orange = orange + 1 end
        end
    end
    check(orange > 0, "detected traps render as markers on the minimap")
end

print(string.format("=== Ward/effect/trait tests: %d passed, %d failed ===", passed, failed))
assert(failed == 0, "permadeath ward / effect tests failed")
