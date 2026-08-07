-- tests/test_model_census_review.lua
-- Pure/seam-level gates for the model-census review harness v2.

local review = require("engine.model_census_review")

print("=== TEST MODEL CENSUS REVIEW HARNESS V2 ===")

local manifest, _, verifiedCount, accounting = review.verifyAndHashDependencies("tools/asset-production/review_manifest.json")
assert(manifest.manifestVersion == "2.0.0", "expected v2 review manifest")
assert(#manifest.assets == 16, "expected 16 concepts")
assert(verifiedCount == 25, "expected 25 materialized state products")
assert(accounting.full == 900, "expected original full matrix of 900")
assert(accounting.required == 600, "expected 600 required visual captures after structured context exclusion")
assert(accounting.skipped == 300, "expected 300 structured functional-context exclusions")
assert(accounting.skipped_by_rule.functional_context_superseded_by_adapter_smoke_gate == 300,
    "functional skip rule should own all 300 exclusions")
print("  [PASS] manifest + structured matrix accounting: 900 = 600 required + 300 skipped")

-- Opening fixtures must exercise the production grid path, never a synthetic
-- session.openingCells side-channel.
local opening = review.buildReviewFixture("opening_model", "dummy.obj", true)
assert(opening.grid[opening.anchor_grid_y][opening.anchor_grid_x] == "o", "opening adapter must author grid value 'o'")
assert(opening.grid[opening.anchor_grid_y][opening.anchor_grid_x - 1] == "#", "opening fixture needs west wall")
assert(opening.grid[opening.anchor_grid_y][opening.anchor_grid_x + 1] == "#", "opening fixture needs east wall")
assert(opening.generatedFeatures[1] == nil, "opening adapter should not masquerade as generated feature")
print("  [PASS] opening_model uses real grid opening semantics")

local floor = review.buildReviewFixture("floor_feature_model", "dummy.obj", true)
assert(floor.generatedFeatures[1] and floor.generatedFeatures[1].material == "census_review_feature",
    "floor feature must use generatedFeatures.material lookup")
assert(floor.featureSpec and floor.featureSpec.role == "floor_feature", "floor feature role mismatch")
assert(floor.featureSpec.model == "dummy.obj", "floor feature must route OBJ through model field")
print("  [PASS] floor_feature_model uses production material lookup")

local wall = review.buildReviewFixture("wall_feature_model", "dummy.obj", true)
assert(wall.grid[wall.anchor_grid_y][wall.anchor_grid_x] == "#", "wall feature must live on an actual wall cell")
assert(wall.grid[wall.anchor_grid_y + 1][wall.anchor_grid_x] == ".", "wall feature south face must be exposed to camera")
assert(wall.generatedFeatures[1] and wall.generatedFeatures[1].material == "census_review_feature",
    "wall feature must use generatedFeatures.material lookup")
assert(wall.featureSpec and wall.featureSpec.role == "wall_feature", "wall feature role mismatch")
print("  [PASS] wall_feature_model is attached to a real visible wall face")

local eventFixture = review.buildReviewFixture("event_model", "dummy.obj", true)
assert(eventFixture.events[1] and eventFixture.events[1].model == "dummy.obj", "event_model must use currentMapData.events[].model")
local largeFixture = review.buildReviewFixture("large_floor_model", "dummy.obj", true)
assert(largeFixture.events[1] and largeFixture.events[1].model == "dummy.obj", "large_floor_model must use production event-model path")
print("  [PASS] event and large-floor model adapters use model events")

-- Oblique view must orbit around the target rather than merely turning away.
local frontal = review.buildCameraFixture(7.5, 6.5, "one_cell", "frontal", 1.0)
local oblique = review.buildCameraFixture(7.5, 6.5, "one_cell", "oblique", 1.0)
assert(frontal.targetX == oblique.targetX and frontal.targetY == oblique.targetY, "frontal/oblique target must be identical")
assert(oblique.playerX < oblique.targetX and oblique.playerY > oblique.targetY,
    "oblique camera should sit southwest of target for halfway N->E turn")
assert(oblique.transitionDir == "turn_right" and oblique.transitionTimer == 0.5, "oblique view must use real turn interpolation")
assert(oblique.effectiveYawDeg == 45.0, "oblique effective yaw should be 45 degrees")
print("  [PASS] oblique camera orbits target while using production turn interpolation")

-- Paired states compare identical camera/geometry signatures; model path is
-- deliberately not part of this signature.
local sigA = review.cameraSignature(oblique, "neutral", "normal", "fixture")
local sigB = review.cameraSignature(oblique, "neutral", "normal", "fixture")
assert(sigA == sigB, "paired camera signature must be stable")
print("  [PASS] paired-state camera signature stability")

local ruleId = review.skipReason(manifest, {
    asset_id = manifest.assets[1].asset_id,
    state = manifest.assets[1].states[1].state,
    context = "functional",
    distance = "one_cell",
    angle = "frontal",
    lighting = "normal",
})
assert(ruleId == "functional_context_superseded_by_adapter_smoke_gate", "functional context should be explicitly skipped")
print("  [PASS] structured skip rule matching")

-- Timer restoration is tested through the actual helper, including exception path.
local originalGetTime = love.timer.getTime
local okFrozen, errFrozen = pcall(function()
    review.withFrozenTime(function()
        assert(love.timer.getTime() == 0.0, "time was not frozen")
        error("simulated capture failure")
    end)
end)
assert(not okFrozen and tostring(errFrozen):find("simulated capture failure", 1, true), "frozen-time helper should rethrow failure")
assert(love.timer.getTime == originalGetTime, "timer function must restore after capture failure")
print("  [PASS] frozen timer restores on exception")

local okMissing = pcall(function()
    review.verifyAndHashDependencies("definitely-not-a-review-manifest.json")
end)
assert(not okMissing, "preflight must fail on missing manifest")
print("  [PASS] missing preflight dependency fails loudly")

print("=== ALL MODEL CENSUS REVIEW HARNESS V2 TESTS OK ===")
