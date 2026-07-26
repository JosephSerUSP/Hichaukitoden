-- Phase flows per SPEC S4 (docs/archive/plans/overhaul-3): data/flows.json maps
-- scene phases ("battle.victory", "exploration.step", ...) to command lists
-- executed in immediate mode by engine/interpreter.lua.
--
-- ctx shape (passed straight to interpreter.runImmediate):
--   session (required), loader, battle, party, enemies,
--   a/b/target/enemy/ally battler refs, v (flow-locals).
--
-- EVERY host calls flow.run(phase, ctx) unconditionally. flows.json is the
-- only source of phase logic, and the validator requires each phase a host
-- depends on to exist, so there is nothing to fall back to and no reason to
-- ask first.
--
-- The battle hosts used to guard their calls with `if flow.has(phase) then ...
-- else <legacy Lua> end`, keeping a second implementation alive behind each
-- one. All three were deleted on 26.07.2026 (round_end, flee_attempt,
-- battle_start); the round-end pair had already drifted apart. `flow.has` now
-- has exactly one caller, the validator's required-phase check, which is the
-- job it should have had all along: proving a phase exists, not choosing
-- whether to use it.
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

-- Runs the phase's command list in immediate mode; returns events[]. An
-- undefined phase yields no events rather than raising, which is why the
-- validator gates the required ones: a host whose phase went missing would
-- otherwise do nothing, quietly.
function flow.run(phase, ctx)
    local loader = ctx.loader or (ctx.session and ctx.session.loader)
    local commands = lookup(loader, phase)
    if not commands then return {} end
    return interpreter.runImmediate(commands, ctx)
end

return flow
