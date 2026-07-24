-- Creature Recruitment Event Builder / Compiler
-- Translates an actor's `recruitEvent` JSON specification into standard
-- interpreter commands (TEXT, CHOICE, TAKE_GOLD, TAKE_ITEM, RECOVER_PARTY,
-- BATTLE, RECRUIT_ACTOR, ERASE_EVENT).
-- Supports raw command arrays, scriptId references, event pages, or preset event types.

local recruitment = {}

-- Compiles an actor's recruitment event definition into an interpreter script command array.
-- `actorData`: Table from loader.getActor(id)
-- `dungeonFloor`: Current floor level (used for scaling level/gold if needed)
-- `ctx`: optional context (session, loader)
function recruitment.compile(actorData, dungeonFloor, ctx)
    if not actorData then return {} end

    local rec = actorData.recruitEvent
    if not rec then
        rec = { type = "free" }
    end

    local session = ctx and ctx.session
    local loader = (ctx and ctx.loader) or (session and session.loader)

    -- Case 1: Direct command array [ { type = "TEXT", ... }, ... ]
    if type(rec) == "table" and rec[1] ~= nil then
        return rec
    end

    -- Case 2: Number or string referencing a scriptId / common event ID
    if type(rec) == "number" or (type(rec) == "string" and tonumber(rec) ~= nil) then
        rec = { scriptId = tonumber(rec) }
    end

    if type(rec) == "table" then
        -- Case 3: RPG Maker-style event pages override resolution
        if rec.pages and #rec.pages > 0 then
            local exploration = require("engine.exploration")
            if exploration and exploration.resolvePage then
                rec = exploration.resolvePage(rec, session) or rec
            end
        end

        -- Case 4: Explicit commands array or script array on event object
        if rec.commands and type(rec.commands) == "table" and #rec.commands > 0 then
            return rec.commands
        elseif rec.script and type(rec.script) == "table" and #rec.script > 0 then
            return rec.script
        end

        -- Case 5: scriptId referencing a common event
        if rec.scriptId and loader and loader.commonEvents then
            local ce = loader.commonEvents[tostring(rec.scriptId)]
            if ce then
                local ceCmds = ce.commands or ce.script
                if ceCmds and #ceCmds > 0 then
                    return ceCmds
                end
            end
        end
    end

    -- Case 6: High-level preset types ("gold", "hostile", "heal", "aid", "free", etc.)
    local recType = (type(rec) == "table" and rec.type) or "free"
    local actorName = actorData.name or "Creature"
    local actorId = actorData.id
    local level = (type(rec) == "table" and rec.level) or actorData.level or (dungeonFloor or 1)

    local commands = {}

    if recType == "gold" then
        local cost = (type(rec) == "table" and rec.goldCost) or actorData.gold or (level * 15)
        local greeting = (type(rec) == "table" and rec.greeting) or (actorName .. " crosses its arms. 'I'll lend you my power for " .. cost .. " Gold.'")
        local acceptText = (type(rec) == "table" and rec.acceptText) or (actorName .. " takes the gold with a nod. 'A deal's a deal!'")
        local declineText = (type(rec) == "table" and rec.declineText) or (actorName .. " scoffs. 'No coin, no deal!'")

        table.insert(commands, {
            type = "TEXT",
            text = greeting
        })
        table.insert(commands, {
            type = "CHOICE",
            options = {
                {
                    label = "Pay " .. cost .. " Gold",
                    condition = "gold:" .. cost,
                    script = {
                        { type = "TAKE_GOLD", value = cost },
                        { type = "TEXT", text = acceptText },
                        { type = "RECRUIT_ACTOR", actorId = actorId, level = level },
                        { type = "ERASE_EVENT" }
                    }
                },
                {
                    label = "Decline",
                    script = {
                        { type = "TEXT", text = declineText }
                    }
                }
            }
        })

    elseif recType == "heal" then
        local greeting = (type(rec) == "table" and rec.greeting) or ("A friendly " .. actorName .. " approaches! 'You look weary. Let me soothe your wounds.'")
        local acceptText = (type(rec) == "table" and rec.acceptText) or (actorName .. " smiles brightly. 'Shall I travel with you?'")

        table.insert(commands, {
            type = "TEXT",
            text = greeting
        })
        table.insert(commands, {
            type = "RECOVER_PARTY"
        })
        table.insert(commands, {
            type = "TEXT",
            text = acceptText
        })
        table.insert(commands, {
            type = "CHOICE",
            options = {
                {
                    label = "Recruit " .. actorName,
                    script = {
                        { type = "RECRUIT_ACTOR", actorId = actorId, level = level },
                        { type = "ERASE_EVENT" }
                    }
                },
                {
                    label = "Leave",
                    script = {
                        { type = "TEXT", text = "You part ways peacefully." }
                    }
                }
            }
        })

    elseif recType == "aid" then
        local itemId = (type(rec) == "table" and rec.itemRequired) or 1 -- 1 = HP Tonic / Potion default
        local itemData = loader and loader.getItem and loader.getItem(itemId)
        local itemName = itemData and itemData.name or "Potion"

        local greeting = (type(rec) == "table" and rec.greeting) or ("A wounded " .. actorName .. " lies collapsed on the ground, needing a " .. itemName .. "...")
        local acceptText = (type(rec) == "table" and rec.acceptText) or (actorName .. " recovers quickly and gazes at you with deep gratitude!")
        local declineText = (type(rec) == "table" and rec.declineText) or (actorName .. " groans softly as you step back.")

        table.insert(commands, {
            type = "TEXT",
            text = greeting
        })
        table.insert(commands, {
            type = "CHOICE",
            options = {
                {
                    label = "Give " .. itemName,
                    condition = "hasItem:" .. itemId,
                    script = {
                        { type = "TAKE_ITEM", item = itemId, count = 1 },
                        { type = "TEXT", text = acceptText },
                        { type = "RECRUIT_ACTOR", actorId = actorId, level = level },
                        { type = "ERASE_EVENT" }
                    }
                },
                {
                    label = "Leave",
                    script = {
                        { type = "TEXT", text = declineText }
                    }
                }
            }
        })

    elseif recType == "hostile" then
        local greeting = (type(rec) == "table" and rec.greeting) or ("A wild " .. actorName .. " snarls and prepares to challenge your strength!")
        local acceptText = (type(rec) == "table" and rec.acceptText) or (actorName .. " bows its head in defeat. 'Your strength is formidable. I yield to your command!'")
        local declineText = (type(rec) == "table" and rec.declineText) or ("You back away slowly from " .. actorName .. ".")
        local troopId = (type(rec) == "table" and rec.troopId) or actorId

        table.insert(commands, {
            type = "TEXT",
            text = greeting
        })
        table.insert(commands, {
            type = "CHOICE",
            options = {
                {
                    label = "Battle " .. actorName,
                    script = {
                        { type = "BATTLE", troopId = troopId },
                        { type = "TEXT", text = acceptText },
                        {
                            type = "CHOICE",
                            options = {
                                {
                                    label = "Recruit " .. actorName,
                                    script = {
                                        { type = "RECRUIT_ACTOR", actorId = actorId, level = level },
                                        { type = "ERASE_EVENT" }
                                    }
                                },
                                {
                                    label = "Leave",
                                    script = {
                                        { type = "TEXT", text = "You leave the defeated creature behind." }
                                    }
                                }
                            }
                        }
                    }
                },
                {
                    label = "Step Back",
                    script = {
                        { type = "TEXT", text = declineText }
                    }
                }
            }
        })

    else -- "free" or default
        local greeting = (type(rec) == "table" and rec.greeting) or ("A wandering " .. actorName .. " gazes at you with curiosity and offers to join!")

        table.insert(commands, {
            type = "TEXT",
            text = greeting
        })
        table.insert(commands, {
            type = "CHOICE",
            options = {
                {
                    label = "Recruit " .. actorName,
                    script = {
                        { type = "RECRUIT_ACTOR", actorId = actorId, level = level },
                        { type = "ERASE_EVENT" }
                    }
                },
                {
                    label = "Decline",
                    script = {
                        { type = "TEXT", text = "You decide not to recruit " .. actorName .. "." }
                    }
                }
            }
        })
    end

    return commands
end

return recruitment
