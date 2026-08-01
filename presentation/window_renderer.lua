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
--   "party"            party members (fields: index, name, level, spriteKey,
--                      portraitKey)
--   "config:<key>"     array from the scene's config (entry fields exposed)
--   "v:<key>"          array stored in scene v by hooks/SCRIPT
--   "static:a,b,c"     inline comma-separated labels
--   "equipSlots"       a member's 3 gear slots (fields: index, name, item, icon)
--   "equipment"        inventory gear matching a slot's type, [ UNEQUIP ] first
--                      (fields: id, name, icon, qty, description, preview)
--   "memberSkills"     a member's skills (fields: id, name, description)
--   "memberPassives"   a member's passives (fields: id, name, description)
-- The equip sources read the window's SET_LIST slot/member formulas at draw
-- time (slot: 1=Weapon 2=Armor 3=Accessory, member: party index). The
-- skill/passive sources read only the member formula.
--
-- Row templates/formulas (SET_LIST format/highlight/filter/priority) are evaluated
-- with the row's fields merged over the scene env, so "{name} (x{qty})" and
-- "meta.craftKind == config.disciplines[v.selectedDisciplineIdx].kind" work.
-- The scene env also exposes sel("window_id") -> the selected row of another
-- window's list, for detail panels.

local ui = require("presentation.ui")
local formula = require("engine.formula")
local small_battlers = require("presentation.small_battlers")
local actor_status = require("presentation.actor_status")
local battle_layout = require("presentation.battle_layout")
local subtractive_fade = require("presentation.subtractive_fade")
-- Summoner rework battle-windows conversion: "enemyRow"/"battleLog"/
-- "victoryPanel" styles dispatch to renderer.lua, which owns the actual
-- draw code (animation-player-driven shaders/particles, the reveal-timer
-- log, the drain-animated victory panel) — no circular require (renderer
-- does not require window_renderer).
local renderer = require("presentation.renderer")
local item_presentation = require("presentation.item_presentation")

local wr = {}

local COLOR_SELECTED = { 1, 1, 0.5, 1 }
local COLOR_NORMAL = { 1, 1, 1, 1 }
local COLOR_HIGHLIGHT = { 0.6, 1, 0.6, 1 }
local COLOR_DIM = { 0.6, 0.6, 0.6, 1 }

-- ---------------------------------------------------------------------------
-- Expression helpers
-- ---------------------------------------------------------------------------

-- Resolve a rect dimension (winDef.rect.x/y/w/h) as a formula against env,
-- falling back to default on nil or eval failure. Shared by the real draw
-- path (drawWindowFromData) and the headless preview path (resolveDataState).
local function resolveDim(dim, default, env)
    if dim == nil then return default end
    local ok, val = pcall(formula.eval, dim, env)
    if ok then
        local n = tonumber(val)
        if n then return n end
    end
    return default
end

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

local compareIds = require("engine.inventory").compareIds

local function inventoryRows(session, env, win)
    local rows = {}
    if not session or not session.inventory then return rows end
    local tab = 1
    if win and win.tabVar then
        tab = math.floor(tonumber((formula.eval(win.tabVar, env))) or 1)
    elseif env and env.v and env.v.tab then
        tab = math.floor(tonumber(env.v.tab) or 1)
    end

    for itemId, qty in pairs(session.inventory) do
        if qty > 0 then
            local item = session.loader.getItem(itemId)
            if item then
                local matches = false
                if tab == 1 then matches = true
                elseif tab == 2 then matches = (item.type == "consumable")
                elseif tab == 3 then matches = (item.type == "equipment")
                elseif tab == 4 then matches = (item.type == "quest" or item.type == "junk")
                else matches = true end

                if matches then
                table.insert(rows, item_presentation.enrich({
                        id = item.id,
                        name = item.name or "",
                        icon = item.icon or 0,
                        qty = qty,
                        meta = item.meta or {},
                        type = item.type,
                    }, item, session.loader))
                end
            end
        end
    end
    table.sort(rows, function(a, b) return compareIds(a.id, b.id) end)
    return rows
end

-- Shared battler-view enrichment for the 'party' and 'reserve' list sources:
-- progression, role, equipment slots and joined passive/skill/state names as
-- flat strings so {expr} templates can print them. maxSlots differs (4 vs 8);
-- source array is session.party or session.reserve.
local function battlerListRows(session, sourceArray, maxSlots)
    local config = require("engine.config")
    local expPerLevel = (config.growth and config.growth.expPerLevel) or 15
    local loader = session and session.loader
    local rows = {}
    for i = 1, maxSlots do
        local m = sourceArray and sourceArray[i]
        if m then
            local view = formula.battlerView(m, session) or {}
            view.index = i
            -- Same sheet-key choice as renderer.drawSmallBattlerCell
            view.spriteKey = (m.actorData and m.actorData.smallBattler) or ""
            view.portraitKey = (m.actorData and m.actorData.portrait) or ""
            view.dead = m.isDead and m:isDead() or false
            -- Not read by {expr} templates; lets the row's sprite share the
            -- same battle-triggered flash/shake state small_battlers keys by
            -- battler identity (drawList passes this through as battlerRef).
            view.battlerRef = m
            view.exp = m.exp or 0
            view.expNeeded = (m.level or 1) * expPerLevel
            view.role = (m.actorData and m.actorData.role) or "CREATURE"
            view.biography = (m.actorData and m.actorData.flavor) or "No biography available."
            -- Creature history as one authorable line (term, not a hardcoded
            -- string) so a scene can show what this creature has lived through.
            local h = m.history or {}
            view.historyText = (loader and loader.formatTerm)
                and loader.formatTerm("status.history",
                    "Born a {0} - {1} expedition(s), {2} battle(s), {3} promotion(s)",
                    h.species or view.name, h.expeditions or 0, h.battles or 0, h.promotions or 0)
                or ""
            local eq = m.equipment or {}
            view.weapon = eq[1] and eq[1].name or "-"
            view.armor = eq[2] and eq[2].name or "-"
            view.accessory = eq[3] and eq[3].name or "-"
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
        else
            table.insert(rows, { index = i, empty = true, name = "--Empty--" })
        end
    end
    return rows
end

local function partyRows(session)
    return battlerListRows(session, session and session.party, 4)
end

local function reserveRows(session)
    return battlerListRows(session, session and session.reserve, 8)
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

local SLOT_TYPES = { "Weapon", "Armor", "Accessory" }

-- "ATK:3->5  DEF:2->4" summary of what trial-equipping `newItem` (nil =
-- unequip) into the member's slot would change — the legacy
-- getStatPreview logic, moved here so equip pickers stay data-authored.
local function equipPreviewString(member, slot, newItem, session)
    local traits = require("engine.traits")
    local function snapshot()
        return {
            hp = member:getMaxHp(session),
            atk = traits.getParam(member, "atk", session),
            def = traits.getParam(member, "def", session),
            mat = traits.getParam(member, "mat", session),
            mdf = traits.getParam(member, "mdf", session),
        }
    end
    local prev = member.equipment[slot]
    local before = snapshot()
    member.equipment[slot] = newItem
    local after = snapshot()
    member.equipment[slot] = prev
    local changes = {}
    for _, f in ipairs({ { "hp", "HP" }, { "atk", "ATK" }, { "def", "DEF" }, { "mat", "MAT" }, { "mdf", "MDF" } }) do
        if before[f[1]] ~= after[f[1]] then
            table.insert(changes, string.format("%s:%d->%d", f[2], before[f[1]], after[f[1]]))
        end
    end
    if #changes == 0 then return "No changes." end
    return table.concat(changes, "  ")
end

-- Evaluate the window's slot/member SET_LIST formulas against the live env.
local function equipContext(win, env, session)
    local slot = tonumber((formula.eval(win.slot, env))) or 1
    local memberIdx = tonumber((formula.eval(win.member, env))) or 1
    return slot, session and session.party and session.party[memberIdx] or nil
end

local function equipSlotRows(session, win, env)
    local _, member = equipContext(win, env, session)
    local loader = session and session.loader
    local labels = (loader and loader.getTermList) and loader.getTermList("menu.equip_slots", { "WPN", "AMR", "ACC" }) or { "WPN", "AMR", "ACC" }
    local rows = {}
    for i = 1, 3 do
        local eq = member and member.equipment[i] or nil
        table.insert(rows, {
            index = i,
            name = labels[i] or SLOT_TYPES[i],
            item = eq and eq.name or "-",
            icon = eq and eq.icon or 0,
            description = eq and eq.description or "",
        })
    end
    return rows
end

-- Inspectable skill/passive rows for the status scene's Skills/Passives
-- pages (owner request: they should be their own pages, individually
-- selectable, with the description shown in the context-help bar — same
-- convention as the equip item picker). win.member is the SAME formula
-- convention equipSlots/equipment use (usually "v.idx").
local function memberSkillRows(session, win, env)
    local memberIdx = tonumber((formula.eval(win.member, env))) or 1
    local member = session and session.party and session.party[memberIdx]
    local loader = session and session.loader
    local rows = {}
    for _, id in ipairs((member and member.actorData and member.actorData.skills) or {}) do
        local skill = loader and loader.getSkill and loader.getSkill(id)
        if skill then
            table.insert(rows, { id = id, name = skill.name or id, description = skill.description or "", icon = skill.icon or 0 })
        end
    end
    if #rows == 0 then
        table.insert(rows, { id = "none", name = "None", description = "" })
    end
    return rows
end

local function memberPassiveRows(session, win, env)
    local memberIdx = tonumber((formula.eval(win.member, env))) or 1
    local member = session and session.party and session.party[memberIdx]
    local loader = session and session.loader
    local rows = {}
    for _, id in ipairs((member and member.actorData and member.actorData.passives) or {}) do
        local passive = loader and loader.getPassive and loader.getPassive(id)
        if passive then
            table.insert(rows, { id = id, name = passive.name or id, description = passive.description or "" })
        end
    end
    if #rows == 0 then
        table.insert(rows, { id = "none", name = "None", description = "" })
    end
    return rows
end

-- Ordering contract: row 1 is [ UNEQUIP ], then matching inventory gear
-- id-ascending — interpreter EQUIP_ITEM resolves itemIndex against the
-- SAME list (keep them in sync). `preview` is live per member/slot.
local function equipmentRows(session, win, env)
    local slot, member = equipContext(win, env, session)
    local slotType = SLOT_TYPES[slot]
    local rows = {}
    if not session or not slotType then return rows end
    local unequipPreview = member and equipPreviewString(member, slot, nil, session) or ""
    table.insert(rows, {
        id = "empty", name = "[ UNEQUIP ]", icon = 0, qty = 0,
        description = "Unequip the item in this slot.",
        preview = unequipPreview,
    })
    local matching = {}
    for itemId, qty in pairs(session.inventory or {}) do
        if qty > 0 then
            local item = session.loader.getItem(itemId)
            if item and item.type == "equipment" and item.equipType == slotType then
                table.insert(matching, { item = item, qty = qty })
            end
        end
    end
    table.sort(matching, function(a, b) return compareIds(a.item.id, b.item.id) end)
    for _, m in ipairs(matching) do
        table.insert(rows, {
            id = m.item.id,
            name = m.item.name or "",
            icon = m.item.icon or 0,
            qty = m.qty,
            description = m.item.description or "",
            preview = member and equipPreviewString(member, slot, m.item, session) or "",
        })
    end
    return rows
end

-- Resolve a window's list into rows, applying priority sort and format.
local function resolveRows(win, state, sceneData, ctx, env)
    local src = win.listId or ""
    local rows
    if src == "inventory" then
        rows = inventoryRows(ctx.session, env, win)
    elseif src == "party" then
        rows = partyRows(ctx.session)
    elseif src == "reserve" then
        rows = reserveRows(ctx.session)
    elseif src == "equipSlots" then
        rows = equipSlotRows(ctx.session, win, env)
    elseif src == "equipment" then
        rows = equipmentRows(ctx.session, win, env)
    elseif src == "memberSkills" then
        rows = memberSkillRows(ctx.session, win, env)
    elseif src == "memberPassives" then
        rows = memberPassiveRows(ctx.session, win, env)
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

    -- Row filter: unlike `priority`, which only sorts, this DROPS rows. It runs
    -- before the sort so a hidden row cannot be selected, counted or landed on
    -- by a cursor — the case `priority` cannot serve (Item Creation must not
    -- merely bury a promotion key at the bottom of the ingredient list).
    if win.filter and win.filter ~= "" then
        local kept = {}
        for _, r in ipairs(rows) do
            local val = formula.eval(win.filter, rowEnv(env, r))
            if val == true or (tonumber(val) or 0) > 0 then table.insert(kept, r) end
        end
        rows = kept
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

-- Advances `line` by however many VISUAL rows a chunk actually occupies once
-- word-wrapped at `limit` (ui.wrapText uses the same font/wrap algorithm
-- ui.drawString's printf call will), not by 1 per logical (\n-separated)
-- chunk. A chunk that word-wraps to 2 lines used to make the NEXT chunk draw
-- on top of its second line — e.g. a long quest summary followed by a hard
-- "\n\nObjectives:" header would overlap the summary's wrapped second line.
local function wrappedLineCount(chunk, limit)
    if chunk == "" then return 1 end
    local wrapped = ui.wrapText(chunk, limit)
    local _, count = wrapped:gsub("\n", "\n")
    return count + 1
end

-- `revealElapsed` (optional) turns this into a typewriter widget. The wrap is
-- computed HERE and only here: after {expr} interpolation (so a substitution
-- can't change the text's length out from under the line breaks) and against
-- the same `limit` ui.drawString hands printf (so printf has nothing left to
-- re-wrap). Both are why words used to hop to the next line mid-reveal.
local function drawTextLines(text, env, x, y, lineSpacing, limit, align, revealElapsed)
    local rendered = interpolate(text, env)
    if revealElapsed then
        local wrapped = ui.wrapText(rendered, limit)
        rendered = ui.utf8Prefix(wrapped, ui.revealedCount(wrapped, revealElapsed))
    end
    local line = 0
    for chunk in (rendered .. "\n"):gmatch("(.-)\n") do
        if chunk ~= "" then
            ui.drawString(chunk, x, y + line * lineSpacing, COLOR_NORMAL, align or "left", limit)
        end
        line = line + wrappedLineCount(chunk, limit)
    end
end

-- Shared cost/gain preview binding for any authored gauge (Summoner
-- rework: MP/EXP/gold previews on hover for spells, ritual, shops, items
-- alike — one authoring surface, ui.drawBar does the actual drawing).
-- costFormula/gainFormula are mutually exclusive per gauge; whichever
-- evaluates non-zero wins. showLabel defaults to true ("cost: N"/"gain:
-- N" printed slim and discreet right after the bar — SPEC 2.1: no
-- per-window reimplementation of this).
local function buildGaugePreview(costFormula, gainFormula, showLabel, env)
    local cost = costFormula and tonumber((formula.eval(costFormula, env)))
    if cost and cost ~= 0 then
        cost = math.abs(cost)
        return { delta = -cost, label = (showLabel ~= false) and ("cost: " .. tostring(cost)) or nil }
    end
    local gain = gainFormula and tonumber((formula.eval(gainFormula, env)))
    if gain and gain ~= 0 then
        gain = math.abs(gain)
        return { delta = gain, label = (showLabel ~= false) and ("gain: " .. tostring(gain)) or nil }
    end
    return nil
end

-- Layout-authored gauges let a panel present live values without a
-- scene-specific renderer.  Labels support the same {formula} interpolation
-- as ordinary window text; values and maxima are formula expressions.
local function drawLayoutGauges(gauges, env, x, y)
    for _, gauge in ipairs(gauges or {}) do
        local gx = x + ui.toPx(gauge.x or 1)
        local gy = y + ui.toPx(gauge.y or 1)
        -- Extra parens truncate formula.eval's (value, err) pair to just
        -- value — without them, a failed eval spills its error STRING into
        -- tonumber's 2nd argument (base), which only accepts a number, and
        -- crashes instead of degrading to the fallback.
        local value = tonumber((formula.eval(gauge.value or "0", env))) or 0
        local maximum = tonumber((formula.eval(gauge.max or "1", env))) or 1
        local preview = buildGaugePreview(gauge.previewCost, gauge.previewGain, gauge.previewLabel, env)
        ui.drawString(interpolate(gauge.label or "", env), gx, gy, COLOR_NORMAL)
        ui.drawBar(gx, ui.gaugeYBelowText(gy), ui.toPx(gauge.width or 18), ui.gaugeHeight,
            value, maximum, gauge.color or { 0.5, 0, 0 }, gauge.fill or { 1, 0.3, 0.3 }, preview)
    end
end

local function resolvePageLayout(layout, env)
    if not layout.pages then return layout end
    local page = math.floor(tonumber((formula.eval(layout.pageFormula or "1", env))) or 1)
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
    local img = (type(key) == "string" and key ~= "") and ui.resolvePortraitImage(key) or nil
    local contentX, contentY = contentOrigin(layout, title, x, y)
    local drawX = x + ui.toPx(layout.portraitX or 1)
    local drawY = layout.portraitY ~= nil and y + ui.toPx(layout.portraitY) or contentY
    local overflow = ui.toPx(layout.portraitOverflow or 0)
    local portraitX = drawX - overflow
    local portraitY = drawY - overflow
    local portraitW = ui.toPx(layout.portraitW or 7.5) + overflow * 2
    local portraitH = ui.toPx(layout.portraitH or 10) + overflow * 2
    local portraitFrame = layout.portraitFrame and formula.eval(layout.portraitFrame, env) or 1

    if img then
        love.graphics.setColor(1, 1, 1, 1)
        if layout.portraitW and layout.portraitH then
            ui.drawSlicedPortrait(img, portraitX, portraitY, portraitW, portraitH, portraitFrame)
        else
            love.graphics.draw(img, drawX, drawY, 0, 1, 1)
        end
    elseif layout.portraitPlaceholder then
        local ph = layout.portraitPlaceholder
        local pw = ui.toPx(layout.portraitW or 7.5)
        local phH = ui.toPx(layout.portraitH or 10)
        love.graphics.push("all")
        if ph == "vignette" or ph == "frame" then
            love.graphics.setColor(unpack(layout.placeholderTint or {0.15, 0.15, 0.22, 0.6}))
            love.graphics.rectangle("fill", drawX, drawY, pw, phH, 4, 4)
            love.graphics.setColor(0.3, 0.3, 0.4, 0.8)
            love.graphics.rectangle("line", drawX, drawY, pw, phH, 4, 4)
        elseif ph == "silhouette" then
            love.graphics.setColor(0.1, 0.1, 0.15, 0.7)
            love.graphics.rectangle("fill", drawX, drawY, pw, phH)
            ui.drawString("?", drawX + pw/2 - 3, drawY + phH/2 - 4, {0.4, 0.4, 0.5, 1})
        end
        love.graphics.pop()
    end

    if layout.portraitName then
        local name = formula.eval(layout.portraitName, env)
        if name and name ~= "" then
            local pw = ui.toPx(layout.portraitW or 7.5)
            local ph = ui.toPx(layout.portraitH or 10)
            local nameH = ui.toPx(2)
            love.graphics.push("all")
            ui.drawString(tostring(name), drawX + 3, drawY + ph - nameH + 3,
                {1, 0.94, 0.76, 1}, "center", pw - 6)
            love.graphics.pop()
        end
    end
end

-- Draws the SAME actor-status cell used everywhere else party status is
-- shown (partyGrid style, battle/map HUD) inside an ordinary "panel"
-- window. layout.actorStatus names the OTHER window whose selected row
-- carries the real battler object (row.battlerRef) — a battler is a Lua
-- object (methods, not just fields), so it can't round-trip through
-- formula.eval, which only returns number/boolean/string by design.
-- env.sel is the same lookup {expr} templates use via sel('id'), just
-- called directly here instead of through the sandboxed formula string.
--
-- Positioned via the window's plain natural content origin (1 tile inset,
-- untitled; 2 if titled) — the SAME thing gridSlot's index-1 cell reduces
-- to (col/row both 0 there). Deliberately NOT contentOrigin()/layout's own
-- contentX/contentY: those belong to this window's separate text/gauge
-- block (drawn further down, below the cell), and reusing them here would
-- drag the cell down to wherever the text starts instead of pinning it to
-- the window's top-left — exactly the "drawing way lower than it should"
-- bug this comment is here to stop from recurring.
local function drawActorStatusCell(layout, env, x, y, title, ctx)
    if not layout.actorStatus then return 0 end
    local row = env.sel and env.sel(layout.actorStatus)
    local battler = row and row.battlerRef
    if not battler then return 0 end
    local session = ctx and ctx.session
    local colW, rowH = actor_status.cellSize(session)
    local cellX, cellY = ui.panelContentOrigin(x, y, title, nil, nil)
    actor_status.draw(battler, cellX, cellY, false, session)
    return rowH
end

local function drawList(win, layout, rows, cursor, env, x, y, w, h, title, session, animScale)
    local contentX, contentY = contentOrigin(layout, title, x, y)

    -- Integrated Tab Header Strip (Option 1 / Approach A):
    local tabs = win.tabs or layout.tabs
    if tabs and #tabs > 0 then
        local tabVar = win.tabVar or layout.tabVar or "v.tab"
        local activeTab = math.floor(tonumber((formula.eval(tabVar, env))) or 1)
        local tabAreaW = w - ui.toPx(2)
        local totalTabs = #tabs
        local tabW = tabAreaW / totalTabs
        for tIdx, tabItem in ipairs(tabs) do
            local tabName = type(tabItem) == "table" and tabItem.name or tostring(tabItem)
            local isTabSel = (tIdx == activeTab)
            local tabX = contentX + (tIdx - 1) * tabW
            if isTabSel then
                ui.drawPanel(tabX + 1, contentY - 2, tabW - 2, ui.lineHeight + 3, nil, "button_highlight")
            end
            local label = tabName
            local color = isTabSel and COLOR_SELECTED or COLOR_DIM
            local textW = ui.measureText(label)
            local textX = tabX + math.max(0, (tabW - textW) / 2)
            ui.drawString(label, textX, contentY, color)
        end
        -- Separator line under tab bar
        local sepY = contentY + ui.lineHeight + 2
        love.graphics.push("all")
        love.graphics.setColor(0.3, 0.35, 0.45, 0.6)
        love.graphics.line(contentX, sepY, contentX + tabAreaW, sepY)
        love.graphics.pop()

        -- Shift contentY down for rows and adjust available height
        contentY = contentY + ui.lineHeight + 4
        h = h - (ui.lineHeight + 4)
    end

    -- Row widgets (vocabulary extension 11.07.2026): win.sprite names a row
    -- field carrying a small-battler sheet key drawn at the row's left;
    -- win.gaugeValue/gaugeMax are row-scoped formulas drawn as a bar under
    -- the text. Both grow the row pitch, which the scroll math follows.
    local spriteField = win.sprite
    local spriteSize = ui.toPx(layout.spriteSize or 3)
    local cardPad = 2 -- inset of a sprite row's own windowskin card
    local hasGauge = win.gaugeValue and win.gaugeValue ~= "" and win.gaugeMax and win.gaugeMax ~= ""
    local rowPitch = ui.lineHeight
    if hasGauge then rowPitch = rowPitch + ui.gaugeHeight + 3 end
    if spriteField then rowPitch = math.max(rowPitch, spriteSize + 2) end
    if layout.rowPitch then rowPitch = ui.toPx(layout.rowPitch) end

    local visible = layout.visibleRows or math.max(1, math.floor((h - ui.toPx(2)) / rowPitch))
    if #rows == 0 then
        local emptyText = layout.emptyText or "No entries."
        ui.drawString(emptyText, contentX, contentY, COLOR_DIM)
        return
    end
    local startOffset = math.max(1, math.min(cursor - 3, #rows - visible + 1))
    local endOffset = math.min(#rows, startOffset + visible - 1)
    local format = win.format or "{name}"
    -- Smooth cursor interpolation
    local targetCursorY = contentY + (cursor - startOffset) * rowPitch
    if type(win) == "table" then
        if not win._cursorY then
            win._cursorY = targetCursorY
        else
            local dt = love.timer and love.timer.getDelta() or 0.016
            win._cursorY = win._cursorY + (targetCursorY - win._cursorY) * math.min(1, dt * 25)
        end
    end
    local drawCursorY = (type(win) == "table" and win._cursorY) or targetCursorY

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
            -- Sprite rows draw a real button card, so they pop with the
            -- window like command slots rather than being wiped by the scissor.
            local cardScale = animScale or 1
            local cardPopped = cardScale < 1
            local cardCx = x + cardPad + (w - cardPad * 2) / 2
            local cardCy = rowY - cardPad + (rowPitch - cardPad) / 2
            if cardPopped then
                love.graphics.push()
                love.graphics.translate(cardCx, cardCy)
                love.graphics.scale(cardScale, cardScale)
                love.graphics.translate(-cardCx, -cardCy)
            end
            ui.drawPanel(x + cardPad, rowY - cardPad, w - cardPad * 2, rowPitch - cardPad, nil, ui.buttonRole(isSel))
            if cardPopped then love.graphics.pop() end
        end

        local textX = contentX + ui.toPx(0.5)
        if spriteField then
            local key = row[spriteField]
            if key and key ~= "" and small_battlers.draw(key, x + ui.toPx(1), rowY - 2, spriteSize, row.dead, row.battlerRef, session) then
            textX = contentX + ui.toPx(0.5) + spriteSize + 3
            end
        end
        -- win.labelField (e.g. equip_slots' slot name "WPN"/"AMR"/"ACC")
        -- draws as plain text BEFORE the icon, so the icon sits immediately
        -- in front of the item name it belongs to instead of in front of
        -- the whole "label: item" line (owner feedback: icon must precede
        -- the name it's for, not the slot label).
        if win.labelField then
            local label = tostring(row[win.labelField] or "") .. ":  "
            ui.drawString(label, textX, rowY, color)
            textX = textX + ui.measureText(label)
        end
        -- Clip the label to the window's interior. A list is no longer always
        -- wide: battle's skill/item lists share the command box's 76px column,
        -- where an untruncated "HP Tonic x5 [1 pending]" ran straight out of
        -- the panel and across the party status beside it.
        local scrollPad = 6
        local rightEdge = spriteField and (x + w - cardPad * 2 - scrollPad)
            or (x + w - ui.toPx(0.5) - scrollPad)

        -- A right-hand column (qty, price) owns its width; the label gets what
        -- is left. Strip \c[N] colour codes before measuring, since drawString
        -- removes them during rendering but measureText counts them.
        local rightText, rightW = nil, 0
        if win.formatRight and win.formatRight ~= "" then
            rightText = interpolate(win.formatRight, rEnv)
            rightW = ui.measureText((rightText:gsub("\\c%[%d+%]", ""))) + ui.toPx(0.5)
        end

        local iconBlockW = (row.icon ~= nil)
            and (ui.toPx(0.25) + ui.iconSize + ui.toPx(0.25)) or 0
        local labelText = ui.fitText(interpolate(format, rEnv),
            rightEdge - rightW - textX - iconBlockW)
        local afterTextX = ui.drawIconText(row.icon, labelText, textX, rowY, color)

        if rightText then
            ui.drawString(rightText, rightEdge - rightW + ui.toPx(0.5), rowY, color)
        end
        if hasGauge then
            -- (extra parens: see drawLayoutGauges — truncates eval's
            -- (value, err) pair so a failed formula degrades to 0/1
            -- instead of crashing tonumber's base argument)
            local val = tonumber((formula.eval(win.gaugeValue, rEnv))) or 0
            local max = tonumber((formula.eval(win.gaugeMax, rEnv))) or 1
            local barX = textX - 2
            -- Stay inside the row's own card (not the whole window) when
            -- one is drawn, so the bar never bleeds past its border.
            local rightEdge = spriteField and (x + w - cardPad * 2 - scrollPad) or (x + w - ui.toPx(1) - scrollPad)
            local barW = math.max(8, rightEdge - barX)
            local preview = isSel
                and buildGaugePreview(win.gaugePreviewCost, win.gaugePreviewGain, win.gaugePreviewLabel, rEnv)
                or nil
            ui.drawBar(barX, ui.gaugeYBelowText(rowY), barW, ui.gaugeHeight,
                val, max,
                win.gaugeColor or { 0.8, 0, 0 }, win.gaugeFill or { 1, 0.3, 0.3 }, preview)
        end
    end

    -- Single smooth-moving cursor drawn at interpolated position
    small_battlers.draw("Cursor", contentX - 6, drawCursorY, 8)

    -- Render lean windowskin scrollbar if total rows exceed visible capacity
    if #rows > visible then
        local listH = visible * rowPitch
        ui.drawScrollbar(x, contentY, w, listH, #rows, visible, startOffset)
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
-- F2 (overhaul-6): shared MP readout — a thin gauge on the sliver UNDER the 2x2
-- actor grid (same thickness as the party HP bars), with the current MP value
-- shown numerically to its right. gaugeW is the gauge's pixel width; the number
-- sits immediately after it, so gauge + number span exactly the 2-panel width.
local function drawMpReadout(session, gaugeX, gaugeY, gaugeW, numX, numY, mpBarH)
    local mp = math.floor(session.displayedMp or session.mp or 0)
    local maxMp = math.floor(session.maxMp or mp or 1)
    if maxMp <= 0 then maxMp = 1 end
    ui.drawBar(gaugeX, gaugeY, gaugeW, mpBarH, mp, maxMp, {0.30, 0.60, 1.0}, {0.65, 0.90, 1.0})
    ui.drawString(tostring(mp), numX, numY, {0.80, 0.90, 1.0, 1})
end

local function drawPartyGridStyle(layout, rows, cursor, env, x, y, session, title, animScale)
    local cols = layout.gridColumns or 2
    local contentX, contentY = contentOrigin(layout, title, x, y)
    -- The slots scale with the window's animated width, so opening and closing
    -- them is an ordinary `anim` on the layout like every other window. This
    -- replaces a hard-coded "if the scene is dialogue, shrink over 0.15s"
    -- special case keyed off a global: the dock now moves between plenty of
    -- variants that have no party slots, and only the one it knew about
    -- animated at all.
    local scale = animScale or 1
    if scale <= 0 then return end

    -- F2 (overhaul-6): the 2x2 actor grid stays at its natural left position
    -- (contentX) so the map party popup — anchored to the grid cells via
    -- cellOf:party — lines up with the sprites. The shared MP gauge is drawn on
    -- the thin sliver under the grid (same thickness as the party HP bars),
    -- with the current MP value shown numerically to its right.
    local colW = actor_status.cellSize(session)
    local gridW = cols * colW
    local h = ui.toPx(layout.height or 12)
    local mpBarH = ui.gaugeHeight
    local mpNum = tostring(math.floor(session.displayedMp or session.mp or 0))
    local mpNumW = ui.measureText(mpNum)
    local gap = 4
    local label = "MP"
    local labelW = ui.measureText(label)
    local labelGap = 4
    -- F2 (overhaul-6): the gauge AND the numeric value both shift up 3px; an
    -- "MP" label sits to the LEFT of the gauge, and the gauge length is reduced
    -- by the label width so label + gauge + number still span the grid width.
    local numberY = y + h - ui.fontSize - 3
    local gaugeY = numberY + math.floor((ui.fontSize - mpBarH) / 2)
    local gaugeX = contentX + labelW + labelGap
    local gaugeW = math.max(8, gridW - labelW - labelGap - mpNumW - gap)
    local numberX = gaugeX + gaugeW + gap
    if not layout.hideMp then
        love.graphics.push()
        local mpCenterX = contentX + gridW / 2
        local mpCenterY = numberY + ui.fontSize / 2
        love.graphics.translate(mpCenterX, mpCenterY)
        love.graphics.scale(scale, scale)
        love.graphics.translate(-mpCenterX, -mpCenterY)
        ui.drawString(label, contentX, numberY, {0.80, 0.90, 1.0, scale})
        drawMpReadout(session, gaugeX, gaugeY, gaugeW, numberX, numberY, mpBarH)
        love.graphics.pop()
    end
    for i, row in ipairs(rows) do
        local cx, cy = actor_status.gridSlot(contentX, contentY, i, session, cols)
        local colW, rowH = actor_status.cellSize(session)
        local scx, scy = cx + colW / 2, cy + rowH / 2
        love.graphics.push()
        love.graphics.translate(scx, scy)
        love.graphics.scale(scale, scale)
        love.graphics.translate(-scx, -scy)
        if row.battlerRef then
            actor_status.draw(row.battlerRef, cx, cy, i == cursor, session)
        else
            ui.drawPanel(cx - 2, cy - 2, colW - 2, rowH - 2, nil, ui.buttonRole(i == cursor))
            if i == cursor then
                small_battlers.draw("Cursor", cx - 6, cy, 8)
            end
            local text = "--Empty--"
            local textW = ui.measureText(text)
            ui.drawString(text, cx + (colW - textW) / 2, cy + (rowH - ui.lineHeight) / 2, { 0.4, 0.4, 0.4, 1 })
        end
        love.graphics.pop()
    end
end

-- Reserve scene (overhaul-6 F3): while picking a Swap target (v.mode == 4),
-- the source slot is shown as a black silhouette and a ghost of it floats
-- above, drifting in a sine wave between a -2 and -6 offset (up-left diagonal,
-- a bit faster). The shadow scales down as the ghost drifts away, selling the
-- "floating" illusion. Works for both an occupied source (ghost of the creature
-- panel) and an empty source (ghost of the empty slot panel).
local swapGhostCanvas = nil
local swapGhostKey = nil
local function drawSwapIndicator(state, sceneData, ctx)
    local v = state.v
    if not v or v.mode ~= 4 then return end
    local session = ctx.session
    if not session then return end
    local isReserve = v.swapSourceIsReserve
    local srcIdx = v.swapSourceIndex
    if not srcIdx then return end
    local arr = isReserve and session.reserve or session.party
    local battler = arr and arr[srcIdx]

    local srcWinId = isReserve and "reserve_roster" or "reserve_party"
    local layouts = (ctx.loader and ctx.loader.engine and ctx.loader.engine.windowLayout) or {}
    local layout = layouts[srcWinId] or {}
    local x = ui.toPx(layout.x or 0)
    local y = ui.toPx(layout.y or 0)
    local contentX, contentY = contentOrigin(layout, nil, x, y)
    local cols = layout.gridColumns or 2
    local cx, cy = actor_status.gridSlot(contentX, contentY, srcIdx, session, cols)

    local colW, rowH = actor_status.cellSize(session)
    colW, rowH = math.floor(colW), math.floor(rowH)

    -- Cache the ghost (creature panel or empty slot) on an offscreen canvas.
    -- Both branches render the panel at canvas (0,0) so the draw position is
    -- exact. The slot's own draw calls set opaque colors, so a global alpha
    -- would not propagate without the canvas.
    local creatureId = battler and (battler.actorData and battler.actorData.id or battler.name) or "empty"
    local key = srcWinId .. ":" .. tostring(srcIdx) .. ":" .. tostring(creatureId)
    if key ~= swapGhostKey or not swapGhostCanvas then
        swapGhostCanvas = love.graphics.newCanvas(colW, rowH)
        swapGhostKey = key
        love.graphics.push("all")
        love.graphics.setCanvas(swapGhostCanvas)
        love.graphics.clear(0, 0, 0, 0)
        if battler then
            actor_status.draw(battler, 2, 2, false, session)
        else
            ui.drawPanel(0, 0, colW - 2, rowH - 2, nil, "button_highlight")
        end
        love.graphics.setCanvas()
        love.graphics.pop()
    end

    local panelX, panelY = cx - 2, cy - 2
    local w, h = colW - 2, rowH - 2
    local t = love.timer.getTime()
    local mag = 4 + 2 * math.sin(t * 4) -- oscillates 2..6 (a bit faster)

    -- The source slot is still drawn by the grid. Fill it pure black so it
    -- reads as the empty "picked up" slot, and float a full-opacity ghost of
    -- it above in a gentle sine wave.
    love.graphics.push("all")
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", panelX, panelY, w, h)
    love.graphics.pop()

    -- The ghost floats above at full opacity, drifting in the same sine wave.
    love.graphics.push("all")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(swapGhostCanvas, panelX - mag, panelY - mag)
    love.graphics.pop()
end

-- Horizontal option row (confirm/command style): options spread across the
-- width. The active choice gets a small button_highlight backdrop behind its
-- text (ui.drawPanel's `highlight` param), same idea as the actor_status
-- cell highlight — one shared way to mark "this is the current selection".
local function drawOptions(rows, cursor, env, x, y, w)
    local n = #rows
    if n == 0 then return end
    local slot = w / n
    for i, row in ipairs(rows) do
        local isSel = (i == cursor)
        local color = isSel and COLOR_SELECTED or COLOR_NORMAL
        local slotX = x + math.floor((i - 1) * slot)
        if isSel then
            ui.drawPanel(slotX + ui.toPx(0.5), y - ui.toPx(0.5), math.floor(slot) - ui.toPx(1), ui.lineHeight + ui.toPx(1), nil, "button_highlight")
            small_battlers.draw("Cursor", slotX + ui.toPx(1), y, 8)
        end
        ui.drawString(row.name or "", slotX + ui.toPx(2), y, color)
    end
end

-- "command" style: fixed-size buttons inside one persistent panel. Buttons do
-- not stretch when a creature authors fewer commands; stable geometry makes
-- the menu feel like a console rather than an accordion.
local function drawCommandSlots(layout, rows, cursor, env, x, y, w, h, animScale)
    animScale = animScale or 1
    local n = #rows
    if n == 0 then return end
    local gap = ui.toPx((layout and layout.slotGap) or 0.5)
    local isVertical = layout and (layout.vertical or layout.direction == "vertical")
    -- A row with an icon (skill/passive-style rows) draws as one centered
    -- "[icon] name" unit via ui.drawIconText, instead of printf's own
    -- "center" alignment (which only knows about the text) — icon-less
    -- rows (Attack/Skill/Defend/Item/Flee) are unaffected.
    local function drawSlotLabel(row, color, slotX, slotW, textY, cursorY)
        local label = row.name or ""
        local hasIcon = row.icon ~= nil
        if hasIcon then
            local textW = ui.measureText(label)
            local iconBlockW = ui.toPx(0.25) + ui.iconSize + ui.toPx(0.25)
            local totalW = iconBlockW + textW
            local startX = slotX + (slotW - totalW) / 2
            if cursorY then
                small_battlers.draw("Cursor", startX - 10, cursorY, 8)
            end
            ui.drawIconText(row.icon, label, startX, textY, color)
        else
            if cursorY then
                local textW = love.graphics.getFont():getWidth(label)
                local textX = slotX + (slotW - textW) / 2
                small_battlers.draw("Cursor", textX - 10, cursorY, 8)
            end
            ui.drawString(label, slotX, textY, color, "center", slotW)
        end
    end

    if isVertical then
        local inset = ui.toPx((layout and layout.slotInset) or 1)
        local slotH = ui.toPx((layout and layout.slotHeight) or 2)
        local slotW = math.max(ui.toPx(2), w - inset * 2)
        for i, row in ipairs(rows) do
            local isSel = (i == cursor)
            local sy = y + inset + (i - 1) * (slotH + gap)
            -- Each button scales about its own centre, so a menu opens as a
            -- set of buttons appearing rather than a panel being wiped.
            local popped = animScale < 1
            if popped then
                love.graphics.push()
                love.graphics.translate(x + inset + slotW / 2, sy + slotH / 2)
                love.graphics.scale(animScale, animScale)
                love.graphics.translate(-(x + inset + slotW / 2), -(sy + slotH / 2))
            end
            ui.drawPanel(x + inset, sy, slotW, slotH, nil, ui.buttonRole(isSel))
            local color = isSel and COLOR_SELECTED or COLOR_NORMAL
            local textY = sy + slotH / 2 - ui.lineHeight / 2
            drawSlotLabel(row, color, x + inset, slotW, textY,
                isSel and (sy + slotH / 2 - 4) or nil)
            if popped then love.graphics.pop() end
        end
    else
        local slotW = (w - gap * (n + 1)) / n
        for i, row in ipairs(rows) do
            local isSel = (i == cursor)
            local sx = x + gap + (i - 1) * (slotW + gap)
            local popped = animScale < 1
            if popped then
                love.graphics.push()
                love.graphics.translate(sx + slotW / 2, y + h / 2)
                love.graphics.scale(animScale, animScale)
                love.graphics.translate(-(sx + slotW / 2), -(y + h / 2))
            end
            ui.drawPanel(sx, y, slotW, h, nil, ui.buttonRole(isSel))
            local color = isSel and COLOR_SELECTED or COLOR_NORMAL
            local textY = y + h / 2 - ui.lineHeight / 2
            drawSlotLabel(row, color, sx, slotW, textY, isSel and (y + h / 2 - 4) or nil)
            if popped then love.graphics.pop() end
        end
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

-- Animation clock tables (weak-keyed by win table so destroyed windows
-- release their entries automatically).
--
-- Open animation: layout.anim.open = { duration = seconds, anchor =
-- "cellOf:<windowId>" (optional), effect = "grow"|"slideUp"|"slideDown"|
-- "slideLeft"|"slideRight"|"fade", fromOffset = pixels (slide effects) }
-- animates the window entering. The "grow" effect (default) scales the
-- rect from an anchor point; slide effects translate the rect from an
-- offset; "fade" animates the panel alpha.
--
-- Close animation: anim.close = { duration, effect, toOffset } plays in
-- reverse when the window hides. The renderer detects visibility
-- transitions and keeps a hidden window alive through its close anim.
--
-- Owner direction 13.07.2026: the windowskin frame/tiles must never be
-- graphically scaled (love.graphics.scale on a 9-sliced texture stretches
-- the corner/edge quads into visible artifacts) — only the window's real
-- x/y/w/h dimensions animate. ui.drawPanel already tiles correctly at any
-- size, so growing the REAL rect fed into it keeps every frame crisp.
-- Content (text/lists) stays laid out at the window's resting size and is
-- simply revealed via scissor as the box grows, rather than reflowing.
local openClocks  = setmetatable({}, { __mode = "k" })
local closeClocks = setmetatable({}, { __mode = "k" })

-- Returns the progress (0..1) and whether the animation is still running.
local function animProgress(clockTable, win, durDefault)
    local now = love.timer.getTime()
    local t0 = clockTable[win]
    if not t0 then
        t0 = now
        clockTable[win] = t0
    end
    local dur = tonumber(durDefault) or 0.22
    local p = dur <= 0 and 1 or math.min(1, (now - t0) / dur)
    return p, p < 1
end

-- Evaluate the eased progress value using the layout's easing field (or
-- quadratic ease-out by default, matching the existing grow animation).
local function animEase(p, easing)
    if easing == "linear" then return p end
    return 1 - (1 - p) * (1 - p) -- quadratic ease-out
end

-- Resolves an anchor spec to a pixel point the window grows FROM. Currently
-- supports "cellOf:<windowId>": the center of that window's currently
-- selected partyGrid cell (e.g. the map's member popup opens from whichever
-- party member was chosen, not the screen center) — reusable by any future
-- popup anchored to a grid selection, not scene-specific.
local function resolveAnchor(spec, ctx, listCache, layouts)
    local targetId = type(spec) == "string" and spec:match("^cellOf:(.+)$")
    if not targetId then return nil end
    local cached = listCache[targetId]
    local targetLayout = layouts[targetId]
    if not cached or not targetLayout or not cached.rows[cached.cursor] then return nil end
    local cols = targetLayout.gridColumns or 2
    local colW, rowH = actor_status.cellSize(ctx.session)
    local contentX, contentY = contentOrigin(targetLayout, targetLayout.title, ui.toPx(targetLayout.x or 0), ui.toPx(targetLayout.y or 0))
    local idx = cached.cursor
    -- Shared slot arithmetic (actor_status.gridSlot); +half a cell centers
    -- the anchor on the selected grid cell.
    local cx, cy = actor_status.gridSlot(contentX, contentY, idx, ctx.session, cols)
    return cx + colW / 2, cy + rowH / 2
end

-- When a window anchors to a grid cell, its RESTING position also relates
-- to that cell (owner direction 13.07.2026: "not dead center of the
-- screen") — centered horizontally over the cell, sitting just above it,
-- clamped to stay on screen. Falls back to the window's own layout.x/y
-- when there's no anchor (or it can't resolve, e.g. nothing selected yet).
local function anchoredRestPosition(ax, ay, x, y, w, h)
    if not ax then return x, y end
    local screenW, screenH = ui.toPx(32), ui.toPx(30)
    local gap = ui.toPx(0.5)
    local rx = math.max(0, math.min(screenW - w, ax - w / 2))
    local ry = math.max(0, math.min(screenH - h, ay - h - gap))
    return rx, ry
end

-- Returns the animated (px, py, pw, ph) rect to actually draw the panel
-- border at, plus an optional alpha (1 = opaque, < 1 = fading), and
-- whether animation is still in progress (caller scissors content to
-- this rect while true, or applies alpha).
-- `closing` (boolean): when true, plays the close animation in reverse.
-- `clockOverride` (number|nil): when set, uses this absolute time as
-- the animation start (used by drawWindowFromData to keep close
-- animation timing across visibility transitions).
local function windowAnimRect(win, layout, x, y, w, h, ctx, listCache, layouts, closing, clockOverride)
    if not closing and win._skipOpenAnim then
        win._skipOpenAnim = nil
        openClocks[win] = love.timer.getTime() - ((layout.anim and layout.anim.open and layout.anim.open.duration) or 0)
        return x, y, w, h, 1, false
    end
    local phase = closing and "close" or "open"
    local anim = layout.anim and layout.anim[phase]
    if not anim then
        openClocks[win] = nil
        closeClocks[win] = nil
        return x, y, w, h, 1, false
    end

    local clockTable = closing and closeClocks or openClocks
    -- Clear the opposite clock so a rapid open→close→open restarts cleanly.
    if closing then openClocks[win] = nil else closeClocks[win] = nil end

    local now = love.timer.getTime()
    if clockOverride then
        -- Use caller-supplied start time (persisted across frames for
        -- close animations triggered by visibility transitions).
        if not clockTable[win] then clockTable[win] = clockOverride end
    end
    local p, running = animProgress(clockTable, win, anim.duration)
    if not running then
        -- If closing animation finished, signal caller via animating=false
        -- but still return the "fully closed" position (slid out).
        if closing then
            closeClocks[win] = nil
        end
        return x, y, w, h, 1, false
    end

    local easing = anim.easing
    local ease = animEase(closing and (1 - p) or p, easing)
    local effect = anim.effect or "grow"
    local offset = closing and (anim.toOffset or 0) or (anim.fromOffset or 0)

    if effect == "grow" or effect == "scale" then
        local ax, ay = resolveAnchor(anim.anchor, ctx, listCache, layouts)
        local growFromX, growFromY = ax or (x + w / 2), ay or (y + h / 2)
        local realCx, realCy = x + w / 2, y + h / 2
        local cx = growFromX + (realCx - growFromX) * ease
        local cy = growFromY + (realCy - growFromY) * ease
        local pw = math.max(16, w * ease)
        local ph = math.max(16, h * ease)
        return cx - pw / 2, cy - ph / 2, pw, ph, 1, true

    elseif effect == "expandRight" then
        local fromW = ui.toPx(anim.fromWidth or 2)
        local pw = fromW + (w - fromW) * ease
        return x, y, pw, h, 1, true

    elseif effect == "fade" then
        -- Rect stays fixed, alpha animates.
        local alpha = ease
        return x, y, w, h, alpha, true

    elseif effect == "slideUp" then
        local offPx = offset or h
        local slideY = y + offPx * (1 - ease)
        return x, slideY, w, h, 1, true

    elseif effect == "slideDown" then
        local offPx = offset or h
        local slideY = y - offPx * (1 - ease)
        return x, slideY, w, h, 1, true

    elseif effect == "slideLeft" then
        local offPx = offset or w
        local slideX = x + offPx * (1 - ease)
        return slideX, y, w, h, 1, true

    elseif effect == "slideRight" then
        local offPx = offset or w
        local slideX = x - offPx * (1 - ease)
        return slideX, y, w, h, 1, true

    else
        -- Unknown effect: fall back to instant.
        return x, y, w, h, 1, false
    end
end

-- Style-specific content: called once per window per frame, either directly
-- (resting state) or inside a scissor clipped to the animated open rect
-- (while opening) -- content is always laid out at the REAL final x/y/w/h so
-- it never reflows, it's simply revealed as the box grows.
-- `animScale` (0..1) is how far through an open/close animation this window
-- is, as a fraction of its settled width. Styles made of discrete cells --
-- party slots, command buttons -- scale each cell about its own centre by it,
-- so they animate as individual panels rather than being wiped by the scissor.
-- 1 whenever no animation is running.
local function drawWindowContent(id, win, layout, style, title, x, y, w, h, env, listCache, ctx, animScale)
    animScale = animScale or 1
    local contentX, contentY = contentOrigin(layout, title, x, y)
    local lineSpacing = ui.toPx(layout.lineSpacing or 1)

    drawPortrait(layout, env, x, y, title)
    drawActorStatusCell(layout, env, x, y, title, ctx)
    drawLayoutGauges(layout.gauges, env, x, y)

    local text = layout.text ~= nil and layout.text or win.text

    if style == "list" then
        local cached = listCache[id]
        if cached then
            drawList(win, layout, cached.rows, cached.cursor, env, x, y, w, h, title, ctx and ctx.session, animScale)
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
    elseif style == "command" then
        -- Each entry is its own bordered slot (owner direction 13.07.2026)
        -- rather than free-floating text in one shared bar -- no outer
        -- panel is drawn for this style, the slots themselves are the
        -- window's whole visible surface.
        local cached = listCache[id]
        if cached then
            drawCommandSlots(layout, cached.rows, cached.cursor, env, x, y, w, h, animScale)
        end
    elseif style == "roulette" then
        local cached = listCache[id]
        if cached then
            drawRoulette(win, layout, cached.rows, cached.cursor, env, x, y, w, h, title)
        end
    elseif style == "partyGrid" then
        local cached = listCache[id]
        if cached then
            drawPartyGridStyle(layout, cached.rows, cached.cursor, env, x, y, ctx.session, title, animScale)
        end
    elseif style == "enemyRow" then
        renderer.drawEnemyRowWindow(env.v and env.v.battle)
    elseif style == "battleLog" then
        renderer.drawBattleLogWindow(env.v and env.v.combatLog, x, y, w, h)
    elseif style == "victoryPanel" then
        renderer.drawVictoryPanelWindow(ctx.session, env.v and env.v.victory,
            env.v and env.v.victoryStage or 0, env.v, x, y, w, h)
    elseif style == "levelUpStats" then
        renderer.drawLevelUpStatsWindow(env.v and env.v.levelUpRows, x, y, w, h, title)
    elseif style == "targetInfo" then
        renderer.drawTargetInfoWindow(ctx and ctx.session, env.v, x, y, w, h)
    elseif style == "itemInfo" then
        local cached = listCache[id]
        local row = cached and cached.rows[cached.cursor]
        local text = row and row.gameplayText or "No item selected."
        drawTextLines(text, env, contentX, contentY, lineSpacing, w - ui.toPx(2))
    elseif style == "keyArt" then
        local cached = listCache[id]
        local row = cached and cached.rows[cached.cursor]
        local path = row and row.keyArt
        if path and path ~= "" and love.filesystem.getInfo(path) then
            win._keyArtCache = win._keyArtCache or {}
            local image = win._keyArtCache[path]
            if not image then
                image = love.graphics.newImage(path)
                -- Showcase sources are Lanczos-downsampled to their native UI
                -- size. Preserve those antialiased edges if a layout applies a
                -- small fractional scale instead of snapping back to nearest.
                image:setFilter("linear", "linear")
                win._keyArtCache[path] = image
            end
            local pad = ui.toPx(1)
            local aw, ah = w - pad * 2, h - pad * 2
            local scale = math.min(aw / image:getWidth(), ah / image:getHeight())
            local dw, dh = image:getWidth() * scale, image:getHeight() * scale
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, x + (w - dw) / 2, y + (h - dh) / 2, 0, scale, scale)
        else
            ui.drawString("NO KEY ART", contentX, y + h / 2 - ui.lineHeight / 2,
                COLOR_DIM, "center", w - ui.toPx(2))
        end
    else -- "panel", "frame" and any unknown style: text content
        if text then
            -- Left-justified by default everywhere (owner feedback: too much
            -- of the UI was center-justified when it shouldn't be) — an
            -- explicit layout.align still overrides per window.
            local align = layout.align or "left"

            -- Padding is symmetric on all 4 sides: contentX/contentY (the
            -- top-left inset, default or author-set) mirrored onto the
            -- right/bottom edges. No dynamic "shrink text to fit, recenter
            -- if it doesn't" behavior here anymore — that rule used to
            -- misfire on ordinary windows (wrapped dialogue text, etc.),
            -- spilling text past the padding instead of respecting it. A
            -- window that's too small for its text should get a smaller
            -- explicit contentX/contentY (e.g. the name-box style small
            -- panels), not a runtime workaround.
            local padX = contentX - x
            local revealElapsed
            if win.reveal then
                local ok, secs = pcall(formula.eval, win.reveal, env)
                if ok then revealElapsed = tonumber(secs) end
            end
            drawTextLines(text, env, contentX, contentY, lineSpacing, w - 2 * padX,
                align, revealElapsed)
        end
    end

    -- Animated waiting-for-input marker (owner feedback 18.07.2026): any
    -- window can declare a waitInput formula; while truthy, the shared
    -- UI_WaitingForInput strip animates at the window's bottom-right,
    -- replacing textual "[Press SPACE]"-style prompts.
    if layout.waitInput then
        local ok, wv = pcall(formula.eval, layout.waitInput, env)
        if ok and (wv == true or (type(wv) == "number" and wv ~= 0)) then
            -- One tile in from the bottom-right corner, diagonally (owner
            -- feedback 18.07.2026): the 12px marker's far corner sits
            -- toPx(1) away from the window's far corner on both axes.
            local size = 12
            small_battlers.draw("UI_WaitingForInput[fps=30]",
                x + w - ui.toPx(1) - size, y + h - ui.toPx(1) - size, size)
        end
    end
end

-- Styles that draw their own panel(s) (or none at all — enemyRow is a
-- transparent viewport) instead of the generic outer ui.drawPanel at the
-- window's rect. battleLog/victoryPanel position their panel from
-- battleLayout, independently of the window's rect (see the Summoner
-- rework note above drawEnemyRowWindow in renderer.lua) — drawing the
-- generic outer panel too would double up or mismatch.
local NO_OUTER_PANEL_STYLES = {
    enemyRow = true, battleLog = true, victoryPanel = true, levelUpStats = true
}

-- A window may contribute content inside a shell/panel drawn by another
-- window. `chrome = "none"` keeps every part of the window's content
-- renderer (lists still draw rows, cursor and highlight) while suppressing
-- only the generic outer panel. This is data-authored rather than tied to
-- dialogue so any composite window can embed content the same way.
local function drawsOuterPanel(layout, style)
    return layout.chrome ~= "none" and not NO_OUTER_PANEL_STYLES[style]
end

-- A window's title was drawn BY its outer panel, so suppressing the panel
-- (`chrome = "none"`, for content sitting on the dock's shared shell) silently
-- took the title with it -- `dock_item_info` lost its "Effects / Traits"
-- header that way. The title belongs to the window, not to its background.
local function drawPanelOrTitle(layout, style, title, x, y, w, h)
    if drawsOuterPanel(layout, style) then
        ui.drawPanel(x, y, w, h, title)
    elseif title and layout.chrome == "none" and not NO_OUTER_PANEL_STYLES[style] then
        -- Only when the panel was suppressed by `chrome`. A NO_OUTER_PANEL
        -- style draws its own panel, title included (drawLevelUpStatsWindow
        -- and drawVictoryPanelWindow both do), so adding one here would
        -- render the title twice.
        ui.drawPanelTitle(title, x, y)
    end
end

-- Applies a layout's shiftWith override after visibility is resolved.
-- When layout.shiftWith names another window id that is currently hidden,
-- the shiftWhenHidden rect (table with x/y/w/h overrides) is merged in.
-- This lets a dependent window fill the space of a hidden sibling
-- (e.g. dialogue_message fills the portrait slot when no portrait is set).
-- shiftResolved is a lookup table: winId -> { visible = bool, layout = tbl }
local function applyShiftWith(layout, shiftResolved)
    local targetId = layout.shiftWith
    if not targetId then return end
    local target = shiftResolved[targetId]
    if target and not target.visible and layout.shiftWhenHidden then
        local shift = layout.shiftWhenHidden
        if shift.x ~= nil then layout.x = shift.x end
        if shift.y ~= nil then layout.y = shift.y end
        if shift.w ~= nil then layout.width = shift.w end
        if shift.h ~= nil then layout.height = shift.h end
    end
end

local function drawWindow(id, win, layout, state, sceneData, ctx, env, listCache, layouts)
    layout = resolvePageLayout(layout, env)
    local x, y = ui.toPx(layout.x or 0), ui.toPx(layout.y or 0)
    local w, h = ui.toPx(layout.width or 8), ui.toPx(layout.height or 4)
    local style = layout.style or "panel"
    local title = layout.title
    if title then title = interpolate(title, env) end

    -- Confirmation windows are modal: dim everything already drawn behind
    -- them with the shared PSX subtractive primitive before drawing the
    -- modal itself. This preserves bright UI colors better than a uniform
    -- alpha-black overlay and keeps every confirm surface consistent.
    if style == "confirm" then
        subtractive_fade.draw(0.4)
    end

    local animOpen = layout.anim and layout.anim.open
    if animOpen and animOpen.anchor then
        local ax, ay = resolveAnchor(animOpen.anchor, ctx, listCache, layouts)
        x, y = anchoredRestPosition(ax, ay, x, y, w, h)
    end

    -- Support alpha fade: if the open animation has effect="fade", push
    -- a global alpha so panel AND content fade in together.
    local alphaPushed = false
    local phase = (win._closing) and "close" or "open"
    local anim = layout.anim and layout.anim[phase]
    if anim and anim.effect == "fade" then
        local _, _, _, _, alpha, animating = windowAnimRect(win, layout, x, y, w, h, ctx, listCache, layouts, win._closing)
        if animating and alpha < 1 then
            love.graphics.push("all")
            love.graphics.setColor(1, 1, 1, alpha)
            alphaPushed = true
        end
    end

    local px, py, pw, ph, _, animating = windowAnimRect(win, layout, x, y, w, h, ctx, listCache, layouts, win._closing)
    if animating then
        local sx, sy, sw, sh = love.graphics.getScissor()
        love.graphics.intersectScissor(px, py, pw, ph)
        drawPanelOrTitle(layout, style, title, px, py, pw, ph)
        drawWindowContent(id, win, layout, style, title, x, y, w, h, env, listCache, ctx,
            (w > 0) and math.max(0, math.min(1, pw / w)) or 1)
        if sx then love.graphics.setScissor(sx, sy, sw, sh) else love.graphics.setScissor() end
    else
        drawPanelOrTitle(layout, style, title, x, y, w, h)
        drawWindowContent(id, win, layout, style, title, x, y, w, h, env, listCache, ctx)
    end

    -- Idle ambient animation (e.g. border pulse)
    if layout.anim and layout.anim.idle and not animating then
        local idle = layout.anim.idle
        if idle.effect == "pulseBorder" then
            local t = love.timer.getTime()
            local period = idle.period or 2.0
            local pulse = 0.5 + 0.5 * math.sin(t * (2 * math.pi / period))
            love.graphics.push("all")
            local col = idle.color or {1, 0.85, 0.5}
            love.graphics.setColor(col[1], col[2], col[3], 0.25 * pulse)
            love.graphics.rectangle("line", x - 1, y - 1, w + 2, h + 2)
            love.graphics.pop()
        end
    end

    -- Focus visual indicator
    if state and state.focusedWindow == id and layout.anim and layout.anim.focus then
        local focusAnim = layout.anim.focus
        if focusAnim.effect == "pulseBorder" or focusAnim.effect == "highlight" then
            local t = love.timer.getTime()
            local pulse = 0.5 + 0.5 * math.sin(t * 8)
            love.graphics.push("all")
            love.graphics.setColor(1, 1, 0.7, 0.3 * pulse)
            love.graphics.rectangle("line", x, y, w, h)
            love.graphics.pop()
        end
    end

    if alphaPushed then
        love.graphics.pop()
    end
end

-- ---------------------------------------------------------------------------
-- S1w: drawWindowFromData — generic window renderer driven entirely by a
-- scene's `windows` array (data/scenes.json).  The windows array declares
-- each window's id, rect (expressions), visible (expr), and an array of
-- typed content blocks (text, list, gauge, image).  Expression evaluation
-- uses the same sandboxed env as scene hooks (v.*, config, sel(), formula
-- engine).  Unknown content-block types fail soft (log once, skip block);
-- unknown optional fields in window defs are ignored (extensibility rule).
--
-- S2w: reserve scene swap indicator (black silhouette + floating ghost) is
-- drawn AFTER the windows pass, so the effect survives data-authored windows.
-- ---------------------------------------------------------------------------

-- Per-type warning-once guard so unknown content block types don't spam.
local warnedBlockTypes = {}

-- Data-authored window visibility tracking for close-animation and
-- shiftWith support. Persisted on state so transitions survive frames.
local function initVisibilityState(state)
    state._visTrack = state._visTrack or {}
end

-- opts (all optional) lets a caller other than the scene drive this renderer:
--   windows -- window defs to draw INSTEAD of sceneData.windows
--   store   -- table holding the persistent `_dataWins` / `_visTrack` bookkeeping.
--              Defaults to the scene state (destroyed on every scene change);
--              presentation/dock.lua passes its own module-level store so the
--              persistent dock's animation clocks survive scene transitions.
--   alpha   -- global alpha multiplier (dock variant cross-fade).
-- Everything else -- env, list resolution, v.* bindings -- still comes from the
-- CURRENT scene, so dock windows bind to the live scene's variables.
function wr.drawWindowFromData(sceneData, state, ctx, opts)
    opts = opts or {}
    local winDefs = opts.windows or (sceneData and sceneData.windows)
    if not winDefs then return end
    local store = opts.store or state

    local alphaPushed = false
    if opts.alpha and opts.alpha < 1 then
        love.graphics.push("all")
        love.graphics.setColor(1, 1, 1, opts.alpha)
        alphaPushed = true
    end

    -- Resolve the list cache and env once, shared by all data windows.
    -- Build a minimal listCache so sel("window_id") works during content
    -- block evaluation (text interpolation, gauge formulas).
    local listCache = {}
    local env = buildEnv(state, sceneData, ctx, listCache)

    -- Pre-resolve lists for every window that has a list content block,
    -- so sel() lookups and cursor evaluation work.
    for _, winDef in ipairs(winDefs) do
        local listBlock = nil
        for _, block in ipairs(winDef.content or {}) do
            if block.type == "list" then
                listBlock = block
                break
            end
        end
        if listBlock then
            local syntheticWin = {
                listId = listBlock.listId,
                format = listBlock.format,
                formatRight = listBlock.formatRight,
                cursorFormula = listBlock.cursor ~= nil and listBlock.cursor or winDef.cursor,
                cursor = 1,
                sprite = listBlock.sprite,
                gaugeValue = listBlock.gaugeValue,
                gaugeMax = listBlock.gaugeMax,
                highlight = listBlock.highlight,
                filter = listBlock.filter,
                priority = listBlock.priority,
                tabs = listBlock.tabs or winDef.tabs,
                tabVar = listBlock.tabVar or winDef.tabVar,
                slot = listBlock.slot,
                member = listBlock.member,
            }
            local rows = resolveRows(syntheticWin, state, sceneData, ctx, env)
            local cur = liveCursor(syntheticWin, env)
            listCache[winDef.id] = { rows = rows, cursor = cur }
        end
    end

    -- Rebuild env now that listCache is populated (sel() needs it).
    env = buildEnv(state, sceneData, ctx, listCache)

    local layouts = (ctx.loader and ctx.loader.engine and ctx.loader.engine.windowLayout) or {}

    -- Persistent synthetic win tables, one per window id. openClocks (the
    -- open-animation timer) is keyed by the win TABLE, so rebuilding it
    -- every frame reset the animation each frame and any anim.open window
    -- stayed frozen at its 16px pop-in floor (the reserve popup "sliver"
    -- bug).
    store._dataWins = store._dataWins or {}
    initVisibilityState(store)

    -- ── Pass 1: resolve visibility for all windows into shiftResolved. ──
    -- We need every window's visibility known before any window draws so
    -- shiftWith (which reads another window's visibility) works reliably.
    local shiftResolved = {}
    for _, winDef in ipairs(winDefs) do
        local visible = true
        if winDef.visible then
            local ok, vv = pcall(formula.eval, winDef.visible, env)
            if not ok then visible = false
            else visible = vv == true or (type(vv) == "number" and vv ~= 0) end
        end
        shiftResolved[winDef.id] = { visible = visible }
    end

    -- ── Pass 2: draw windows, applying shiftWith and close/open anims. ──
    for _, winDef in ipairs(winDefs) do
        local visible = shiftResolved[winDef.id].visible

        -- Close-animation detection: if this window was visible last frame
        -- and is now hidden, and has anim.close, keep it "alive" through
        -- the close animation before truly hiding it.
        local prevVis = store._visTrack[winDef.id]
        store._visTrack[winDef.id] = visible
        local closeAnimStart = nil
        local wasVisible = prevVis ~= false -- default true for first frame
        if not visible and wasVisible then
            local winTable = store._dataWins[winDef.id]
            if winTable then
                local baseLayout = layouts[winDef.id]
                local hasClose = false
                if baseLayout and baseLayout.anim and baseLayout.anim.close then
                    hasClose = true
                elseif winDef.anim and winDef.anim.close then
                    hasClose = true
                end
                if hasClose then
                    -- Keep drawing this window for the close animation duration.
                    -- Signal to drawWindow that it's closing by setting _closing.
                    winTable._closing = true
                    closeAnimStart = love.timer.getTime()
                    visible = true -- override: keep drawing
                end
            end
        end

        -- A close animation spans many frames, but `wasVisible` is only true
        -- on the FIRST hidden frame -- `_visTrack` was set to false above. So
        -- from frame two the override no longer applied, the branch below ran
        -- and cleared `_closing`, and every close animation in the game lasted
        -- exactly one frame. Keep a closing window alive; the `_closing` check
        -- further down ends it when its clock reports done.
        if not visible then
            local closingWin = store._dataWins[winDef.id]
            if closingWin and closingWin._closing then visible = true end
        end

        if not visible then
            -- Drop the hidden window's anim clocks so re-showing replays
            -- the animation.
            local prev = store._dataWins[winDef.id]
            if prev then
                openClocks[prev] = nil
                closeClocks[prev] = nil
                prev._closing = nil
            end
            goto continue
        end

        -- Build a synthetic window layout: start from engine.json
        -- windowLayout, then overlay the windows array's own properties.
        local layout = {}
        local baseLayout = layouts[winDef.id]
        if baseLayout then
            for k, v in pairs(baseLayout) do layout[k] = v end
        end

        -- Resolve rect (expressions allowed per-value).
        local x = resolveDim(winDef.rect and winDef.rect.x, layout.x or 0, env)
        local y = resolveDim(winDef.rect and winDef.rect.y, layout.y or 0, env)
        local w = resolveDim(winDef.rect and winDef.rect.w, layout.width or 8, env)
        local h = resolveDim(winDef.rect and winDef.rect.h, layout.height or 4, env)
        layout.x = x
        layout.y = y
        layout.width = w
        layout.height = h
        if winDef.style ~= nil then layout.style = winDef.style end
        if winDef.title ~= nil then layout.title = winDef.title end
        if winDef.emptyText ~= nil then layout.emptyText = winDef.emptyText end
        if winDef.lineSpacing ~= nil then layout.lineSpacing = winDef.lineSpacing end
        if winDef.visibleRows ~= nil then layout.visibleRows = winDef.visibleRows end
        if winDef.align ~= nil then layout.align = winDef.align end
        if winDef.waitInput ~= nil then layout.waitInput = winDef.waitInput end
        if winDef.chrome ~= nil then layout.chrome = winDef.chrome end
        -- Propagate shiftWith from winDef to layout (scenes.json overrides
        -- engine.json, so this must happen AFTER baseLayout merge).
        if winDef.shiftWith ~= nil then layout.shiftWith = winDef.shiftWith end
        if winDef.shiftWhenHidden ~= nil then layout.shiftWhenHidden = winDef.shiftWhenHidden end
        -- Propagate anim blocks from winDef, merged over baseLayout's.
        if winDef.anim then
            layout.anim = layout.anim or {}
            for k, v in pairs(winDef.anim) do layout.anim[k] = v end
        end

        -- Apply shiftWith: if the referenced window is hidden, override
        -- this window's rect to fill the void.
        applyShiftWith(layout, shiftResolved)

        -- Grab or create the persistent win entry. If this window is
        -- closing from a prior frame, the existing table is reused so
        -- the close clock (keyed by the win TABLE) survives.
        local win = store._dataWins[winDef.id]
        if not win then
            win = {}
            store._dataWins[winDef.id] = win
        elseif win._closing then
            -- Close animation continued from a prior frame: check if done.
            -- Compute progress; if finished, truly hide and skip drawing.
            local closeAnim = layout.anim and layout.anim.close
            if closeAnim then
                local p, running = animProgress(closeClocks, win, closeAnim.duration)
                if not running then
                    -- Close animation complete: truly hide.
                    win._closing = nil
                    openClocks[win] = nil
                    closeClocks[win] = nil
                    goto continue
                end
            else
                -- No close anim after all (layout changed between frames?)
                win._closing = nil
            end
        end

        -- If we started a close animation this frame, inject the clock start.
        if closeAnimStart and win._closing then
            if not closeClocks[win] then
                closeClocks[win] = closeAnimStart
            end
        end

        -- Clear fields from the previous frame's draw cycle; they're
        -- re-derived from the current content blocks below.
        win.open = true
        win.listId, win.format, win.formatRight, win.text, win.cursor = nil, nil, nil, nil, 1
        win.cursorFormula, win.sprite = nil, nil
        win.gaugeValue, win.gaugeMax, win.highlight, win.priority = nil, nil, nil, nil
        win.filter = nil
        win.tabs, win.tabVar = nil, nil
        win.gaugePreviewCost, win.gaugePreviewGain, win.gaugePreviewLabel = nil, nil, nil
        win.slot, win.member, win.labelField = nil, nil, nil
        win._resolvedRows, win._resolvedCursor = nil, nil
        local gauges = {}

        for _, block in ipairs(winDef.content or {}) do
            if block.type == "list" then
                win.listId = block.listId
                win.format = block.format
                win.formatRight = block.formatRight
                win.cursorFormula = block.cursor
                win.sprite = block.sprite
                win.gaugeValue = block.gaugeValue
                win.gaugeMax = block.gaugeMax
                win.gaugePreviewCost = block.gaugePreviewCost
                win.gaugePreviewGain = block.gaugePreviewGain
                win.gaugePreviewLabel = block.gaugePreviewLabel
                win.highlight = block.highlight
                win.filter = block.filter
                win.priority = block.priority
                win.tabs = block.tabs or winDef.tabs
                win.tabVar = block.tabVar or winDef.tabVar
                win.slot = block.slot
                win.member = block.member
                win.labelField = block.labelField
                -- pull rows from pre-resolved cache
                local cached = listCache[winDef.id]
                if cached then
                    win._resolvedRows = cached.rows
                    win._resolvedCursor = cached.cursor
                end
            elseif block.type == "text" then
                win.text = block.text
                -- Optional formula yielding seconds elapsed on this text's
                -- typewriter reveal; absent means "draw it all at once".
                win.reveal = block.reveal
            elseif block.type == "gauge" then
                table.insert(gauges, block)
            elseif block.type == "image" then
                -- image blocks are passed through as layout-level properties
                -- for the existing drawPortrait path; future richer image
                -- support can extend this.
                if block.portraitField then
                    layout.portrait = block.portraitField
                end
                if block.portraitX ~= nil then layout.portraitX = block.portraitX end
                if block.portraitY ~= nil then layout.portraitY = block.portraitY end
                -- Optional box-fit size (tile units). Without these, drawPortrait
                -- keeps its old 1:1, unsliced draw exactly as before -- existing
                -- callers (e.g. the ritual scene's portrait toggle) are
                -- unaffected. Portrait sheets are 640x192 (5 128x192 columns);
                -- box-fit sizing slices the neutral first column via
                -- ui.drawSlicedPortrait.
                if block.portraitW ~= nil then layout.portraitW = block.portraitW end
                if block.portraitH ~= nil then layout.portraitH = block.portraitH end
                if block.portraitOverflow ~= nil then layout.portraitOverflow = block.portraitOverflow end
                if block.portraitFrame ~= nil then layout.portraitFrame = block.portraitFrame end
                if block.portraitName ~= nil then layout.portraitName = block.portraitName end
            else
                -- Unknown block types fail soft (extensibility rule).
                if not warnedBlockTypes[block.type] then
                    print("[window_renderer] warning: unknown content block type '" .. tostring(block.type) .. "' in window '" .. tostring(winDef.id) .. "' — skipping")
                    warnedBlockTypes[block.type] = true
                end
            end
        end

        -- If any gauge blocks were collected, attach them to the layout.
        if #gauges > 0 then
            layout.gauges = gauges
        end

        -- Override cursor from list cache if available.
        if win._resolvedCursor then
            win.cursor = win._resolvedCursor
        end
        -- If the window def has its own cursor formula (e.g. party grid with
        -- cursor hidden as 0), use it as fallback when the content block
        -- doesn't specify one. PartyGrid windows that define cursor at the
        -- def level but have a listId in content need this fallback path.
        if winDef.cursor ~= nil and win.cursorFormula == nil then
            win.cursorFormula = tostring(winDef.cursor)
        end

        -- Use the list cache for sel() when drawing this window.
        local winListCache = {}
        if win._resolvedRows then
            winListCache[winDef.id] = { rows = win._resolvedRows, cursor = win.cursor }
        end

        -- Adaptive height (owner feedback 18.07.2026): fitRows shrinks a
        -- list window to its actual row count (rect h stays the numeric MAX,
        -- keeping the editor's geometry math working). "bottom" re-anchors
        -- so the window hugs its rect's bottom edge -- the dialogue choice
        -- strip grows upward from the dialog box's bottom.
        if winDef.fitRows and win._resolvedRows then
            local rowCount = #win._resolvedRows
            if rowCount > 0 then
                -- Mirror drawList's scroll math exactly (visible rows =
                -- (h - toPx(3)) / rowPitch), or the shrunk window would
                -- clip rows it was sized for.
                local pitch = layout.rowPitch and ui.toPx(layout.rowPitch) or ui.lineHeight
                local fitPx = rowCount * pitch + ui.toPx(3)
                local maxPx = ui.toPx(layout.height)
                if fitPx < maxPx then
                    local shrinkTiles = (maxPx - fitPx) / ui.toPx(1)
                    layout.height = layout.height - shrinkTiles
                    if winDef.fitRows == "bottom" then
                        layout.y = layout.y + shrinkTiles
                    end
                end
            end
        end

        drawWindow(winDef.id, win, layout, state, sceneData, ctx, env, winListCache, layouts)

        ::continue::
    end

    if alphaPushed then love.graphics.pop() end
end

-- ---------------------------------------------------------------------------
-- Entry point: draw all open windows of the scene state, in open order.
-- If the scene has a data-authored `windows` array, uses drawWindowFromData
-- instead of the runtime winState path.
--
-- Who still needs the runtime winState path (25.07.2026): every `"draw":
-- "windows"` scene is now declarative -- Item Creation was the last holdout --
-- but the path is NOT dead. It still serves the `map` world scene (no windows
-- array; its hooks drive the exploration HUD through window commands) and
-- main.lua's drawSharedPartyHud, which hands us a synthetic winState with no
-- sceneData at all. Note the early return below: for a scene WITH a windows
-- array, any OPEN_WINDOW/SET_TEXT its hooks still emit is inert.
-- ---------------------------------------------------------------------------
function wr.draw(state, sceneData, ctx)
    -- S1w: scenes with a data-authored windows array draw entirely through
    -- drawWindowFromData.  Unknown optional fields in the window def are
    -- silently ignored (extensibility rule).
    if sceneData and sceneData.windows and #sceneData.windows > 0 then
        wr.drawWindowFromData(sceneData, state, ctx)
        -- S2w: reserve swap indicator must survive data-authored windows.
        if sceneData and sceneData.id == "reserve" then
            drawSwapIndicator(state, sceneData, ctx)
        end
        return
    end

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

    local layouts = (ctx.loader and ctx.loader.engine and ctx.loader.engine.windowLayout) or {}
    for _, id in ipairs(state.windowOrder or {}) do
        local win = state.winState[id]
        if win and win.open then
            drawWindow(id, win, layouts[id] or {}, state, sceneData, ctx, env, listCache, layouts)
        elseif win then
            -- Closed windows drop their open-anim clock so re-opening
            -- replays the animation.
            openClocks[win] = nil
        end
    end

    -- Reserve scene (overhaul-6 F3): while picking a Swap target (v.mode == 4),
    -- the source slot is dimmed and a full-opacity ghost of its panel floats
    -- above it (sine drift), as a "select target slot" cue.
    if sceneData and sceneData.id == "reserve" then
        drawSwapIndicator(state, sceneData, ctx)
    end
end

-- Screenshot/export seam: mark every currently materialized window, plus any
-- declarative definitions supplied by the caller, as already through its open
-- animation. Window animations use love.timer.getTime() in live play, which is
-- correct there but means a headless exporter that renders immediately sees
-- only the first 16px frame (or no useful content at all). The next draw
-- consumes _skipOpenAnim and renders the resting geometry without sleeping.
--
-- `store` may be a scene state or the persistent dock store. Runtime winState
-- windows are handled too, so the exporter does not need to know which of the
-- two generic window paths a scene uses.
function wr.finishAnimationsForCapture(store, windowDefs)
    if type(store) ~= "table" then return end

    store._dataWins = store._dataWins or {}
    for _, winDef in ipairs(windowDefs or {}) do
        if winDef.id and not store._dataWins[winDef.id] then
            store._dataWins[winDef.id] = {}
        end
    end

    local function finish(win)
        if type(win) ~= "table" then return end
        openClocks[win] = nil
        closeClocks[win] = nil
        win._closing = nil
        win._skipOpenAnim = true
    end

    for _, win in pairs(store._dataWins) do finish(win) end
    for _, win in pairs(store.winState or {}) do finish(win) end
end

-- ---------------------------------------------------------------------------
-- E5: materialize the current window state as plain data for the headless
-- scene preview (`lovec . preview-scene <id>`). Same resolution code paths
-- as wr.draw — list sources expanded to formatted row strings, {expr} text
-- interpolated, live cursor evaluated — but no drawing. Per-window failures
-- become an `error` field on that window instead of crashing the preview.
--
-- S2w: for data-authored scenes (scene.windows) whose hooks no longer emit
-- OPEN_WINDOW commands (those are redundant with the declarative windows
-- array), winState is empty — delegate to resolveDataState so the preview
-- reads directly from the scene's windows array with real v-state.
-- ---------------------------------------------------------------------------
function wr.resolveState(state, sceneData, ctx)
    -- S2w: delegate to resolveDataState when the scene is data-authored but
    -- has no winState (hooks were cleaned of redundant window commands).
    if sceneData and sceneData.windows and #sceneData.windows > 0
        and state and (not state.winState or #state.winState == 0) then
        return wr.resolveDataState(sceneData, ctx, state)
    end

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

-- ---------------------------------------------------------------------------
-- S1w: resolveState for data-authored windows — produces the same preview
-- metadata shape as the winState path, but reads from the scene's windows
-- array instead of runtime winState.  Used by the scene preview endpoint
-- when a scene has a `windows` array.
-- ---------------------------------------------------------------------------
function wr.resolveDataState(sceneData, ctx, state)
    local result = {
        tileSize = ui.tileSize,
        focused = state and state.focusedWindow or nil,
        windows = {},
    }
    if not sceneData or not sceneData.windows then return result end

    local listCache = {}
    -- Use caller-supplied state (with real v from hook execution) when
    -- available; fall back to an empty state for ad-hoc/preview use.
    state = state or { v = {}, winState = {}, windowOrder = {} }
    local env = buildEnv(state, sceneData, ctx, listCache)

    -- Pre-resolve lists for sel().
    for _, winDef in ipairs(sceneData.windows) do
        local listBlock = nil
        for _, block in ipairs(winDef.content or {}) do
            if block.type == "list" then
                listBlock = block
                break
            end
        end
        if listBlock then
            local syntheticWin = {
                listId = listBlock.listId,
                format = listBlock.format,
                formatRight = listBlock.formatRight,
                cursorFormula = listBlock.cursor ~= nil and listBlock.cursor or winDef.cursor,
                cursor = 1,
                sprite = listBlock.sprite,
                gaugeValue = listBlock.gaugeValue,
                gaugeMax = listBlock.gaugeMax,
                highlight = listBlock.highlight,
                filter = listBlock.filter,
                priority = listBlock.priority,
                slot = listBlock.slot,
                member = listBlock.member,
            }
            local ok, rows = pcall(resolveRows, syntheticWin, state, sceneData, ctx, env)
            local cur = 1
            if ok then
                local okC, curV = pcall(liveCursor, syntheticWin, env)
                if okC then cur = curV end
            end
            listCache[winDef.id] = { rows = ok and rows or {}, cursor = cur }
        end
    end

    -- Rebuild env with populated listCache.
    env = buildEnv(state, sceneData, ctx, listCache)

    -- Same engine.json windowLayout base the real draw path merges
    -- (drawWindowFromData): a window that omits rect/style/title inherits them
    -- from its layout entry rather than from invented defaults. Without this the
    -- preview reported every such window at 0,0 8x4 with no title -- an
    -- approximation of the renderer instead of the renderer's own geometry.
    local layouts = (ctx.loader and ctx.loader.engine and ctx.loader.engine.windowLayout) or {}

    for _, winDef in ipairs(sceneData.windows) do
        local visible = true
        if winDef.visible then
            local ok, vv = pcall(formula.eval, winDef.visible, env)
            if ok then
                visible = vv == true or (type(vv) == "number" and vv ~= 0)
            else
                visible = false
            end
        end

        local baseLayout = resolvePageLayout(layouts[winDef.id] or {}, env)
        local x = resolveDim(winDef.rect and winDef.rect.x, baseLayout.x or 0, env)
        local y = resolveDim(winDef.rect and winDef.rect.y, baseLayout.y or 0, env)
        local w = resolveDim(winDef.rect and winDef.rect.w, baseLayout.width or 8, env)
        local h = resolveDim(winDef.rect and winDef.rect.h, baseLayout.height or 4, env)

        local entry = {
            id = winDef.id,
            open = visible,
            hasLayout = layouts[winDef.id] ~= nil,
            style = winDef.style or baseLayout.style or "panel",
            x = x,
            y = y,
            width = w,
            height = h,
        }

        local titleSrc = winDef.title ~= nil and winDef.title or baseLayout.title
        if titleSrc ~= nil then
            local okT, title = pcall(interpolate, titleSrc, env)
            entry.title = okT and title or ("<error: " .. tostring(title) .. ">")
        end

        -- Collect text content from text blocks. A layout-level `text` wins, as
        -- it does in drawWindow.
        if baseLayout.text ~= nil then
            local okT, text = pcall(interpolate, baseLayout.text, env)
            entry.text = okT and text or ("<error: " .. tostring(text) .. ">")
        end
        for _, block in ipairs(winDef.content or {}) do
            if block.type == "text" and entry.text == nil then
                local okT, text = pcall(interpolate, block.text or "", env)
                entry.text = okT and text or ("<error: " .. tostring(text) .. ">")
            end
        end

        local cached = listCache[winDef.id]
        if cached then
            entry.cursor = cached.cursor
            entry.rows = {}
            -- Find the list block's format for row rendering.
            local format = "{name}"
            local highlight = nil
            for _, block in ipairs(winDef.content or {}) do
                if block.type == "list" then
                    entry.listId = block.listId
                    if block.format then format = block.format end
                    highlight = block.highlight
                    break
                end
            end
            for _, row in ipairs(cached.rows) do
                local rEnv = rowEnv(env, row)
                local okR, textR = pcall(interpolate, format, rEnv)
                local highlighted = false
                if highlight and highlight ~= "" then
                    local okH, hv = pcall(formula.eval, highlight, rEnv)
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

    return result
end

return wr
