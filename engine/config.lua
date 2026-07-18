local json = require("data.json")

local config = {}

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

return config
