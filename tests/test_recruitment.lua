-- Unit test for Creature Recruitment system
-- Run via Love2D or Lua test runner

package.path = package.path .. ";./?.lua;./engine/?.lua"

local sessionModule = require("engine.session")
local interpreter = require("engine.interpreter")
local config = require("engine.config")
local savegame = require("engine.savegame")
local recruitment = require("engine.recruitment")
local GameSession = sessionModule.GameSession

print("[TEST] Starting creature recruitment system tests...")

-- Mock loader for testing
local mockLoader
mockLoader = {
    actors = {
        [1] = { id = 1, name = "Pixie", level = 1, role = "Healer", recruitEvent = { type = "heal" } },
        [3] = { id = 3, name = "Skeleton", level = 1, role = "Attacker", recruitEvent = { type = "hostile" } },
        [4] = { id = 4, name = "Angel", level = 2, role = "Support", recruitEvent = { type = "gold", goldCost = 30 } },
        [12] = { id = 12, name = "Ooze", level = 1, role = "Debuffer", recruitEvent = { type = "aid", itemRequired = 1 } },
        [13] = { id = 13, name = "Bat", level = 1, role = "Attacker", recruitEvent = { type = "free" } },
        [15] = { id = 15, name = "CustomCreature", level = 1, recruitEvent = { commands = { { cmd = "TEXT", text = "Custom event!" } } } },
        [16] = { id = 16, name = "ArrayCreature", level = 1, recruitEvent = { { cmd = "TEXT", text = "Direct array event!" } } },
        [17] = { id = 17, name = "ScriptIdCreature", level = 1, recruitEvent = 4 },
    },
    commonEvents = {
        ["4"] = { id = "4", name = "Recruit Pixie", commands = { { cmd = "TEXT", text = "Common event recruit!" } } }
    },
    items = {
        [1] = { id = 1, name = "Potion", type = "item" }
    },
    getActor = function(a, b)
        local id = (type(a) == "number" or type(a) == "string") and a or b
        return mockLoader.actors[id]
    end,
    getActorByRole = function(role) return { id = 99, name = "Summoner", role = role } end,
    getItem = function(a, b)
        local id = b ~= nil and b or a
        return mockLoader.items[id]
    end,
    getTerm = function(self, key, default) return default end,
    formatTerm = function(self, key, default, p1) return (default:gsub("{0}", tostring(p1))) end,
    system = { combat = { encounterChance = 0.1 } }
}

-- Test 1: recruit events are authored events, not Lua-generated ones.
-- engine/recruitment.lua used to expand six preset types into command lists at
-- runtime, with the dialogue built by string concatenation in the engine. The
-- presets were baked into data; these assertions are over what is authored.
local realLoader = require("data.loader")
realLoader.init()

local recruitables, withBattle = 0, 0
for _, actorData in ipairs(realLoader.actors) do
    local ev = actorData.recruitEvent
    if ev ~= nil then
        recruitables = recruitables + 1
        assert(type(ev) == "table" and #ev > 0 and ev[1].cmd,
            "actor " .. tostring(actorData.id) .. " recruitEvent must be a command list")

        -- It has to actually be able to recruit, somewhere down some branch.
        local found = false
        local function scan(cmds)
            for _, c in ipairs(cmds or {}) do
                if c.cmd == "OPEN_RECRUIT" or c.cmd == "RECRUIT" then found = true end
                for _, opt in ipairs(c.options or {}) do scan(opt.commands) end
                scan(c.commands); scan(c.onVictory); scan(c.onDefeat)
                scan(c["then"]); scan(c["else"]); scan(c.elseCommands)
            end
        end
        scan(ev)
        assert(found, "actor " .. tostring(actorData.id)
            .. " recruitEvent never reaches OPEN_RECRUIT or RECRUIT")

        -- A challenge recruit fights the creature itself and continues on
        -- victory. Before BATTLE could carry a troop or resume, it fought the
        -- map's random encounter and the event ended at the fight.
        local function scanBattles(cmds)
            for _, c in ipairs(cmds or {}) do
                if c.cmd == "BATTLE" then
                    withBattle = withBattle + 1
                    assert(type(c.troop) == "string" and realLoader.troops[c.troop],
                        "a recruit battle must name a real troop, not roll the map table")
                    assert(c.onVictory and #c.onVictory > 0,
                        "a recruit battle must continue on victory")
                end
                for _, opt in ipairs(c.options or {}) do scanBattles(opt.commands) end
                scanBattles(c.commands); scanBattles(c.onVictory); scanBattles(c.onDefeat)
            end
        end
        scanBattles(ev)
    end
end
assert(recruitables > 0, "no actor authors a recruit event")
assert(withBattle > 0, "no recruit event challenges the player to a battle")
print("  [PASS] " .. recruitables .. " authored recruit events, "
    .. withBattle .. " of them fighting a named troop and resuming on victory")

-- Test 2: GameSession:recruitActor party vs reserve filling
local sess = GameSession.new(mockLoader)
assert(#sess.party == 0, "Party should start empty")

-- Recruit up to 4 members into active party
for i = 1, 4 do
    local battler, slotType = sess:recruitActor(13, 1)
    assert(battler ~= nil, "Failed to recruit Bat #" .. i)
    assert(slotType == "party", "Bat #" .. i .. " should be placed in party")
end
assert(#sess.party == 4, "Party should have 4 members")

-- 5th member should be routed to reserve roster
local battler5, slotType5 = sess:recruitActor(13, 1)
assert(battler5 ~= nil, "Failed to recruit 5th Bat")
assert(slotType5 == "reserve", "5th Bat should be placed in reserve")
assert(sess.reserve[1] ~= nil, "Reserve slot 1 should hold 5th Bat")
print("  [PASS] GameSession:recruitActor places members correctly in party and reserve")

-- The expedition roster is deliberately small. A ninth creature must not
-- silently expand it or overwrite an existing instance.
assert(config.MAX_RESERVE_SIZE == 4, "Expedition reserve must contain four slots")
local capSess = GameSession.new(mockLoader)
for i = 1, 4 + config.MAX_RESERVE_SIZE do
    local b, where = capSess:recruitActor(13, 1)
    assert(b and where == (i <= 4 and "party" or "reserve"),
        "Expedition roster slot " .. i .. " did not fill")
end
local overflow, overflowWhere = capSess:recruitActor(13, 1)
assert(overflow == nil and overflowWhere == "Full",
    "Recruitment beyond four party and four reserve slots must fail loudly")
print("  [PASS] Expedition reserve is capped at four creatures")

-- Town storage is a separate 99-slot collection and survives save/load.
assert(config.MAX_STORAGE_SIZE == 99, "Town storage must contain 99 slots")
local storageSess = GameSession.new(mockLoader)
for i = 1, 8 do assert(storageSess:recruitActor(13, 1)) end
local stored = storageSess.party[4]
storageSess.party[4] = nil
local storageSlot = assert(storageSess:storeCreature(stored))
assert(storageSlot == 1 and storageSess.storage[1] == stored,
    "storeCreature must use the first open town-storage slot")
local payload = savegame.serialize(storageSess, mockLoader, "map")
local restored = savegame.deserialize(payload, mockLoader)
assert(restored.storage[1] and restored.storage[1].id == stored.id,
    "Town storage did not survive save/load")
local withdrawn, reserveSlot = restored:withdrawCreature(1)
assert(withdrawn == nil and reserveSlot == "Expedition reserve full"
        and restored.storage[1] ~= nil,
    "A full expedition reserve must refuse storage withdrawal")
restored.reserve[4] = nil
withdrawn, reserveSlot = restored:withdrawCreature(1)
assert(withdrawn and reserveSlot == 4 and restored.storage[1] == nil,
    "Storage withdrawal must move the same instance into an open reserve slot")
print("  [PASS] Town storage is separate, capped at 99, and save-persistent")

local dismissed, dismissedSlot = restored:dismissToStorage(true, 1)
assert(dismissed and dismissedSlot == 1 and restored.reserve[1] == nil,
    "Dismissing a reserve creature must send the same instance to storage")
for i = 2, 4 do restored.party[i] = nil end
local refused, refusedReason = restored:dismissToStorage(false, 1)
assert(refused == nil and refusedReason == "Cannot dismiss the last active creature",
    "Dismiss must never leave the active party empty")
print("  [PASS] Dungeon dismissal transfers instances and protects the last active creature")

-- Test 3: Interpreter command handlers (OPEN_RECRUIT, ERASE_EVENT, CHANGE_ITEM)
sess.inventory[1] = 5
local ctx = { session = sess, events = {} }

interpreter.runImmediate({
    { cmd = "CHANGE_ITEM", item = 1, count = -2 },
    { cmd = "OPEN_RECRUIT", actorId = 4, level = 2 }
}, ctx)

assert(sess.inventory[1] == 3, "CHANGE_ITEM did not deduct items correctly")
assert(sess.reserve[2] ~= nil and sess.reserve[2].actorData.id == 4, "OPEN_RECRUIT did not add Angel to reserve")
print("  [PASS] Interpreter commands CHANGE_ITEM and OPEN_RECRUIT executed cleanly")

-- Test 4: ERASE_EVENT removes map event
sess.currentMapData = {
    events = {
        { id = "recruit_1", type = "recruit" },
        { id = "stairs_1", type = "stairs" }
    }
}
ctx.eventId = "recruit_1"
interpreter.runImmediate({
    { cmd = "ERASE_EVENT" }
}, ctx)

assert(#sess.currentMapData.events == 1, "ERASE_EVENT did not remove target event")
assert(sess.currentMapData.events[1].id == "stairs_1", "Wrong event was erased")
print("  [PASS] Interpreter command ERASE_EVENT erased target map event")

-- Test 5: Interpreter command handlers (GAIN_GOLD with amount, RECOVER_PARTY)
sess.gold = 50
interpreter.runImmediate({
    { cmd = "GAIN_GOLD", amount = -30 }
}, ctx)
assert(sess.gold == 20, "GAIN_GOLD (negative) failed to deduct gold correctly. Got: " .. tostring(sess.gold))

interpreter.runImmediate({
    { cmd = "GAIN_GOLD", amount = 15 }
}, ctx)
assert(sess.gold == 35, "GAIN_GOLD (positive) failed to add gold correctly. Got: " .. tostring(sess.gold))

interpreter.runImmediate({
    { cmd = "RECOVER_PARTY" }
}, ctx)
for _, member in ipairs(sess.party) do
    assert(member.hp == member:getMaxHp(sess), "RECOVER_PARTY failed to restore hp for party member")
end
print("  [PASS] Interpreter commands GAIN_GOLD and RECOVER_PARTY executed cleanly")

-- Test 6: conditions.evalPrefixed handles gold prefix
local conditions = require("engine.conditions")
local matched, result = conditions.evalPrefixed("gold:30", sess)
assert(matched == true and result == true, "gold:30 condition evaluation failed when gold is 35")

local matched2, result2 = conditions.evalPrefixed("gold:100", sess)
assert(matched2 == true and result2 == false, "gold:100 condition evaluation failed when gold is 35")
print("  [PASS] Condition evaluator correctly handles gold: prefix")

-- Test 7: End-to-end recruitment execution of compiled gold recruit option script
sess.gold = 30
sess.activeEvent = { id = "recruit_4", actorId = 4 }
sess.currentMapData = {
    events = {
        { id = "recruit_4", type = "recruit" }
    }
}
-- The compiled option script mixes interactive commands (TEXT) with
-- side-effect commands; at runtime the dialogue host renders the former and
-- runs the latter through runImmediate. Mirror that split here.
-- Straight off the authored event now, rather than off a script the engine
-- built a moment earlier -- so this exercises what actually ships.
local angelScript = realLoader.getActor(4).recruitEvent
local angelOptScript = {}
for _, c in ipairs(angelScript[2].options[1].commands) do
    if not interpreter.INTERACTIVE_IDS[c.cmd] then
        table.insert(angelOptScript, c)
    end
end
interpreter.runImmediate(angelOptScript, { session = sess, events = {} })
assert(sess.gold == 0, "Recruiting Angel did not deduct 30 gold")
assert(#sess.currentMapData.events == 0, "Recruiting Angel did not erase the map event")
print("  [PASS] End-to-end gold recruitment script executed successfully")


-- Test 8: canonical transaction costs are deferred and charged exactly once.
local itemSess = GameSession.new(mockLoader)
itemSess.flags.recruit_onboarding_shown = true
itemSess.inventory[1] = 3
local itemNode = recruitment.getOrCreateRecruitNode(itemSess, mockLoader,
    "test:item-cost", 13, 1, {
        requirement = { type = "item", itemRequired = 1, amount = 2 }
    })
local itemCtx = {
    session = itemSess, loader = mockLoader, events = {},
    v = { sourceKey = "test:item-cost", mode = 1, slotIdx = 1 },
}
recruitment.onSelectRecruitScene(itemCtx)
assert(itemNode.requirementSatisfied and itemCtx.v.mode == 2,
    "Affordable item requirement did not advance to placement")
assert(itemSess.inventory[1] == 3,
    "Item requirement was consumed before final transaction commit")
recruitment.onSelectRecruitScene(itemCtx)
assert(itemCtx.v.mode == 3, "Recruitment did not enter confirmation mode")
recruitment.onSelectRecruitScene(itemCtx)
assert(itemSess.inventory[1] == 1, "Item recruitment cost was not charged exactly once")
assert(itemSess.party[1] and itemSess.party[1].instanceId == itemNode.recruitedInstanceId,
    "Committed item recruit did not place its persistent candidate")
print("  [PASS] Item recruitment validates first and charges exactly once")

local goldSess = GameSession.new(mockLoader)
goldSess.flags.recruit_onboarding_shown = true
goldSess.gold = 50
local goldNode = recruitment.getOrCreateRecruitNode(goldSess, mockLoader,
    "test:gold-cost", 13, 1, {
        requirement = { type = "gold", goldCost = 30 }
    })
local goldCtx = {
    session = goldSess, loader = mockLoader, events = {},
    v = { sourceKey = "test:gold-cost", mode = 1, slotIdx = 1 },
}
recruitment.onSelectRecruitScene(goldCtx)
assert(goldNode.requirementSatisfied and goldSess.gold == 50,
    "Gold requirement must not charge before confirmation")
recruitment.onSelectRecruitScene(goldCtx)
recruitment.onSelectRecruitScene(goldCtx)
assert(goldSess.gold == 20, "Gold recruitment cost was not charged exactly once")
print("  [PASS] Gold recruitment validates first and charges exactly once")

-- Deprecated quantity aliases are rejected instead of silently disagreeing.
local badAmountOk, badAmountErr = pcall(function()
    recruitment.getOrCreateRecruitNode(GameSession.new(mockLoader), mockLoader,
        "test:obsolete-amount", 13, 1, {
            requirement = { type = "item", itemRequired = 1, amountRequired = 2 }
        })
end)
assert(not badAmountOk and tostring(badAmountErr):find("use 'amount'", 1, true),
    "Obsolete item quantity fields must fail loud")
print("  [PASS] Item requirement has one canonical quantity field")

-- Test 9: failed or malformed placement is lossless and cannot overwrite.
local blockedSess = GameSession.new(mockLoader)
blockedSess.inventory[1] = 2
local existing = assert(blockedSess:recruitActor(13, 1))
local blockedNode = recruitment.getOrCreateRecruitNode(blockedSess, mockLoader,
    "test:blocked-placement", 13, 1, {
        requirement = { type = "item", itemRequired = 1, amount = 2 }
    })
blockedNode.requirementSatisfied = true
local blockedPlan = recruitment.buildCommitPlan(blockedSess, blockedNode,
    { isReserve = false, slot = 1 })
local blockedOk, blockedErr = recruitment.applyCommitPlan(blockedSess, blockedPlan)
assert(not blockedOk and blockedErr == "Destination slot is occupied",
    "Occupied destination without an explicit move must fail")
assert(blockedSess.inventory[1] == 2 and blockedSess.party[1] == existing,
    "Failed placement charged a cost or overwrote its occupant")
assert(not blockedNode.completed and blockedNode.candidate,
    "Failed placement destroyed the persistent candidate")
print("  [PASS] Malformed placement cannot overwrite or charge")

-- Active displacement into reserve keeps the exact existing instance.
local displacedPlan = recruitment.buildCommitPlan(blockedSess, blockedNode,
    { isReserve = false, slot = 1, substituteSlot = 1 })
local displacedOk, displacedErr = recruitment.applyCommitPlan(blockedSess, displacedPlan)
assert(displacedOk, displacedErr)
assert(blockedSess.reserve[1] == existing,
    "Occupied active creature was not moved intact to reserve")
assert(blockedSess.inventory[1] == nil,
    "Successful displacement did not charge the item cost exactly once")
print("  [PASS] Active-slot substitution is atomic")

-- Full town storage rejects a reserve replacement without charging.
local fullSess = GameSession.new(mockLoader)
for i = 1, config.MAX_PARTY_SIZE + config.MAX_RESERVE_SIZE do
    assert(fullSess:recruitActor(13, 1))
end
for i = 1, config.MAX_STORAGE_SIZE do
    fullSess.storage[i] = fullSess:createPersistentBattler(mockLoader.actors[13], 1)
end
fullSess.gold = 99
local fullNode = recruitment.getOrCreateRecruitNode(fullSess, mockLoader,
    "test:full-storage", 13, 1, {
        requirement = { type = "gold", goldCost = 40 }
    })
fullNode.requirementSatisfied = true
local fullPlan = recruitment.buildCommitPlan(fullSess, fullNode, {
    isReserve = true, slot = 1, dismissIndex = 1, dismissIsReserve = true,
})
local fullOk, fullErr = recruitment.applyCommitPlan(fullSess, fullPlan)
assert(not fullOk and fullErr == "Town storage is full!", "Full storage must reject replacement")
assert(fullSess.gold == 99 and not fullNode.completed and fullNode.candidate,
    "Full-storage failure charged or destroyed candidate state")
print("  [PASS] Full expedition and storage failure is lossless")

-- Test 10: challenge resume compiles into a new OPEN_RECRUIT continuation and
-- reuses the same persistent candidate instead of transient host state.
local compileSess = GameSession.new(mockLoader)
local challengeGraph = interpreter.runInteractive({
    {
        cmd = "OPEN_RECRUIT", actorId = 13, sourceKey = "test:challenge",
        requirement = { type = "challenge" },
        onRequirement = {
            {
                cmd = "BATTLE", troop = "test_troop",
                onVictory = { { cmd = "RESUME_RECRUIT", result = "requirement_satisfied" } },
                onDefeat = {},
            },
        },
        onCommitted = { { cmd = "TEXT", text = "joined" } },
        onDeclined = { { cmd = "TEXT", text = "declined" } },
    },
}, { session = compileSess, loader = mockLoader, recoverParty = function() end })
local resumeAction
for _, graphNode in pairs(challengeGraph.nodes) do
    if graphNode.action == "OPEN_RECRUIT"
        and graphNode.requirement and graphNode.requirement.type == "resume" then
        resumeAction = graphNode
        break
    end
end
assert(resumeAction, "RESUME_RECRUIT did not compile into a host OPEN_RECRUIT continuation")
assert(resumeAction.sourceKey == "test:challenge" and resumeAction.committedNode,
    "Compiled resume lost source identity or outcome continuation")

local challengeNode = recruitment.getOrCreateRecruitNode(compileSess, mockLoader,
    "test:challenge", 13, 1, { requirement = { type = "challenge" } })
local challengeInstance = challengeNode.candidate.instanceId
local resumedNode = recruitment.getOrCreateRecruitNode(compileSess, mockLoader,
    resumeAction.sourceKey, resumeAction.actorId, resumeAction.level,
    { requirement = resumeAction.requirement })
assert(resumedNode == challengeNode and resumedNode.requirementSatisfied,
    "Challenge resume did not satisfy the original persistent node")
assert(resumedNode.candidate.instanceId == challengeInstance,
    "Challenge resume rerolled the candidate instance")
print("  [PASS] Challenge resume preserves source and candidate identity")

local strayResumeOk, strayResumeErr = pcall(function()
    interpreter.runInteractive({ { cmd = "RESUME_RECRUIT" } }, {
        session = compileSess, loader = mockLoader, recoverParty = function() end,
    })
end)
assert(not strayResumeOk and tostring(strayResumeErr):find("must be nested", 1, true),
    "Stray RESUME_RECRUIT must fail during compilation")
print("  [PASS] Stray challenge resume fails loud")

-- Test 11: unresolved and completed recruit nodes round-trip without duplication.
local saveSess = GameSession.new(mockLoader)
local saveNode = recruitment.getOrCreateRecruitNode(saveSess, mockLoader,
    "test:save-node", 13, 1, { requirement = { type = "free" } })
local savedInstance = saveNode.candidate.instanceId
local savePayload = savegame.serialize(saveSess, mockLoader, "map")
local loadedSaveSess = savegame.deserialize(savePayload, mockLoader)
local loadedNode = loadedSaveSess.recruitNodes["test:save-node"]
assert(loadedNode and loadedNode.candidate
        and loadedNode.candidate.instanceId == savedInstance,
    "Unresolved recruit candidate identity did not survive save/load")
local commitOk, commitErr = recruitment.commitRecruitNode(loadedSaveSess, mockLoader,
    "test:save-node", { isReserve = false, slot = 1 })
assert(commitOk, commitErr)
local secondOk = recruitment.commitRecruitNode(loadedSaveSess, mockLoader,
    "test:save-node", { isReserve = false, slot = 2 })
assert(not secondOk, "Completed recruit node committed twice")
local occurrences = 0
for _, member in pairs(loadedSaveSess.party) do
    if member.instanceId == savedInstance then occurrences = occurrences + 1 end
end
for _, member in pairs(loadedSaveSess.reserve) do
    if member.instanceId == savedInstance then occurrences = occurrences + 1 end
end
assert(occurrences == 1, "Completed recruit candidate was duplicated")
local completedPayload = savegame.serialize(loadedSaveSess, mockLoader, "map")
local completedSess = savegame.deserialize(completedPayload, mockLoader)
local completedNode = completedSess.recruitNodes["test:save-node"]
assert(completedNode and completedNode.completed and not completedNode.candidate
        and completedNode.recruitedInstanceId == savedInstance,
    "Completed recruit node did not survive save/load")
print("  [PASS] Persistent recruit nodes save, complete once, and do not duplicate")

print("[TEST] All Creature Recruitment tests passed successfully!")

