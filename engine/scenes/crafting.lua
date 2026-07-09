local ui = require("presentation.ui")
local formula = require("engine.formula")
local interpreter = require("engine.interpreter")

local crafting = {}

local windows = {}
local v = {}  -- scene locals alias

function crafting.registerKindWindows(host)
  windows = {
    header = { type = "header", style = "header" },
    discipline_list = { type = "list", source = "config.disciplines", bind = "label", format = "{label}" },
    crafter_list = { type = "list", source = "party", bind = "name", format = "{name}" },
    ingredient_slots = { type = "slots", height = 5 },
    inventory_list = { type = "list", source = "inventory", bind = "item", format = "{item.name} x{item.qty}", icon = true, filter = true },
    detail_panel = { type = "panel", title = "Item Info" },
    confirm_panel = { type = "confirm", title = "Confirm Crafting" },
    confirm_options = { type = "list", source = "[{label:'Craft'},{label:'Back'}]" },
    roulette_window = { type = "roulette", title = "Crafting..." },
    result_window = { type = "result", title = "Crafting Success!" },
    yield_text = { type = "text" },
    portrait = { scale = 1.0 }
  }
  host.registerKindWindows("crafting", windows)
end

local function refreshInventory(disc)
  -- Called from SET_LIST source/filter in hooks; legacy logic moved to interpreter SET_LIST for crafting context
end

local function calcCraftYield(ctx)
  local config = ctx.loader.scenes[1].config
  local disc = config.disciplines[ctx.v.selectedDiscipline or 1]
  local S = formula.getBattlerStat(ctx.v.crafter, disc.stat)
  local mockCtx = { i1 = formula.itemView(ctx.v.i1), i2 = formula.itemView(ctx.v.i2), crafter = ctx.v.crafter, alpha = config.alpha, S = S }
  local yield = formula.eval(config.yieldFormula, mockCtx)
  local anomaly = formula.eval(config.anomalyFormula, mockCtx)
  ctx.v.yield = yield
  ctx.v.isAnomaly = anomaly > 1.0
  return yield
end

function crafting.init(ctx)
  v = ctx.v or {}
  v.state = 1
end

function crafting.update(dt, ctx)
  v = ctx.v or v
  if ctx.sceneData and ctx.sceneData.hooks and ctx.sceneData.hooks.on_frame then
    return false -- let host drive via on_frame hook
  end
  -- legacy fallback removed per spec (thin host)
  return false
end

-- draw/keypressed/state fully removed; all via D2 hooks + windowLayout (D4 success criteria)
-- CALC_CRAFT_YIELD and START_ROULETTE registered in interpreter for scene context

return crafting
