describe("Paper Pro InkStore", function()
    local InkStore, InkStroke, JSON, lfs, util
    local directories = {}

    setup(function()
        require("commonrequire")
        InkStore = require("apps/paperpro/ink/inkstore")
        InkStroke = require("apps/paperpro/ink/inkstroke")
        JSON = require("rapidjson")
        lfs = require("libs/libkoreader-lfs")
        util = require("util")
    end)

    local function tempDirectory()
        local directory = os.tmpname() .. "-paperpro-ink"
        os.remove(directory)
        assert.is_true(util.makePath(directory))
        table.insert(directories, directory)
        return directory
    end

    local function stroke(id, page)
        local value = InkStroke:new{
            id = id, tool = "pen", coordinate_space = "pdf-page-v1",
            anchor = { kind = "fixed_page", document_id = "book.pdf", page = page },
        }
        value:addPoint{ x = 10, y = 20, timestamp = 1 }
        value:addPoint{ x = 30, y = 40, timestamp = 2, pressure = 7 }
        value:finish(3)
        return value
    end

    teardown(function()
        for _, directory in ipairs(directories) do
            for _, suffix in ipairs({ "", ".old", ".tmp" }) do
                os.remove(directory .. "/" .. InkStore.FILENAME .. suffix)
            end
            lfs.rmdir(directory)
        end
    end)

    it("loads an empty document and saves/reloads multiple raw strokes", function()
        local directory = tempDirectory()
        local store = InkStore:new{ document_id = "book.pdf", candidate_dirs = { directory } }
        assert.are.same({}, store:load())
        assert.is_true(store:save({ stroke("one", 1), stroke("two", 2) }))
        local loaded = InkStore:new{
            document_id = "book.pdf", candidate_dirs = { directory },
        }:load()
        assert.are.same(2, #loaded)
        assert.are.same("two", loaded[2].id)
        assert.are.same(7, loaded[2].points[2].pressure)
    end)

    it("repeats atomic saves and retains a recovery file", function()
        local directory = tempDirectory()
        local store = InkStore:new{ document_id = "book.pdf", candidate_dirs = { directory } }
        assert.is_true(store:save({ stroke("one", 1) }))
        assert.is_true(store:save({ stroke("one", 1), stroke("two", 1) }))
        assert.is_true(util.fileExists(directory .. "/" .. InkStore.FILENAME .. ".old"))
        assert.are.same(2, #store:load())
    end)

    it("recovers from a malformed primary without executing it", function()
        local directory = tempDirectory()
        local store = InkStore:new{ document_id = "book.pdf", candidate_dirs = { directory } }
        store:save({ stroke("one", 1) })
        store:save({ stroke("one", 1), stroke("two", 1) })
        util.writeToFile("not json", directory .. "/" .. InkStore.FILENAME)
        local loaded, err = InkStore:new{
            document_id = "book.pdf", candidate_dirs = { directory },
        }:load()
        assert.are.same(1, #loaded)
        assert.is_nil(err)
        assert.are.same("one", loaded[1].id)
    end)

    it("fails closed on an unsupported schema", function()
        local directory = tempDirectory()
        util.writeToFile(JSON.encode({
            schema_version = 999, document_id = "book.pdf", strokes = {},
        }), directory .. "/" .. InkStore.FILENAME)
        local loaded, err = InkStore:new{
            document_id = "book.pdf", candidate_dirs = { directory },
        }:load()
        assert.are.same({}, loaded)
        assert.are.same("unsupported_schema", err)
    end)

    it("purges only the current document ink files", function()
        local directory = tempDirectory()
        local store = InkStore:new{ document_id = "book.pdf", candidate_dirs = { directory } }
        store:save({ stroke("one", 1) })
        assert.is_true(store:purge())
        assert.is_nil(util.fileExists(directory .. "/" .. InkStore.FILENAME))
    end)
end)
