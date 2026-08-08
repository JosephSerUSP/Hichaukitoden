-- #179: battle presentation may delay what is visible, never what is true.
--
-- This suite is intentionally small and behavioral. It proves both sides of
-- the seam:
--   1. BattleView can advance HP/state/MP/roster presentation without changing
--      authoritative Battler/GameSession semantic fields.
--   2. REAP_FALLEN has committed party membership before immediate engine
--      execution returns; no animation callback is required for permadeath.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local battle_view = require("presentation.battle_view")
local loader = require("data.loader")
local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")

local M = {}

local function containsState(states, id)
    for _, st in ipairs(states or {}) do
        if st.id == id then return true end
    end
    return false
end

local function fakeBattler(name, hp, maxHp)
    local b = {
        name = name,
        hp = hp,
        displayedHp = hp,
        states = {},
    }
    function b:getMaxHp() return maxHp end
    function b:isDead()
        return self.hp <= 0 or containsState(self.states, "dead")
    end
    return b
end

function M.run()
    print("[TEST] Starting battle presentation authority tests...")

    -- Detached projection: authoritative objects are first advanced to their
    -- already-resolved final state, then presentation catches up from the old
    -- visible frame. Applying presentation events must not write those domain
    -- fields a second time.
    do
        battle_view.clear()
        local outgoing = fakeBattler("Outgoing", 40, 50)
        local incoming = fakeBattler("Incoming", 30, 30)
        local enemy = fakeBattler("Enemy", 20, 20)
        local sess = {
            party = { outgoing },
            reserve = { incoming },
            mp = 18,
            displayedMp = 18,
        }
        local btl = {}
        function btl:getAllActiveBattlers() return { outgoing, enemy } end

        battle_view.beginRound(btl, sess)

        -- Engine truth after resolution. These writes stand in for Battle,
        -- effects and interpreter semantics; BattleView must only observe them.
        outgoing.hp = 7
        outgoing.states = { { id = "poison", duration = 2 } }
        sess.mp = 11
        sess.party[1] = incoming
        sess.reserve[1] = nil

        local authoritativeStates = outgoing.states
        local authoritativeParty = sess.party
        local authoritativeReserve = sess.reserve

        battle_view.apply({
            target = outgoing,
            resolved = {
                hp = 7,
                maxHp = 50,
                states = { { id = "poison", duration = 2 } },
            },
        }, { hp = true, maxHp = true, states = true })
        battle_view.apply({ resolved = { mp = 11 } }, { mp = true })
        battle_view.applyWaveSlot({
            slot = 1,
            battler = incoming,
            partyAfter = incoming,
            reserveKey = 1,
            reserveAfter = nil,
        })

        -- Even the per-frame gauge interpolation is allowed to touch only the
        -- explicitly presentation-owned displayedHp/displayedMp caches.
        battle_view.update(1 / 60, sess)

        assert(outgoing.hp == 7,
            "BattleView changed authoritative battler.hp")
        assert(outgoing.states == authoritativeStates
            and containsState(outgoing.states, "poison"),
            "BattleView replaced or changed authoritative battler.states")
        assert(sess.mp == 11,
            "BattleView changed authoritative session.mp")
        assert(sess.party == authoritativeParty and sess.party[1] == incoming,
            "BattleView changed authoritative session.party")
        assert(sess.reserve == authoritativeReserve and sess.reserve[1] == nil,
            "BattleView changed authoritative session.reserve")

        local view = battle_view.inspect(outgoing)
        assert(view and view.hp == 7 and containsState(view.states, "poison"),
            "BattleView did not advance resolved battler facts")
        assert(view.mp == 11 and view.party[1] == incoming,
            "BattleView did not advance resolved MP/roster facts")
        assert(battle_view.sessionFor(sess).party[1] == incoming,
            "battle render session did not expose projected roster")
        battle_view.clear()
    end

    -- Permadeath authority: the public engine interpreter must return with the
    -- reaped slot already final. The reap event carries the roster snapshot the
    -- UI may reveal later, but presentation is not required to make death true.
    do
        loader.init()
        local sess = sessionModule.GameSession.new(loader)
        local doomed = sess:recruitActor(3, 5) -- Skeleton
        assert(doomed and sess.party[1] == doomed,
            "test setup failed to recruit doomed creature")
        doomed.hp = 0
        doomed:addState("dead")

        local ctx = { session = sess, events = {} }
        interpreter.runImmediate({ { cmd = "REAP_FALLEN" } }, ctx)

        local reap
        for _, ev in ipairs(ctx.events) do
            if ev.type == "reap" then reap = ev break end
        end
        assert(reap ~= nil, "REAP_FALLEN emitted no reap event")
        assert(sess.party[1] == nil,
            "REAP_FALLEN returned before authoritative party removal")
        assert(reap.resolved and reap.resolved.party
            and reap.resolved.party[1] == nil,
            "reap event did not publish the resolved roster")
    end

    battle_view.clear()
    print("[PASS] Battle presentation authority boundary")
    return true
end

return M
