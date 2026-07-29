local loader = require("data.loader")
local session = require("engine.session")
local interpreter = require("engine.interpreter")
local savegame = require("engine.savegame")

local function assertEq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local sess = session.GameSession.new(loader)
local ctx = { session = sess, loader = loader, party = sess.party, v = {}, events = {} }

interpreter.runImmediate({ { cmd = "LIST_UNLOCKED_LORE" } }, ctx)
assertEq(ctx.v.loreCount, 2, "baseline lore count")
assertEq(ctx.v.loreRows[1].id, "second_rite", "authored lore order")

interpreter.runImmediate({ { cmd = "UNLOCK_LORE", loreId = "old_gate" } }, ctx)
interpreter.runImmediate({ { cmd = "LIST_UNLOCKED_LORE" } }, ctx)
assertEq(ctx.v.loreCount, 3, "unlocked lore count")
assertEq(ctx.v.loreRows[3].id, "old_gate", "new lore appears in authored order")

local restored = savegame.deserialize(savegame.serialize(sess, loader, "map"), loader)
assertEq(restored.unlockedLore.old_gate, true, "lore unlock save round-trip")

print("  datalog tests passed")
