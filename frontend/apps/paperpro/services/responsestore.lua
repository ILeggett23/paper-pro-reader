local AtomicJSONStore = require("apps/paperpro/services/atomicjsonstore")
local DataStorage = require("datastorage")
local SelectionService = require("apps/paperpro/services/selectionservice")

local ResponseStore = {}
ResponseStore.__index = ResponseStore

ResponseStore.SCHEMA_VERSION = 1
ResponseStore.MAX_RESPONSES = 500
ResponseStore.FILENAME = "paperpro-ai-responses.json"

local function validResponse(item)
    return type(item) == "table" and type(item.request_id) == "string"
        and type(item.response_id) == "string" and type(item.question) == "string"
        and type(item.answer) == "string" and type(item.document_id) == "string"
        and type(item.created_at) == "number" and type(item.completed_at) == "number"
        and type(item.anchor) == "table" and item.status == "completed"
end

local function validate(data)
    if type(data.responses) ~= "table" or #data.responses > ResponseStore.MAX_RESPONSES then
        return false, "response_limit"
    end
    for _, item in ipairs(data.responses) do
        if not validResponse(item) then return false, "invalid_response" end
    end
    return true
end

function ResponseStore:new(options)
    options = options or {}
    options.path = options.path or (DataStorage:getSettingsDir() .. "/" .. self.FILENAME)
    options.store = options.store or AtomicJSONStore:new{
        path = options.path,
        schema_version = self.SCHEMA_VERSION,
        validate = validate,
        default_data = function()
            return { schema_version = ResponseStore.SCHEMA_VERSION, responses = {} }
        end,
    }
    local data, err = options.store:load()
    options.data = data or { schema_version = self.SCHEMA_VERSION, responses = {} }
    options.load_error = err
    return setmetatable(options, self)
end

function ResponseStore:getByRequestId(request_id)
    for _, item in ipairs(self.data.responses) do
        if item.request_id == request_id then return SelectionService.deepCopy(item) end
    end
end

function ResponseStore:saveExchange(request, response)
    if type(request) ~= "table" or type(response) ~= "table"
            or type(response.response_id) ~= "string" or type(response.answer) ~= "string" then
        return nil, "invalid_exchange"
    end
    local existing
    for index, item in ipairs(self.data.responses) do
        if item.request_id == request.request_id then
            existing = index
            break
        end
    end
    local context = request.reading_context or {}
    local book, location, selection = context.book or {}, context.location or {}, context.selection or {}
    local item = {
        request_id = request.request_id,
        response_id = response.response_id,
        question = request.question.text,
        answer = response.answer,
        document_id = book.document_id,
        book_title = book.title,
        author = SelectionService.deepCopy(book.author),
        chapter = location.chapter,
        anchor = SelectionService.deepCopy(location.anchor),
        source_text = selection.text,
        created_at = request.created_at,
        completed_at = response.completed_at or os.time(),
        context_mode = context.context_mode or request.preferences.context_mode,
        status = "completed",
    }
    if not validResponse(item) then return nil, "invalid_exchange" end
    if existing then
        self.data.responses[existing] = item
    else
        table.insert(self.data.responses, item)
    end
    table.sort(self.data.responses, function(a, b) return a.completed_at > b.completed_at end)
    while #self.data.responses > self.MAX_RESPONSES do table.remove(self.data.responses) end
    local saved, err = self.store:save(self.data)
    if not saved then return nil, err end
    return SelectionService.deepCopy(item)
end

function ResponseStore:listForDocument(document_id)
    local items = {}
    for _, item in ipairs(self.data.responses) do
        if item.document_id == document_id then
            table.insert(items, SelectionService.deepCopy(item))
        end
    end
    return items
end

ResponseStore.validate = validate

return ResponseStore
