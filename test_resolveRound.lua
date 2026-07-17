local loader = require("data.loader")
loader.init()
local session = require("engine.session")
local battleSystem = require("engine.battle")

local vSession = session.GameSession.new(loader)
vSession:initializeStartingParty()

local fastEnemyData = { id = "fast_enemy", name = "Fast Enemy", level = 10, skills = {"attack"}, maxHp = 100 }
local slowEnemyData = { id = "slow_enemy", name = "Slow Enemy", level = 1, skills = {"attack"}, maxHp = 100 }

local fastEnemy = session.Battler.new(fastEnemyData, 10)
fastEnemy.hp = fastEnemy:getMaxHp(vSession)

local slowEnemy = session.Battler.new(slowEnemyData, 1)
slowEnemy.hp = slowEnemy:getMaxHp(vSession)


local vBattle = battleSystem.Battle.new(vSession, { fastEnemy, slowEnemy })

local actions = {}
actions[1] = { type = "attack", target = slowEnemy }
actions[2] = { type = "attack", target = fastEnemy }

local events = vBattle:resolveRound(actions)
for _, ev in ipairs(events) do
    if ev.type == "action" then
        print(ev.actor.name, "acts")
    end
end
