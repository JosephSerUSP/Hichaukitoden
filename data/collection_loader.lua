local json = require("data.json")

local collection_loader = {}

local function readJson(path)
    local contents = love.filesystem.read(path)
    if not contents then
        error("Could not read JSON collection file: " .. path)
    end
    local ok, value = pcall(json.decode, contents)
    if not ok then
        error("Could not decode JSON collection file '" .. path .. "': " .. tostring(value))
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

local function appendFragment(out, value, path)
    if type(value) ~= "table" then
        error("JSON collection fragment must contain an object or array: " .. path)
    end

    -- A single authored object is the normal form. Arrays are accepted so a
    -- generator can deliberately group tightly coupled entries without the
    -- runtime needing a second collection format.
    if value.id ~= nil then
        table.insert(out, value)
        return
    end

    if #value == 0 then
        error("JSON collection fragment is neither an object with id nor a non-empty array: " .. path)
    end
    for index, entry in ipairs(value) do
        if type(entry) ~= "table" then
            error("JSON collection fragment array contains a non-object at "
                .. path .. "[" .. tostring(index) .. "]")
        end
        table.insert(out, entry)
    end
end

local function validateCollection(entries, stem, source)
    if type(entries) ~= "table" or #entries == 0 then
        error("JSON collection '" .. stem .. "' is not a non-empty array: " .. source)
    end
    local ids = {}
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" or entry.id == nil then
            error("JSON collection '" .. stem .. "' entry " .. tostring(index)
                .. " has no id: " .. source)
        end
        -- Runtime lookups stringify authored map and scene ids, so numeric 1
        -- and string "1" are the same identity and must not coexist.
        local key = tostring(entry.id)
        if ids[key] then
            error("JSON collection '" .. stem .. "' has duplicate id '"
                .. key .. "' in " .. source)
        end
        ids[key] = true
    end
    return entries
end

-- Load an ordered JSON collection from either:
--   <root>/<stem>.json                  legacy monolith
--   <root>/<stem>/index.json + files    split collection
--
-- The monolith intentionally wins while both exist. That makes it possible to
-- generate and review fragments before every writer (web editor, game dev
-- server, campaign generator) has switched over, without the runtime reading a
-- different source of truth from the tools. Removing the monolith is the
-- explicit migration boundary that activates the split collection.
function collection_loader.load(root, stem)
    local monolith = root .. "/" .. stem .. ".json"
    if love.filesystem.getInfo(monolith) then
        return validateCollection(readJson(monolith), stem, monolith), "monolith"
    end

    local directory = root .. "/" .. stem
    local indexPath = directory .. "/index.json"
    if not love.filesystem.getInfo(indexPath) then
        error("Could not find JSON collection '" .. stem .. "' at "
            .. monolith .. " or " .. indexPath)
    end

    local manifest = readJson(indexPath)
    local files = fragmentFiles(manifest, stem)
    local seen = {}
    local out = {}
    for _, entry in ipairs(files) do
        validateFragmentPath(stem, entry, seen)
        local path = directory .. "/" .. entry
        if not love.filesystem.getInfo(path) then
            error(stem .. "/index.json references a missing fragment: " .. path)
        end
        appendFragment(out, readJson(path), path)
    end
    return validateCollection(out, stem, indexPath), "fragments"
end

return collection_loader
