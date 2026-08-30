local DataStorage = require("datastorage")
local Device = require("device")
local JSON = require("json")
local SQ3 = require("lua-ljsqlite3/init")
local LuaData = require("luadata")
local logger = require("logger")

local db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"

local DB_SCHEMA_VERSION = 20260830
local VOCABULARY_DB_SCHEMA = [[
    -- To store looked up words
    CREATE TABLE IF NOT EXISTS vocabulary (
        word          TEXT NOT NULL UNIQUE,
        title_id      INTEGER,
        create_time   INTEGER NOT NULL,
        review_time   INTEGER,
        due_time      INTEGER NOT NULL,
        review_count  INTEGER NOT NULL DEFAULT 0,
        prev_context  TEXT,
        next_context  TEXT,
        streak_count  INTEGER NOT NULL DEFAULT 0,
        highlight     TEXT,
        definition    TEXT,
        dictionary_source TEXT,
        definitions_json TEXT,
        author        TEXT,
        chapter       TEXT,
        document_id   TEXT,
        source_text   TEXT,
        anchor_kind   TEXT,
        anchor_start  TEXT,
        anchor_finish TEXT,
        anchor_page   INTEGER,
        anchor_pos0_json TEXT,
        anchor_pos1_json TEXT,
        anchor_page_boxes_json TEXT,
        updated_time  INTEGER,
        PRIMARY KEY(word)
    );
    CREATE TABLE IF NOT EXISTS title (
        id            INTEGER NOT NULL UNIQUE,
        name          TEXT UNIQUE,
        filter        INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY(id)
    );
    CREATE INDEX IF NOT EXISTS due_time_index ON vocabulary(due_time);
    CREATE INDEX IF NOT EXISTS title_name_index ON title(name);
]]

local VocabularyBuilder = {
    path = db_location
}

local function hasColumn(conn, table_name, column_name)
    local columns = conn:exec("PRAGMA table_info(" .. table_name .. ");")
    if not (columns and columns.name) then return false end
    for _, name in ipairs(columns.name) do
        if name == column_name then return true end
    end
    return false
end

function VocabularyBuilder:init()
    VocabularyBuilder:createDB()
end

function VocabularyBuilder:selectCount(vocab_widget)
    local db_conn = SQ3.open(db_location)
    local sql
    if vocab_widget.search_text_sql then
        sql = "SELECT count(0) FROM vocabulary WHERE word LIKE '" .. vocab_widget.search_text_sql .. "'"
    else
        local where_clause = vocab_widget:check_reverse() and " WHERE due_time <= " .. vocab_widget.reload_time or ""
        sql = "SELECT count(0) FROM vocabulary INNER JOIN title ON filter=true AND title_id=id" .. where_clause .. ";"
    end
    local count = tonumber(db_conn:rowexec(sql))
    db_conn:close()
    return count
end

function VocabularyBuilder:createDB(path)
    local db_conn = SQ3.open(path or self.path)
    -- Make it WAL, if possible
    if Device:canUseWAL() then
        db_conn:exec("PRAGMA journal_mode=WAL;")
    else
        db_conn:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    -- Create db
    db_conn:exec(VOCABULARY_DB_SCHEMA)
    -- Check version
    local db_version = tonumber(db_conn:rowexec("PRAGMA user_version;"))
    if db_version == 0 then
        self:insertLookupData(db_conn)
        -- Update version
        db_conn:exec(string.format("PRAGMA user_version=%d;", DB_SCHEMA_VERSION))
    elseif db_version < DB_SCHEMA_VERSION then
        local ok, re
        local log = function(msg)
            logger.warn("[vocab builder db migration]", msg)
        end
        if db_version < 20220608 then
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary ADD prev_context TEXT;")
            if not ok then log(re) end
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary ADD next_context TEXT;")
            if not ok then log(re) end
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary ADD title_id INTEGER;")
            if not ok then log(re) end
            ok, re = pcall(db_conn.exec, db_conn, "INSERT OR IGNORE INTO title (name) SELECT DISTINCT book_title FROM vocabulary;")
            if not ok then log(re) end
            ok, re = pcall(db_conn.exec, db_conn, "UPDATE vocabulary SET title_id = (SELECT id FROM title WHERE name = book_title);")
            if not ok then log(re) end
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary DROP book_title;")
            if not ok then log(re) end
        end
        if db_version < 20220730 then
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE title ADD filter INTEGER NOT NULL DEFAULT 1;")
            if not ok then log(re) end
        end
        if db_version < 20221002 then
            ok, re = pcall(db_conn.exec, db_conn, [[
                ALTER TABLE vocabulary ADD streak_count INTEGER NULL DEFAULT 0;
                UPDATE vocabulary SET streak_count = review_count; ]])
            if not ok then log(re) end
        end
        if db_version < 20240905 then
            ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary ADD highlight TEXT;")
            if not ok then log(re) end
        end
        if db_version < 20260830 then
            local rich_columns = {
                "definition TEXT", "dictionary_source TEXT", "definitions_json TEXT",
                "author TEXT", "chapter TEXT", "document_id TEXT", "source_text TEXT",
                "anchor_kind TEXT", "anchor_start TEXT", "anchor_finish TEXT",
                "anchor_page INTEGER", "anchor_pos0_json TEXT", "anchor_pos1_json TEXT",
                "anchor_page_boxes_json TEXT", "updated_time INTEGER",
            }
            db_conn:exec("BEGIN IMMEDIATE;")
            local migration_ok = true
            for _, column in ipairs(rich_columns) do
                local column_name = column:match("^(%S+)")
                if not hasColumn(db_conn, "vocabulary", column_name) then
                    ok, re = pcall(db_conn.exec, db_conn, "ALTER TABLE vocabulary ADD " .. column .. ";")
                    if not ok then
                        log(re)
                        migration_ok = false
                        break
                    end
                end
            end
            if migration_ok then
                db_conn:exec("COMMIT;")
            else
                pcall(db_conn.exec, db_conn, "ROLLBACK;")
                db_conn:close()
                return false
            end
        end

        db_conn:exec("CREATE INDEX IF NOT EXISTS title_id_index ON vocabulary(title_id);")
        -- Update version
        db_conn:exec(string.format("PRAGMA user_version=%d;", DB_SCHEMA_VERSION))

    end
    db_conn:close()
end

function VocabularyBuilder:insertLookupData(db_conn)
    local file_path = DataStorage:getSettingsDir() .. "/lookup_history.lua"

    local lookup_history = LuaData:open(file_path, "LookupHistory")
    if lookup_history:has("lookup_history") then
        local lookup_history_table = lookup_history:readSetting("lookup_history")
        local book_titles = {}
        local stmt = db_conn:prepare("INSERT INTO title (name) values (?);")
        for i = #lookup_history_table, 1, -1 do
            local book_title = lookup_history_table[i].book_title or ""
            if not book_titles[book_title] then
                stmt:bind(book_title)
                stmt:step()
                stmt:clearbind():reset()
                book_titles[book_title] = true
            end
        end

        local words = {}
        local insert_sql = [[INSERT OR REPLACE INTO vocabulary
                            (word, title_id, create_time, due_time, review_time) values
                            (?, (SELECT id FROM title WHERE name = ?), ?, ?, ?);]]
        stmt = db_conn:prepare(insert_sql)
        for i = #lookup_history_table, 1, -1 do
            local value = lookup_history_table[i]
            if not words[value.word] then
                stmt:bind(value.word, value.book_title or "", value.time, value.time + 5*60, value.time)
                stmt:step()
                stmt:clearbind():reset()
                words[value.word] = true
            end
        end

    end
end

function VocabularyBuilder:_select_items(items, start_idx, reload_time, search_text)
    local conn = SQ3.open(db_location)
    local sql
    if search_text then
        sql = string.format("SELECT * FROM vocabulary INNER JOIN title ON title_id = title.id WHERE word LIKE '%s' LIMIT 32 OFFSET %d", search_text, start_idx-1)
    elseif not reload_time then
        sql = string.format("SELECT * FROM vocabulary INNER JOIN title ON title_id = title.id AND filter = true ORDER BY due_time limit %d OFFSET %d;", 32, start_idx-1)
    else
        sql = string.format([[SELECT * FROM vocabulary INNER JOIN title
                              ON title_id = title.id AND filter = true
                              WHERE due_time <= ]] .. reload_time ..
                            " ORDER BY due_time desc limit %d OFFSET %d;", 32, start_idx-1)
    end

    local results = conn:exec(sql)
    conn:close()
    if not results then return end

    local current_time = os.time()

    for i = 1, #results.word do
        local item = items[start_idx+i-1]
        if item and not item.word then
            item.word = results.word[i]
            item.review_count = math.max(0, tonumber(results.review_count[i]))
            item.streak_count = math.max(0, tonumber(results.streak_count[i]))
            item.book_title = results.name[i] or ""
            item.highlight = results.highlight[i]
            item.create_time = tonumber( results.create_time[i])
            item.review_time = nil --use this field to flag change
            item.due_time = tonumber(results.due_time[i])
            item.is_dim = tonumber(results.due_time[i]) > current_time
            item.prev_context = results.prev_context[i]
            item.next_context = results.next_context[i]
            item.got_it_callback = function(item_input)
                VocabularyBuilder:gotOrForgot(item_input, true)
            end
            item.forgot_callback = function(item_input)
                VocabularyBuilder:gotOrForgot(item_input, false)
            end
            item.remove_callback = function(item_input)
                VocabularyBuilder:remove(item_input)
            end
        end
    end


end

function VocabularyBuilder:select_items(vocab_widget, start_idx, end_idx)
    local items = vocab_widget.item_table
    local start_cursor
    if #items == 0 then
        start_cursor = 0
    else
        for i = start_idx+1, end_idx do
            if not items[i].word then
                start_cursor = i
                break
            end
        end
    end

    if not start_cursor then return end
    self:_select_items(items, start_cursor, vocab_widget:check_reverse() and vocab_widget.reload_time, vocab_widget.search_text_sql)
end


function VocabularyBuilder:gotOrForgot(item, isGot)
    local current_time = os.time()

    local due_time
    local target_review_count = math.max(item.review_count + (isGot and 1 or -1), 0)
    local target_count = isGot and item.streak_count + 1 or 0
    if target_count == 0 then
        due_time = current_time + 5 * 60
    elseif target_count == 1 then
        due_time = current_time + 30 * 60
    elseif target_count == 2 then
        due_time = current_time + 12 * 3600
    elseif target_count == 3 then
        due_time = current_time + 24 * 3600
    elseif target_count == 4 then
        due_time = current_time + 48 * 3600
    elseif target_count == 5 then
        due_time = current_time + 96 * 3600
    elseif target_count == 6 then
        due_time = current_time + 24 * 7 * 3600
    elseif target_count == 7 then
        due_time = current_time + 24 * 15 * 3600
    else
        due_time = current_time + 24 * 3600 * 30 * 2 ^ (math.min(target_count - 8, 6))
    end

    item.last_streak_count = item.streak_count
    item.last_review_count = item.review_count
    item.last_review_time = item.review_time
    item.last_due_time = item.due_time

    item.streak_count = target_count
    item.review_count = target_review_count
    item.review_time = current_time
    item.due_time = due_time
end

function VocabularyBuilder:batchUpdateItems(items)
    local sql = [[UPDATE vocabulary
                SET review_count = ?,
                    streak_count = ?,
                    review_time = ?,
                        due_time = ?
                    WHERE word = ?;]]

    local conn = SQ3.open(db_location)
    local stmt = conn:prepare(sql)

    for _, item in ipairs(items) do
        if item.review_time then
            stmt:bind(item.review_count, item.streak_count, item.review_time, item.due_time, item.word)
            stmt:step()
            stmt:clearbind():reset()
            item.review_time = nil
        end
    end

    conn:exec("DELETE FROM title WHERE NOT EXISTS( SELECT title_id FROM vocabulary WHERE id = title_id );")
    conn:close()
end

function VocabularyBuilder:insertOrUpdate(entry)
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("INSERT OR IGNORE INTO title (name) VALUES (?);")
    stmt:bind(entry.book_title)
    stmt:step()
    stmt:clearbind():reset()

    stmt = conn:prepare([[INSERT INTO vocabulary (word, title_id, create_time, due_time, review_time, prev_context, next_context, highlight)
                        VALUES (?, (SELECT id FROM title WHERE name = ?), ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(word) DO UPDATE SET title_id = excluded.title_id,
                        create_time = excluded.create_time,
                        review_count = MAX(review_count-1, 0),
                        streak_count = 0,
                        due_time = ?,
                        prev_context = ifnull(excluded.prev_context, prev_context),
                        next_context = ifnull(excluded.next_context, next_context),
                        highlight = ifnull(excluded.highlight, highlight);]]);
    stmt:bind(entry.word, entry.book_title, entry.time, entry.time+300, entry.time,
              entry.prev_context, entry.next_context, entry.highlight, entry.time+300)
    stmt:step()
    stmt:clearbind():reset()
    conn:close()
end

-- Enrich an existing review row without changing spaced-repetition state.
-- If the word does not yet exist, create the authoritative review row with
-- the same neutral initial state used by normal lookup insertion.
function VocabularyBuilder:enrichDefinition(entry, path)
    local conn = SQ3.open(path or self.path)
    local stmt = conn:prepare("SELECT count(0) FROM vocabulary WHERE word = ?;")
    local existed = tonumber(stmt:bind(entry.word):step()[1]) ~= 0
    stmt:close()
    stmt = conn:prepare("INSERT OR IGNORE INTO title (name) VALUES (?);")
    stmt:bind(entry.book_title or ""):step()
    stmt:close()
    stmt = conn:prepare([[
        INSERT INTO vocabulary
            (word, title_id, create_time, due_time, review_time, prev_context, next_context, highlight,
             definition, dictionary_source, definitions_json, author, chapter, document_id, source_text,
             anchor_kind, anchor_start, anchor_finish, anchor_page, anchor_pos0_json, anchor_pos1_json,
             anchor_page_boxes_json, updated_time)
        VALUES (?, (SELECT id FROM title WHERE name = ?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(word) DO UPDATE SET
            title_id = excluded.title_id,
            prev_context = COALESCE(NULLIF(excluded.prev_context, ''), prev_context),
            next_context = COALESCE(NULLIF(excluded.next_context, ''), next_context),
            highlight = COALESCE(NULLIF(excluded.highlight, ''), highlight),
            definition = COALESCE(NULLIF(excluded.definition, ''), definition),
            dictionary_source = COALESCE(NULLIF(excluded.dictionary_source, ''), dictionary_source),
            definitions_json = COALESCE(NULLIF(excluded.definitions_json, ''), definitions_json),
            author = COALESCE(NULLIF(excluded.author, ''), author),
            chapter = COALESCE(NULLIF(excluded.chapter, ''), chapter),
            document_id = COALESCE(NULLIF(excluded.document_id, ''), document_id),
            source_text = COALESCE(NULLIF(excluded.source_text, ''), source_text),
            anchor_kind = COALESCE(NULLIF(excluded.anchor_kind, ''), anchor_kind),
            anchor_start = COALESCE(NULLIF(excluded.anchor_start, ''), anchor_start),
            anchor_finish = COALESCE(NULLIF(excluded.anchor_finish, ''), anchor_finish),
            anchor_page = COALESCE(excluded.anchor_page, anchor_page),
            anchor_pos0_json = COALESCE(NULLIF(excluded.anchor_pos0_json, ''), anchor_pos0_json),
            anchor_pos1_json = COALESCE(NULLIF(excluded.anchor_pos1_json, ''), anchor_pos1_json),
            anchor_page_boxes_json = COALESCE(NULLIF(excluded.anchor_page_boxes_json, ''), anchor_page_boxes_json),
            updated_time = MAX(COALESCE(updated_time, 0), excluded.updated_time);
    ]])
    local time = entry.time or os.time()
    stmt:bind(entry.word, entry.book_title or "", time, time + 300, time,
        entry.prev_context, entry.next_context, entry.highlight, entry.definition,
        entry.dictionary_source, entry.definitions_json, entry.author, entry.chapter,
        entry.document_id, entry.source_text, entry.anchor_kind, entry.anchor_start,
        entry.anchor_finish, entry.anchor_page, entry.anchor_pos0_json, entry.anchor_pos1_json,
        entry.anchor_page_boxes_json, entry.updated_time or time)
    stmt:step()
    stmt:close()
    conn:close()
    return existed and "already" or "added"
end

function VocabularyBuilder:hasWord(word, path)
    local conn = SQ3.open(path or self.path)
    local sql = [[SELECT title.name as book_title, vocabulary.word, create_time, review_time, due_time, review_count, streak_count, prev_context, next_context, highlight,
          definition, dictionary_source, definitions_json, author, chapter, document_id, source_text, anchor_kind,
          anchor_start, anchor_finish, anchor_page, anchor_pos0_json, anchor_pos1_json, anchor_page_boxes_json, updated_time
          FROM vocabulary INNER JOIN title ON title_id = title.id WHERE word = ?]]
    local stmt = conn:prepare(sql)
    stmt:bind(word)
    local result = stmt:step()
    stmt:close()
    conn:close()
    if result then
        return {
            book_title = result[1],
            word = result[2],
            create_time = tonumber(result[3]),
            review_time = tonumber(result[4]),
            due_time = tonumber(result[5]),
            review_count = tonumber(result[6]),
            streak_count = tonumber(result[7]),
            prev_context = result[8],
            next_context = result[9],
            highlight = result[10],
            definition = result[11], dictionary_source = result[12], definitions_json = result[13],
            author = result[14], chapter = result[15], document_id = result[16], source_text = result[17],
            anchor_kind = result[18], anchor_start = result[19], anchor_finish = result[20],
            anchor_page = tonumber(result[21]), anchor_pos0_json = result[22], anchor_pos1_json = result[23],
            anchor_page_boxes_json = result[24], updated_time = tonumber(result[25]),
        }
    else
        return nil
    end
end

function VocabularyBuilder:selectRichItems(search_text, path)
    local conn = SQ3.open(path or self.path)
    local sql = [[SELECT vocabulary.word FROM vocabulary
        WHERE (? = '' OR vocabulary.word LIKE ?)
        ORDER BY COALESCE(updated_time, create_time) DESC, vocabulary.word ASC;]]
    local stmt = conn:prepare(sql)
    local query = search_text or ""
    stmt:bind(query, "%" .. query .. "%")
    local words = {}
    while true do
        local row = stmt:step()
        if not row then break end
        table.insert(words, row[1])
    end
    stmt:close()
    conn:close()
    local items = {}
    for _, word in ipairs(words) do
        table.insert(items, self:hasWord(word, path))
    end
    return items
end

function VocabularyBuilder:toggleBookFilter(ids)
    local id_string = ""
    for key, _ in pairs(ids) do
        id_string = id_string .. (id_string == "" and "" or ",") .. key
    end
    local conn = SQ3.open(db_location)
    conn:exec("UPDATE title SET filter = (filter | 1) - (filter & 1) WHERE id in ("..id_string..");")
    conn:close()
end

function VocabularyBuilder:updateBookIdOfWord(word, id)
    if not word or type(id) ~= "number" then return end
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("UPDATE vocabulary SET title_id = ? WHERE word = ?;")
    stmt:bind(id, word)
    stmt:step()
    stmt:clearbind():reset()
    conn:close()
end

function VocabularyBuilder:insertNewBook(title)
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("INSERT INTO title (name) VALUES (?);")
    stmt:bind(title):step()
    stmt:clearbind():reset()
    stmt = conn:prepare("SELECT id FROM title WHERE name = ?")
    local result = stmt:bind(title):step()
    stmt:clearbind():reset()
    conn:close()
    return tonumber(result[1])
end

function VocabularyBuilder:changeBookTitle(old_title, title)
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("UPDATE title SET name = ? WHERE name = ?;")
    stmt:bind(title, old_title):step()
    stmt:clearbind():reset()
    conn:close()
end

function VocabularyBuilder:selectBooks()
    local conn = SQ3.open(db_location)
    local sql = string.format("SELECT * FROM title")

    local results = conn:exec(sql)
    conn:close()

    local items = {}
    if not results then return items end

    for i = 1, #results.id do
        table.insert(items, {
            id = tonumber(results.id[i]),
            name = results.name[i],
            filter = tonumber(results.filter[i]) ~= 0
        })
    end
    return items
end

function VocabularyBuilder:hasFilteredBook()
    local conn = SQ3.open(db_location)
    local has_filter = tonumber(conn:rowexec("SELECT count(0) FROM title WHERE filter = false limit 1;"))
    conn:close()
    return has_filter ~= 0
end

function VocabularyBuilder:remove(item)
    local conn = SQ3.open(db_location)
    local stmt = conn:prepare("DELETE FROM vocabulary WHERE word = ? ;")
    stmt:bind(item.word)
    stmt:step()
    stmt:clearbind():reset()

    conn:close()
end

function VocabularyBuilder:resetProgress()
    local conn = SQ3.open(db_location)
    local due_time = os.time()
    conn:exec(string.format("UPDATE vocabulary SET review_count = 0, streak_count = 0, due_time = %d;", due_time))
    conn:close()
end

function VocabularyBuilder:purge()
    local conn = SQ3.open(db_location)
    conn:exec("DELETE FROM vocabulary; DELETE FROM title;")
    conn:close()
end


-- Synchronization
function VocabularyBuilder.onSync(local_path, cached_path, income_path)
    -- we try to open income db
    local conn_income = SQ3.open(income_path)
    local ok1, v1 = pcall(conn_income.rowexec, conn_income, "PRAGMA schema_version")
    if not ok1 or tonumber(v1) == 0 then
        -- no income db or wrong db, first time sync
        logger.dbg("vocabbuilder open income DB failed", v1)
        conn_income:close()
        return true
    end

    -- Handle possible inconsistensies in db version
    local sync_columns = {
        "highlight TEXT", "definition TEXT", "dictionary_source TEXT", "definitions_json TEXT",
        "author TEXT", "chapter TEXT", "document_id TEXT", "source_text TEXT", "anchor_kind TEXT",
        "anchor_start TEXT", "anchor_finish TEXT", "anchor_page INTEGER", "anchor_pos0_json TEXT",
        "anchor_pos1_json TEXT", "anchor_page_boxes_json TEXT", "updated_time INTEGER",
    }
    for _, column in ipairs(sync_columns) do
        local column_name = column:match("^(%S+)")
        if not hasColumn(conn_income, "vocabulary", column_name) then
            pcall(conn_income.exec, conn_income, "ALTER TABLE vocabulary ADD " .. column .. ";")
        end
    end

    -- Do not let incomplete or malformed rich payloads from an older/edited
    -- database erase a valid local anchor or definition list during merge.
    local rich_rows = conn_income:exec([[SELECT rowid AS rich_rowid, definitions_json,
        document_id, anchor_kind, anchor_start, anchor_finish, anchor_page,
        anchor_pos0_json, anchor_pos1_json, anchor_page_boxes_json FROM vocabulary;]])
    if rich_rows then
        local clear_anchor = conn_income:prepare([[UPDATE vocabulary SET
            document_id = NULL, anchor_kind = NULL, anchor_start = NULL, anchor_finish = NULL,
            anchor_page = NULL, anchor_pos0_json = NULL, anchor_pos1_json = NULL,
            anchor_page_boxes_json = NULL WHERE rowid = ?;]])
        local clear_definitions = conn_income:prepare(
            "UPDATE vocabulary SET definitions_json = NULL WHERE rowid = ?;")
        local function decodedTable(value)
            if not value or value == "" then return nil end
            local decoded, result = pcall(JSON.decode, value)
            return decoded and type(result) == "table" and result or nil
        end
        for i, rowid in ipairs(rich_rows.rich_rowid) do
            local definitions_json = rich_rows.definitions_json[i]
            if definitions_json and not decodedTable(definitions_json) then
                clear_definitions:bind(rowid):step()
                clear_definitions:clearbind():reset()
            end
            local kind = rich_rows.anchor_kind[i]
            local has_anchor_data = rich_rows.document_id[i] or kind
                or rich_rows.anchor_start[i] or rich_rows.anchor_finish[i]
                or rich_rows.anchor_page[i] or rich_rows.anchor_pos0_json[i]
                or rich_rows.anchor_pos1_json[i] or rich_rows.anchor_page_boxes_json[i]
            local document_id = rich_rows.document_id[i]
            local valid_anchor = kind == "xpointer" and document_id and document_id ~= ""
                and rich_rows.anchor_start[i] and rich_rows.anchor_start[i] ~= ""
                and rich_rows.anchor_finish[i] and rich_rows.anchor_finish[i] ~= ""
                or kind == "fixed_page" and document_id and document_id ~= ""
                and tonumber(rich_rows.anchor_page[i])
                and decodedTable(rich_rows.anchor_pos0_json[i])
                and decodedTable(rich_rows.anchor_pos1_json[i])
                and (not rich_rows.anchor_page_boxes_json[i]
                    or decodedTable(rich_rows.anchor_page_boxes_json[i]))
            if has_anchor_data and not valid_anchor then
                clear_anchor:bind(rowid):step()
                clear_anchor:clearbind():reset()
            end
        end
        clear_anchor:close()
        clear_definitions:close()
    end

    local sql = "attach '" .. income_path:gsub("'", "''") .."' as income_db;"
    -- then we try to open cached db
    local conn_cached = SQ3.open(cached_path)
    local ok2, v2 = pcall(conn_cached.rowexec, conn_cached, "PRAGMA schema_version")
    local attached_cache
    if not ok2 or tonumber(v2) == 0 then
        -- no cached or error, no item to delete
        logger.dbg("vocabbuilder open cached DB failed", v2)
    else
        attached_cache = true
        sql = sql .. "attach '" .. cached_path:gsub("'", "''") ..[[' as cached_db;
            -- first we delete from income_db words that exist in cached_db but not in local_db,
            -- namely the ones that were deleted since last sync
            DELETE FROM income_db.vocabulary WHERE word IN (
                SELECT word FROM cached_db.vocabulary WHERE word NOT IN (
                    SELECT word FROM vocabulary
                )
            );
            -- We need to delete words that were delete in income_db since last sync
            DELETE FROM vocabulary WHERE word IN (
                SELECT word FROM cached_db.vocabulary WHERE word NOT IN (
                    SELECT word FROM income_db.vocabulary
                )
            );
        ]]
    end

    conn_cached:close()
    conn_income:close()
    local conn = SQ3.open(local_path)
    local ok3, v3 = pcall(conn.exec, conn, "PRAGMA schema_version")
    if not ok3 or tonumber(v3) == 0 then
        -- no local db, this is an error
        logger.err("vocabbuilder open local DB", v3)
        conn:close()
        return false
    end

    sql = sql .. [[
        -- We merge the local db with income db to form the synced db.
        -- First we do the books
        INSERT INTO title (name) SELECT name FROM income_db.title WHERE name NOT IN (SELECT name FROM title);

        -- Then update income db's book title id references
        UPDATE income_db.vocabulary SET title_id = ifnull(
            (SELECT mid FROM (
                SELECT m.id as mid, title_id as i_tid FROM title as m -- main db
                INNER JOIN income_db.title as i -- income db
                ON m.name = i.name
                LEFT JOIN income_db.vocabulary
                on title_id = i.id
            ) WHERE income_db.vocabulary.title_id = i_tid
        ) , title_id);

        -- Then we merge the income_db's contents into the local db
        INSERT INTO vocabulary
              (word, create_time, review_time, due_time, review_count, prev_context, next_context, title_id, streak_count, highlight,
               definition, dictionary_source, definitions_json, author, chapter, document_id, source_text, anchor_kind,
               anchor_start, anchor_finish, anchor_page, anchor_pos0_json, anchor_pos1_json, anchor_page_boxes_json, updated_time)
        SELECT word, create_time, review_time, due_time, review_count, prev_context, next_context, title_id, streak_count, highlight,
               definition, dictionary_source, definitions_json, author, chapter, document_id, source_text, anchor_kind,
               anchor_start, anchor_finish, anchor_page, anchor_pos0_json, anchor_pos1_json, anchor_page_boxes_json, updated_time
        FROM income_db.vocabulary WHERE true
        ON CONFLICT(word) DO UPDATE SET
        due_time = MAX(due_time, excluded.due_time),
        review_count = CASE
            WHEN create_time = excluded.create_time THEN MAX(review_count, excluded.review_count)
            ELSE review_count + excluded.review_count
        END,
        prev_context = ifnull(excluded.prev_context, prev_context),
        next_context = ifnull(excluded.next_context, next_context),
        highlight = ifnull(excluded.highlight, highlight),
        definition = COALESCE(NULLIF(excluded.definition, ''), definition),
        dictionary_source = COALESCE(NULLIF(excluded.dictionary_source, ''), dictionary_source),
        definitions_json = COALESCE(NULLIF(excluded.definitions_json, ''), definitions_json),
        author = COALESCE(NULLIF(excluded.author, ''), author),
        chapter = COALESCE(NULLIF(excluded.chapter, ''), chapter),
        document_id = COALESCE(NULLIF(document_id, ''), NULLIF(excluded.document_id, '')),
        source_text = COALESCE(NULLIF(excluded.source_text, ''), source_text),
        anchor_kind = COALESCE(NULLIF(anchor_kind, ''), NULLIF(excluded.anchor_kind, '')),
        anchor_start = COALESCE(NULLIF(anchor_start, ''), NULLIF(excluded.anchor_start, '')),
        anchor_finish = COALESCE(NULLIF(anchor_finish, ''), NULLIF(excluded.anchor_finish, '')),
        anchor_page = COALESCE(anchor_page, excluded.anchor_page),
        anchor_pos0_json = COALESCE(NULLIF(anchor_pos0_json, ''), NULLIF(excluded.anchor_pos0_json, '')),
        anchor_pos1_json = COALESCE(NULLIF(anchor_pos1_json, ''), NULLIF(excluded.anchor_pos1_json, '')),
        anchor_page_boxes_json = COALESCE(NULLIF(anchor_page_boxes_json, ''), NULLIF(excluded.anchor_page_boxes_json, '')),
        updated_time = MAX(COALESCE(updated_time, 0), COALESCE(excluded.updated_time, 0)),
        streak_count = CASE
            WHEN review_time > excluded.review_time THEN streak_count
            ELSE excluded.streak_count
        END,
        review_time = MAX(review_time, excluded.review_time),
        create_time = excluded.create_time, -- we always use the remote value to eliminate duplicate review_count sum
        title_id = excluded.title_id -- use remote in case re-assignable book id be supported
    ]]
    conn:exec(sql)
    pcall(conn.exec, conn, "COMMIT;")
    conn:exec("DETACH income_db;"..(attached_cache and "DETACH cached_db;" or ""))
    conn:exec("PRAGMA temp_store = 2;") -- use memory for temp files
    local ok, errmsg = pcall(conn.exec, conn, "VACUUM;") -- we upload a compact file
    if not ok then
        logger.warn("Failed compacting vocab database:", errmsg)
    end
    conn:close()
    return true
end

VocabularyBuilder:init()

return VocabularyBuilder
