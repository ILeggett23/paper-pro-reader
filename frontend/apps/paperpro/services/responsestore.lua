local AtomicJSONStore = require("apps/paperpro/services/atomicjsonstore")
local DataStorage = require("datastorage")
local JSON = require("rapidjson")
local SelectionService = require("apps/paperpro/services/selectionservice")
local util = require("util")

local ResponseStore = {}
ResponseStore.__index = ResponseStore
ResponseStore.SCHEMA_VERSION = 2
ResponseStore.LEGACY_SCHEMA_VERSION = 1
ResponseStore.MAX_RESPONSES = 500
ResponseStore.MAX_CONVERSATIONS = 500
ResponseStore.MAX_TURNS = 100
ResponseStore.FILENAME = "paperpro-ai-responses.json"

local function validResponse(item)
    return type(item) == "table" and type(item.request_id) == "string"
        and type(item.response_id) == "string" and type(item.question) == "string"
        and type(item.answer) == "string" and type(item.document_id) == "string"
        and type(item.created_at) == "number" and type(item.completed_at) == "number"
        and type(item.anchor) == "table" and item.status == "completed"
end

local function validConversation(item)
    if type(item) ~= "table" or type(item.conversation_id) ~= "string"
            or type(item.document_id) ~= "string" or type(item.anchor) ~= "table"
            or type(item.source_text) ~= "string" or type(item.turns) ~= "table"
            or #item.turns == 0 or #item.turns > ResponseStore.MAX_TURNS then return false end
    for _, turn in ipairs(item.turns) do
        if type(turn) ~= "table" or type(turn.request_id) ~= "string"
                or (turn.question_type ~= "text" and turn.question_type ~= "ink")
                or type(turn.answer) ~= "string" or type(turn.status) ~= "string"
                or type(turn.created_at) ~= "number" then return false end
    end
    return true
end

local function validate(data)
    if type(data.responses) ~= "table" or #data.responses > ResponseStore.MAX_RESPONSES
            or type(data.conversations) ~= "table"
            or #data.conversations > ResponseStore.MAX_CONVERSATIONS then
        return false, "response_limit"
    end
    for _, item in ipairs(data.responses) do
        if not validResponse(item) then return false, "invalid_response" end
    end
    for _, item in ipairs(data.conversations) do
        if not validConversation(item) then return false, "invalid_conversation" end
    end
    return true
end

local function legacyConversation(item)
    return {
        conversation_id = "legacy-" .. item.request_id,
        document_id = item.document_id, book_title = item.book_title,
        author = SelectionService.deepCopy(item.author), chapter = item.chapter,
        anchor = SelectionService.deepCopy(item.anchor), source_text = item.source_text or "",
        context_mode = item.context_mode, created_at = item.created_at,
        updated_at = item.completed_at,
        reading_context = {
            schema_version = 1,
            book = { document_id = item.document_id, title = item.book_title,
                author = SelectionService.deepCopy(item.author) },
            location = { chapter = item.chapter, anchor = SelectionService.deepCopy(item.anchor) },
            selection = { text = item.source_text or "" }, context = {},
            context_mode = item.context_mode or "nearby",
            truncation = { any = false }, capabilities = {},
        },
        turns = {{
            turn_id = "legacy-" .. item.request_id, request_id = item.request_id,
            response_id = item.response_id, question_type = "text",
            question_text = item.question, answer = item.answer,
            status = "completed", created_at = item.created_at,
            completed_at = item.completed_at,
        }},
    }
end

local function migrate(data)
    if type(data) ~= "table" or data.schema_version ~= ResponseStore.LEGACY_SCHEMA_VERSION
            or type(data.responses) ~= "table" then return nil end
    local migrated = { schema_version = ResponseStore.SCHEMA_VERSION,
        responses = SelectionService.deepCopy(data.responses), conversations = {} }
    for _, item in ipairs(data.responses) do
        if validResponse(item) then table.insert(migrated.conversations, legacyConversation(item)) end
    end
    return migrated
end

function ResponseStore:new(options)
    options = options or {}
    options.path = options.path or (DataStorage:getSettingsDir() .. "/" .. self.FILENAME)
    local legacy
    if options.store then
        local raw = options.store:load()
        legacy = migrate(raw)
    else
        local content = util.readFromFile(options.path, "rb")
        if content then legacy = migrate(JSON.decode(content)) end
        options.store = AtomicJSONStore:new{
            path = options.path, schema_version = self.SCHEMA_VERSION, validate = validate,
            default_data = function()
                return { schema_version = ResponseStore.SCHEMA_VERSION,
                    responses = {}, conversations = {} }
            end,
        }
    end
    local data, err
    if legacy then
        data = legacy
        local saved, save_err = options.store:save(data)
        if not saved then err = save_err end
    else
        data, err = options.store:load()
    end
    options.data = data or { schema_version = self.SCHEMA_VERSION,
        responses = {}, conversations = {} }
    options.data.conversations = options.data.conversations or {}
    options.load_error = err
    return setmetatable(options, self)
end

function ResponseStore:getByRequestId(request_id)
    for _, item in ipairs(self.data.responses) do
        if item.request_id == request_id then return SelectionService.deepCopy(item) end
    end
end

function ResponseStore:_conversation(id)
    for index, item in ipairs(self.data.conversations) do
        if item.conversation_id == id then return item, index end
    end
end

function ResponseStore:saveExchange(request, response)
    if type(request) ~= "table" or type(response) ~= "table"
            or type(response.response_id) ~= "string" or type(response.answer) ~= "string" then
        return nil, "invalid_exchange"
    end
    local existing
    for index, value in ipairs(self.data.responses) do
        if value.request_id == request.request_id then existing = index break end
    end
    local context = request.reading_context or {}
    local book, location, selection = context.book or {}, context.location or {}, context.selection or {}
    local question_text = request.question.text or response.recognized_question or "Handwritten question"
    local item = {
        request_id = request.request_id, response_id = response.response_id,
        question = question_text, answer = response.answer,
        document_id = book.document_id, book_title = book.title,
        author = SelectionService.deepCopy(book.author), chapter = location.chapter,
        anchor = SelectionService.deepCopy(location.anchor), source_text = selection.text,
        created_at = request.created_at, completed_at = response.completed_at or os.time(),
        context_mode = context.context_mode or request.preferences.context_mode,
        status = "completed", recognized_question = response.recognized_question,
        recognition_status = response.recognition_status,
        clarification_required = response.clarification_required and true or false,
    }
    if not validResponse(item) then return nil, "invalid_exchange" end
    if existing then self.data.responses[existing] = item else table.insert(self.data.responses, item) end

    local conversation_id = request.conversation and request.conversation.id
        or "legacy-" .. request.request_id
    local conversation = self:_conversation(conversation_id)
    if not conversation then
        conversation = {
            conversation_id = conversation_id, document_id = book.document_id,
            book_title = book.title, author = SelectionService.deepCopy(book.author),
            chapter = location.chapter, anchor = SelectionService.deepCopy(location.anchor),
            source_text = selection.text or "", context_mode = item.context_mode,
            reading_context = SelectionService.deepCopy(context),
            created_at = request.created_at, updated_at = item.completed_at, turns = {},
        }
        table.insert(self.data.conversations, conversation)
    end
    local turn = {
        turn_id = request.conversation and request.conversation.turn_id or request.request_id,
        request_id = request.request_id, response_id = response.response_id,
        question_type = request.question.type, question_text = request.question.text,
        recognized_question = response.recognized_question,
        recognition_status = response.recognition_status,
        clarification_required = response.clarification_required and true or false,
        question_ink = request.question.type == "ink"
            and SelectionService.deepCopy(request.question.local_ink) or nil,
        answer = response.answer, status = response.status or "completed",
        created_at = request.created_at, completed_at = item.completed_at,
        kept_in_book = false,
    }
    local replaced = false
    for index, value in ipairs(conversation.turns) do
        if value.request_id == request.request_id then
            conversation.turns[index] = turn
            replaced = true
            break
        end
    end
    if not replaced then table.insert(conversation.turns, turn) end
    conversation.updated_at = item.completed_at

    table.sort(self.data.responses, function(a, b) return a.completed_at > b.completed_at end)
    table.sort(self.data.conversations, function(a, b) return a.updated_at > b.updated_at end)
    while #self.data.responses > self.MAX_RESPONSES do table.remove(self.data.responses) end
    while #self.data.conversations > self.MAX_CONVERSATIONS do table.remove(self.data.conversations) end
    local saved, err = self.store:save(self.data)
    if not saved then return nil, err end
    return SelectionService.deepCopy(item)
end

function ResponseStore:listForDocument(document_id)
    local items = {}
    for _, item in ipairs(self.data.responses) do
        if item.document_id == document_id then table.insert(items, SelectionService.deepCopy(item)) end
    end
    return items
end

function ResponseStore:listConversationsForDocument(document_id)
    local items = {}
    for _, item in ipairs(self.data.conversations) do
        if item.document_id == document_id then table.insert(items, SelectionService.deepCopy(item)) end
    end
    return items
end

function ResponseStore:getConversation(id)
    local item = self:_conversation(id)
    return item and SelectionService.deepCopy(item) or nil
end

function ResponseStore:markKeptInBook(conversation_id, request_id)
    local conversation = self:_conversation(conversation_id)
    if not conversation then return false end
    for _, turn in ipairs(conversation.turns) do
        if turn.request_id == request_id then
            turn.kept_in_book = true
            conversation.updated_at = os.time()
            return self.store:save(self.data)
        end
    end
    return false
end

ResponseStore.validate = validate
ResponseStore.migrate = migrate

return ResponseStore
