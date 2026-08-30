local ContextResolver = require("apps/paperpro/services/contextresolver")
local SelectionService = require("apps/paperpro/services/selectionservice")
local random = require("random")

local AIRequest = {}

AIRequest.SCHEMA_VERSION = 1
AIRequest.MAX_QUESTION_BYTES = 1024

local function cleanQuestion(question)
    question = ContextResolver.cleanText(question)
    if not question then return nil, "question_empty" end
    if #question > AIRequest.MAX_QUESTION_BYTES then return nil, "question_too_long" end
    return question
end

function AIRequest.create(reading_context, question, preferences, options)
    options = options or {}
    local cleaned, err = cleanQuestion(question)
    if not cleaned then return nil, err end
    if type(reading_context) ~= "table"
            or reading_context.schema_version ~= ContextResolver.SCHEMA_VERSION
            or not (reading_context.book and reading_context.book.document_id)
            or not (reading_context.selection and reading_context.selection.text) then
        return nil, "invalid_reading_context"
    end
    local context_mode = preferences and preferences.context_mode
        or reading_context.context_mode or "nearby"
    if context_mode ~= "minimal" and context_mode ~= "nearby" then
        return nil, "invalid_context_mode"
    end
    return {
        schema_version = AIRequest.SCHEMA_VERSION,
        request_id = options.request_id or random.uuid(true):lower(),
        created_at = options.created_at or os.time(),
        question = { type = "text", text = cleaned },
        reading_context = SelectionService.deepCopy(reading_context),
        preferences = {
            response_length = preferences and preferences.response_length or "concise",
            context_mode = context_mode,
        },
    }
end

function AIRequest.validate(request)
    if type(request) ~= "table" or request.schema_version ~= AIRequest.SCHEMA_VERSION
            or type(request.request_id) ~= "string" or request.request_id == ""
            or type(request.created_at) ~= "number" or type(request.question) ~= "table"
            or request.question.type ~= "text" then
        return false, "invalid_request"
    end
    local question, err = cleanQuestion(request.question.text)
    if not question then return false, err end
    local context = request.reading_context
    if type(context) ~= "table" or context.schema_version ~= ContextResolver.SCHEMA_VERSION
            or type(context.book) ~= "table" or type(context.book.document_id) ~= "string"
            or type(context.location) ~= "table" or type(context.location.anchor) ~= "table"
            or type(context.selection) ~= "table" or type(context.selection.text) ~= "string"
            or #context.selection.text > ContextResolver.LIMITS.selection_bytes then
        return false, "invalid_reading_context"
    end
    local source_bytes = #context.selection.text
    local fields = {
        before = ContextResolver.LIMITS.side_bytes,
        after = ContextResolver.LIMITS.side_bytes,
        sentence = ContextResolver.LIMITS.sentence_bytes,
        paragraph = ContextResolver.LIMITS.paragraph_bytes,
    }
    for key, limit in pairs(fields) do
        local value = context.context and context.context[key]
        if value ~= nil and (type(value) ~= "string" or #value > limit) then
            return false, "invalid_reading_context"
        end
        source_bytes = source_bytes + #(value or "")
    end
    if source_bytes > ContextResolver.LIMITS.source_bytes then
        return false, "invalid_reading_context"
    end
    local mode = request.preferences and request.preferences.context_mode
    if mode ~= "minimal" and mode ~= "nearby" then return false, "invalid_context_mode" end
    return true
end

AIRequest.cleanQuestion = cleanQuestion

return AIRequest
