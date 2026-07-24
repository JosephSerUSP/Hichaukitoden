local json = require("data.json")

local config = {}

-- Party/reserve size bounds (used engine-wide instead of magic numbers)
config.MAX_PARTY_SIZE = 4
config.MAX_RESERVE_SIZE = 8

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
end

config.load()

-- Party/reserve size bounds — engine-wide constants replacing magic numbers.
-- system.json may override these; these are fallback defaults.
if not config.MAX_PARTY_SIZE then config.MAX_PARTY_SIZE = 4 end
if not config.MAX_RESERVE_SIZE then config.MAX_RESERVE_SIZE = 8 end

return config
