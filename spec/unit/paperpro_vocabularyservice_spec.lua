describe("Paper Pro VocabularyService", function()
    local VocabularyService

    setup(function()
        require("commonrequire")
        VocabularyService = require("apps/paperpro/services/vocabularyservice")
    end)

    local function successModel()
        return {
            status = "success", display_word = "Run",
            definitions = {
                { text = "Move quickly.", dictionary_name = "First" },
                { text = "An act of running.", dictionary_name = "Second" },
            },
        }
    end

    local function snapshot(word)
        return {
            text = word or "selected phrase", selected_word = word,
            before_context = "They ", after_context = " home.",
            book_title = "Example", author = "Author", chapter = "One",
            anchor = {
                kind = "xpointer", document_id = "/books/example.epub",
                start = "/body/p[1].0", finish = "/body/p[1].3",
            },
        }
    end

    it("sends detached rich metadata for an eligible result", function()
        local received
        local ui = {
            handleEvent = function(_, event)
                received = event.args[1]
                event.args[2]("added")
                return true
            end,
        }
        local status
        VocabularyService:new{ ui = ui }:recordDefinition(snapshot("run"), successModel(), function(value)
            status = value
        end)
        assert.are.same("added", status)
        assert.are.same("run", received.word)
        assert.are.same("Run", received.display_word)
        assert.are.same("First", received.definitions[1].dictionary_name)
        assert.are.same("Second", received.definitions[2].dictionary_name)
        assert.are.same("xpointer", received.anchor_kind)
        assert.are.same("One", received.chapter)
    end)

    it("does not persist phrases, no-results, or errors", function()
        local calls = 0
        local service = VocabularyService:new{ ui = {
            handleEvent = function() calls = calls + 1 end,
        }}
        assert.is_false(service:recordDefinition(snapshot(nil), successModel(), function() end))
        assert.is_false(service:recordDefinition(snapshot("missing"), {
            status = "no_definition", definitions = {},
        }, function() end))
        assert.is_false(service:recordDefinition(snapshot("broken"), {
            status = "error", definitions = {},
        }, function() end))
        assert.is_false(service:recordDefinition(snapshot("blank"), {
            status = "success", definitions = {{ text = "   " }},
        }, function() end))
        assert.are.same(0, calls)
    end)

    it("reports an unavailable plugin without crashing", function()
        local status
        local service = VocabularyService:new{ ui = { handleEvent = function() return false end } }
        assert.is_false(service:recordDefinition(snapshot("run"), successModel(), function(value)
            status = value
        end))
        assert.are.same("unavailable", status)
    end)

    it("uses the current-book back stack and existing XPointer navigation", function()
        local ui = {}
        ui.document = {
            file = "/books/example.epub",
            isXPointerInDocument = function(_, xp) return xp == "/body/p[1].0" end,
        }
        ui.rolling = {
            onGotoXPointer = function(_, xp, marker)
                ui.goto_xpointer, ui.goto_marker = xp, marker
            end,
        }
        ui.link = {
            addCurrentLocationToStack = function() ui.added_to_stack = true end,
        }
        local service = VocabularyService:new{ ui = ui }
        local item = {
            document_id = "/books/example.epub", anchor_kind = "xpointer",
            anchor_start = "/body/p[1].0", anchor_finish = "/body/p[1].3",
        }
        assert.is_true(service:goToPassage(item))
        assert.is_true(ui.added_to_stack)
        assert.are.same("/body/p[1].0", ui.goto_xpointer)
        assert.are.same("/body/p[1].0", ui.goto_marker)

        item.anchor_start = "malformed"
        item.anchor = nil
        assert.is_false(service:goToPassage(item))
    end)
end)
