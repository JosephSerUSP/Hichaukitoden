-- Unit tests for reachability analysis helpers (engine/reachability.lua)
local reachability = require("engine.reachability")

local function runTests()
    local mockLoader = {
        actors = {
            { id = 1, name = "Starter", initialParty = true },
            { id = 16, name = "Phoenix" },
            { id = 61, name = "Moa" },
            { id = 999, name = "Unreachable Dummy" },
        },
        system = {
            newGame = {
                party = {
                    fixedMembers = {
                        { id = 61, level = 3, name = "Saban" }
                    }
                }
            }
        },
        maps = {},
        items = {},
        getActor = function(id)
            for _, a in ipairs({
                { id = 1, name = "Starter" },
                { id = 16, name = "Phoenix" },
                { id = 61, name = "Moa" },
                { id = 999, name = "Unreachable Dummy" },
            }) do
                if a.id == id then return a end
            end
            return nil
        end
    }

    -- 1. Fixed starting member is reachable
    local sources = reachability.collectActorSources(mockLoader)
    assert(sources["61"] ~= nil, "Actor 61 (fixed member) must be reachable")
    assert(sources["61"]["initial party (fixed)"] == true, "Actor 61 must have 'initial party (fixed)' source")

    -- 2. Authored individual name does not change species reachability
    mockLoader.system.newGame.party.fixedMembers[1].name = "RenamedSaban"
    local sourcesRenamed = reachability.collectActorSources(mockLoader)
    assert(sourcesRenamed["61"] ~= nil, "Renaming fixed member must not alter species reachability")
    assert(sourcesRenamed["61"]["initial party (fixed)"] == true, "Renamed fixed member must retain source")

    -- 3. Actor with no producer and no fixedMembers entry remains unreachable
    assert(sources["999"] == nil, "Actor 999 with no producer or fixedMembers entry must be unreachable")
    assert(sources["16"] == nil, "Actor 16 with no producer or fixedMembers entry must be unreachable")

    -- 4. Malformed/nonexistent fixedMember ID is ignored (mirroring newgame.rollMembers)
    mockLoader.system.newGame.party.fixedMembers = {
        { id = 8888, level = 1, name = "Ghost" }
    }
    local sourcesNonexistent = reachability.collectActorSources(mockLoader)
    assert(sourcesNonexistent["8888"] == nil, "Nonexistent actor ID in fixedMembers must be ignored")

    print("[test_reachability] ALL REACHABILITY TESTS OK")
end

runTests()
