describe("Paper Pro OfflineQueue", function()
    local AIRequest, ContextResolver, OfflineQueue, SelectionService

    setup(function()
        require("commonrequire")
        AIRequest = require("apps/paperpro/services/airequest")
        ContextResolver = require("apps/paperpro/services/contextresolver")
        OfflineQueue = require("apps/paperpro/services/offlinequeue")
        SelectionService = require("apps/paperpro/services/selectionservice")
    end)

    local function request(id)
        local context = assert(ContextResolver:new():resolve({ document = {} }, {
            text = "passage", anchor = {
                kind = "fixed_page", document_id = "book.pdf", page = 2,
                pos0 = { page = 2, x = 1, y = 2 }, pos1 = { page = 2, x = 3, y = 4 },
            },
        }))
        return assert(AIRequest.create(context, "Question?", nil, {
            request_id = id, created_at = 100,
        }))
    end

    local function memoryStore(initial)
        local state = SelectionService.deepCopy(initial
            or { schema_version = 1, items = {} })
        return {
            load = function() return SelectionService.deepCopy(state) end,
            save = function(_, value) state = SelectionService.deepCopy(value) return true end,
            state = function() return SelectionService.deepCopy(state) end,
        }
    end

    local immediate_ui = { nextTick = function(_, callback) callback() end }

    it("persists stable IDs and recovers interrupted sends after restart", function()
        local store = memoryStore()
        local queue = OfflineQueue:new{ store = store, clock = function() return 100 end, ui_manager = immediate_ui }
        assert.are.same("id-one", queue:enqueue(request("id-one")).id)
        store.state().items[1].state = "sending"
        local persisted = store.state()
        persisted.items[1].state = "sending"
        store:save(persisted)
        local reloaded = OfflineQueue:new{ store = store, clock = function() return 200 end, ui_manager = immediate_ui }
        local item = reloaded:get("id-one")
        assert.are.same("queued", item.state)
        assert.are.same("interrupted", item.last_error_category)
        assert.are.same("id-one", item.request.request_id)
    end)

    it("sends once across duplicate processing events and saves completed responses", function()
        local queue = OfflineQueue:new{ store = memoryStore(), clock = function() return 100 end, ui_manager = immediate_ui }
        queue:enqueue(request("id-two"))
        local calls, finish = 0
        local provider = {
            isAvailable = function() return true end,
            submit = function(_, _, callback) calls = calls + 1 finish = callback return true end,
        }
        local saved
        local responses = { saveExchange = function(_, req, response)
            saved = { req = req, response = response }
            return { request_id = req.request_id }
        end }
        assert.is_true(queue:processNext(provider, responses))
        assert.is_false(queue:processNext(provider, responses))
        assert.are.same(1, calls)
        finish({ response_id = "r2", answer = "Answer", completed_at = 110 })
        assert.are.same("completed", queue:get("id-two").state)
        assert.are.same("id-two", saved.req.request_id)
    end)

    it("applies bounded backoff, explicit retry, and cancellation", function()
        local now = 100
        local queue = OfflineQueue:new{ store = memoryStore(), clock = function() return now end, ui_manager = immediate_ui }
        queue:enqueue(request("id-three"))
        local provider = {
            isAvailable = function() return true end,
            submit = function(_, _, callback)
                callback(nil, { category = "timeout", retryable = true })
                return true
            end,
        }
        queue:processNext(provider, { saveExchange = function() end })
        local item = queue:get("id-three")
        assert.are.same("queued", item.state)
        assert.are.same(130, item.next_retry_at)
        assert.is_true(item.next_retry_at - now <= OfflineQueue.MAX_BACKOFF)
        assert.is_true(queue:retry("id-three"))
        assert.are.same(now, queue:get("id-three").next_retry_at)
        assert.is_true(queue:cancel("id-three"))
        assert.are.same("cancelled", queue:get("id-three").state)
    end)

    it("fails closed on non-retryable authentication errors", function()
        local queue = OfflineQueue:new{ store = memoryStore(), clock = function() return 100 end, ui_manager = immediate_ui }
        queue:enqueue(request("id-four"))
        queue:processNext({
            isAvailable = function() return true end,
            submit = function(_, _, callback)
                callback(nil, { category = "authentication", retryable = false })
                return true
            end,
        }, { saveExchange = function() end })
        assert.are.same("failed", queue:get("id-four").state)
        assert.are.same("authentication", queue:get("id-four").last_error_category)
    end)
end)
