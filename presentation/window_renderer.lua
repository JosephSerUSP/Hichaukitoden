-- Generic declarative window renderer (D13).
--
-- Draws a scene's runtime window state — built by scene_host from the D2
-- window commands (OPEN_WINDOW, SET_LIST, SET_TEXT, SET_CURSOR, ...) — using
-- engine.json -> windowLayout for geometry and style. There is NO scene-
-- specific code here: content comes from named list sources, {expr} text
-- templates and cursor formulas, all evaluated at draw time so windows stay
-- live as scene variables change.
--
-- A scene opts in with "draw": "windows" in scenes.json; scenes without the
-- flag keep their legacy Lua drawing (SPEC S2 fallback rule).
--
-- List sources (SET_LIST listId):
--   "inventory"        session inventory (fields: id, name, icon, qty, meta)
--   "party"            party members (fields: index, name, level, spriteKey)
--   "config:<key>"     array from the scene's config (entry fields exposed)
--   "v:<key>"          array stored in scene v by hooks/SCRIPT
--   "static:a,b,c"     inline comma-separated labels
--
-- Row templates/formulas (SET_LIST format/highlight/priority) are evaluated
-- with the row's fields merged over the scene env, so "{name} (x{qty})" and
-- "meta.craftKind == config.disciplines[v.selectedDisciplineIdx].kind" work.
-- The scene env also exposes sel("window_id") -> the selected row of another
-- window's list, for detail panels.

local ui = require("presentation.ui")
local formula = require("engine.formula")
local small_battlers = require("presentation.small_battlers")
local actor_status = require("presentation.actor_status")

local wr = {}

local COLOR_SELECTED = { 1, 1, 0.5, 1 }
local COLOR_NORMAL = { 1, 1, 1, 1 }
local COLOR_HIGHLIGHT = { 0.6, 1, 0.6, 1 }
local COLOR_DIM = { 0.6, 0.6, 0.6, 1 }

-- Portrait image cache (love.graphics.newImage per frame is a perf bug the
-- legacy crafting draw had; don't repeat it).
local imageCache = {}
local function getImage(path)
    if imageCache[path] == nil then
        if love.filesystem.getInfo(path) then
            local img = love.graphics.newImage(path)
            img:setFilter("nearest", "nearest")
            imageCache[path] = img
        else
            imageCache[path] = false
        end
    end
    return imageCache[path] or nil
end

-- ---------------------------------------------------------------------------
-- Expression helpers
-- ---------------------------------------------------------------------------

-- Replace every {expr} in template with formula.eval(expr, env).
local function interpolate(template, env)
    if template == nil then return "" end
    return (tostring(template):gsub("{(.-)}", function(expr)
        local val = formula.eval(expr, env)
        if val == nil then return "" end
        return tostring(val)
    end))
end

-- Row-scoped env: row fields shadow the scene env.
local function rowEnv(env, row)
    local e = {}
    for k, v in pairs(env) do e[k] = v end
    if type(row) == "table" then
        for k, v in pairs(row) do e[k] = v end
        e.row = row
    end
    return e
end

-- ---------------------------------------------------------------------------
-- List sources
-- ---------------------------------------------------------------------------

local function inventoryRows(session)
    local rows = {}
    if not session or not session.inventory then return rows end
    for itemId, qty in pairs(session.inventory) do
        if qty > 0 then
            local item = session.loader.getItem(itemId)
            if item then
                table.insert(rows, {
                    id = item.id,
                    name = item.name or "",
                    icon = item.icon or 0,
                    qty = qty,
                    description = item.description or "",
                    meta = item.meta or {},
                })
            end
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

local function partyRows(session)
    local config = require("engine.config")
    local expPerLevel = (config.growth and config.growth.expPerLevel) or 15
    local loader = session and session.loader
    local rows = {}
    for i, m in ipairs(session and session.party or {}) do
        local view = formula.battlerView(m, session) or {}
        view.index = i
        -- Same sheet-key choice as renderer.drawSmallBattlerCell
        view.spriteKey = (m.actorData and (m.actorData.smallBattler or m.actorData.spriteKey)) or m.spriteKey
        -- Portrait art key (assets/portraits), same as the battle renderer
        view.portraitKey = (m.actorData and m.actorData.spriteKey) or m.spriteKey or ""
        view.icon = view.icon or 0
        view.dead = m.isDead and m:isDead() or false
        -- Not read by {expr} templates; lets the row's sprite share the
        -- same battle-triggered flash/shake state small_battlers keys by
        -- battler identity (drawList passes this through as battlerRef).
        view.battlerRef = m
        -- Status-scene fields (generic enrichment of the 'party' source):
        -- progression, role, equipment slots and joined passive/skill/state
        -- names as flat strings so {expr} templates can print them.
        view.exp = m.exp or 0
        view.expNeeded = (m.level or 1) * expPerLevel
        view.role = (m.actorData and m.actorData.role) or "CREATURE"
        view.biography = (m.actorData and m.actorData.flavor) or "No biography available."
        local eq = m.equipment or {}
        view.weapon = eq[1] and eq[1].name or "[ EMPTY ]"
        view.armor = eq[2] and eq[2].name or "[ EMPTY ]"
        view.accessory = eq[3] and eq[3].name or "[ EMPTY ]"
        local function joinNames(ids, getter)
            local names = {}
            for _, id in ipairs(ids or {}) do
                local entry = getter and getter(id)
                table.insert(names, (entry and entry.name) or tostring(id))
            end
            return #names > 0 and table.concat(names, ", ") or "None"
        end
        view.passiveText = joinNames(m.actorData and m.actorData.passives, loader and loader.getPassive)
        view.skillText = joinNames(m.actorData and m.actorData.skills, loader and loader.getSkill)
        local stateNames = {}
        for _, st in ipairs(m.states or {}) do
            local def = loader and loader.getState and loader.getState(st.id)
            table.insert(stateNames, (def and def.name) or tostring(st.id))
        end
        view.stateText = #stateNames > 0 and table.concat(stateNames, ", ") or "Normal"
        table.insert(rows, view)
    end
    return rows
end

local function configRows(sceneData, key)
    local rows = {}
    local arr = (sceneData and sceneData.config or {})[key]
    for i, entry in ipairs(arr or {}) do
        local r = { index = i }
        if type(entry) == "table" then
            for k, v in pairs(entry) do r[k] = v end
        else
            r.name = tostring(entry)
        end
        r.name = r.name or r.label or ""
        table.insert(rows, r)
    end
    return rows
end

local function vRows(state, key)
    local rows = {}
    local arr = state and state.v and state.v[key]
    for i, entry in ipairs(arr or {}) do
        local r = { index = i }
        if type(entry) == "table" then
            for k, v in pairs(entry) do r[k] = v end
        else
            r.name = tostring(entry)
        end
        r.name = r.name or ""
        table.insert(rows, r)
    end
    return rows
end

-- E10: rows from a terms.json list entry (e.g. "term:title.options"), so
-- menu labels stay owner-editable without touching scene data.
local function termRows(loader, path)
    local rows = {}
    local labels = (loader and loader.getTermList) and loader.getTermList(path, {}) or {}
    for _, label in ipairs(labels) do
        table.insert(rows, { name = tostring(label) })
    end
    return rows
end

local function staticRows(spec)
    local rows = {}
    for label in tostring(spec):gmatch("[^,]+") do
        table.insert(rows, { name = label })
    end
    return rows
end

-- Resolve a window's list into rows, applying priority sort and format.
local function resolveRows(win, state, sceneData, ctx, env)
    local src = win.listId or ""
    local rows
    if src == "inventory" then
        rows = inventoryRows(ctx.session)
    elseif src == "party" then
        rows = partyRows(ctx.session)
    elseif src:sub(1, 7) == "config:" then
        rows = configRows(sceneData, src:sub(8))
    elseif src:sub(1, 2) == "v:" then
        rows = vRows(state, src:sub(3))
    elseif src:sub(1, 7) == "static:" then
        rows = staticRows(src:sub(8))
    elseif src:sub(1, 5) == "term:" then
        rows = termRows(ctx.loader or (ctx.session and ctx.session.loader), src:sub(6))
    else
        rows = {}
    end

    -- Stable priority sort: rows whose priority formula is truthy come first.
    if win.priority and win.priority ~= "" then
        local flagged = {}
        for i, r in ipairs(rows) do
            local val = formula.eval(win.priority, rowEnv(env, r))
            flagged[i] = { row = r, pri = (val == true or (tonumber(val) or 0) > 0) and 0 or 1, ord = i }
        end
        table.sort(flagged, function(a, b)
            if a.pri ~= b.pri then return a.pri < b.pri end
            return a.ord < b.ord
        end)
        rows = {}
        for _, f in ipairs(flagged) do table.insert(rows, f.row) end
    end
    return rows
end

-- ---------------------------------------------------------------------------
-- Scene env (draw-time formula context)
-- ---------------------------------------------------------------------------

local function buildEnv(state, sceneData, ctx, listCache)
    local env = {}
    env.v = state.v or {}
    env.config = sceneData and sceneData.config or {}
    if ctx.session then
        env.session = formula.sessionView(ctx.session)
        env.party = formula.groupView(ctx.session.party or {}, ctx.session)
    end
    -- sel("window_id") -> the selected row of that window's list (or nil).
    env.sel = function(winId)
        local cached = listCache[winId]
        if cached then return cached.rows[cached.cursor] end
        return nil
    end
    return env
end

local function liveCursor(win, env)
    if win.cursorFormula and type(win.cursorFormula) == "string" then
        local val = formula.eval(win.cursorFormula, env)
        local n = tonumber(val)
        if n then return math.floor(n) end
    end
    return math.floor(tonumber(win.cursor) or 1)
end

-- ---------------------------------------------------------------------------
-- Widget drawing
-- ---------------------------------------------------------------------------

local function drawTextLines(text, env, x, y, lineSpacing, limit, align)
    local rendered = interpolate(text, env)
    local line = 0
    for chunk in (rendered .. "\n"):gmatch("(.-)\n") do
        if chunk ~= "" then
            ui.drawString(chunk, x, y + line * lineSpacing, COLOR_NORMAL, align or "left", limit)
        end
        line = line + 1
    end
end

-- Layout-authored gauges let a panel present live values without a
-- scene-specific renderer.  Labels support the same {formula} interpolation
-- as ordinary window text; values and maxima are formula expressions.
local function drawLayoutGauges(gauges, env, x, y)
    for _, gauge in ipairs(gauges or {}) do
        local gx = x + ui.toPx(gauge.x or 1)
        local gy = y + ui.toPx(gauge.y or 1)
        local value = tonumber(formula.eval(gauge.value or "0", env)) or 0
        local maximum = tonumber(formula.eval(gauge.max or "1", env)) or 1
        ui.drawString(interpolate(gauge.label or "", env), gx, gy, COLOR_NORMAL)
        ui.drawBar(gx, gy + ui.lineHeight, ui.toPx(gauge.width or 18), gauge.height or 3,
            value, maximum, gauge.color or { 0.5, 0, 0 }, gauge.fill or { 1, 0.3, 0.3 })
    end
end

local function resolvePageLayout(layout, env)
    if not layout.pages then return layout end
    local page = math.floor(tonumber(formula.eval(layout.pageFormula or "1", env)) or 1)
    local pageLayout = layout.pages[page] or layout.pages[1] or {}
    local resolved = {}
    for key, value in pairs(layout) do resolved[key] = value end
    for key, value in pairs(pageLayout) do resolved[key] = value end
    return resolved
end

local function contentOrigin(layout, title, x, y)
    return ui.panelContentOrigin(x, y, title, layout.contentX or layout.textX, layout.contentY)
end

local function drawPortrait(layout, env, x, y, title)
    if not layout.portrait then return end
    local key = formula.eval(layout.portrait, env)
    if type(key) ~= "string" or key == "" then return end
    local img = getImage("assets/portraits/" .. key .. ".png")
    if img then
        love.graphics.setColor(1, 1, 1, 1)
        local contentX, contentY = contentOrigin(layout, title, x, y)
        love.graphics.draw(img, x + ui.toPx(layout.portraitX or 1), layout.portraitY ~= nil and y + ui.toPx(layout.portraitY) or contentY, 0, 1, 1)
    end
end

local function drawList(win, layout, rows, cursor, env, x, y, w, h, title)
    local contentX, contentY = contentOrigin(layout, title, x, y)

    -- Row widgets (vocabulary extension 11.07.2026): win.sprite names a row
    -- field carrying a small-battler sheet key drawn at the row's left;
    -- win.gaugeValue/gaugeMax are row-scoped formulas drawn as a bar under
    -- the text. Both grow the row pitch, which the scroll math follows.
    local spriteField = win.sprite
    local spriteSize = ui.toPx(layout.spriteSize or 3)
    local cardPad = 2 -- inset of a sprite row's own windowskin card
    local hasGauge = win.gaugeValue and win.gaugeValue ~= "" and win.gaugeMax and win.gaugeMax ~= ""
    local rowPitch = ui.lineHeight
    if hasGauge then rowPitch = rowPitch + (layout.gaugeHeight or 3) + 3 end
    if spriteField then rowPitch = math.max(rowPitch, spriteSize + 2) end
    if layout.rowPitch then rowPitch = ui.toPx(layout.rowPitch) end

    local visible = layout.visibleRows or math.max(1, math.floor((h - ui.toPx(3)) / rowPitch))
    if #rows == 0 then
        local emptyText = layout.emptyText or "No entries."
        ui.drawString(emptyText, contentX, contentY, COLOR_DIM)
        return
    end
    local startOffset = math.max(1, math.min(cursor - 3, #rows - visible + 1))
    local endOffset = math.min(#rows, startOffset + visible - 1)
    local format = win.format or "{name}"
    for i = startOffset, endOffset do
        local row = rows[i]
        local rEnv = rowEnv(env, row)
        local isSel = (i == cursor)
        local color = isSel and COLOR_SELECTED or (row.dead and COLOR_DIM or COLOR_NORMAL)
        if not isSel and not row.dead and win.highlight and win.highlight ~= "" then
            local hv = formula.eval(win.highlight, rEnv)
            if hv == true then color = COLOR_HIGHLIGHT end
        end
        local rowY = contentY + (i - startOffset) * rowPitch

        -- A sprite-bearing row is a battler status cell: give it its own
        -- windowskin card, same treatment the battle/map HUD gives each
        -- party slot (owner direction 11.07.2026 — one shared look for
        -- party status everywhere it's drawn).
        if spriteField then
            ui.drawPanel(x + cardPad, rowY - cardPad, w - cardPad * 2, rowPitch - cardPad)
        end

        local textX = contentX + ui.toPx(0.5)
        ui.drawString(isSel and ">" or " ", contentX, rowY, color)
        if spriteField then
            local key = row[spriteField]
            if key and key ~= "" and small_battlers.draw(key, x + ui.toPx(1), rowY - 2, spriteSize, row.dead, row.battlerRef) then
            textX = contentX + ui.toPx(0.5) + spriteSize + 3
            end
        end
        if row.icon and row.icon > 0 then
            ui.drawIcon(row.icon, textX + ui.toPx(0.5), rowY - 2)
            textX = textX + ui.toPx(2.5)
        end
        ui.drawString(interpolate(format, rEnv), textX, rowY, color)
        if hasGauge then
            local val = tonumber(formula.eval(win.gaugeValue, rEnv)) or 0
            local max = tonumber(formula.eval(win.gaugeMax, rEnv)) or 1
            local barX = textX
            -- Stay inside the row's own card (not the whole window) when
            -- one is drawn, so the bar never bleeds past its border.
            local rightEdge = spriteField and (x + w - cardPad * 2) or (x + w - ui.toPx(1))
            local barW = math.max(8, rightEdge - barX)
            ui.drawBar(barX, rowY + ui.lineHeight + 1, barW, layout.gaugeHeight or 3,
                val, max,
                win.gaugeColor or { 0.8, 0, 0 }, win.gaugeFill or { 1, 0.3, 0.3 })
        end
    end
end

-- "partyGrid" style (owner direction 11.07.2026): arranges one
-- actor_status.draw cell per row, wrapped into a grid (layout.gridColumns,
-- default 2 — reproduces the battle/map HUD's 2x2 for a 4-member party).
-- Rows come from the SAME 'party' list source as the old sprite+gauge list
-- rows, but here each one draws through the exact function
-- renderer.drawPartyGrid uses, via row.battlerRef (the real battler object
-- partyRows keeps a reference to) — so a party member's status is one
-- single thing, not a re-implementation per screen.
local function drawPartyGridStyle(layout, rows, cursor, env, x, y, session, title)
    local colW, rowH = actor_status.cellSize(session)
    local cols = layout.gridColumns or 2
    local contentX, contentY = contentOrigin(layout, title, x, y)
    for i, row in ipairs(rows) do
        if row.battlerRef then
            local col = (i - 1) % cols
            local rowIdx = math.floor((i - 1) / cols)
            local cx = contentX + col * colW
            local cy = contentY + rowIdx * rowH
            actor_status.draw(row.battlerRef, cx, cy, i == cursor, session)
        end
    end
end

-- Horizontal option row (confirm style): options spread across the width.
local function drawOptions(rows, cursor, env, x, y, w)
    local n = #rows
    if n == 0 then return end
    local slot = w / n
    for i, row in ipairs(rows) do
        local isSel = (i == cursor)
        local color = isSel and COLOR_SELECTED or COLOR_NORMAL
        local label = (isSel and "> " or "  ") .. (row.name or "")
        ui.drawString(label, x + math.floor((i - 1) * slot) + ui.toPx(2), y, color)
    end
end

local function drawRoulette(win, layout, rows, cursor, env, x, y, w, h, title)
    if #rows == 0 or cursor < 1 or cursor > #rows then return end
    local row = rows[cursor]
    local cx = x + w / 2
    local _, contentY = contentOrigin(layout, title, x, y)
    local iconY = contentY + ui.toPx(1)
    love.graphics.setColor(1, 1, 0.5, 0.5 + 0.5 * math.sin(love.timer.getTime() * 15))
    love.graphics.rectangle("line", cx - ui.iconSize / 2 - 4, iconY - 4, ui.iconSize + 8, ui.iconSize + 8)
    love.graphics.setColor(1, 1, 1, 1)
    if row.icon and row.icon > 0 then
        ui.drawIcon(row.icon, cx - ui.iconSize / 2, iconY)
    end
    ui.drawString(row.name or "", x, contentY + ui.toPx(4.5), COLOR_SELECTED, "center", w)
end

local function drawWindow(id, win, layout, state, sceneData, ctx, env, listCache)
    layout = resolvePageLayout(layout, env)
    local x, y = ui.toPx(layout.x or 0), ui.toPx(layout.y or 0)
    local w, h = ui.toPx(layout.width or 8), ui.toPx(layout.height or 4)
    local style = layout.style or "panel"
    local title = layout.title
    if title then title = interpolate(title, env) end

    ui.drawPanel(x, y, w, h, title)

    local contentX, contentY = contentOrigin(layout, title, x, y)
    local lineSpacing = ui.toPx(layout.lineSpacing or 2)

    drawPortrait(layout, env, x, y, title)
    drawLayoutGauges(layout.gauges, env, x, y)

    local text = layout.text ~= nil and layout.text or win.text

    if style == "list" then
        local cached = listCache[id]
        if cached then
            drawList(win, layout, cached.rows, cached.cursor, env, x, y, w, h, title)
        end
        if text then
            drawTextLines(text, env, contentX, contentY, lineSpacing, w - ui.toPx(2))
        end
    elseif style == "confirm" then
        if text then
            drawTextLines(text, env, x + ui.toPx(2), contentY, lineSpacing, w - ui.toPx(4))
        end
        local cached = listCache[id]
        if cached then
            drawOptions(cached.rows, cached.cursor, env, x, y + h - ui.toPx(2.5), w)
        end
    elseif style == "roulette" then
        local cached = listCache[id]
        if cached then
            drawRoulette(win, layout, cached.rows, cached.cursor, env, x, y, w, h, title)
        end
    elseif style == "partyGrid" then
        local cached = listCache[id]
        if cached then
            drawPartyGridStyle(layout, cached.rows, cached.cursor, env, x, y, ctx.session, title)
        end
    else -- "panel", "frame" and any unknown style: text content
        if text then
            local align = (style == "frame") and "center" or "left"
            local tx = (style == "frame") and x or contentX
            drawTextLines(text, env, tx, contentY, lineSpacing, w - ui.toPx(1), align)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Entry point: draw all open windows of the scene state, in open order.
-- ---------------------------------------------------------------------------
function wr.draw(state, sceneData, ctx)
    if not state or not state.winState then return end

    -- Resolve every open window's list once per frame (cursor + rows), so
    -- sel() lookups and the draw loop share one resolution.
    local listCache = {}
    local env = buildEnv(state, sceneData, ctx, listCache)
    for _, id in ipairs(state.windowOrder or {}) do
        local win = state.winState[id]
        if win and win.open and win.listId then
            listCache[id] = {
                rows = resolveRows(win, state, sceneData, ctx, env),
                cursor = 1,
            }
        end
    end
    for id, cached in pairs(listCache) do
        cached.cursor = liveCursor(state.winState[id], env)
    end

    for _, id in ipairs(state.windowOrder or {}) do
        local win = state.winState[id]
        if win and win.open then
            local layouts = (ctx.loader and ctx.loader.engine and ctx.loader.engine.windowLayout) or {}
            drawWindow(id, win, layouts[id] or {}, state, sceneData, ctx, env, listCache)
        end
    end
end

-- ---------------------------------------------------------------------------
-- E5: materialize the current window state as plain data for the headless
-- scene preview (`lovec . preview-scene <id>`). Same resolution code paths
-- as wr.draw — list sources expanded to formatted row strings, {expr} text
-- interpolated, live cursor evaluated — but no drawing. Per-window failures
-- become an `error` field on that window instead of crashing the preview.
-- ---------------------------------------------------------------------------
function wr.resolveState(state, sceneData, ctx)
    local result = {
        tileSize = ui.tileSize,
        focused = state and state.focusedWindow or nil,
        windows = {},
    }
    if not state or not state.winState then return result end

    local listCache = {}
    local env = buildEnv(state, sceneData, ctx, listCache)
    for _, id in ipairs(state.windowOrder or {}) do
        local win = state.winState[id]
        if win and win.open and win.listId then
            local ok, rows = pcall(resolveRows, win, state, sceneData, ctx, env)
            local entry = { rows = {}, cursor = 1 }
            if ok then entry.rows = rows else entry.error = tostring(rows) end
            listCache[id] = entry
        end
    end
    for id, cached in pairs(listCache) do
        local ok, cur = pcall(liveCursor, state.winState[id], env)
        cached.cursor = ok and cur or 1
    end

    local layouts = (ctx.loader and ctx.loader.engine and ctx.loader.engine.windowLayout) or {}
    for _, id in ipairs(state.windowOrder or {}) do
        local win = state.winState[id]
        if win then
            local layout = resolvePageLayout(layouts[id] or {}, env)
            local entry = {
                id = id,
                open = win.open == true,
                hasLayout = layouts[id] ~= nil,
                x = layout.x or 0,
                y = layout.y or 0,
                width = layout.width or 8,
                height = layout.height or 4,
                style = layout.style or "panel",
                listId = win.listId,
            }
            local okT, title = pcall(interpolate, layout.title, env)
            if layout.title ~= nil then entry.title = okT and title or ("<error: " .. tostring(title) .. ">") end
            local windowText = layout.text ~= nil and layout.text or win.text
            if windowText ~= nil then
                local okX, text = pcall(interpolate, windowText, env)
                entry.text = okX and text or nil
                if not okX then entry.error = tostring(text) end
            end
            local cached = listCache[id]
            if cached then
                entry.cursor = cached.cursor
                if cached.error then entry.error = cached.error end
                entry.rows = {}
                local format = win.format or "{name}"
                for _, row in ipairs(cached.rows) do
                    local rEnv = rowEnv(env, row)
                    local okR, textR = pcall(interpolate, format, rEnv)
                    local highlighted = false
                    if win.highlight and win.highlight ~= "" then
                        local okH, hv = pcall(formula.eval, win.highlight, rEnv)
                        highlighted = okH and hv == true
                    end
                    table.insert(entry.rows, {
                        text = okR and textR or ("<error: " .. tostring(textR) .. ">"),
                        highlighted = highlighted,
                        icon = row.icon or 0,
                    })
                end
            end
            table.insert(result.windows, entry)
        end
    end
    return result
end

return wr
