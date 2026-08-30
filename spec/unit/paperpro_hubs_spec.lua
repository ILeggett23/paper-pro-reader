describe("Paper Pro study hubs", function()
    local NotesHub, VocabularyHub

    setup(function()
        require("commonrequire")
        NotesHub = require("apps/paperpro/hubs/noteshub")
        VocabularyHub = require("apps/paperpro/hubs/vocabularyhub")
    end)

    it("builds vocabulary list and detail content from adapter records", function()
        local service = {
            decodeItem = function(_, item) return item end,
        }
        local hub = VocabularyHub:new{ service = service }
        hub.search_text = ""
        local item = {
            word = "run", definition = "Move quickly.", dictionary_source = "First",
            definitions = {
                { text = "Move quickly.", dictionary_name = "First" },
                { text = "An act of running.", dictionary_name = "Second" },
            },
            source_text = "run", prev_context = "They ", next_context = " home.",
            book_title = "Example", chapter = "One", create_time = 100,
            review_count = 3, streak_count = 2,
        }
        local menu_items = hub:_itemsForMenu({ item })
        assert.are.same("run", menu_items[2].text)
        local detail = hub:_detailText(item)
        assert.is_truthy(detail:find("First", 1, true))
        assert.is_truthy(detail:find("Second", 1, true))
        assert.is_truthy(detail:find("They run home.", 1, true))
        assert.is_truthy(detail:find("Reviews: 3", 1, true))
    end)

    it("shows vocabulary empty state after search", function()
        local hub = VocabularyHub:new{ service = { decodeItem = function(_, item) return item end } }
        hub.search_text = "missing"
        local items = hub:_itemsForMenu({})
        assert.are.same("No matching vocabulary", items[2].text)
        assert.is_false(items[2].select_enabled)
    end)

    it("builds Notes Hub rows from current-book note records only", function()
        local service = {
            listNotes = function()
                return {{
                    text = "A quoted passage", note = "Personal note", chapter = "Chapter One",
                    datetime = "2026-08-29 10:00:00", can_navigate = true,
                    annotation_ref = { document_id = "/books/book.epub" },
                }}
            end,
        }
        local hub = NotesHub:new{ service = service }
        local items = hub:_menuItems()
        assert.are.same(1, #items)
        assert.is_truthy(items[1].text:find("A quoted passage", 1, true))
        assert.is_truthy(items[1].text:find("Personal note", 1, true))
        assert.is_truthy(items[1].mandatory:find("Chapter One", 1, true))
        local detail = hub:_detailText(items[1].note_item)
        assert.is_truthy(detail:find("Chapter One", 1, true))
        assert.is_truthy(detail:find("Personal note", 1, true))
    end)

    it("shows a Notes Hub empty state", function()
        local hub = NotesHub:new{ service = { listNotes = function() return {} end } }
        local items = hub:_menuItems()
        assert.are.same(1, #items)
        assert.is_false(items[1].select_enabled)
    end)
end)
