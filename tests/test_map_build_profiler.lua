local profiler = require("engine.map_build_profiler")

profiler.begin({ mapId = 8, density = 1.0 })
local cpu = profiler.span("cpu.stage", "cpu")
for _ = 1, 1000 do local _x = 1 + 1 end
cpu()
local graphics = profiler.span("graphics.stage", "graphics")
graphics()
profiler.add("cache.hits", 2)
profiler.cache("geometry", true)
profiler.cache("geometry", false)

local snap = profiler.snapshot({ marker = "ok" })
assert(snap.metadata.mapId == 8)
assert(snap.marker == "ok")
assert(snap.stages["cpu.stage"].calls == 1)
assert(snap.stages["cpu.stage"].totalMs >= 0)
assert(snap.stages["graphics.stage"].bucket == "graphics")
assert(snap.counters["cache.hits"] == 2)
assert(snap.counters["geometry.hits"] == 1)
assert(snap.counters["geometry.misses"] == 1)
assert(snap.cpuObservedMs >= 0)
assert(snap.graphicsObservedMs >= 0)
assert(snap.cpuScalingProjection["1.5x"].projectedObservedMs
    == snap.cpuObservedMs * 1.5 + snap.graphicsObservedMs)

profiler.stop()
local noop = profiler.span("after.stop", "cpu")
noop()
local stopped = profiler.snapshot()
assert(stopped.stages["after.stop"] == nil)

print("test_map_build_profiler: OK")
