-- The persistent bottom dock.
--
-- WHY THIS EXISTS (29.07.2026): the bottom strip of the screen — SPEC §1.4's
-- dock — used to be re-declared by every scene that wanted it: five menu
-- scenes each carried their own copy of a `party` window, `map` opened one at
-- runtime through window commands, `dialogue` laid three windows over the same
-- footprint, and frame_renderer drew yet another one for battle. Because
-- scene_host.push builds a fresh state table per scene and the renderer's
-- animation clocks are keyed by the window TABLE, that meant the dock was
-- destroyed and rebuilt on every single scene change: it replayed its 0.24s
-- grow-in each time, and the two band-aids for that (`windowFootprint` /
-- `_seamlessWindowFootprint` in scene_host, `_skipOpenAnim` hardcoded to the
-- map scene in love.update, the 0.15s `dialogueEnterTime` overlap in
-- frame_renderer) each papered over one transition while leaving the rest.
--
-- So the dock is no longer a scene's window. It is one surface, owned here,
-- whose state — window tables, animation clocks, visibility history — lives in
-- module-level `store` and therefore survives push/pop/goto untouched. Scenes
-- only declare WHICH VARIANT they want (`config.dock` in scenes.json); the
-- variants themselves live in `data/engine.json`'s `dock` registry, so adding
-- one is a data edit.
--
-- Transition rules:
--   same variant      -- nothing animates at all. The dock stays put and its
--                        content simply re-binds to the new scene's variables.
--                        (map -> items -> options -> map is now dead silent.)
--   different variant -- cross-fade in place over the shared footprint: the
--                        outgoing variant fades out against the incoming one,
--                        which arrives at rest rather than growing in. This is
--                        the party-status <-> dialogue continuity.
--   -> no dock        -- the outgoing variant plays its ordinary close anim.
--
-- Content still binds to the CURRENT scene: window defs are handed to
-- window_renderer with the live scene's env, so `v.dialogueText` and friends
-- resolve exactly as they did when dialogue owned these windows. The outgoing
-- variant keeps drawing against the departed scene's `v` table (held by
-- reference in `fade.v`) for the length of the cross-fade, so a fading-out
-- dialogue box shows its last line rather than blanking.

local dock = {}

-- Persistent bookkeeping for the live variant (window tables + visibility
-- history). Never cleared on scene change — that is the entire point.
local store = { _dataWins = {}, _visTrack = {} }

-- Currently displayed variant name, and the in-flight cross-fade (if any):
-- { variant, defs, store, v, t0, duration }.
local currentVariant = nil
local fade = nil

-- Last scene state we drew against, so a transition can keep rendering the
-- outgoing variant's content after its scene is gone.
local lastV = nil

local function registry(ctx)
    local engine = ctx and ctx.loader and ctx.loader.engine
    return engine and engine.dock or nil
end

-- scenes.json `config.dock` accepts either a bare variant name or a table of
-- { variant, cursor, visible, windows = { <id> = { <field overrides> } } }.
local function sceneDockConfig(sceneData)
    local cfg = sceneData and sceneData.config and sceneData.config.dock
    if type(cfg) == "string" then return { variant = cfg } end
    if type(cfg) == "table" then return cfg end
    return nil
end

-- Build the window defs for a variant, applying the scene's overrides onto
-- copies so the registry entry itself is never mutated.
local function resolveDefs(reg, cfg)
    local variant = reg.variants and reg.variants[cfg.variant]
    if not variant then
        error("scene declares dock variant '" .. tostring(cfg.variant)
            .. "' which data/engine.json's dock registry does not define", 0)
    end
    local perWindow = cfg.windows or {}
    local out = {}
    for _, def in ipairs(variant.windows or {}) do
        local copy = {}
        for k, val in pairs(def) do copy[k] = val end
        -- Shorthand: bare `cursor` / `visible` on the scene's dock config
        -- apply to the variant's primary window (the one the player drives).
        if variant.primary == copy.id then
            if cfg.cursor ~= nil then copy.cursor = cfg.cursor end
            if cfg.visible ~= nil then copy.visible = cfg.visible end
        end
        for k, val in pairs(perWindow[copy.id] or {}) do copy[k] = val end
        table.insert(out, copy)
    end
    return out
end

function dock.draw(state, sceneData, ctx)
    local reg = registry(ctx)
    if not reg then return end

    local cfg = sceneDockConfig(sceneData)
    local wantVariant = cfg and cfg.variant or nil

    -- Hold the dock's FIRST appearance until the door/world reveal finishes,
    -- so its grow-in doesn't play underneath the blackout (this is what the
    -- old map-specific block in love.update was for). Only the initial open is
    -- gated: a dock already on screen rides through door transitions as before.
    if currentVariant == nil and wantVariant
        and require("presentation.door_transition").isActive() then
        return
    end

    if wantVariant ~= currentVariant then
        local outgoingDefs = nil
        if currentVariant then
            local outgoingCfg = { variant = currentVariant }
            local ok, defs = pcall(resolveDefs, reg, outgoingCfg)
            if ok then outgoingDefs = defs end
        end
        -- Any variant change — swap OR retract to no dock at all — is one
        -- mechanism: the outgoing variant keeps drawing at falling alpha over
        -- the shared footprint. It moves to its own store so the incoming
        -- variant starts clean, and holds the departed scene's `v` so its
        -- content doesn't blank out mid-fade.
        if outgoingDefs then
            fade = {
                defs = outgoingDefs,
                store = store,
                v = lastV,
                t0 = love.timer.getTime(),
                duration = reg.crossfade or 0.18,
            }
            store = { _dataWins = {}, _visTrack = {} }
        else
            fade = nil
        end
        currentVariant = wantVariant
        -- The incoming variant arrives at rest and fades up, rather than
        -- replaying the grow-in on top of a dock that is already there.
        if wantVariant and fade then
            local incoming = resolveDefs(reg, cfg)
            for _, def in ipairs(incoming) do
                store._dataWins[def.id] = { _skipOpenAnim = true }
            end
        end
    end

    -- Optional per-scene vertical offset in pixels, as a formula over the
    -- scene's variables. Battle's defeat sequence slides the dock off the
    -- bottom of the screen with it ("(v.defeatSlideT or 0) * 240"); nothing
    -- else uses it, but it keeps that motion in data rather than in a
    -- battle-shaped branch in the compositor.
    local offsetY = 0
    if cfg and cfg.offsetY and state then
        local ok, val = pcall(require("engine.formula").eval, cfg.offsetY, { v = state.v or {} })
        if ok and type(val) == "number" then offsetY = val end
    end
    local translated = offsetY ~= 0
    if translated then
        love.graphics.push()
        love.graphics.translate(0, offsetY)
    end

    if fade then
        local p = (love.timer.getTime() - fade.t0) / fade.duration
        if p >= 1 then
            fade = nil
        else
            local wr = require("presentation.window_renderer")
            wr.drawWindowFromData(sceneData, { v = fade.v or {} }, ctx, {
                windows = fade.defs,
                store = fade.store,
                alpha = 1 - p,
            })
        end
    end

    if state then lastV = state.v end

    if currentVariant then
        local alpha = nil
        if fade then
            alpha = math.min(1, (love.timer.getTime() - fade.t0) / fade.duration)
        end
        require("presentation.window_renderer").drawWindowFromData(sceneData, state, ctx, {
            windows = resolveDefs(reg, cfg),
            store = store,
            alpha = alpha,
        })
    end

    if translated then love.graphics.pop() end
end

-- The golden/preview harnesses re-enter scenes repeatedly; a dock left over
-- from a previous run must not leak into the next one's first frame.
function dock.reset()
    store = { _dataWins = {}, _visTrack = {} }
    currentVariant = nil
    fade = nil
    lastV = nil
end

-- Which variant is on screen right now (nil = none). For the headless scene
-- preview and tests.
function dock.variant()
    return currentVariant
end

-- Test seams (tests/test_dock.lua). The dock's whole contract is that its
-- state OUTLIVES scenes, and the only honest way to assert that is to look at
-- the persistent tables directly — window-table identity across a scene change
-- IS the animation continuity.
function dock.__store()
    return store
end

function dock.__fading()
    return fade ~= nil
end

return dock
