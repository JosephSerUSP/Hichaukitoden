local loader = require("data.loader")
loader.init()
local session = require("engine.session")
local battleSystem = require("engine.battle")

local mockFastEnemyData = { id = "e_fast", name = "Fast", level = 50 }
local mockSlowEnemyData = { id = "e_slow", name = "Slow", level = 1 }

local testSession = session.GameSession.new(loader)
testSession.party = {}

local fastEnemy = session.Battler.new(mockFastEnemyData, 50)
fastEnemy.hp = 100
local slowEnemy = session.Battler.new(mockSlowEnemyData, 1)
slowEnemy.hp = 100

local testBattle = battleSystem.Battle.new(testSession, { fastEnemy, slowEnemy })

-- Override getAIAction so they don't depend on actual skills from db that we can't guarantee
function testBattle:getAIAction(enemy)
    return {
        type = "attack",
        actor = enemy,
        skill = { speed = 0, effects = {} },
        target = enemy
    }
end

local testEvents = testBattle:resolveRound({})
for _, ev in ipairs(testEvents) do
    if ev.type == "action" then
        print(ev.actor.id, "acts")
    else
        print(ev.type, "happens")
    end
end
