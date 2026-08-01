-- How a test suite reports failure.
--
-- Every suite used to end with `error("... tests failed")`, which drops LÖVE
-- into its interactive error screen -- a window that sits there until a HUMAN
-- notices and closes it. Under the CLI runner (and for any agent or CI job
-- driving `lovec . unittest`) that turned a red test into a hang: the failure
-- detail was already printed, but the process refused to end.
--
-- Worse, it stopped the run dead at the FIRST red suite, leaving everything
-- after it unmeasured. That is how a broken early-balance assertion sat
-- unnoticed behind a failing status-infliction suite -- nobody had seen the
-- later suites run at all.
--
-- So a suite records its failure here and returns; main.lua runs the whole
-- list, prints one summary and exits non-zero at the end. No keypress, no
-- hidden suites, and the exit code is still the gate's answer.
local record = {}

local M = setmetatable({}, {
    __call = function(_, suiteName, failed, passed)
        if passed ~= nil then
            print(("=== %s: %d passed, %d failed ==="):format(suiteName, passed, failed))
        end
        if (failed or 0) > 0 then
            print(("FAIL: %s (%s failing)"):format(suiteName, tostring(failed)))
            table.insert(record, { name = suiteName, failed = failed })
        end
    end
})

--- A suite that CRASHED rather than counting a failure (main.lua pcalls each
--- one, so a hard Lua error is caught and recorded instead of reaching LÖVE's
--- error screen).
function M.crashed(suiteName, err)
    print(("CRASH: %s -- %s"):format(suiteName, tostring(err)))
    table.insert(record, { name = suiteName, failed = "crashed" })
end

--- Called by main.lua once every suite has run. Exits the process itself, so
--- no caller can forget to and the exit code always matches what was printed.
function M.finish()
    if io and io.stdout and io.stdout.flush then io.stdout:flush() end
    if #record == 0 then
        print("ALL UNIT TESTS OK")
        if io and io.stdout and io.stdout.flush then io.stdout:flush() end
        os.exit(0)
    end
    print("")
    print(("UNIT TESTS FAILED -- %d suite(s):"):format(#record))
    for _, r in ipairs(record) do
        print(("  - %s (%s)"):format(r.name, tostring(r.failed)))
    end
    if io and io.stdout and io.stdout.flush then io.stdout:flush() end
    os.exit(1)
end

return M
