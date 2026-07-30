-- Level-up reporting: what changed about a creature between two points in time.
--
-- The engine has never had a way to SAY that a creature grew. Battler:gainExp
-- applies growth silently and returns a boolean, so the only visible trace of a
-- level-up was the victory panel's gauge rolling over. This module turns "the
-- party before" and "the party now" into structured rows a window can draw.
--
-- It lives here, not in the battle scene, for two reasons. It is not
-- battle-specific -- any host that can grant EXP (a quest reward, a ritual, a
-- future training site) can snapshot around its own grant and get the same
-- report. And the battle scene's job is to PUBLISH this onto its scene vars, so
-- the window itself stays entirely data-authored (data/scenes.json +
-- engine.json windowLayout) rather than a bespoke Lua drawer.
--
-- Snapshots are keyed by PARTY SLOT, never by battler identity: a level-up can
-- fire an automatic transform (engine/transform.lua), which replaces the object
-- sitting in session.party[i] with a new one. Identity-keyed lookup would lose
-- exactly the creature whose report matters most.
local growth = require("engine.growth")
local traits = require("engine.traits")
local config = require("engine.config")

local progress = {}

-- Display labels for the growing parameters. Growth's PARAMS list stays the
-- single source of WHICH parameters exist; this only names them.
local PARAM_LABELS = {
    maxHp = "HP",
    atk = "ATK",
    def = "DEF",
    mat = "MAT",
    mdf = "MDF",
}

local function paramLabel(param)
    return PARAM_LABELS[param] or param:upper()
end

local function skillIds(battler)
    local out = {}
    for _, id in ipairs(battler.skills or {}) do out[id] = true end
    return out
end

-- One party slot's state, as of now.
local function snapshotMember(battler, session)
    local params = {}
    for _, p in ipairs(growth.PARAMS) do
        params[p] = traits.getParam(battler, p, session)
    end
    return {
        battler = battler,
        actorId = battler.actorData and battler.actorData.id,
        name = battler.name,
        level = battler.level or 1,
        exp = battler.exp or 0,
        params = params,
        skills = skillIds(battler),
    }
end

-- The whole active party, indexed by slot. Take one before granting EXP.
function progress.snapshot(session)
    local snap = {}
    for i = 1, config.MAX_PARTY_SIZE do
        local c = session.party[i]
        if c then snap[i] = snapshotMember(c, session) end
    end
    return snap
end

-- Compares the party against `before` and returns one entry per creature that
-- gained a level, in party order. Creatures that were reaped, replaced or left
-- the party in between simply produce no entry -- there is nobody left to show
-- the report to.
function progress.levelUps(session, before)
    local expPerLevel = (config.growth and config.growth.expPerLevel) or 15
    local loader = session.loader
    local entries = {}
    for i = 1, config.MAX_PARTY_SIZE do
        local now = session.party[i]
        local was = before and before[i]
        if now and was and (now.level or 1) > was.level then
            local after = snapshotMember(now, session)
            local rows = {}
            for _, p in ipairs(growth.PARAMS) do
                local from, to = was.params[p] or 0, after.params[p] or 0
                local delta = to - from
                table.insert(rows, {
                    param = p,
                    label = paramLabel(p),
                    from = from,
                    to = to,
                    delta = delta,
                    -- Pre-signed so a format string can print it directly; a
                    -- level that skipped a stat shows nothing rather than "+0".
                    deltaText = delta > 0 and ("+" .. delta) or (delta < 0 and tostring(delta) or ""),
                })
            end

            -- Notes: what changed that isn't a number. Skills first (a new
            -- skill is the most actionable thing a level-up can grant), then a
            -- transform, which renames the creature's whole form.
            local notes = {}
            local learned = {}
            for id in pairs(after.skills) do
                if not was.skills[id] then
                    local sk = loader and loader.getSkill and loader.getSkill(id)
                    table.insert(learned, (sk and sk.name) or tostring(id))
                end
            end
            table.sort(learned)
            for _, name in ipairs(learned) do
                table.insert(notes, (loader and loader.formatTerm)
                    and loader.formatTerm("battle.learns_skill", "- {0} learns {1}!", after.name, name)
                    or ("- " .. after.name .. " learns " .. name .. "!"))
            end
            if after.actorId ~= was.actorId then
                table.insert(notes, (loader and loader.formatTerm)
                    and loader.formatTerm("battle.transform", "- {0} becomes {1}!", was.name, after.name)
                    or ("- " .. was.name .. " becomes " .. after.name .. "!"))
            end
            for _, evolution in ipairs((now.actorData and now.actorData.evolutions) or {}) do
                local required = tonumber(evolution.level)
                if required and was.level < required and after.level >= required then
                    table.insert(notes, (loader and loader.formatTerm)
                        and loader.formatTerm("battle.potential_unlocked",
                            "...{0}'s potential has been unlocked!", after.name)
                        or ("..." .. after.name .. "'s potential has been unlocked!"))
                end
            end

            table.insert(entries, {
                name = after.name,
                portraitKey = (now.actorData and now.actorData.portrait) or "",
                fromLevel = was.level,
                toLevel = after.level,
                exp = after.exp,
                expNeeded = after.level * expPerLevel,
                rows = rows,
                noteText = table.concat(notes, "\n"),
            })
        end
    end
    return entries
end

-- Publishes entry `index` of a `progress.levelUps` list onto a scene's var
-- table, under the names data/scenes.json and engine.json's windowLayout read.
-- Nothing here decides how any of it looks: this is the seam that lets the
-- level-up window be authored data instead of a drawer.
function progress.publish(v, entries, index)
    local e = entries and entries[index]
    v.levelUpRows = e and e.rows or {}
    v.levelUpName = e and e.name or ""
    v.levelUpPortrait = e and e.portraitKey or ""
    v.levelUpFromLevel = e and e.fromLevel or 0
    v.levelUpToLevel = e and e.toLevel or 0
    v.levelUpExp = e and e.exp or 0
    v.levelUpExpNeeded = e and e.expNeeded or 0
    v.levelUpNoteText = e and e.noteText or ""
    -- "2/3" only while there is more than one to read; a single level-up
    -- needs no position indicator.
    v.levelUpCounter = (entries and #entries > 1) and (index .. "/" .. #entries) or ""
end

return progress
