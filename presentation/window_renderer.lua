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
                    meta = item.meta or {},
                })
            end
        end
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

local function partyRows(session)
    local rows = {}
    for i, m in ipairs(session and session.party or {}) do
        local view = formula.battlerView(m, session) or {}
        view.index = i
        view.spriteKey = m.actorData and m.actorData.spriteKey or nil
        view.icon = view.icon or 0
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

local function drawPortrait(layout, env, x, y)
    if not layout.portrait then return end
    local key = formula.eval(layout.portrait, env)
    if type(key) ~= "string" or key == "" then return end
    local img = getImage("assets/portraits/" .. key .. ".png")
    if img then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(img, x + ui.toPx(layout.portraitX or 1), y + ui.toPx(layout.portraitY or 2), 0, 1, 1)
    end
end

local function drawList(win, layout, rows, cursor, env, x, y, w, h)
    local contentY = y + ui.toPx(layout.contentY or 2)
    local visible = layout.visibleRows or math.max(1, math.floor((h - ui.toPx(3)) / ui.lineHeight))
    if #rows == 0 then
        local emptyText = layout.emptyText or "No entries."
        ui.drawString(emptyText, x + ui.toPx(0.5), contentY, COLOR_DIM)
        return
    end
    local startOffset = math.max(1, math.min(cursor - 3, #rows - visible + 1))
    local endOffset = math.min(#rows, startOffset + visible - 1)
    local format = win.format or "{name}"
    for i = startOffset, endOffset do
        local row = rows[i]
        local isSel = (i == cursor)
        local color = isSel and COLOR_SELECTED or COLOR_NORMAL
        if not isSel and win.highlight and win.highlight ~= "" then
            local hv = formula.eval(win.highlight, rowEnv(env, row))
            if hv == true then color = COLOR_HIGHLIGHT end
        end
        local rowY = contentY + (i - startOffset) * ui.lineHeight
        local textX = x + ui.toPx(1)
        ui.drawString(isSel and ">" or " ", x + ui.toPx(0.5), rowY, color)
        if row.icon and row.icon > 0 then
            ui.drawIcon(row.icon, x + ui.toPx(1.5), rowY - 2)
            textX = x + ui.toPx(3.5)
        end
        ui.drawString(interpolate(format, rowEnv(env, row)), textX, rowY, color)
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

local function drawRoulette(win, layout, rows, cursor, env, x, y, w, h)
    if #rows == 0 or cursor < 1 or cursor > #rows then return end
    local row = rows[cursor]
    local cx = x + w / 2
    local iconY = y + ui.toPx(3)
    love.graphics.setColor(1, 1, 0.5, 0.5 + 0.5 * math.sin(love.timer.getTime() * 15))
    love.graphics.rectangle("line", cx - ui.iconSize / 2 - 4, iconY - 4, ui.iconSize + 8, ui.iconSize + 8)
    love.graphics.setColor(1, 1, 1, 1)
    if row.icon and row.icon > 0 then
        ui.drawIcon(row.icon, cx - ui.iconSize / 2, iconY)
    end
    ui.drawString(row.name or "", x, y + ui.toPx(6.5), COLOR_SELECTED, "center", w)
end

local function drawWindow(id, win, layout, state, sceneData, ctx, env, listCache)
    local x, y = ui.toPx(layout.x or 0), ui.toPx(layout.y or 0)
    local w, h = ui.toPx(layout.width or 8), ui.toPx(layout.height or 4)
    local style = layout.style or "panel"
    local title = layout.title
    if title then title = interpolate(title, env) end

    ui.drawPanel(x, y, w, h, title)

    local contentY = y + ui.toPx(layout.contentY or 2)
    local lineSpacing = ui.toPx(layout.lineSpacing or 2)

    drawPortrait(layout, env, x, y)

    if style == "list" then
        local cached = listCache[id]
        if cached then
            drawList(win, layout, cached.rows, cached.cursor, env, x, y, w, h)
        end
        if win.text then
            drawTextLines(win.text, env, x + ui.toPx(0.5), contentY, lineSpacing, w - ui.toPx(1))
        end
    elseif style == "confirm" then
        if win.text then
            drawTextLines(win.text, env, x + ui.toPx(2), contentY, lineSpacing, w - ui.toPx(4))
        end
        local cached = listCache[id]
        if cached then
            drawOptions(cached.rows, cached.cursor, env, x, y + h - ui.toPx(2.5), w)
        end
    elseif style == "roulette" then
        local cached = listCache[id]
        if cached then
            drawRoulette(win, layout, cached.rows, cached.cursor, env, x, y, w, h)
        end
    else -- "panel", "frame" and any unknown style: text content
        if win.text then
            local align = (style == "frame") and "center" or "left"
            local tx = (style == "frame") and x or (x + ui.toPx(layout.textX or 0.5))
            drawTextLines(win.text, env, tx, contentY, lineSpacing, w - ui.toPx(1), align)
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

return wr
