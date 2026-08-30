describe("Paper Pro Vocabulary Builder migration", function()
    local DB, SQ3
    local paths = {}

    local function contains(values, expected)
        for _, value in ipairs(values or {}) do
            if value == expected then return true end
        end
        return false
    end

    local function tempPath()
        local path = os.tmpname()
        os.remove(path)
        table.insert(paths, path)
        return path
    end

    local function phaseOneDatabase(path)
        local conn = SQ3.open(path)
        conn:exec([[
            CREATE TABLE title (id INTEGER NOT NULL UNIQUE, name TEXT UNIQUE,
                filter INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(id));
            CREATE TABLE vocabulary (
                word TEXT NOT NULL UNIQUE, title_id INTEGER, create_time INTEGER NOT NULL,
                review_time INTEGER, due_time INTEGER NOT NULL,
                review_count INTEGER NOT NULL DEFAULT 0, prev_context TEXT, next_context TEXT,
                streak_count INTEGER NOT NULL DEFAULT 0, highlight TEXT, PRIMARY KEY(word));
            INSERT INTO title (id, name) VALUES (1, 'Existing book');
            INSERT INTO vocabulary
                (word, title_id, create_time, review_time, due_time, review_count,
                 prev_context, next_context, streak_count, highlight)
                VALUES ('run', 1, 100, 200, 300, 7, NULL, NULL, 4, 'run');
            PRAGMA user_version=20240905;
        ]])
        conn:close()
    end

    setup(function()
        require("commonrequire")
        SQ3 = require("lua-ljsqlite3/init")
        DB = dofile("plugins/vocabbuilder.koplugin/db.lua")
    end)

    teardown(function()
        for _, path in ipairs(paths) do
            os.remove(path)
            os.remove(path .. "-shm")
            os.remove(path .. "-wal")
        end
    end)

    it("creates the rich schema for a new database", function()
        local path = tempPath()
        DB:createDB(path)
        local conn = SQ3.open(path)
        local columns = conn:exec("PRAGMA table_info(vocabulary);")
        assert.are.same(20260830, tonumber(conn:rowexec("PRAGMA user_version;")))
        assert.is_true(contains(columns.name, "definition"))
        assert.is_true(contains(columns.name, "anchor_pos0_json"))
        conn:close()
    end)

    it("migrates populated Phase 1 data repeatedly without changing review state", function()
        local path = tempPath()
        phaseOneDatabase(path)
        DB:createDB(path)
        DB:createDB(path)
        DB:enrichDefinition({
            word = "run", book_title = "Existing book", time = 500,
            definition = "Move quickly.", dictionary_source = "Local",
            anchor_kind = "xpointer", document_id = "/books/example.epub",
            anchor_start = "/body/p[1].0", anchor_finish = "/body/p[1].3",
            updated_time = 500,
        }, path)
        local item = DB:hasWord("run", path)
        assert.are.same(7, item.review_count)
        assert.are.same(4, item.streak_count)
        assert.are.same(200, item.review_time)
        assert.are.same(300, item.due_time)
        assert.is_nil(item.prev_context)
        assert.are.same("Move quickly.", item.definition)
    end)

    it("enriches a legacy auto-added row without duplicating or resetting it", function()
        local path = tempPath()
        phaseOneDatabase(path)
        DB:createDB(path)
        local status = DB:enrichDefinition({
            word = "run", book_title = "Existing book", time = 600,
            definition = "Move quickly.", dictionary_source = "Local", updated_time = 600,
        }, path)
        local conn = SQ3.open(path)
        assert.are.same("already", status)
        assert.are.same(1, tonumber(conn:rowexec("SELECT count(0) FROM vocabulary WHERE word='run';")))
        assert.are.same(7, tonumber(conn:rowexec("SELECT review_count FROM vocabulary WHERE word='run';")))
        assert.are.same(4, tonumber(conn:rowexec("SELECT streak_count FROM vocabulary WHERE word='run';")))
        conn:close()
    end)

    it("keeps lookup-history-style rows with empty titles and null context", function()
        local path = tempPath()
        phaseOneDatabase(path)
        local conn = SQ3.open(path)
        conn:exec("UPDATE title SET name='';")
        conn:close()
        DB:createDB(path)
        local item = DB:hasWord("run", path)
        assert.is_truthy(item)
        assert.are.same("", item.book_title)
        assert.is_nil(item.prev_context)
        assert.are.same(7, item.review_count)
    end)

    it("lists newest words first and applies basic search", function()
        local path = tempPath()
        DB:createDB(path)
        DB:enrichDefinition({
            word = "older", book_title = "Book", time = 100,
            definition = "Old", updated_time = 100,
        }, path)
        DB:enrichDefinition({
            word = "newer", book_title = "Book", time = 200,
            definition = "New", updated_time = 200,
        }, path)
        local all = DB:selectRichItems("", path)
        local matching = DB:selectRichItems("new", path)
        assert.are.same("newer", all[1].word)
        assert.are.same(1, #matching)
        assert.are.same("newer", matching[1].word)
    end)

    it("preserves local rich metadata when syncing an older database", function()
        local local_path, income_path, cached_path = tempPath(), tempPath(), tempPath()
        phaseOneDatabase(local_path)
        phaseOneDatabase(income_path)
        DB:createDB(local_path)
        DB:createDB(income_path)
        DB:enrichDefinition({
            word = "run", book_title = "Existing book", time = 700,
            definition = "Local definition", dictionary_source = "Local",
            definitions_json = '[{"text":"Local definition","dictionary_name":"Local"}]',
            anchor_kind = "xpointer", document_id = "/books/example.epub",
            anchor_start = "/body/p[1].0", anchor_finish = "/body/p[1].3",
            updated_time = 700,
        }, local_path)
        local income = SQ3.open(income_path)
        income:exec([[UPDATE vocabulary SET document_id='/books/bad.pdf',
            anchor_kind='fixed_page', anchor_page=2, anchor_pos0_json='not json',
            anchor_pos1_json='{}', definitions_json='not json' WHERE word='run';]])
        income:close()
        assert.is_true(DB.onSync(local_path, cached_path, income_path))
        local item = DB:hasWord("run", local_path)
        assert.are.same("Local definition", item.definition)
        assert.are.same("/body/p[1].0", item.anchor_start)
        assert.are.same('/books/example.epub', item.document_id)
        assert.is_truthy(item.definitions_json:find("Local definition", 1, true))
        assert.are.same(7, item.review_count)
    end)
end)
