-- Creature Recruitment System (Canonical Recruitment Transaction Engine)
--
-- Owns candidate generation, equipment resolution, transaction commit planning,
-- validation, and atomic execution.
-- GameSession owns roster storage and primitive table operations; interpreter
-- and scene_host own interactive continuations; presentation owns UI rendering.

local config = require("engine.config")
local traits = require("engine.traits")
local formation = require("engine.formation")

local recruitment = {}

-- ---------------------------------------------------------------------------
-- Equipment Resolution
-- ---------------------------------------------------------------------------

-- Resolves equipment ONCE deterministically for a candidate using its growthSeed.
-- Merges actor defaults and event equipment rules.
function recruitment.resolveCandidateEquipment(actorData, equipmentRules, growthSeed)
    local result = { nil, nil, nil }
    if not actorData then return result end
    local loader = require("data.loader")

    local seed = growthSeed or 1
    local rngState = seed

    local function nextRandom()
        rngState = (rngState * 1103515245 + 12345) % 2147483648
        return rngState / 2147483648
    end

    -- Process each slot (1=Weapon, 2=Armor, 3=Accessory)
    for slot = 1, 3 do
        local rule = equipmentRules and equipmentRules[slot]
        local chosenItemId = nil

        if rule then
            if rule.item ~= nil then
                chosenItemId = rule.item
            elseif rule.choices and #rule.choices > 0 then
                local totalWeight = 0
                for _, c in ipairs(rule.choices) do
                    totalWeight = totalWeight + (c.weight or 1)
                end
                if totalWeight > 0 then
                    local roll = nextRandom() * totalWeight
                    local current = 0
                    for _, c in ipairs(rule.choices) do
                        current = current + (c.weight or 1)
                        if roll <= current then
                            chosenItemId = c.item
                            break
                        end
                    end
                end
            end
        end

        -- Fallback to actor default equipment if rule was not specified or empty
        if chosenItemId == nil and not (rule and rule.override) then
            if actorData.equipment and actorData.equipment[slot] then
                chosenItemId = actorData.equipment[slot]
            end
        end

        if chosenItemId then
            local itemData = loader.getItem(chosenItemId)
            if itemData then
                result[slot] = itemData
            end
        end
    end

    return result
end

-- ---------------------------------------------------------------------------
-- Persistent Recruit Node Management
-- ---------------------------------------------------------------------------

function recruitment.getOrCreateRecruitNode(session, loader, sourceKey, actorId, level, options)
    if not session then return nil, "No session" end
    if not sourceKey or sourceKey == "" then
        error("OPEN_RECRUIT requires a stable recruitNodeKey / sourceKey")
    end

    session.recruitNodes = session.recruitNodes or {}

    if session.recruitNodes[sourceKey] then
        return session.recruitNodes[sourceKey]
    end

    local actorData = loader.getActor(actorId)
    if not actorData then
        error("Actor " .. tostring(actorId) .. " not found for recruitment")
    end

    options = options or {}
    level = level or options.level or actorData.level or 1

    -- Create persistent battler with monotonically allocated instanceId
    local battler = session:createPersistentBattler(actorData, level, options)
    if options.name and options.name ~= "" then
        battler.name = options.name
    end

    -- Initial HP fraction or HP override
    if options.hpFraction then
        local maxHp = battler:getMaxHp(session)
        battler.hp = math.max(1, math.floor(maxHp * options.hpFraction))
    elseif options.hp then
        battler.hp = math.min(options.hp, battler:getMaxHp(session))
    end

    -- Initial states
    if options.states and type(options.states) == "table" then
        for _, sDef in ipairs(options.states) do
            if type(sDef) == "string" then
                battler:addState(sDef)
            elseif type(sDef) == "table" and sDef.id then
                battler:addState(sDef.id, sDef.duration)
            end
        end
    end

    -- Equipment spawning
    battler.equipment = recruitment.resolveCandidateEquipment(actorData, options.equipmentRules, battler.growthSeed)

    local requirement = options.requirement or { type = "free" }

    local node = {
        candidate = battler,
        requirement = requirement,
        requirementSatisfied = (requirement.type == "free"),
        suggestedSlot = options.suggestedSlot,
        completed = false,
    }

    session.recruitNodes[sourceKey] = node
    return node
end

-- ---------------------------------------------------------------------------
-- Transaction Commit Planning
-- ---------------------------------------------------------------------------

function recruitment.buildCommitPlan(session, node, choice)
    choice = choice or {}
    local isReserve = choice.isReserve
    if isReserve == nil then
        local prefSlot = node and node.suggestedSlot
        if prefSlot and formation.isValidSlot(prefSlot) and not session.party[prefSlot] then
            isReserve = false
        else
            local freePartySlot = nil
            for i = 1, config.MAX_PARTY_SIZE do
                if not session.party[i] then freePartySlot = i; break end
            end
            if freePartySlot then
                isReserve = false
            else
                isReserve = true
            end
        end
    end

    local defaultSlot = node and node.suggestedSlot
    if isReserve then
        if not defaultSlot or session.reserve[defaultSlot] then
            for i = 1, config.MAX_RESERVE_SIZE do
                if not session.reserve[i] then defaultSlot = i; break end
            end
            defaultSlot = defaultSlot or 1
        end
    else
        if not defaultSlot or session.party[defaultSlot] then
            for i = 1, config.MAX_PARTY_SIZE do
                if not session.party[i] then defaultSlot = i; break end
            end
            defaultSlot = defaultSlot or 1
        end
    end

    local plan = {
        node = node,
        isReserve = isReserve == true,
        slot = choice.slot or defaultSlot,
        substituteSlot = choice.substituteSlot,
        dismissIndex = choice.dismissIndex,
        dismissIsReserve = choice.dismissIsReserve,
        costs = {},
    }

    if node and node.requirement then
        local req = node.requirement
        if req.type == "gold" and req.goldCost then
            plan.costs.gold = req.goldCost
        elseif req.type == "item" and req.itemRequired then
            plan.costs.item = req.itemRequired
            plan.costs.itemAmount = req.itemAmount or 1
        end
    end

    return plan
end

function recruitment.findEmptyStorageSlot(session)
    for i = 1, config.MAX_STORAGE_SIZE do
        if not session.storage[i] then
            return i
        end
    end
    return nil
end

function recruitment.validateCommitPlan(session, plan)
    if not plan or not plan.node then
        return false, "Invalid recruitment plan"
    end
    local node = plan.node
    if node.completed then
        return false, "Recruitment already completed"
    end
    if not node.candidate then
        return false, "No candidate creature"
    end

    -- 1. Validate costs
    if plan.costs.gold and (session.gold or 0) < plan.costs.gold then
        return false, "Insufficient gold (" .. tostring(session.gold) .. " / " .. tostring(plan.costs.gold) .. ")"
    end
    if plan.costs.item then
        if not session:hasItem(plan.costs.item, plan.costs.itemAmount or 1) then
            return false, "Missing required item"
        end
    end

    -- 2. Validate destination slot
    if plan.isReserve then
        if plan.slot < 1 or plan.slot > config.MAX_RESERVE_SIZE then
            return false, "Invalid reserve slot"
        end
    else
        if plan.slot < 1 or plan.slot > config.MAX_PARTY_SIZE then
            return false, "Invalid party slot"
        end
    end

    -- 3. Validate dismissal to town storage if requested
    if plan.dismissIndex then
        local storageSlot = recruitment.findEmptyStorageSlot(session)
        if not storageSlot then
            return false, "Town storage is full!"
        end
        plan.storageSlot = storageSlot
    end

    -- 4. Active party invariant check (resulting active party must have >= 1 member)
    local simPartyCount = 0
    for i = 1, config.MAX_PARTY_SIZE do
        if i == plan.slot and not plan.isReserve then
            simPartyCount = simPartyCount + 1 -- candidate becomes active
        elseif session.party[i] then
            if plan.dismissIndex and not plan.dismissIsReserve and plan.dismissIndex == i then
                -- creature dismissed to storage
            elseif plan.substituteSlot and not plan.isReserve and plan.slot == i then
                -- creature displaced
            else
                simPartyCount = simPartyCount + 1
            end
        end
    end

    if simPartyCount < 1 then
        return false, "Active party cannot be left empty!"
    end

    return true
end

function recruitment.applyCommitPlan(session, plan)
    local ok, err = recruitment.validateCommitPlan(session, plan)
    if not ok then return false, err end

    local node = plan.node
    local candidate = node.candidate

    -- 1. Deduct costs
    if plan.costs.gold then
        session.gold = session.gold - plan.costs.gold
    end
    if plan.costs.item then
        session:addItem(plan.costs.item, -(plan.costs.itemAmount or 1))
    end

    -- 2. Handle dismissal of existing expedition creature to town storage if requested
    if plan.dismissIndex and plan.storageSlot then
        local roster = plan.dismissIsReserve and session.reserve or session.party
        local dismissedBattler = roster[plan.dismissIndex]
        if dismissedBattler then
            session.storage[plan.storageSlot] = dismissedBattler
            roster[plan.dismissIndex] = nil
        end
    end

    -- 3. Handle active/reserve substitution if candidate displaces an active creature into reserve
    if not plan.isReserve and plan.substituteSlot and session.party[plan.slot] then
        local displaced = session.party[plan.slot]
        session.reserve[plan.substituteSlot] = displaced
        session.party[plan.slot] = nil
    end

    -- 4. Insert candidate into chosen destination slot
    if plan.isReserve then
        session.reserve[plan.slot] = candidate
    else
        session.party[plan.slot] = candidate
    end

    -- 5. Mark node completed and relinquish candidate ownership on node
    node.completed = true
    node.recruitedInstanceId = candidate.instanceId
    node.candidate = nil

    -- 6. First-recruit bookkeeping
    if not session.flags.first_recruit_complete then
        session.flags.first_recruit_complete = true
        session.firstRecruitInstanceId = candidate.instanceId
        session.firstRecruitOriginalActorId = candidate.id
    end

    return true
end

function recruitment.commitRecruitNode(session, loader, sourceKey, choice)
    local node = session.recruitNodes and session.recruitNodes[sourceKey]
    if not node or node.completed then return false, "Node missing or already completed" end
    local plan = recruitment.buildCommitPlan(session, node, choice)
    return recruitment.applyCommitPlan(session, plan)
end

-- ---------------------------------------------------------------------------
-- Recruit Scene Hooks & Interaction
-- ---------------------------------------------------------------------------

function recruitment.onEnterRecruitScene(ctx)
    local v = ctx.v
    local session = ctx.session
    local loader = ctx.loader or session.loader

    if not session.flags.recruit_onboarding_shown then
        session.flags.recruit_onboarding_shown = true
        v.showOnboarding = true
    end

    local sourceKey = v.sourceKey
    if not sourceKey then return end

    local node = session.recruitNodes and session.recruitNodes[sourceKey]
    if not node or not node.candidate then return end

    local c = node.candidate
    v.mode = v.mode or 1
    v.candidateName = c.name
    v.candidateActorId = c.id
    v.candidateLevel = c.level
    v.candidateHp = c.hp
    v.candidateMaxHp = c:getMaxHp(session)
    v.portraitKey = (c.actorData and c.actorData.smallBattler) or c.id

    v.atk = traits.getParam(c, "atk", session)
    v.def = traits.getParam(c, "def", session)
    v.mat = traits.getParam(c, "mat", session)
    v.mdf = traits.getParam(c, "mdf", session)
    v.mpdDelta = (traits.getCreatureMpdDelta and traits.getCreatureMpdDelta(c, session)) or 0
    v.favoriteFood = c.favoriteFood

    local skills = {}
    for _, s in ipairs(c.skills or {}) do
        local def = loader.getSkill(s)
        table.insert(skills, { name = (def and def.name) or tostring(s) })
    end
    v.candidateSkills = skills

    local passives = {}
    for _, p in ipairs(c.passives or {}) do
        local def = loader.getSkill(p)
        table.insert(passives, { name = (def and def.name) or tostring(p) })
    end
    v.candidatePassives = passives

    local eqList = {}
    for slot = 1, 3 do
        local item = c.equipment and c.equipment[slot]
        table.insert(eqList, { name = (item and item.name) or "- None -" })
    end
    v.candidateEquipment = eqList

    v.slotIdx = v.slotIdx or node.suggestedSlot or v.suggestedSlot or 1
    v.errorText = nil
end

function recruitment.onNavRecruitScene(ctx, dir)
    local v = ctx.v
    if v.mode == 2 then
        if dir == "up" then
            v.slotIdx = math.max(1, v.slotIdx - 1)
        elseif dir == "down" then
            v.slotIdx = math.min(8, v.slotIdx + 1)
        elseif dir == "left" and v.slotIdx > 4 then
            v.slotIdx = v.slotIdx - 4
        elseif dir == "right" and v.slotIdx <= 4 then
            v.slotIdx = v.slotIdx + 4
        end
    end
end

function recruitment.onSelectRecruitScene(ctx)
    local v = ctx.v
    local session = ctx.session
    local loader = ctx.loader or session.loader
    local node = session.recruitNodes and session.recruitNodes[v.sourceKey]
    if not node then return end

    if v.showOnboarding then
        v.showOnboarding = false
        return
    end

    v.errorText = nil

    if v.mode == 1 then
        if not node.requirementSatisfied then
            local req = node.requirement
            if req.type == "item" then
                if session:hasItem(req.itemRequired, req.amountRequired or 1) then
                    session:addItem(req.itemRequired, -(req.amountRequired or 1))
                    node.requirementSatisfied = true
                    v.mode = 2
                else
                    local itemDef = loader.getItem(req.itemRequired)
                    local itemName = (itemDef and itemDef.name) or req.itemRequired
                    v.errorText = "Missing item: " .. itemName .. " x" .. tostring(req.amountRequired or 1)
                end
            elseif req.type == "gold" then
                if (session.gold or 0) >= (req.goldCost or 0) then
                    node.requirementSatisfied = true
                    v.mode = 2
                else
                    v.errorText = "Missing gold: " .. tostring(req.goldCost or 0) .. " G"
                end
            elseif req.type == "challenge" then
                v.outcome = "requirement"
                table.insert(ctx.events, { type = "scene_change", kind = "pop" })
            end
        else
            v.mode = 2
        end
    elseif v.mode == 2 then
        local isReserve = v.slotIdx > 4
        local slot = isReserve and (v.slotIdx - 4) or v.slotIdx
        local choice = { isReserve = isReserve, slot = slot }

        local targetRoster = isReserve and session.reserve or session.party
        local occupant = targetRoster[slot]
        if occupant then
            if not isReserve then
                local emptyReserve = nil
                for r = 1, config.MAX_RESERVE_SIZE do
                    if not session.reserve[r] then emptyReserve = r; break end
                end
                if emptyReserve then
                    choice.substituteSlot = emptyReserve
                else
                    local storageSlot = recruitment.findEmptyStorageSlot(session)
                    if storageSlot then
                        choice.dismissIndex = slot
                        choice.dismissIsReserve = false
                    else
                        v.errorText = "Reserve and Town Storage are full!"
                        return
                    end
                end
            else
                local storageSlot = recruitment.findEmptyStorageSlot(session)
                if storageSlot then
                    choice.dismissIndex = slot
                    choice.dismissIsReserve = true
                else
                    v.errorText = "Town Storage is full!"
                    return
                end
            end
        end

        v.selectedChoice = choice
        v.mode = 3
    elseif v.mode == 3 then
        local plan = recruitment.buildCommitPlan(session, node, v.selectedChoice)
        local ok, err = recruitment.applyCommitPlan(session, plan)
        if ok then
            v.outcome = "commit"
            table.insert(ctx.events, { type = "scene_change", kind = "pop" })
        else
            v.errorText = err
        end
    end
end

function recruitment.onCancelRecruitScene(ctx)
    local v = ctx.v
    if v.showOnboarding then
        v.showOnboarding = false
        return
    end
    if v.mode == 3 then
        v.mode = 2
        v.errorText = nil
    elseif v.mode == 2 then
        v.mode = 1
        v.errorText = nil
    elseif v.mode == 1 then
        v.outcome = "declined"
        table.insert(ctx.events, { type = "scene_change", kind = "pop" })
    end
end

function recruitment.onExitRecruitScene(ctx)
    local v = ctx.v
    local outcome = v.outcome or "cancelled"
    if recruitment.onResolved then
        recruitment.onResolved(outcome)
    end
end

return recruitment
