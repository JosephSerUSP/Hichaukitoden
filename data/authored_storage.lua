local json = require("data.json")

local authored_storage = {}

local function readJson(path)
    local contents = love.filesystem.read(path)
    if not contents then
        error("Could not read authored JSON file: " .. path)
    end
    local ok, value = pcall(json.decode, contents)
    if not ok then
        error("Could not decode authored JSON file '" .. path .. "': " .. tostring(value))
    end
    return value
end

local function validateFragmentPath(stem, entry, seen)
    if type(entry) ~= "string" or entry == "" then
        error(stem .. "/index.json entries must be non-empty filenames")
    end
    if entry:find("..", 1, true) or entry:sub(1, 1) == "/"
        or entry:sub(1, 1) == "\\" then
        error(stem .. "/index.json contains an unsafe fragment path: " .. entry)
    end
    if not entry:match("%.json$") then
        error(stem .. "/index.json fragment must end in .json: " .. entry)
    end
    if seen[entry] then
        error(stem .. "/index.json lists the same fragment twice: " .. entry)
    end
    seen[entry] = true
end

local function fragmentFiles(manifest, stem)
    local files = manifest
    if type(manifest) == "table" and type(manifest.files) == "table" then
        files = manifest.files
    end
    if type(files) ~= "table" or #files == 0 then
        error(stem .. "/index.json must be an array or { files = [...] }")
    end
    return files
end

local function orderedFragmentPaths(root, stem)
    local directory = root .. "/" .. stem
    local indexPath = directory .. "/index.json"
    if not love.filesystem.getInfo(indexPath) then
        error("Could not find ordered collection '" .. stem .. "' at "
            .. root .. "/" .. stem .. ".json or " .. indexPath)
    end
    local files = fragmentFiles(readJson(indexPath), stem)
    local seen = {}
    local paths = { indexPath }
    for _, entry in ipairs(files) do
        validateFragmentPath(stem, entry, seen)
        local fragmentPath = directory .. "/" .. entry
        if not love.filesystem.getInfo(fragmentPath) then
            error(stem .. "/index.json references a missing fragment: " .. fragmentPath)
        end
        table.insert(paths, fragmentPath)
    end
    return paths
end

local function registryFragmentPaths(root, stem)
    local directory = root .. "/" .. stem
    if not love.filesystem.getInfo(directory) then
        error("Could not find registry '" .. stem .. "' at "
            .. root .. "/" .. stem .. ".json or " .. directory)
    end
    local files = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(directory)) do
        if name:match("%.json$") then
            if name == "index.json" then
                error("Registry '" .. stem .. "' must not use a shared index.json")
            end
            table.insert(files, name)
        end
    end
    table.sort(files)
    if #files == 0 then
        error("Registry '" .. stem .. "' has no JSON fragments: " .. directory)
    end
    local paths = {}
    for _, name in ipairs(files) do
        table.insert(paths, directory .. "/" .. name)
    end
    return paths
end

local function appendOrderedFragment(out, value, path)
    if type(value) ~= "table" then
        error("Ordered collection fragment must contain an object or array: " .. path)
    end
    if value.id ~= nil then
        table.insert(out, value)
        return
    end
    if #value == 0 then
        error("Ordered collection fragment is neither an object with id nor a non-empty array: " .. path)
    end
    for index, entry in ipairs(value) do
        if type(entry) ~= "table" then
            error("Ordered collection fragment array contains a non-object at "
                .. path .. "[" .. tostring(index) .. "]")
        end
        table.insert(out, entry)
    end
end

local function validateOrderedCollection(entries, stem, source)
    if type(entries) ~= "table" or #entries == 0 then
        error("Ordered collection '" .. stem .. "' is not a non-empty array: " .. source)
    end
    local ids = {}
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" or entry.id == nil then
            error("Ordered collection '" .. stem .. "' entry " .. tostring(index)
                .. " has no id: " .. source)
        end
        local key = tostring(entry.id)
        if ids[key] then
            error("Ordered collection '" .. stem .. "' has duplicate id '"
                .. key .. "' in " .. source)
        end
        ids[key] = true
    end
    return entries
end

local function validateRegistryRecord(record, stem, source)
    if type(record) ~= "table" then
        error("Registry '" .. stem .. "' record is not an object: " .. source)
    end
    if type(record.id) ~= "string" or record.id == "" then
        error("Registry '" .. stem .. "' record must own a non-empty string id: " .. source)
    end
    return record.id
end

local function validateRegistryMonolith(value, stem, source)
    if type(value) ~= "table" then
        error("Registry '" .. stem .. "' is not an object: " .. source)
    end
    local out = {}
    local count = 0
    for key, record in pairs(value) do
        if type(key) ~= "string" then
            error("Registry '" .. stem .. "' monolith must be keyed by string ids: " .. source)
        end
        local id = validateRegistryRecord(record, stem, source .. "[" .. key .. "]")
        if key ~= id then
            error("Registry '" .. stem .. "' key '" .. key
                .. "' disagrees with record.id '" .. id .. "': " .. source)
        end
        if out[id] then
            error("Registry '" .. stem .. "' has duplicate id '" .. id .. "': " .. source)
        end
        out[id] = record
        count = count + 1
    end
    if count == 0 then
        error("Registry '" .. stem .. "' is empty: " .. source)
    end
    return out
end

function authored_storage.authoritativeFiles(root, stem, kind)
    local monolith = root .. "/" .. stem .. ".json"
    if love.filesystem.getInfo(monolith) then return { monolith }, "monolith" end
    if kind == "ordered" then return orderedFragmentPaths(root, stem), "fragments" end
    if kind == "registry" then return registryFragmentPaths(root, stem), "fragments" end
    error("Unknown authored storage kind: " .. tostring(kind))
end

function authored_storage.loadOrderedCollection(root, stem)
    local monolith = root .. "/" .. stem .. ".json"
    if love.filesystem.getInfo(monolith) then
        return validateOrderedCollection(readJson(monolith), stem, monolith), "monolith"
    end
    local paths = orderedFragmentPaths(root, stem)
    local out = {}
    for index = 2, #paths do
        appendOrderedFragment(out, readJson(paths[index]), paths[index])
    end
    return validateOrderedCollection(out, stem, paths[1]), "fragments"
end

function authored_storage.loadRegistry(root, stem)
    local monolith = root .. "/" .. stem .. ".json"
    if love.filesystem.getInfo(monolith) then
        return validateRegistryMonolith(readJson(monolith), stem, monolith), "monolith"
    end
    local out = {}
    for _, fragmentPath in ipairs(registryFragmentPaths(root, stem)) do
        local record = readJson(fragmentPath)
        local id = validateRegistryRecord(record, stem, fragmentPath)
        if out[id] then
            error("Registry '" .. stem .. "' has duplicate id '" .. id .. "': " .. fragmentPath)
        end
        out[id] = record
    end
    return out, "fragments"
end

return authored_storage
