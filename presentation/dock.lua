-- Persistent N-shell bottom dock.
--
-- Every dock variant speaks the same visual language: an ordered set of
-- windowskin rectangles spanning the bottom footprint. Scene changes clear
-- their content, morph shared rectangles, collapse removed rectangles to zero
-- width, grow added rectangles from zero width, then populate them.
-- The shell geometry is persistent; scene-specific content is data-authored in
-- engine.json dock.variants.<id>.windows.

local ui = require("presentation.ui")
local util = require("presentation.util")

local dock = {}

local store = { _dataWins = {}, _visTrack = {} }
local currentVariant = nil
local currentShells = nil
local transition = nil
local lastV = nil

local function registry(ctx)
    local engine = ctx and ctx.loader and ctx.loader.engine
    return engine and engine.dock or nil
end

local function sceneDockConfig(sceneData)
    local cfg = sceneData and sceneData.config and sceneData.config.dock
    if type(cfg) == "string" then return { variant = cfg } end
    if type(cfg) == "table" then return cfg end
    return nil
end

local function copyRect(rect)
    return { x = rect.x or 0, y = rect.y or 18, w = rect.w or 16, h = rect.h or 12 }
end

local function variantFor(reg, name)
    local variant = name and reg.variants and reg.variants[name]
    if name and not variant then
        error("scene declares dock variant '" .. tostring(name)
            .. "' which data/engine.json's dock registry does not define", 0)
    end
    return variant
end

local function shellsFor(reg, name)
    local variant = variantFor(reg, name)
    if not variant then return nil end
    local shells = variant.shells
    if type(shells) ~= "table" or #shells == 0 then
        error("dock variant '" .. tostring(name)
            .. "' must declare at least one shell", 0)
    end
    local out = {}
    for _, shell in ipairs(shells) do table.insert(out, copyRect(shell)) end
    return out
end

local function resolveDefs(reg, cfg)
    cfg = cfg or {}
    local variant = variantFor(reg, cfg.variant)
    -- No variant named at all is "this scene has no dock", which is a normal
    -- state, not an error -- variantFor already raises for a name the registry
    -- does not define, which is the case worth failing on.
    if not variant then return {} end
    local perWindow = cfg.windows or {}
    local out = {}
    for _, def in ipairs(variant.windows or {}) do
        local copy = {}
        for k, val in pairs(def) do copy[k] = val end
        if variant.primary == copy.id then
            if cfg.cursor ~= nil then copy.cursor = cfg.cursor end
            if cfg.visible ~= nil then copy.visible = cfg.visible end
        end
        for k, val in pairs(perWindow[copy.id] or {}) do copy[k] = val end
        table.insert(out, copy)
    end
    return out
end

local function drawShells(shells)
    if not shells then return end
    for _, rect in ipairs(shells) do
        local w, h = ui.toPx(rect.w), ui.toPx(rect.h)
        -- A windowskin needs room for its two 8px borders. During a collapse
        -- either dimension legitimately passes through zero; do not feed that
        -- transient geometry to LÖVE's scissor API.
        if w >= 16 and h >= 16 then
            ui.drawPanel(ui.toPx(rect.x), ui.toPx(rect.y), w, h)
        end
    end
end

local function interpolateShells(from, to, p)
    local eased = util.easeOut(p)
    local out = {}
    for i = 1, math.max(#from, #to) do
        local a, b = from[i], to[i]
        if not a then
            b = copyRect(b)
            a = { x = b.x + b.w / 2, y = b.y, w = 0, h = b.h }
        elseif not b then
            a = copyRect(a)
            b = { x = a.x + a.w / 2, y = a.y, w = 0, h = a.h }
        end
        out[i] = {
            x = a.x + (b.x - a.x) * eased,
            y = a.y + (b.y - a.y) * eased,
            w = a.w + (b.w - a.w) * eased,
            h = a.h + (b.h - a.h) * eased,
        }
    end
    return out
end

local function beginTransition(reg, wantVariant)
    local target = wantVariant and shellsFor(reg, wantVariant) or nil
    if not currentVariant then
        -- The first dock appearing over a scene has no predecessor geometry.
        -- Grow each shell from its centre in both axes. Added shells during an
        -- ordinary dock-to-dock morph still grow horizontally only.
        local source = {}
        for i, shell in ipairs(target or {}) do
            source[i] = {
                x = shell.x + shell.w / 2,
                y = shell.y + shell.h / 2,
                w = 0,
                h = 0,
            }
        end
        transition = {
            from = source,
            to = target or {},
            targetVariant = wantVariant,
            started = love.timer.getTime(),
            clearDuration = 0,
            morphDuration = (reg.transition and reg.transition.morphDuration) or 0.16,
        }
        store = { _dataWins = {}, _visTrack = {} }
        return
    end

    local source = currentShells or shellsFor(reg, currentVariant)
    -- No dock destination: collapse every shell into its centre in both axes.
    if not target then
        target = {}
        for i, shell in ipairs(source) do
            target[i] = {
                x = shell.x + shell.w / 2,
                y = shell.y + shell.h / 2,
                w = 0,
                h = 0,
            }
        end
    end
    transition = {
        from = source,
        to = target,
        targetVariant = wantVariant,
        started = love.timer.getTime(),
        clearDuration = (reg.transition and reg.transition.clearDuration) or 0.08,
        morphDuration = (reg.transition and reg.transition.morphDuration) or 0.16,
    }
    -- Destination content gets a clean cache and remains absent until morphing
    -- finishes. The shells themselves are drawn directly throughout.
    --
    -- The outgoing variant's cache is handed to the transition rather than
    -- dropped: under `staticShell` the shell no longer animates, so the clear
    -- phase is where the OUTGOING content plays its close animation, and
    -- window_renderer can only run one for a window it already has a
    -- `_dataWins` entry for. Without this the party slots simply blinked out
    -- on the way to a variant that has no slots.
    transition.fromVariant = currentVariant
    transition.fromStore = store

    -- A window the incoming variant ALSO has is not opening -- it is simply
    -- still there. The party slots survive map -> items and exploration ->
    -- battle, so wiping the whole cache made them replay their open animation
    -- on every variant change for no reason. Carry those entries over; only
    -- genuinely new windows start fresh, and only genuinely departing ones
    -- close (below).
    local carried = { _dataWins = {}, _visTrack = {} }
    local incoming = {}
    -- No destination variant (the dock is going away entirely): nothing
    -- persists, so every window closes.
    if wantVariant then
        for _, def in ipairs(resolveDefs(reg, { variant = wantVariant })) do
            incoming[def.id] = true
        end
    end
    for id, win in pairs(store._dataWins or {}) do
        if incoming[id] then carried._dataWins[id] = win end
    end
    for id, vis in pairs(store._visTrack or {}) do
        if incoming[id] then carried._visTrack[id] = vis end
    end
    transition.persisting = incoming
    store = carried
end

function dock.draw(state, sceneData, ctx)
    local reg = registry(ctx)
    if not reg then return end
    local cfg = sceneDockConfig(sceneData)
    local wantVariant = cfg and cfg.variant or nil

    if currentVariant == nil and wantVariant
        and require("presentation.door_transition").isActive() then
        return
    end
    if wantVariant ~= currentVariant
        and (not transition or transition.targetVariant ~= wantVariant) then
        beginTransition(reg, wantVariant)
    end
    if state and state.v then
        state.v._dockContentReady = transition == nil and currentVariant == wantVariant
    end

    local offsetY = 0
    if cfg and cfg.offsetY and state then
        local ok, value = pcall(require("engine.formula").eval,
            cfg.offsetY, { v = state.v or {} })
        if ok and type(value) == "number" then offsetY = value end
    end
    if offsetY ~= 0 then
        love.graphics.push()
        love.graphics.translate(0, offsetY)
    end

    -- `staticShell` (engine.json dock registry): one windowskin spanning the
    -- whole footprint, drawn once and never animated, with every variant's
    -- content composited on top of it. Two things motivate it, both from the
    -- windowskin going semitransparent: per-variant shells that morph made the
    -- dock's outline move against a world now visible through it, and any two
    -- panels sharing a rect (dialogue_message and dialogue_choices do exactly
    -- that) stacked two translucent skins and read twice as dark.
    -- Variant content windows carry `chrome: "none"` so nothing draws a second
    -- skin inside this one.
    local staticShell = reg.staticShell and (currentVariant or transition)
    if staticShell then
        drawShells({ copyRect(reg.footprint or { x = 0, y = 18, w = 32, h = 12 }) })
    end

    -- Windows the outgoing and incoming variants share keep drawing right
    -- through the transition, from the carried-over cache, so they neither
    -- animate nor blink. Without this the party slots vanished for the
    -- clear+morph duration on every dock change and popped back.
    -- Only when there IS a destination variant. Leaving the dock entirely
    -- (the status scene declares no dock at all) means nothing persists, and
    -- asking for the defs of a nil variant used to crash here.
    if transition and staticShell and state and cfg and cfg.variant
        and transition.persisting and next(transition.persisting) then
        local persisting = {}
        for _, def in ipairs(resolveDefs(reg, cfg)) do
            if transition.persisting[def.id] then table.insert(persisting, def) end
        end
        if #persisting > 0 then
            require("presentation.window_renderer").drawWindowFromData(
                sceneData, state, ctx, { windows = persisting, store = store })
        end
    end

    if transition then
        local elapsed = love.timer.getTime() - transition.started
        if elapsed >= transition.clearDuration then
            local p = math.min(1,
                (elapsed - transition.clearDuration) / transition.morphDuration)
            if not staticShell then
                drawShells(interpolateShells(transition.from, transition.to, p))
            end
            if p >= 1 then
                currentVariant = transition.targetVariant
                currentShells = currentVariant and transition.to or nil
                transition = nil
                if state and state.v then state.v._dockContentReady = true end
            end
        elseif staticShell then
            -- Clear phase: the outgoing content is still drawn, forced hidden,
            -- so each window runs its own close animation over the static
            -- shell. Anything without an `anim.close` just stops drawing, which
            -- is the previous behaviour.
            if transition.fromVariant and state then
                local closing = {}
                for _, def in ipairs(resolveDefs(reg, { variant = transition.fromVariant })) do
                    -- A window the destination also has is not closing; it is
                    -- carried over untouched and keeps drawing from the new
                    -- store, so animating it out here would be a flicker.
                    if not (transition.persisting or {})[def.id] then
                        def.visible = "false"
                        table.insert(closing, def)
                    end
                end
                if #closing > 0 then
                    require("presentation.window_renderer").drawWindowFromData(
                        sceneData, state, ctx,
                        { windows = closing, store = transition.fromStore })
                end
            end
        else
            drawShells(transition.from)
        end
    elseif currentVariant and state then
        lastV = state.v
        -- Content windows draw their own shell panel at the settled geometry.
        -- There is exactly one visible content layer per shell.
        require("presentation.window_renderer").drawWindowFromData(
            sceneData, state, ctx, {
                windows = resolveDefs(reg, cfg),
                store = store,
            })
    end

    if offsetY ~= 0 then love.graphics.pop() end
end

function dock.reset()
    store = { _dataWins = {}, _visTrack = {} }
    currentVariant = nil
    currentShells = nil
    transition = nil
    lastV = nil
end

function dock.variant()
    return currentVariant
end

function dock.__store()
    return store
end

function dock.__fading()
    return transition ~= nil
end

function dock.__transition()
    return transition
end

-- Deterministic unit-test seam: animation time is visual state, and sleeping
-- inside the unit suite would make it slow and flaky.
function dock.__finishTransition()
    if not transition then return end
    currentVariant = transition.targetVariant
    currentShells = currentVariant and transition.to or nil
    transition = nil
end

return dock
