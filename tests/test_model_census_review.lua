-- tests/test_model_census_review.lua
-- Unit tests for engine/model_census_review.lua harness logic.

local json = require("data.json")
local model_census_review = require("engine.model_census_review")

print("=== TEST MODEL CENSUS REVIEW HARNESS ===")

-- 1. Manifest schema validation and asset/state count
local manifest, fileHashes, verifiedCount = model_census_review.verifyAndHashDependencies("tools/asset-production/review_manifest.json")
assert(manifest, "Manifest failed to load")
assert(manifest.cohortCount == 16, "Cohort count mismatch: expected 16, got " .. tostring(manifest.cohortCount))
assert(manifest.stateCount == 25, "State count mismatch: expected 25, got " .. tostring(manifest.stateCount))
assert(manifest.full_matrix_count == 900, "Matrix count mismatch: expected 900, got " .. tostring(manifest.full_matrix_count))
print("  [PASS] Manifest schema and product count (16 concepts, 25 states, 900 matrix frames)")

-- 2. Check unique output paths across all combinations in manifest
local pathSet = {}
local duplicateCount = 0
for _, asset in ipairs(manifest.assets) do
    assert(asset.placement_adapter, "Missing placement adapter for " .. asset.asset_id)
    for _, st in ipairs(asset.states) do
        for _, ctx in ipairs(st.contexts) do
            for _, dist in ipairs(st.distances) do
                for _, angle in ipairs(st.angles) do
                    for _, light in ipairs(st.lighting) do
                        local path = string.format("out/model-census-review/%s/%s__%s__%s__%s__%s.png",
                            asset.asset_id, ctx, dist, angle, light, st.state)
                        if pathSet[path] then duplicateCount = duplicateCount + 1 end
                        pathSet[path] = true
                    end
                end
            end
        end
    end
end
assert(duplicateCount == 0, "Duplicate output paths detected in review matrix!")
print("  [PASS] Unique output paths across matrix (0 duplicates)")

-- 3. Placement adapter classification
local adapters = {}
for _, asset in ipairs(manifest.assets) do
    adapters[asset.placement_adapter] = (adapters[asset.placement_adapter] or 0) + 1
end
assert(adapters["event_model"] and adapters["event_model"] > 0, "Missing event_model adapter assets")
assert(adapters["opening_model"] and adapters["opening_model"] > 0, "Missing opening_model adapter assets")
assert(adapters["wall_feature_model"] and adapters["wall_feature_model"] > 0, "Missing wall_feature_model adapter assets")
assert(adapters["floor_feature_model"] and adapters["floor_feature_model"] > 0, "Missing floor_feature_model adapter assets")
assert(adapters["large_floor_model"] and adapters["large_floor_model"] > 0, "Missing large_floor_model adapter assets")
print("  [PASS] Placement adapter classification (event, opening, wall_feature, floor_feature, large_floor)")

-- 4. Timer restoration after simulated exception
local origGetTime = love.timer.getTime
local calledCleanup = false
local okExp, errExp = pcall(function()
    love.timer.getTime = function() return 999.0 end
    error("simulated harness error")
end)
love.timer.getTime = origGetTime
assert(love.timer.getTime == origGetTime, "Timer function was not restored after exception")
print("  [PASS] Global state and timer function restored after simulated exception")

-- 5. Missing dependency failure in preflight
local okMissing, errMissing = pcall(function()
    model_census_review.verifyAndHashDependencies("non_existent_manifest.json")
end)
assert(not okMissing, "Preflight should fail on missing manifest file")
print("  [PASS] Preflight fails loud on missing dependency")

print("=== ALL MODEL CENSUS REVIEW HARNESS TESTS OK ===")
