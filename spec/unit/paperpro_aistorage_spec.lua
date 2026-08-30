describe("Paper Pro AI settings, responses, and navigation", function()
    local AISettings, AnchorNavigator, ConversationService, ResponseStore, SelectionService

    setup(function()
        require("commonrequire")
        AISettings = require("apps/paperpro/services/aisettings")
        AnchorNavigator = require("apps/paperpro/services/anchornavigator")
        ConversationService = require("apps/paperpro/services/conversationservice")
        ResponseStore = require("apps/paperpro/services/responsestore")
        SelectionService = require("apps/paperpro/services/selectionservice")
    end)

    local function memoryStore(initial)
        local data = SelectionService.deepCopy(initial or { schema_version = 1, responses = {} })
        return {
            load = function() return SelectionService.deepCopy(data) end,
            save = function(_, value) data = SelectionService.deepCopy(value) return true end,
        }
    end

    it("stores only a revocable backend token and requires HTTPS remotely", function()
        local values = {}
        local settings = {
            isTrue = function(_, key) return values[key] == true end,
            readSetting = function(_, key, default) return values[key] == nil and default or values[key] end,
            saveSetting = function(_, key, value) values[key] = value end,
        }
        local service = AISettings:new{ settings = settings }
        assert.is_false(service:saveBackend("http://reader.example", "token"))
        assert.is_true(service:saveBackend("http://127.0.0.1:8787", "device-token"))
        assert.is_true(service:isConfigured())
        assert.are.same("device-token", service:getConfig().backend_token)
        assert.is_true(service:setContextMode("minimal"))
        assert.are.same("minimal", service:getContextMode())
        service:setEnabled(true)
        assert.is_true(service:isEnabled())
        assert.is_true(service:setInputMode("write"))
        assert.is_true(service:setResponseStyle("handwriting"))
        assert.are.same("write", service:getInputMode())
        assert.are.same("handwriting", service:getResponseStyle())
        assert.is_nil(values.OPENAI_API_KEY)
    end)

    it("migrates Phase 4 exchanges repeat-safely into single-turn conversations", function()
        local legacy = {
            schema_version = 1,
            responses = {{
                request_id = "legacy", response_id = "answer", question = "Why?",
                answer = "Because.", document_id = "book.epub", book_title = "Book",
                anchor = { kind = "xpointer", document_id = "book.epub", start = "/p", finish = "/p.4" },
                source_text = "Passage", created_at = 1, completed_at = 2,
                context_mode = "nearby", status = "completed",
            }},
        }
        local store = ResponseStore:new{ store = memoryStore(legacy) }
        local conversations = store:listConversationsForDocument("book.epub")
        assert.are.same(2, store.data.schema_version)
        assert.are.same(1, #conversations)
        assert.are.same("Why?", conversations[1].turns[1].question_text)
        assert.are.same("Because.", conversations[1].turns[1].answer)
    end)

    it("groups typed and ink follow-ups in one locally canonical conversation", function()
        local store = ResponseStore:new{ store = memoryStore() }
        local context = {
            schema_version = 1, context_mode = "nearby", context = {}, capabilities = {},
            truncation = { any = false },
            book = { document_id = "book.epub", title = "Book" },
            location = { anchor = { kind = "xpointer", document_id = "book.epub",
                start = "/p", finish = "/p.4" } },
            selection = { text = "Passage" },
        }
        local function request(id, kind)
            return {
                request_id = id, created_at = id == "one" and 1 or 3,
                question = kind == "text" and { type = "text", text = "Why?" }
                    or { type = "ink", local_ink = { strokes = {{
                        id = "stroke", tool = "pen", coordinate_space = "screen-v1",
                        points = {{ x = 1, y = 2, timestamp = 1 }},
                    }} } },
                preferences = { context_mode = "nearby" }, reading_context = context,
                conversation = { id = "conversation", turn_id = "turn-" .. id, history = {} },
            }
        end
        assert(store:saveExchange(request("one", "text"), {
            response_id = "a1", answer = "First", completed_at = 2, status = "completed",
        }))
        assert(store:saveExchange(request("two", "ink"), {
            response_id = "a2", answer = "Second", completed_at = 4, status = "completed",
            recognized_question = "Example?", recognition_status = "clear",
            clarification_required = false,
        }))
        local conversation = store:getConversation("conversation")
        assert.are.same(2, #conversation.turns)
        assert.are.same("ink", conversation.turns[2].question_type)
        assert.are.same("Example?", conversation.turns[2].recognized_question)
        assert.is_truthy(conversation.turns[2].question_ink)
        local history = ConversationService:new{ responses = store }:history("conversation")
        assert.are.same(2, #history)
    end)

    it("saves completed exchanges for offline current-book reading", function()
        local store = ResponseStore:new{ store = memoryStore() }
        local request = {
            request_id = "q1", created_at = 10,
            question = { type = "text", text = "Why?" }, preferences = { context_mode = "nearby" },
            reading_context = {
                context_mode = "nearby",
                book = { document_id = "book.epub", title = "Book" },
                location = { chapter = "One", anchor = {
                    kind = "xpointer", document_id = "book.epub", start = "/p.0", finish = "/p.4",
                } },
                selection = { text = "Source passage" },
            },
        }
        local saved = assert(store:saveExchange(request, {
            response_id = "a1", answer = "Because.", completed_at = 20,
        }))
        request.reading_context.location.anchor.start = "changed"
        assert.are.same("/p.0", saved.anchor.start)
        assert.are.same("Because.", store:getByRequestId("q1").answer)
        assert.are.same(1, #store:listForDocument("book.epub"))
        assert.are.same(0, #store:listForDocument("other.epub"))
    end)

    it("navigates valid EPUB and PDF anchors through existing reader modules", function()
        local calls = {}
        local ui = {
            document = {
                file = "book.epub",
                isXPointerInDocument = function(_, value) return value == "/good" end,
                getPageCount = function() return 10 end,
            },
            link = { addCurrentLocationToStack = function() calls.back = true end },
            rolling = { onGotoXPointer = function(_, value) calls.xpointer = value end },
        }
        local navigator = AnchorNavigator:new{ ui = ui }
        assert.is_true(navigator:goToPassage{
            kind = "xpointer", document_id = "book.epub", start = "/good", finish = "/end",
        })
        assert.are.same("/good", calls.xpointer)
        assert.is_false(navigator:canNavigate{
            kind = "xpointer", document_id = "book.epub", start = "/stale",
        })
        ui.document.file, ui.rolling, ui.paging = "book.pdf", nil, {
            onGotoPage = function(_, page, pos) calls.page, calls.pos = page, pos end,
        }
        assert.is_true(navigator:goToPassage{
            kind = "fixed_page", document_id = "book.pdf", page = 3, pos0 = { x = 1, y = 2 },
        })
        assert.are.same(3, calls.page)
    end)
end)
