-- The item-atlas vocabulary: use occasion, percentage recovery, permanent
-- Summoner Max MP, ITEM_EFFECT_RATE, and Item Creation ingredient exclusion.
--
-- None of it is visible to the golden gates: no fixture in goldenBattles.json
-- eats a percentage food or wears a Pharmacology accessory, and the ingredient
-- exclusion only shows up once content authors it. Unit tests own the behavior
-- instead, the same arrangement element affinity has.
package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local sessionModule = require("engine.session")
local effects = require("engine.effects")
local usability = require("engine.usability")
local craft = require("engine.craft")
local traits = require("engine.traits")
local interpreter = require("engine.interpreter")
local config = require("engine.config")

print("[TEST] Starting item vocabulary tests...")

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

local function freshBattler()
    local sess = sessionModule.GameSession.new(loader)
    local b = sess:recruitActor(3, 5) -- Skeleton, level 5
    return sess, b
end

-- The item context every real item-use site passes. Effects applied WITHOUT it
-- are skill effects, which ITEM_EFFECT_RATE deliberately does not touch.
local ITEM = { isItem = true }

------------------------------------------------------------------ occasion --

-- Every scope the registry enumerates must be one usability actually
-- implements: a scope the engine does not branch on reads as a restriction and
-- behaves as none.
do
    local scopes = (loader.engine and loader.engine.itemScopes) or {}
    check(#scopes > 0, "engine.json enumerates item scopes")

    local function usableIn(scope, inBattle)
        local item = { type = "consumable", scope = scope, effects = {} }
        local ok = usability.canUseItem(item, nil, { isBattle = inBattle })
        return ok
    end

    check(usableIn("always", true) and usableIn("always", false),
        "scope 'always' is usable in battle and in the field")
    check(usableIn("battle", true) and not usableIn("battle", false),
        "scope 'battle' is refused in the field")
    check(not usableIn("field", true) and usableIn("field", false),
        "scope 'field' is refused in battle")
    check(not usableIn("none", true) and not usableIn("none", false),
        "scope 'none' is never usable")

    local implemented = { always = true, battle = true, field = true, none = true }
    local allKnown = true
    for _, s in ipairs(scopes) do
        if not implemented[s.scope] then allKnown = false end
    end
    check(allKnown, "every registered scope has an implemented branch")
end

--------------------------------------------------------- roster capacities --

-- Item usability must obey the same authored structural limits as recruitment
-- itself. Keeping literal 4/16 values here can make a recruit item appear
-- usable even though the canonical roster transaction has no destination.
do
    local previousParty = config.MAX_PARTY_SIZE
    local previousReserve = config.MAX_RESERVE_SIZE
    config.MAX_PARTY_SIZE = 2
    config.MAX_RESERVE_SIZE = 3

    local sess = {
        party = { {}, {} },
        reserve = { {}, {}, {} },
    }
    local egg = {
        type = "consumable",
        target = "none",
        effects = { { type = "recruit_egg" } },
    }

    local ok, reason = usability.canUseItem(egg, nil, { session = sess, isBattle = false })
    check(not ok and reason == "Party and reserve are full",
        "recruit item refuses use at the canonical party/reserve limits")

    sess.reserve[3] = nil
    ok = usability.canUseItem(egg, nil, { session = sess, isBattle = false })
    check(ok, "recruit item becomes usable when a canonical reserve slot is free")

    config.MAX_PARTY_SIZE = previousParty
    config.MAX_RESERVE_SIZE = previousReserve
end

-------------------------------------------------------------- percentages --

do
    local sess, b = freshBattler()
    local maxHp = b:getMaxHp(sess)
    b.hp = 1

    effects.apply({ type = "hp", percent = 0.5 }, b, b, sess, ITEM)
    check(b.hp == 1 + math.floor(maxHp * 0.5),
        "a percentage HP restore heals a share of the recipient's own Max HP")

    b.hp = 1
    effects.apply({ type = "hp", value = 10, percent = 0.25 }, b, b, sess, ITEM)
    check(b.hp == 1 + math.floor(10 + maxHp * 0.25),
        "flat and percentage HP compose in one effect")

    b.hp = 1
    effects.apply({ type = "hp", value = 7 }, b, b, sess, ITEM)
    check(b.hp == 8, "a flat-only HP restore is unchanged by the percentage param")

    b.hp = maxHp
    effects.apply({ type = "hp", percent = 1.0 }, b, b, sess, ITEM)
    check(b.hp == maxHp, "HP restore never overheals")
end

do
    local sess = sessionModule.GameSession.new(loader)
    sess.maxMp = 3000
    sess.mp = 0
    effects.apply({ type = "mp_heal", percent = 0.2 }, nil, nil, sess, ITEM)
    check(sess.mp == 600, "a percentage MP restore is a share of Max MP")

    sess.mp = 0
    effects.apply({ type = "mp_heal", value = 150, percent = 0.05 }, nil, nil, sess, ITEM)
    check(sess.mp == 300, "flat and percentage MP compose in one effect")

    sess.mp = sess.maxMp - 10
    effects.apply({ type = "mp_heal", value = 9999 }, nil, nil, sess, ITEM)
    check(sess.mp == sess.maxMp, "MP restore never overfills the pool")
end

------------------------------------------------------- permanent Max MP ----

do
    local sess = sessionModule.GameSession.new(loader)
    local cap = ((loader.system and loader.system.summoner) or {}).maxMpCap or 9999
    sess.maxMp = 3000
    sess.mp = 500

    effects.apply({ type = "max_mp_plus", value = 100 }, nil, nil, sess, ITEM)
    check(sess.maxMp == 3100, "max_mp_plus permanently raises Max MP")
    check(sess.mp == 600, "max_mp_plus restores what it adds")

    sess.maxMp = cap - 40
    sess.mp = 0
    effects.apply({ type = "max_mp_plus", value = 500 }, nil, nil, sess, ITEM)
    check(sess.maxMp == cap, "max_mp_plus is clamped to the Max MP cap")
    check(sess.mp == 40, "only the applied share is restored at the cap")

    local item = { type = "consumable", target = "none",
        effects = { { type = "max_mp_plus", value = 100 } } }
    local ok = usability.canUseItem(item, nil, { session = sess, isBattle = false })
    check(not ok, "a Max MP item at the cap is refused rather than wasted")
end

-- Max MP must survive the round trip, or the permanent gain quietly is not one.
do
    local savegame = require("engine.savegame")
    local sess = sessionModule.GameSession.new(loader)
    sess.maxMp = 3210
    sess.mp = 77
    local data = savegame.serialize(sess, loader, "map")
    check(data.maxMp == 3210, "a raised Max MP is written to the save")
    local restored = savegame.deserialize(data, loader)
    check(restored and restored.maxMp == 3210,
        "a raised Max MP survives the save round trip")
end

--------------------------------------------------- ITEM_EFFECT_RATE --------

do
    local sess, b = freshBattler()
    -- Headroom: a level-5 test creature's Max HP is small enough that the
    -- overheal cap, not the rate, would decide the result.
    b.paramPlus = b.paramPlus or {}
    b.paramPlus.maxHp = 200
    local maxHp = b:getMaxHp(sess)

    b.hp = 1
    effects.apply({ type = "hp", value = 20 }, b, b, sess, ITEM)
    local plain = b.hp - 1

    -- Carry the trait on a private actorData copy. loader.getActor hands back
    -- the one table every holder of that species sees, so appending to it here
    -- would give every Skeleton in every later test the trait.
    local privateData = {}
    for k, v in pairs(b.actorData) do privateData[k] = v end
    privateData.traits = { { code = "ITEM_EFFECT_RATE", value = 0.5 } }
    b.actorData = privateData

    b.hp = 1
    effects.apply({ type = "hp", value = 20 }, b, b, sess, ITEM)
    local boosted = b.hp - 1
    check(boosted == math.floor(plain * 1.5),
        "ITEM_EFFECT_RATE scales an item's HP restore for its recipient")

    b.hp = 1
    effects.apply({ type = "hp_heal", formula = "20" }, b, b, sess, ITEM)
    check(b.hp - 1 == 30, "ITEM_EFFECT_RATE scales formula heals from items too")

    -- Same effect, no item context: this is a skill, and a constitution for
    -- consumables must not amplify spells.
    b.hp = 1
    effects.apply({ type = "hp_heal", formula = "20" }, b, b, sess)
    check(b.hp - 1 == 20, "ITEM_EFFECT_RATE leaves skill effects alone")

    b.hp = 1
    effects.apply({ type = "param_plus", param = "atk", value = 2 }, b, b, sess, ITEM)
    check((b.paramPlus.atk or 0) == 2,
        "ITEM_EFFECT_RATE does not inflate permanent parameter gains")
    check(maxHp == b:getMaxHp(sess), "the rate did not disturb Max HP")
end

--------------------------------------------- ingredient exclusion ----------

do
    check(craft.isIngredient({ id = 1, meta = {} }),
        "an ordinary item is a valid ingredient")
    check(craft.isIngredient({ id = 1 }),
        "an item with no meta at all is a valid ingredient")
    check(not craft.isIngredient({ id = 1, meta = { craftIngredient = false } }),
        "meta.craftIngredient false excludes an item from ingredient selection")

    -- The two exclusions are independent: this is exactly the monster-remains
    -- policy (ingredient, never output) and it must remain expressible.
    local remains = { id = 1, cost = 10, meta = { craftable = false } }
    check(craft.isIngredient(remains),
        "an item excluded from outputs is still a valid ingredient")

    local pool = craft.pool("alchemy", loader)
    local anyExcluded = false
    for _, item in ipairs(pool) do
        if (item.meta or {}).craftable == false then anyExcluded = true end
    end
    check(not anyExcluded, "output exclusion still keeps items out of the pool")
end

--------------------------------------------------- common_event requests ---

-- The Forbidden Lamp shape: an item that opens a scripted encounter.
-- CALL_COMMON_EVENT is an interactive command that compiles to a dialogue
-- node, and immediate mode refuses it outright -- so this effect cannot run the
-- event, only ask the host to. These tests pin that contract from both ends.
do
    local interpreter = require("engine.interpreter")
    local sess = sessionModule.GameSession.new(loader)

    -- Pick any authored common event, so the test does not invent content.
    local realId
    for id in pairs(loader.commonEvents or {}) do realId = realId or id end
    check(realId ~= nil, "the campaign has a common event to call")

    local evs = effects.apply({ type = "common_event", value = realId }, nil, nil, sess, ITEM)
    local request
    for _, ev in ipairs(evs) do
        if ev.type == "run_common_event" then request = ev end
    end
    check(request ~= nil and tostring(request.id) == tostring(realId),
        "a common_event effect raises a request naming the event")

    -- An unknown id says so rather than raising a request the host would
    -- silently fail to honour.
    local bad = effects.apply({ type = "common_event", value = "no_such_event" }, nil, nil, sess, ITEM)
    local raised = false
    for _, ev in ipairs(bad) do
        if ev.type == "run_common_event" then raised = true end
    end
    check(not raised, "an unknown common event raises no request")

    -- Unbound (validator, golden harness, any headless run) the request is
    -- simply unclaimed -- it must not error, or every headless path breaks the
    -- moment an item like this is authored.
    interpreter.bindPresentation({})
    check(interpreter.startCommonEvent(realId) == false,
        "an unbound host declines the request instead of failing")

    -- Bound, the host is asked exactly once with the id it was given.
    local seen = {}
    interpreter.bindPresentation({
        runCommonEvent = function(id) table.insert(seen, id) return true end
    })
    check(interpreter.startCommonEvent(realId) == true and #seen == 1
        and tostring(seen[1]) == tostring(realId),
        "a bound host is handed the event id to start")
    interpreter.bindPresentation({})
end

------------------------------------------------ party meals and shared MP --

do
    local sess = sessionModule.GameSession.new(loader)
    sess.party = {}
    local a = sess:recruitActor(3, 4)
    local b = sess:recruitActor(10, 4)
    a.hp = 1
    b.hp = 1
    sess.mp = sess.maxMp - 1000
    sess.inventory = {}
    sess:addItem(174, 1) -- Moonfish Moqueca: party HP + shared MP
    local before = sess.mp
    interpreter.runImmediate({
        { cmd = "USE_ITEM", itemIndex = "1", target = "0" }
    }, {
        session = sess, loader = loader, party = sess.party,
        events = {}, v = { tab = 1 }
    })
    check(sess.mp - before == 220,
        "a party meal restores shared Summoner MP exactly once")
    check(a.hp > 1 and b.hp > 1,
        "the same party meal applies creature-targeted HP recovery to everyone")
end

------------------------------------------------ Favorite Food and Savor --

do
    local sess, b = freshBattler()
    local food = {
        id = 9876, name = "Test Curry", type = "consumable", meal = true,
        savor = { battles = 3, traits = { { code = "PARAM_PLUS", dataId = "atk", value = 4 } } }
    }
    b.favoriteFood = food.id
    b.favoriteFoodFound = false
    local evs = effects.finishItemUse(food, nil, { b }, sess)
    check(b.favoriteFoodFound and #evs >= 2, "a creature discovers its exact Favorite Food")
    check(b.savor and b.savor.battlesRemaining == 3, "Favorite Food starts its authored Savor")
    check(traits.getParam(b, "atk", sess) >= b.actorData.baseParams.atk + 4,
        "Savor traits participate in the ordinary trait pipeline")

    effects.finishItemUse(food, nil, { b }, sess)
    check(b.savor.battlesRemaining == 3, "feeding during Savor does not refresh its cooldown")
    for _ = 1, 3 do
        interpreter.runImmediate({ { cmd = "TICK_SAVOR", target = "target" } },
            { session = sess, loader = loader, target = b, events = {}, v = {} })
    end
    check(b.savor == nil, "Savor expires after its authored number of victories")
end

print(("=== Item Vocabulary Tests Completed: %d passed, %d failed ==="):format(passed, failed))
if failed > 0 then require("tests.fail_fast")("item vocabulary tests failed", failed) end
