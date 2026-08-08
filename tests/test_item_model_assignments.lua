-- Focused unit tests for item 3D model assignments and resolution contracts.

package.path = package.path .. ";./?.lua;./engine/?.lua"

local loader = require("data.loader")
local item_model_view = require("presentation.item_model_view")
local mesh = require("presentation.mesh")

print("[TEST] Starting 3D item model assignment tests...")

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

local EXPECTED_ASSIGNMENTS = {
    [1]  = { name = "HP Tonic",             model = "assets/models/items/bottle_family__basis.obj" },
    [2]  = { name = "Sigil Ink",            model = "assets/models/items/bottle_family__angular.obj" },
    [3]  = { name = "Whispered Lessons",    model = "assets/models/items/crystal.obj" },
    [4]  = { name = "Elixir of Insight",    model = "assets/models/items/bottle_family__tall.obj" },
    [5]  = { name = "Silver Blade",         model = "assets/models/items/silver_blade.obj" },
    [6]  = { name = "Bone Plate",           model = "assets/models/items/bone_plate.obj" },
    [7]  = { name = "Wind Charm",           model = "assets/models/items/wind_charm.obj" },
    [8]  = { name = "Light Amulet",         model = "assets/models/items/wind_charm.obj" },
    [9]  = { name = "Alert Charm",          model = "assets/models/items/wind_charm.obj" },
    [10] = { name = "Rear Mirror",          model = "assets/models/items/rear_mirror.obj" },
    [11] = { name = "Mystic Egg",           model = "assets/models/items/mystic_egg.obj" },
    [12] = { name = "Golden Egg",           model = "assets/models/items/golden_egg.obj" },
    [13] = { name = "Vitality Seal 1",      model = "assets/models/items/vitality_seal_1.obj" },
    [14] = { name = "Vitality Seal 2",      model = "assets/models/items/vitality_seal_2.obj" },
    [15] = { name = "Vitality Seal 3",      model = "assets/models/items/vitality_seal_3.obj" },
    [16] = { name = "Radiant Blade Flavio", model = "assets/models/items/radiant_blade_flavio.obj" },
    [17] = { name = "Wind Dancer",          model = "assets/models/items/wind_dancer.obj" },
    [18] = { name = "Water Scepter",        model = "assets/models/items/water_scepter.obj" },
    [19] = { name = "Holy Sword Gram",      model = "assets/models/items/holy_sword_gram.obj" },
    [20] = { name = "Dark Scepter Lucille", model = "assets/models/items/dark_scepter_lucille.obj" },
    [21] = { name = "Mars Emblem",         model = "assets/models/items/mars_emblem.obj" },
    [22] = { name = "Mercury Crest",       model = "assets/models/items/mercury_crest.obj" },
    [23] = { name = "Hermes' Boots",       model = "assets/models/items/hermes_boots.obj" },
    [24] = { name = "Glittering Teardrop", model = "assets/models/items/glittering_teardrop.obj" },
    [25] = { name = "Untarnished Signet", model = "assets/models/items/untarnished_signet.obj" },
    [26] = { name = "Shattered Blade",    model = "assets/models/items/shattered_blade.obj" },
    [27] = { name = "Shattered Edge",     model = "assets/models/items/shattered_edge.obj" },
    [28] = { name = "Meteorite Plate",    model = "assets/models/items/meteorite_plate.obj" },
    [29] = { name = "Mug of Ale",         model = "assets/models/items/mug_of_ale.obj" },
    [30] = { name = "Pint of Stout",       model = "assets/models/items/pint_of_stout.obj" },
    [31] = { name = "Glass of Wine",       model = "assets/models/items/glass_of_wine.obj" },
    [32] = { name = "Scrap Plating",      model = "assets/models/items/scrap_plating.obj" },
    [33] = { name = "Sludge",             model = "assets/models/items/sludge.obj" },
    [34] = { name = "Burnt Slop",         model = "assets/models/items/burnt_slop.obj" },
    [35] = { name = "Broken Spring",      model = "assets/models/items/broken_spring.obj" },
    [36] = { name = "Ambrosia",           model = "assets/models/items/ambrosia.obj" },
    [37] = { name = "Philosopher's Stone",model = "assets/models/items/philosophers_stone.obj" },
    [38] = { name = "Chrysalis Sigil",   model = "assets/models/items/chrysalis_sigil.obj" },
    [39] = { name = "Obsidian Shard",     model = "assets/models/items/obsidian_shard.obj" },
    [40] = { name = "Melted Wax",         model = "assets/models/items/melted_wax.obj" },
    [41] = { name = "Ectoplasm",          model = "assets/models/items/ectoplasm.obj" },
    [42] = { name = "Warding Charm",      model = "assets/models/items/warding_charm.obj" },
    [43] = { name = "Vial of Second Breath", model = "assets/models/items/vial_of_second_breath.obj" },
    [44] = { name = "Thrice-Blessed Bead", model = "assets/models/items/thrice_blessed_bead.obj" },
    [45] = { name = "Tome: Wind Blade",   model = "assets/models/items/tome_wind_blade.obj" },
    [46] = { name = "Whetstone Draught",  model = "assets/models/items/whetstone_draught.obj" },
    [47] = { name = "Black Hinge",        model = "assets/models/items/black_hinge.obj" },
    [48] = { name = "Ember Bit",          model = "assets/models/items/ember_bit.obj" },
    [49] = { name = "Qilin Bell",         model = "assets/models/items/qilin_bell.obj" },
    [50] = { name = "Cinder Ruby",        model = "assets/models/items/cinder_ruby.obj" },
    [51] = { name = "Abyssal Pearl",      model = "assets/models/items/abyssal_pearl.obj" },
    [52] = { name = "Verdigris Coin",     model = "assets/models/items/verdigris_coin.obj" },
}

-------------------------------------------------- 1. Exact mapping coverage --

for id, exp in pairs(EXPECTED_ASSIGNMENTS) do
    local item = loader.getItem(id)
    check(item ~= nil, "Item ID " .. id .. " exists in database")
    if item then
        check(item.model == exp.model,
            "Item ID " .. id .. " (" .. item.name .. ") model path matches expected ('" .. tostring(exp.model) .. "')")
        check(type(item.model) == "string" and item.model ~= "",
            "Item ID " .. id .. " model path is non-empty")
        check(love.filesystem.getInfo(item.model) ~= nil,
            "OBJ file exists for Item ID " .. id .. ": " .. tostring(item.model))
        
        -- Verify OBJ mtllib resolution if present
        local text = love.filesystem.read(item.model)
        if text then
            local mtlName = text:match("^mtllib%s+(%S+)") or text:match("\nmtllib%s+(%S+)")
            if mtlName then
                local baseDir = mesh.dirname(item.model)
                local mtlPath = mesh.joined(baseDir, mtlName)
                check(love.filesystem.getInfo(mtlPath) ~= nil,
                    "MTL file exists for Item ID " .. id .. ": " .. mtlPath)
            end
        end
    end
end

-------------------------------------------------- 2. Optional-model behavior --

-- Derived, not hard-coded: each fabrication batch assigns the next contiguous
-- block of ids, so a literal list here goes stale the moment one lands. What
-- matters is that an item without a `model` field stays legal and reaches the
-- fallback, not which ids happen to be unassigned today.
local unassigned = {}
for _, item in ipairs(loader.items or {}) do
    if item.model == nil then unassigned[#unassigned + 1] = item end
end

check(#unassigned > 0, "At least one item still omits 'model' (fallback path stays exercised)")
for i = 1, math.min(4, #unassigned) do
    local item = unassigned[i]
    check(item.model == nil, "Item ID " .. item.id .. " (" .. item.name .. ") omits 'model' field")
end

for _, item in ipairs(loader.items or {}) do
    check(item.model ~= "assets/models/items/placeholder_question.obj",
        "No production item explicitly references placeholder_question.obj (ID " .. tostring(item.id) .. ")")
end

-------------------------------------------------- 3. Runtime presentation smoke coverage --

item_model_view.clearCache()

-- Bone Plate (Armor)
local bpModel, bpPath, bpFb = item_model_view.resolveModel(loader.getItem(6).model)
check(bpModel ~= nil and bpPath == "assets/models/items/bone_plate.obj" and bpFb == false,
    "Bone Plate (ID 6) resolves real model rather than fallback")

-- Holy Sword Gram (Named Weapon)
local hgModel, hgPath, hgFb = item_model_view.resolveModel(loader.getItem(19).model)
check(hgModel ~= nil and hgPath == "assets/models/items/holy_sword_gram.obj" and hgFb == false,
    "Holy Sword Gram (ID 19) resolves real model rather than fallback")

-- Ambrosia (Consumable)
local ambModel, ambPath, ambFb = item_model_view.resolveModel(loader.getItem(36).model)
check(ambModel ~= nil and ambPath == "assets/models/items/ambrosia.obj" and ambFb == false,
    "Ambrosia (ID 36) resolves real model rather than fallback")

-- Qilin Bell (Promotion Key)
local qbModel, qbPath, qbFb = item_model_view.resolveModel(loader.getItem(49).model)
check(qbModel ~= nil and qbPath == "assets/models/items/qilin_bell.obj" and qbFb == false,
    "Qilin Bell (ID 49) resolves real model rather than fallback")

-- First still-unassigned item: the fallback must remain reachable through
-- ordinary viewer behavior, whichever id that happens to be.
local cfItem = unassigned[1]
local cfModel, cfPath, cfFb = item_model_view.resolveModel(cfItem and cfItem.model)
check(cfModel ~= nil and cfPath == item_model_view.FALLBACK_PATH and cfFb == true,
    (cfItem and cfItem.name or "?") .. " (ID " .. tostring(cfItem and cfItem.id)
        .. ") resolves fallback placeholder through normal viewer behavior")

print("Item model assignment tests completed: " .. passed .. " passed, " .. failed .. " failed")
if failed > 0 then error("test_item_model_assignments failed", 0) end
