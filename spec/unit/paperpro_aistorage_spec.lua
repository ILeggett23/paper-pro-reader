describe("Paper Pro AI settings, responses, and navigation", function()
    local AISettings, AnchorNavigator, ResponseStore, SelectionService

    setup(function()
        require("commonrequire")
        AISettings = require("apps/paperpro/services/aisettings")
        AnchorNavigator = require("apps/paperpro/services/anchornavigator")
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
        assert.is_nil(values.OPENAI_API_KEY)
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
