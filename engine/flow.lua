-- Phase flows per SPEC S4 (docs/plans/overhaul-3): data/flows.json maps
-- scene phases ("battle.victory", "exploration.step", ...) to command lists
-- executed in immediate mode by engine/interpreter.lua.
--
-- ctx shape (passed straight to interpreter.runImmediate):
--   session (required), loader, battle, party, enemies,
--   a/b/target/enemy/ally battler refs, v (flow-locals).
--
-- Fallback rule: a phase absent from flows.json runs the legacy Lua block —
-- hosts guard conversions with `if flow.has(phase)` so every conversion is
-- independently shippable and revertable.
--
-- A future host (e.g. a menu scene) declares phases by simply adding a new
-- top-level object to flows.json ("menu": { "open": [...] }) and calling
-- flow.run("menu.open", ctx) at the right moment; no registration step.
local interpreter = require("engine.interpreter")

local flow = {}

local function lookup(loader, phase)
    local flows = loader and loader.flows
    if not flows then return nil end
    local host, name = phase:match("^([^%.]+)%.(.+)$")
    if not host then return nil end
    local hostFlows = flows[host]
    local commands = hostFlows and hostFlows[name]
    if type(commands) == "table" and #commands > 0 then
        return commands
    end
    return nil
end

-- True when flows.json defines a non-empty command list for the phase.
function flow.has(phase, loader)
    local l = loader or (package.loaded["data.loader"])
    return lookup(l, phase) ~= nil
end

-- Runs the phase's command list in immediate mode; returns events[] (empty
-- when the phase is not defined — callers pair this with flow.has).
function flow.run(phase, ctx)
    local loader = ctx.loader or (ctx.session and ctx.session.loader)
    local commands = lookup(loader, phase)
    if not commands then return {} end
    return interpreter.runImmediate(commands, ctx)
end

return flow
