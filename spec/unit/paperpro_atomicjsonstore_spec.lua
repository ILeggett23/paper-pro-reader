describe("Paper Pro AtomicJSONStore", function()
    local AtomicJSONStore, JSON, lfs, util
    local directories = {}

    setup(function()
        require("commonrequire")
        AtomicJSONStore = require("apps/paperpro/services/atomicjsonstore")
        JSON = require("rapidjson")
        lfs = require("libs/libkoreader-lfs")
        util = require("util")
    end)

    local function tempPath()
        local directory = os.tmpname() .. "-paperpro-ai"
        os.remove(directory)
        assert.is_true(util.makePath(directory))
        table.insert(directories, directory)
        return directory .. "/store.json"
    end

    teardown(function()
        for _, directory in ipairs(directories) do
            for _, suffix in ipairs({ "", ".old", ".tmp" }) do os.remove(directory .. "/store.json" .. suffix) end
            lfs.rmdir(directory)
        end
    end)

    it("repeats atomic saves and recovers a malformed primary", function()
        local path = tempPath()
        local store = AtomicJSONStore:new{
            path = path, schema_version = 1,
            validate = function(data) return type(data.items) == "table", "invalid" end,
            default_data = function() return { schema_version = 1, items = {} } end,
        }
        assert.is_true(store:save{ schema_version = 1, items = { "first" } })
        assert.is_true(store:save{ schema_version = 1, items = { "second" } })
        assert.is_true(util.fileExists(path .. ".old"))
        util.writeToFile("not json", path)
        assert.are.same("first", store:load().items[1])
    end)

    it("fails closed on unsupported future schemas", function()
        local path = tempPath()
        util.writeToFile(JSON.encode{ schema_version = 99, items = {} }, path)
        local data, err = AtomicJSONStore:new{
            path = path, schema_version = 1,
            default_data = function() return { schema_version = 1, items = {} } end,
        }:load()
        assert.is_nil(data)
        assert.are.same("unsupported_schema", err)
    end)
end)
