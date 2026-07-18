local socket = require("socket")
local json = require("data.json")

local server = {}
local tcpListener = nil
local active = false

-- Single manifest of database files exposed to the editor. Keep in sync with
-- DATA_FILES in tools/editor/server.js.
local DATA_FILES = {
    "actors", "elements", "events", "items", "maps", "quests", "shops",
    "sounds", "terms", "actionSequences", "system", "commonEvents",
    "skills", "passives", "states", "roles", "engine", "flows", "scenes"
}

function server.start()
    tcpListener = socket.bind("127.0.0.1", 8081)
    if tcpListener then
        tcpListener:settimeout(0)
        active = true
        print("Developer hot-reload server running on http://127.0.0.1:8081/")
        
        -- Ping the editor server to notify successful startup
        pcall(function()
            local http = require("socket.http")
            http.TIMEOUT = 0.5
            http.request("http://127.0.0.1:8080/ping?scene=game_loaded")
        end)
    else
        print("Failed to bind developer hot-reload server to port 8081")
    end
end

function server.stop()
    if tcpListener then
        tcpListener:close()
        tcpListener = nil
    end
    active = false
end

function server.isActive()
    return active
end

local function sendResponse(client, status, contentType, body)
    local headers = {
        "HTTP/1.1 " .. status,
        "Content-Type: " .. contentType,
        "Access-Control-Allow-Origin: http://127.0.0.1:8080",
        "Access-Control-Allow-Methods: GET, POST, OPTIONS",
        "Access-Control-Allow-Headers: Content-Type",
        "Content-Length: " .. tostring(#body),
        "Connection: close",
        "",
        body
    }
    client:send(table.concat(headers, "\r\n"))
    client:close()
end

function server.update(dt)
    if not active or not tcpListener then return end
    
    local client = tcpListener:accept()
    if client then
        client:settimeout(1.0)
        local line, err = client:receive()
        if line then
            local method, path = line:match("^(%S+)%s+(%S+)%s+HTTP/")
            if method then
                if method == "OPTIONS" then
                    sendResponse(client, "200 OK", "text/plain", "")
                elseif method == "GET" and path == "/reload" then
                    -- Reload loader caches
                    local loader = require("data.loader")
                    loader.init()
                    
                    -- Reload configuration
                    local config = require("engine.config")
                    config.load()

                    -- Hot-reload active UI font
                    local ui = require("presentation.ui")
                    if config.ui and config.ui.activeFont then
                        ui.setFont(config.ui.activeFont, config.ui.fontSize)
                    end
                    if config.battle_screen and config.battle_screen.popup and config.battle_screen.popup.font then
                        ui.loadPopupFont(config.battle_screen.popup.font, config.battle_screen.popup.fontSize)
                    end
                    
                    sendResponse(client, "200 OK", "application/json", json.encode({ success = true, message = "Reloaded config and database" }))
                elseif method == "GET" and path == "/data" then
                    local function getFileContents(fpath)
                        local contents = love.filesystem.read(fpath)
                        return contents and json.decode(contents) or nil
                    end

                    local data = {}
                    for _, name in ipairs(DATA_FILES) do
                        data[name] = getFileContents(require("data.loader").root .. "/" .. name .. ".json")
                    end

                    local responseBody = json.encode(data)
                    sendResponse(client, "200 OK", "application/json", responseBody)
                    
                elseif method == "POST" and path == "/save" then
                    local contentLength = 0
                    while true do
                        local headerLine = client:receive()
                        if not headerLine or headerLine == "" then break end
                        local len = headerLine:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")
                        if len then contentLength = tonumber(len) end
                    end
                    
                    local body = ""
                    if contentLength > 0 then
                        body = client:receive(contentLength)
                    end
                    
                    local success = false
                    local statusMsg = "Failed to parse save data."
                    
                    if body and body ~= "" then
                        local payload = json.decode(body)
                        if payload then
                            local function saveFile(fpath, tbl)
                                if tbl then
                                    local encoded = json.encode(tbl)
                                    -- Write to project source directory using absolute path
                                    local absPath = love.filesystem.getSourceDirectory() .. "/" .. fpath
                                    local file, err = io.open(absPath, "w")
                                    if file then
                                        file:write(encoded)
                                        file:close()
                                    else
                                        print("Failed to write to project file: " .. tostring(err))
                                    end
                                    -- Also write to save directory
                                    love.filesystem.write(fpath, encoded)
                                end
                            end
                            
                            for _, name in ipairs(DATA_FILES) do
                                saveFile(require("data.loader").root .. "/" .. name .. ".json", payload[name])
                            end
                            
                            -- Reload loader caches
                            local loader = require("data.loader")
                            loader.init()
                            
                            -- Reload configuration
                            local config = require("engine.config")
                            config.load()

                            -- Hot-reload active UI font
                            local ui = require("presentation.ui")
                            if config.ui and config.ui.activeFont then
                                ui.setFont(config.ui.activeFont, config.ui.fontSize)
                            end
                            if config.battle_screen and config.battle_screen.popup and config.battle_screen.popup.font then
                                ui.loadPopupFont(config.battle_screen.popup.font, config.battle_screen.popup.fontSize)
                            end
                            
                            success = true
                            statusMsg = "Saved and hot-reloaded successfully!"
                        end
                    end
                    
                    local statusText = success and "200 OK" or "400 Bad Request"
                    local responseJson = json.encode({ success = success, message = statusMsg })
                    sendResponse(client, statusText, "application/json", responseJson)
                else
                    sendResponse(client, "404 Not Found", "text/plain", "Not Found")
                end
            else
                client:close()
            end
        else
            client:close()
        end
    end
end

return server
