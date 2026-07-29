local traits = require("engine.traits")
local config = require("engine.config")
local growthMod = require("engine.growth")
local newgame = require("engine.newgame")

local session = {}

-- Developer mode is a property of the launch (`lovec . developer`), not of any
-- one session, so it is stamped onto every GameSession at construction rather
-- than copied from session to session. Every path that builds a session --
-- startup, RESET_SESSION, and savegame.deserialize behind LOAD_GAME and F6 --
-- therefore inherits it without a carry-over step of its own to forget.
session.developerMode = false

-- Recruited allies (never the Summoner) draw a random name from
-- actorData.names when one is defined, so starting parties don't all use
-- the same handful of default names.
local function randomAllyName(actorData)
    if not actorData then return "Unknown" end
    if actorData.role == "Summoner" then return actorData.name end
    local list = actorData.names
    if list and #list > 0 then
        return list[math.random(#list)]
    end
    return actorData.name
end

session.randomAllyName = randomAllyName

-- Game_Battler definition
local Battler = {}
Battler.__index = Battler

function Battler.new(actorData, level, growthSeed)
    local self = setmetatable({}, Battler)
    self.actorData = actorData
    self.id = actorData.id
    self.name = actorData.name
    self.meta = actorData.meta or {}
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
    -- Seeded growth (engine/growth.lua). The seed is the creature's identity as
    -- an individual: it decides how its authored band budgets break into uneven
    -- per-level packets, so two Pixies of the same level are genuinely
    -- different creatures. Assigned once, saved, and never rerolled -- reloading
    -- must not be able to re-roll a level-up.
    --
    -- Without an explicit seed the actor's own stable seed is used, so enemies,
    -- previews and the golden harness stay reproducible; session:recruitActor
    -- supplies a real per-instance seed for creatures the player keeps.
    self.growthSeed = growthSeed or growthMod.defaultSeed(actorData)
    -- Accumulated permanent growth, replayed from the seed for a creature that
    -- arrives already levelled (a generated level-20 recruit lives the same
    -- history as one that walked there).
    self.growth = growthMod.accumulate(actorData, self.growthSeed, self.level)
    -- Favorite Food belongs to the INDIVIDUAL, not the species: one exact item
    -- drawn once from the species' authored pool and kept for life, through
    -- promotion, metamorphosis and a reversible curse alike. Hidden until the
    -- creature is actually given it. Drawn from the same seed rather than
    -- math.random so it is fixed the moment the creature exists and a reload
    -- cannot fish for a better one.
    local pool = actorData.favoriteFoods
    if pool and #pool > 0 then
        self.favoriteFood = pool[(self.growthSeed % #pool) + 1]
        self.favoriteFoodFound = false
    end
    -- Creature history (proof-build brief): the numbers that turn a generated
    -- creature into "my Pixie". Counted by the RECORD_HISTORY command from
    -- flow phases, so what gets counted is data, not code. `species` keeps the
    -- creature's ORIGIN name so a promoted Titania still remembers it hatched
    -- as a Pixie.
    self.history = {
        species = actorData.name,
        expeditions = 0,
        battles = 0,
        promotions = 0,
    }
    
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

-- Falls back to the state's own authored duration (data/states.json) when the
-- inflicting effect/command omits one, rather than a fixed guess -- every
-- current skill/item/flow that inflicts a state passes an explicit duration,
-- so this only matters for a future omission, but it means that omission
-- gets the author's declared default instead of a silent 3.
local function defaultStateDuration(stateId)
    local loader = require("data.loader")
    local stateData = loader.getState(stateId)
    return (stateData and stateData.duration) or 3
end

function Battler:addState(stateId, duration)
    -- Check if state already exists
    for _, s in ipairs(self.states) do
        if s.id == stateId then
            s.duration = duration or s.maxDuration
            return
        end
    end
    local resolved = duration or defaultStateDuration(stateId)
    table.insert(self.states, { id = stateId, duration = resolved, maxDuration = resolved })
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

-- EXP the growth curve charges to go from fromLevel to toLevel (exclusive of
-- residual). Same linear curve gainExp levels through: each level l costs
-- l * growth.expPerLevel. Shared by summon pricing and sacrifice yields so
-- the EXP Bank conserves training value.
function session.expCurveCost(fromLevel, toLevel)
    local expPerLevel = (config.growth and config.growth.expPerLevel) or 15
    local total = 0
    for l = fromLevel, toLevel - 1 do
        total = total + l * expPerLevel
    end
    return total
end

-- Total training value of this battler: the curve cost from level 1 to its
-- current level plus residual exp. Sacrifice yields are computed from this,
-- so a creature summoned at a high level (bank-funded) returns that value.
function Battler:totalExp()
    return session.expCurveCost(1, self.level) + (self.exp or 0)
end

function Battler:gainExp(amount, sess)
    -- XP_RATE traits (equipment/passives) boost experience gained
    if sess then
        local bonus = traits.getRate(self, "XP_RATE", sess)
        if bonus ~= 0 then
            amount = math.floor(amount * (1 + bonus))
        end
    end
    self.exp = self.exp + amount
    local leveledUp = false
    local expPerLevel = (config.growth and config.growth.expPerLevel) or 15
    while true do
        local needed = self.level * expPerLevel
        if self.exp >= needed then
            self.exp = self.exp - needed
            self.level = self.level + 1
            -- Add this level's seeded packet to the permanent record. Additive
            -- and one-way: nothing recomputes the earlier levels, which is what
            -- lets a promotion keep them.
            local packet = growthMod.packetFor(self.actorData, self.growthSeed, self.level)
            self.growth = self.growth or {}
            for _, param in ipairs(growthMod.PARAMS) do
                self.growth[param] = (self.growth[param] or 0) + (packet[param] or 0)
            end
            leveledUp = true
        else
            break
        end
    end
    if leveledUp then
        self.hp = self:getMaxHp(sess)
        if sess then
            local transformed = require("engine.transform").applyAutomatic(sess, self)
            transformed.hp = transformed:getMaxHp(sess)
            return leveledUp, transformed
        end
    end
    return leveledUp
end

-- GameSession class definition
local GameSession = {}
GameSession.__index = GameSession

function GameSession.new(loader)
    local self = setmetatable({}, GameSession)
    self.loader = loader
    self.developerMode = session.developerMode
    self.gold = 0
    self.inventory = {}
    self.flags = {}
    self.unlockedLore = {}
    self.dungeonFloor = 1
    self.mapStates = {}
    self.portalReturn = nil
    self.mapPresentationOverrides = {}
    -- The graveyard: one record per creature that left the party permanently
    -- (reaped or sacrificed), keeping its history after the battler object is
    -- gone. This is what makes a loss legible days later instead of a silently
    -- emptied slot.
    self.memorial = {}
    self.transitionTimer = 0
    self.transitionDir = "forward"
    self.autoRedirect = (loader and loader.system and loader.system.combat and loader.system.combat.autoRedirect) or false
    
    -- Summoner details
    local startMp = loader.system and loader.system.summoner and loader.system.summoner.startMp or 820
    self.mp = startMp
    self.maxMp = startMp
    -- EXP Bank: accrued mostly by sacrificing creatures; spent to summon
    -- creatures above their base level.
    self.expBank = 0
    self.summoner = Battler.new(loader.getActorByRole("Summoner"), 1)
    self.summoner.hp = self.summoner:getMaxHp(self)
    
    -- Party composition: 1-4 active creatures.
    self.party = {}
    -- Expedition reserve: four creatures physically brought below.
    self.reserve = {}
    -- Town storage is deliberately separate from the expedition reserve.
    self.storage = {}
    
    return self
end

function GameSession:initializeStartingParty()
    -- All starting gold/inventory/party rules come from system.newGame
    self.gold = newgame.rollGold(self.loader)

    for _, itemId in ipairs(newgame.rollInventory(self.loader)) do
        self:addItem(itemId, 1)
    end

    -- Setup members
    local members = newgame.rollMembers(self.loader)
    for i, m in ipairs(members) do
        local actorData = self.loader.getActor(m.id)
        if actorData then
            local battler = Battler.new(actorData, m.level)
            battler.name = m.name or randomAllyName(actorData)
            battler.hp = battler:getMaxHp(self)
            table.insert(self.party, battler)
        end
    end
end

function GameSession:storeCreature(battler)
    if not battler then return nil, "No creature" end
    for i = 1, config.MAX_STORAGE_SIZE do
        if not self.storage[i] then
            self.storage[i] = battler
            return i
        end
    end
    return nil, "Storage full"
end

function GameSession:withdrawCreature(index)
    local battler = self.storage[index]
    if not battler then return nil, "Empty slot" end
    for i = 1, config.MAX_RESERVE_SIZE do
        if not self.reserve[i] then
            self.storage[index] = nil
            self.reserve[i] = battler
            return battler, i
        end
    end
    return nil, "Expedition reserve full"
end

function GameSession:dismissToStorage(isReserve, index)
    local roster = isReserve and self.reserve or self.party
    local battler = roster and roster[index]
    if not battler then return nil, "Empty slot" end
    if not isReserve then
        local livingParty = 0
        for _, member in pairs(self.party) do
            if member then livingParty = livingParty + 1 end
        end
        if livingParty <= 1 then return nil, "Cannot dismiss the last active creature" end
    end
    local storageSlot, err = self:storeCreature(battler)
    if not storageSlot then return nil, err end
    roster[index] = nil
    return battler, storageSlot
end

-- Files a creature into the memorial and returns the record. `cause` is a term
-- key ("battle", "sacrifice"), resolved to text at display time so the record
-- stays language-neutral.
function GameSession:remember(battler, cause)
    if not battler then return nil end
    local h = battler.history or {}
    local record = {
        name = battler.name,
        species = h.species or (battler.actorData and battler.actorData.name),
        finalForm = battler.actorData and battler.actorData.name,
        level = battler.level,
        expeditions = h.expeditions or 0,
        battles = h.battles or 0,
        promotions = h.promotions or 0,
        cause = cause,
        sacrificed = (cause == "sacrifice"),
    }
    self.memorial = self.memorial or {}
    table.insert(self.memorial, record)
    return record
end

function GameSession:recruitActor(actorId, level)
    local actorData = self.loader.getActor(actorId)
    if not actorData then
        return nil, "Actor not found"
    end
    level = level or actorData.level or 1
    -- A creature the player KEEPS gets a genuine per-instance growth seed, so
    -- two Pixies recruited from the same pool grow into different creatures.
    -- Enemies and previews keep the actor's stable default (Battler.new), which
    -- is what holds the golden harness reproducible: this draw happens only on
    -- recruitment, a path the fixtures never take.
    local battler = Battler.new(actorData, level, math.random(1, 2147483646))
    battler.name = randomAllyName(actorData)
    battler.hp = battler:getMaxHp(self)

    -- Check active party slots (1-4)
    for i = 1, config.MAX_PARTY_SIZE do
        if not self.party[i] then
            battler.row = (i <= 2) and "front" or "back"
            self.party[i] = battler
            return battler, "party"
        end
    end

    -- Check reserve roster (slots 1-8)
    for i = 1, config.MAX_RESERVE_SIZE do
        if not self.reserve[i] then
            self.reserve[i] = battler
            return battler, "reserve"
        end
    end

    return nil, "Full"
end

local function compareIds(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then return na < nb end
    if na then return true end
    if nb then return false end
    return tostring(a) < tostring(b)
end

function GameSession:addItem(itemId, amount)
    amount = amount or 1
    local id = tonumber(itemId) or itemId
    self.inventory[id] = (self.inventory[id] or 0) + amount
    if self.inventory[id] <= 0 then
        self.inventory[id] = nil
    end
end

function GameSession:hasItem(itemId, amount)
    amount = amount or 1
    local id = tonumber(itemId) or itemId
    return (self.inventory[id] or 0) >= amount
end

function GameSession:isPartyEmpty()
    for i = 1, config.MAX_PARTY_SIZE do
        if self.party[i] then return false end
    end
    return true
end

-- Fills every empty fielded slot (1-4) from the reserve, in reserve-key
-- order, assigning row by slot (1-2 front, 3-4 back). Shared by the
-- Summoner rework's emergency wave (engine/battle.lua) and the general
-- auto-field rule (SPEC: the party is never left empty while a reserve
-- exists) so there is exactly one "pull from reserve" implementation.
-- Returns a list of { battler, slot, reserveKey } records (empty if the
-- reserve had nothing to give) — richer than a plain battler list so
-- callers that need to defer/replay the write (the emergency wave's
-- presentation-timed swap) have what they need; callers that just want
-- "did anything deploy" only need #result.
function GameSession:fillEmptySlotsFromReserve()
    local keys = {}
    for k, b in pairs(self.reserve or {}) do
        if b then table.insert(keys, k) end
    end
    table.sort(keys, compareIds)

    local deployed = {}
    local ki = 1
    for i = 1, config.MAX_PARTY_SIZE do
        if not self.party[i] and keys[ki] then
            local key = keys[ki]
            local b = self.reserve[key]
            self.reserve[key] = nil
            b.row = (i <= 2) and "front" or "back"
            self.party[i] = b
            table.insert(deployed, { battler = b, slot = i, reserveKey = key })
            ki = ki + 1
        end
    end
    return deployed
end

-- Auto-field rule: the fielded party is never left empty while the
-- reserve holds anyone. Called after any path that can empty the party
-- (battle permadeath sweep, ritual sacrifice). Returns true if anyone
-- was deployed.
function GameSession:autoFieldIfEmpty()
    if not self:isPartyEmpty() then return false end
    return #self:fillEmptySlotsFromReserve() > 0
end

function GameSession:getActiveParty()
    -- Returns the creatures active in combat (slots 1 to 4). The summoner
    -- is not a battle participant (overhaul-6 F1) -- they keep a Battler
    -- object for their name/level/equipment/MP-adjacent data, used outside
    -- battle (shop level-gates, RECOVER_PARTY, etc.), but never fights.
    local active = {}
    for i = 1, config.MAX_PARTY_SIZE do
        if self.party[i] then
            table.insert(active, self.party[i])
        end
    end
    return active
end

session.GameSession = GameSession
session.Battler = Battler

return session
