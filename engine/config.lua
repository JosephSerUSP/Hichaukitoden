local json = require("data.json")

local config = {}

-- Engine-wide capacity defaults. system.json may override them, but they are
-- structural limits rather than ordinary optional presentation settings, so a
-- config reload must never make them disappear when the active campaign omits
-- an override.
local LIMIT_DEFAULTS = {
    MAX_PARTY_SIZE = 4,
    MAX_RESERVE_SIZE = 4,
    MAX_STORAGE_SIZE = 99,
}

local function applyLimitDefaults()
    for key, value in pairs(LIMIT_DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
end

function config.load()
    -- Follows the active campaign root (see data/loader.lua resolveRoot):
    -- reads loader.root when the loader module is already loaded, else
    -- resolves the pointer file itself (this module loads at require time,
    -- possibly before loader.init has run).
    local ldr = package.loaded["data.loader"]
    local root = (ldr and ldr.root ~= "data" and ldr.root)
        or (ldr and ldr.resolveRoot and ldr.resolveRoot())
        or "data"
    if love.filesystem.getInfo(root .. "/system.json") then
        local contents = love.filesystem.read(root .. "/system.json")
        if contents then
            local data = json.decode(contents)
            if data then
                -- Clear existing keys except load function
                for k, _ in pairs(config) do
                    if k ~= "load" then
                        config[k] = nil
                    end
                end

                -- Populate with new data
                for k, v in pairs(data) do
                    if k ~= "load" then
                        config[k] = v
                    end
                end
            end
        end
    end

    -- The old fallback lived only after the module's initial config.load(), so
    -- later reloads (save loading / campaign switching) cleared MAX_* forever.
    -- Restore missing structural limits on every load while still honoring an
    -- authored system.json override when one exists.
    applyLimitDefaults()
end

config.load()

return config