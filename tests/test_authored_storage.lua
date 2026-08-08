local M = {}

local function expectError(label, needle, fn)
    local ok, err = pcall(fn)
    if ok then
        error(label .. ": expected an error")
    end
    if needle and not tostring(err):find(needle, 1, true) then
        error(label .. ": expected error containing '" .. needle .. "', got: " .. tostring(err))
    end
end

function M.run()
    local originalLove = _G.love
    local originalJson = package.loaded["data.json"]
    local originalStorage = package.loaded["data.authored_storage"]

    local decoded = {}
    local files = {}
    local directories = {}

    local function reset()
        decoded = {}
        files = {}
        directories = {}
    end

    local function addFile(path, value)
        files[path] = true
        decoded[path] = value
    end

    local function addDirectory(path, names)
        directories[path] = names
    end

    package.loaded["data.json"] = {
        decode = function(token)
            local value = decoded[token]
            if value == nil then error("missing decoded fixture for " .. tostring(token)) end
            return value
        end,
    }
    _G.love = {
        filesystem = {
            read = function(path)
                if files[path] then return path end
                return nil
            end,
            getInfo = function(path)
                if files[path] then return { type = "file" } end
                if directories[path] then return { type = "directory" } end
                return nil
            end,
            getDirectoryItems = function(path)
                local source = directories[path] or {}
                local copy = {}
                for index, name in ipairs(source) do copy[index] = name end
                return copy
            end,
        },
    }
    package.loaded["data.authored_storage"] = nil

    local ok, err = pcall(function()
        local storage = require("data.authored_storage")

        reset()
        addDirectory("data/widgets", { "z-storage-name.json", "a-storage-name.json", "README.md" })
        addFile("data/widgets/z-storage-name.json", { id = "alpha", value = 1 })
        addFile("data/widgets/a-storage-name.json", { id = "omega", value = 2 })
        local registry, mode = storage.loadRegistry("data", "widgets")
        assert(mode == "fragments", "registry fragment mode not reported")
        assert(registry.alpha.value == 1, "registry did not derive alpha key from record.id")
        assert(registry.omega.value == 2, "registry did not derive omega key from record.id")
        assert(registry["z-storage-name"] == nil, "registry filename leaked into identity")
        local registryFiles, registryFilesMode = storage.authoritativeFiles("data", "widgets", "registry")
        assert(registryFilesMode == "fragments", "registry provenance mode not reported")
        assert(registryFiles[1] == "data/widgets/a-storage-name.json"
            and registryFiles[2] == "data/widgets/z-storage-name.json",
            "registry provenance was not deterministic")

        reset()
        addFile("data/widgets.json", {
            alpha = { id = "alpha", value = 3 },
        })
        addDirectory("data/widgets", { "fragment.json" })
        addFile("data/widgets/fragment.json", { id = "fragment", value = 4 })
        registry, mode = storage.loadRegistry("data", "widgets")
        assert(mode == "monolith", "registry monolith must remain authoritative while it exists")
        assert(registry.alpha.value == 3 and registry.fragment == nil,
            "registry read both sources of truth at once")
        local monolithFiles, monolithMode = storage.authoritativeFiles("data", "widgets", "registry")
        assert(monolithMode == "monolith" and #monolithFiles == 1
            and monolithFiles[1] == "data/widgets.json",
            "registry provenance disagreed with monolith activation boundary")

        reset()
        addFile("data/widgets.json", {
            wrong_key = { id = "canonical" },
        })
        expectError("registry key/id mismatch", "disagrees with record.id", function()
            storage.loadRegistry("data", "widgets")
        end)

        reset()
        addDirectory("data/widgets", { "one.json", "two.json" })
        addFile("data/widgets/one.json", { id = "same" })
        addFile("data/widgets/two.json", { id = "same" })
        expectError("duplicate registry id", "duplicate id 'same'", function()
            storage.loadRegistry("data", "widgets")
        end)

        reset()
        addDirectory("data/widgets", { "index.json", "one.json" })
        addFile("data/widgets/index.json", { files = { "one.json" } })
        addFile("data/widgets/one.json", { id = "one" })
        expectError("registry manifest", "must not use a shared index.json", function()
            storage.loadRegistry("data", "widgets")
        end)

        reset()
        addDirectory("data/maps", { "index.json", "second.json", "first.json" })
        addFile("data/maps/index.json", { files = { "second.json", "first.json" } })
        addFile("data/maps/second.json", { id = 2 })
        addFile("data/maps/first.json", { id = 1 })
        local ordered, orderedMode = storage.loadOrderedCollection("data", "maps")
        assert(orderedMode == "fragments", "ordered fragment mode not reported")
        assert(ordered[1].id == 2 and ordered[2].id == 1,
            "ordered collection did not preserve manifest order")
        local orderedFiles = storage.authoritativeFiles("data", "maps", "ordered")
        assert(orderedFiles[1] == "data/maps/index.json"
            and orderedFiles[2] == "data/maps/second.json"
            and orderedFiles[3] == "data/maps/first.json",
            "ordered provenance did not preserve manifest order")
    end)

    package.loaded["data.authored_storage"] = originalStorage
    package.loaded["data.json"] = originalJson
    _G.love = originalLove

    if not ok then error(err) end
    print("=== Authored storage: 9 passed, 0 failed ===")
end

return M
