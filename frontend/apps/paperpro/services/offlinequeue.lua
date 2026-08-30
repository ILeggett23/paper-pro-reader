local AIRequest = require("apps/paperpro/services/airequest")
local AtomicJSONStore = require("apps/paperpro/services/atomicjsonstore")
local DataStorage = require("datastorage")
local SelectionService = require("apps/paperpro/services/selectionservice")
local UIManager = require("ui/uimanager")

local OfflineQueue = {}
OfflineQueue.__index = OfflineQueue

OfflineQueue.SCHEMA_VERSION = 1
OfflineQueue.MAX_ITEMS = 500
OfflineQueue.MAX_BATCH = 3
OfflineQueue.MAX_BACKOFF = 3600
OfflineQueue.FILENAME = "paperpro-ai-queue.json"

local valid_states = {
    queued = true, sending = true, completed = true, failed = true, cancelled = true,
}

local function validate(data)
    if type(data.items) ~= "table" or #data.items > OfflineQueue.MAX_ITEMS then
        return false, "queue_limit"
    end
    local ids = {}
    for _, item in ipairs(data.items) do
        if type(item) ~= "table" then return false, "invalid_queue_item" end
        local valid_request = AIRequest.validate(item.request)
        if type(item.id) ~= "string" or ids[item.id]
                or item.id ~= item.request.request_id or not valid_states[item.state]
                or type(item.attempts) ~= "number" or not valid_request then
            return false, "invalid_queue_item"
        end
        ids[item.id] = true
    end
    return true
end

function OfflineQueue:new(options)
    options = options or {}
    options.path = options.path or (DataStorage:getSettingsDir() .. "/" .. self.FILENAME)
    options.clock = options.clock or os.time
    options.ui_manager = options.ui_manager or UIManager
    options.store = options.store or AtomicJSONStore:new{
        path = options.path,
        schema_version = self.SCHEMA_VERSION,
        validate = validate,
        default_data = function()
            return { schema_version = OfflineQueue.SCHEMA_VERSION, items = {} }
        end,
    }
    local data, err = options.store:load()
    options.data = data or { schema_version = self.SCHEMA_VERSION, items = {} }
    options.load_error = err
    options.listeners = {}
    options.listener_sequence = 0
    setmetatable(options, self)
    options:_recoverInterrupted()
    return options
end

function OfflineQueue:_save()
    return self.store:save(self.data)
end

function OfflineQueue:_recoverInterrupted()
    local recovered = false
    for _, item in ipairs(self.data.items) do
        if item.state == "sending" then
            item.state = "queued"
            item.last_error_category = "interrupted"
            item.next_retry_at = self.clock()
            recovered = true
        end
    end
    if recovered then self:_save() end
end

function OfflineQueue:_find(id)
    for index, item in ipairs(self.data.items) do
        if item.id == id then return item, index end
    end
end

function OfflineQueue:get(id)
    local item = self:_find(id)
    return item and SelectionService.deepCopy(item) or nil
end

function OfflineQueue:addListener(callback)
    self.listener_sequence = self.listener_sequence + 1
    self.listeners[self.listener_sequence] = callback
    return self.listener_sequence
end

function OfflineQueue:removeListener(id)
    self.listeners[id] = nil
end

function OfflineQueue:_emit(item)
    local copy = SelectionService.deepCopy(item)
    for _, callback in pairs(self.listeners) do callback(copy) end
end

function OfflineQueue:_prune()
    while #self.data.items >= self.MAX_ITEMS do
        local remove_index
        for index = #self.data.items, 1, -1 do
            local state = self.data.items[index].state
            if state == "completed" or state == "cancelled" then
                remove_index = index
                break
            end
        end
        if not remove_index then return false end
        table.remove(self.data.items, remove_index)
    end
    return true
end

function OfflineQueue:enqueue(request)
    local valid, err = AIRequest.validate(request)
    if not valid then return nil, err end
    local existing = self:_find(request.request_id)
    if existing then return SelectionService.deepCopy(existing), "already_exists" end
    if not self:_prune() then return nil, "queue_full" end
    local item = {
        id = request.request_id,
        request = SelectionService.deepCopy(request),
        state = "queued",
        attempts = 0,
        created_at = request.created_at,
        updated_at = self.clock(),
        next_retry_at = self.clock(),
    }
    table.insert(self.data.items, 1, item)
    local saved, save_err = self:_save()
    if not saved then
        table.remove(self.data.items, 1)
        return nil, save_err
    end
    self:_emit(item)
    return SelectionService.deepCopy(item)
end

function OfflineQueue:listForDocument(document_id)
    local items = {}
    for _, item in ipairs(self.data.items) do
        local book = item.request.reading_context.book
        if book and book.document_id == document_id then
            table.insert(items, SelectionService.deepCopy(item))
        end
    end
    table.sort(items, function(a, b) return a.updated_at > b.updated_at end)
    return items
end

function OfflineQueue:cancel(id)
    local item = self:_find(id)
    if not item or item.state == "completed" or item.state == "cancelled" then return false end
    item.state = "cancelled"
    item.updated_at = self.clock()
    item.next_retry_at = nil
    local saved, err = self:_save()
    if saved then self:_emit(item) end
    return saved, err
end

function OfflineQueue:retry(id)
    local item = self:_find(id)
    if not item or (item.state ~= "failed" and item.state ~= "queued") then return false end
    item.state = "queued"
    item.last_error_category = nil
    item.next_retry_at = self.clock()
    item.updated_at = self.clock()
    local saved, err = self:_save()
    if saved then self:_emit(item) end
    return saved, err
end

function OfflineQueue:_next(preferred_id)
    local now = self.clock()
    if preferred_id then
        local item = self:_find(preferred_id)
        if item and item.state == "queued" and (item.next_retry_at or 0) <= now then return item end
    end
    for index = #self.data.items, 1, -1 do
        local item = self.data.items[index]
        if item.state == "queued" and (item.next_retry_at or 0) <= now then return item end
    end
end

function OfflineQueue:_settle(item, response_store, response, err)
    if item.state == "cancelled" then return end
    if response then
        local saved, save_err = response_store:saveExchange(item.request, response)
        if saved then
            item.state = "completed"
            item.response_id = response.response_id
            item.last_error_category = nil
            item.next_retry_at = nil
        else
            err = { category = save_err or "storage_failure", retryable = true }
        end
    end
    if not response or item.state ~= "completed" then
        item.attempts = item.attempts + 1
        item.last_error_category = err and err.category or "unknown"
        if err and err.retryable then
            item.state = "queued"
            item.next_retry_at = self.clock()
                + math.min(self.MAX_BACKOFF, 30 * (2 ^ math.min(item.attempts - 1, 7)))
        else
            item.state = "failed"
            item.next_retry_at = nil
        end
    end
    item.updated_at = self.clock()
    self:_save()
    self:_emit(item)
end

function OfflineQueue:processNext(provider, response_store, options)
    options = options or {}
    if self.processing_id or not provider:isAvailable() then return false end
    local item = self:_next(options.preferred_id)
    if not item then return false end
    item.state = "sending"
    item.updated_at = self.clock()
    self.processing_id = item.id
    self:_save()
    self:_emit(item)

    local callback_called = false
    local started, start_err = provider:submit(item.request, function(response, err)
        callback_called = true
        if self.processing_id == item.id then self.processing_id = nil end
        self:_settle(item, response_store, response, err)
        if options.on_settled then options.on_settled(item) end
    end)
    if not started and not callback_called then
        self.processing_id = nil
        self:_settle(item, response_store, nil,
            { category = start_err or "network_failure", retryable = true })
        if options.on_settled then options.on_settled(item) end
    end
    return started or callback_called
end

function OfflineQueue:processBatch(provider, response_store, options)
    options = options or {}
    local remaining = math.min(options.max_count or self.MAX_BATCH, self.MAX_BATCH)
    local function nextItem()
        if remaining <= 0 then return end
        remaining = remaining - 1
        self:processNext(provider, response_store, {
            preferred_id = options.preferred_id,
            on_settled = function(item)
                if options.on_settled then options.on_settled(item) end
                options.preferred_id = nil
                self.ui_manager:nextTick(nextItem)
            end,
        })
    end
    nextItem()
end

OfflineQueue.validate = validate

return OfflineQueue
