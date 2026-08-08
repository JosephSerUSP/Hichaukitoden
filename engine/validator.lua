-- G1 extension for the combat-state resource vocabulary introduced by #166.
-- The comprehensive validator remains in validator_core.lua; this public
-- surface adds the small authored contract which only #166 knows about.
local core = require("engine.validator_core")

local validator = {}
for k, v in pairs(core) do validator[k] = v end

local HEAL_TYPES = { hp_heal = true, hp = true, hp_drain = true }

-- #179 reverses one old validator invariant: REAP_FALLEN now MUST finish its
-- authoritative party-membership write before presentation receives the event.
-- validator_core.lua still contains the pre-#179 behavioral assertion while
-- #178's `_core` + facade consolidation is pending. Core collects every problem
-- and throws only at the end, so filtering exactly this retired assertion keeps
-- every unrelated G1 failure intact rather than weakening validation broadly.
--
-- Remove this compatibility shim when #178 folds validator.lua back into
-- validator_core.lua; the replacement core assertion should check immediate
-- removal + a resolved roster snapshot instead.
local RETIRED_REAP_ASSERTION =
    "REAP_FALLEN must not remove party members itself -- that's deferred to animation completion"

local function runCore(loader)
    local ok, err = pcall(core.run, loader)
    if ok then return end

    local remaining = {}
    for line in tostring(err):gmatch("[^\r\n]+") do
        if line ~= RETIRED_REAP_ASSERTION then
            table.insert(remaining, line)
        end
    end
    if #remaining > 0 then
        error(table.concat(remaining, "\n"), 0)
    end
end

local function checkOverhealVocabulary(loader)
    local problems = {}
    local function check(cond, msg)
        if not cond then table.insert(problems, msg) end
    end

    local combat = loader.system and loader.system.combat or {}
    if combat.overhealCap ~= nil then
        check(type(combat.overhealCap) == "number" and combat.overhealCap >= 1,
            "combat.overhealCap must be a number >= 1")
    end

    local function checkEffects(list, where)
        for i, eff in ipairs(list or {}) do
            local desc = where .. " effect #" .. i
            if eff.overheal ~= nil then
                check(HEAL_TYPES[eff.type] == true,
                    desc .. " authors overheal on non-healing effect '" .. tostring(eff.type) .. "'")
                check(type(eff.overheal) == "boolean",
                    desc .. ".overheal must be true or false")
            end
            if eff.overhealCap ~= nil then
                check(eff.overheal == true,
                    desc .. ".overhealCap requires overheal=true")
                check(type(eff.overhealCap) == "number" and eff.overhealCap >= 1,
                    desc .. ".overhealCap must be a number >= 1")
            end
        end
    end

    for id, skill in pairs(loader.skills or {}) do
        checkEffects(skill.effects, "skill '" .. tostring(id) .. "'")
    end
    for _, item in ipairs(loader.items or {}) do
        checkEffects(item.effects, "item '" .. tostring(item.id) .. "'")
    end

    if #problems > 0 then
        error("Combat-state resource validation failed:\n- " .. table.concat(problems, "\n- "), 0)
    end
end

function validator.run(loader)
    runCore(loader)
    checkOverhealVocabulary(loader)
end

return validator
