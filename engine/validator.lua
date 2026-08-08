-- G1 extension for the combat-state resource vocabulary introduced by #166.
-- The comprehensive validator remains unchanged in validator_core.lua; this
-- public surface adds the small authored contract which only #166 knows about.
local core = require("engine.validator_core")

local validator = {}
for k, v in pairs(core) do validator[k] = v end

local HEAL_TYPES = { hp_heal = true, hp = true, hp_drain = true }

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
    core.run(loader)
    checkOverhealVocabulary(loader)
end

return validator
