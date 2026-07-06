local traits = require("engine.traits")

local session = {}

-- Game_Battler definition
local Battler = {}
Battler.__index = Battler

function Battler.new(actorData, level)
    local self = setmetatable({}, Battler)
    self.actorData = actorData
    self.id = actorData.id
    self.name = actorData.name
    self.level = level or actorData.level or 1
    self.exp = 0
    self.passives = {}
    if actorData.passives then
        for _, p in ipairs(actorData.passives) do
            table.insert(self.passives, p)
        end
    end
    self.skills = {}
    if actorData.skills then
        for _, s in ipairs(actorData.skills) do
            table.insert(self.skills, s)
        end
    end
    self.equipment = { nil, nil, nil }
    self.states = {}
    self.hp = 10 -- placeholder, will update to maxHp
    self.paramPlus = { maxHp = 0, atk = 0, def = 0, mat = 0, mdf = 0 }
    
    return self
end

function Battler:getMaxHp(sess)
    return traits.getParam(self, "maxHp", sess)
end

function Battler:getAtk(sess)
    return traits.getParam(self, "atk", sess)
end

function Battler:getDef(sess)
    return traits.getParam(self, "def", sess)
end

function Battler:getMpd(sess)
    return traits.getParam(self, "mpd", sess)
end

function Battler:addState(stateId, duration)
    -- Check if state already exists
    for _, s in ipairs(self.states) do
        if s.id == stateId then
            s.duration = duration or s.maxDuration
            return
        end
    end
    table.insert(self.states, { id = stateId, duration = duration or 3, maxDuration = duration or 3 })
end

function Battler:removeState(stateId)
    for i = #self.states, 1, -1 do
        if self.states[i].id == stateId then
            table.remove(self.states, i)
            break
        end
    end
end

function Battler:isDead()
    for _, s in ipairs(self.states) do
        if s.id == "dead" then return true end
    end
    return self.hp <= 0
end

function Battler:gainExp(amount, sess)
    self.exp = self.exp + amount
    local leveledUp = false
    while true do
        local needed = self.level * 15
        if self.exp >= needed then
            self.exp = self.exp - needed
            self.level = self.level + 1
            leveledUp = true
        else
            break
        end
    end
    if leveledUp then
        self.hp = self:getMaxHp(sess)
    end
    return leveledUp
end

-- GameSession class definition
local GameSession = {}
GameSession.__index = GameSession

function GameSession.new(loader)
    local self = setmetatable({}, GameSession)
    self.loader = loader
    self.gold = 0
    self.inventory = {}
    self.flags = {}
    self.dungeonFloor = 1
    self.transitionTimer = 0
    self.transitionDir = "forward"
    
    -- Summoner details
    local startMp = loader.system and loader.system.summoner and loader.system.summoner.startMp or 820
    self.mp = startMp
    self.maxMp = startMp
    self.summoner = Battler.new(loader.getActorByRole("Summoner"), 1)
    self.summoner.hp = self.summoner:getMaxHp(self)
    
    -- Party composition: 1-4 active creatures, 5 is summoner, 6+ are reserve
    self.party = {}
    
    return self
end

function GameSession:initializeStartingParty()
    self.gold = self.loader.party.getGold()
    
    -- Setup inventory
    local startInv = self.loader.party.getInventory(self.loader.items)
    for _, item in ipairs(startInv) do
        self:addItem(item.id, 1)
    end
    self:addItem(20, 1) -- Dark Scepter Lucille
    self:addItem(6, 1) -- Bone Plate
    
    -- Setup members
    local members = self.loader.party.getMembers(self.loader.actors)
    for i, m in ipairs(members) do
        local actorData = self.loader.getActor(m.id)
        if actorData then
            local battler = Battler.new(actorData, m.level)
            battler.hp = battler:getMaxHp(self)
            table.insert(self.party, battler)
        end
    end
end

function GameSession:addItem(itemId, amount)
    amount = amount or 1
    self.inventory[itemId] = (self.inventory[itemId] or 0) + amount
    if self.inventory[itemId] <= 0 then
        self.inventory[itemId] = nil
    end
end

function GameSession:hasItem(itemId, amount)
    amount = amount or 1
    return (self.inventory[itemId] or 0) >= amount
end

function GameSession:getActiveParty()
    -- Returns list of creatures active in combat (slots 1 to 4) plus the summoner (slot 5)
    local active = {}
    for i = 1, 4 do
        if self.party[i] then
            table.insert(active, self.party[i])
        end
    end
    table.insert(active, self.summoner)
    return active
end

session.GameSession = GameSession
session.Battler = Battler

return session
