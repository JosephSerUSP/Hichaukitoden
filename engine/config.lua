local json = require("data.json")

local config = {}

function config.load()
    if love.filesystem.getInfo("data/system.json") then
        local contents = love.filesystem.read("data/system.json")
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
                    config[k] = v
                end
            end
        end
    end
end

config.load()

return config
