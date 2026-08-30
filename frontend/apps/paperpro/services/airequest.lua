local ContextResolver = require("apps/paperpro/services/contextresolver")
local InkStroke = require("apps/paperpro/ink/inkstroke")
local SelectionService = require("apps/paperpro/services/selectionservice")
local random = require("random")

local AIRequest = {}

AIRequest.SCHEMA_VERSION = 2
AIRequest.LEGACY_SCHEMA_VERSION = 1
AIRequest.MAX_QUESTION_BYTES = 1024
AIRequest.MAX_INK_STROKES = 32
AIRequest.MAX_INK_POINTS = 5000
AIRequest.MAX_HISTORY_TURNS = 6
AIRequest.MAX_HISTORY_BYTES = 8192

local function cleanQuestion(question)
    question = ContextResolver.cleanText(question)
    if not question then return nil, "question_empty" end
    if #question > AIRequest.MAX_QUESTION_BYTES then return nil, "question_too_long" end
    return question
end

local function baseRequest(reading_context, preferences, options)
    options = options or {}
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
        reading_context = SelectionService.deepCopy(reading_context),
        preferences = {
            response_length = preferences and preferences.response_length or "concise",
            context_mode = context_mode,
        },
        conversation = {
            id = options.conversation_id or random.uuid(true):lower(),
            turn_id = options.turn_id or random.uuid(true):lower(),
            history = SelectionService.deepCopy(options.history or {}),
            history_truncated = options.history_truncated and true or false,
        },
    }
end

function AIRequest.createText(reading_context, question, preferences, options)
    local cleaned, err = cleanQuestion(question)
    if not cleaned then return nil, err end
    local request, request_err = baseRequest(reading_context, preferences, options)
    if not request then return nil, request_err end
    request.question = { type = "text", text = cleaned }
    return request
end

local function validateInk(strokes)
    if type(strokes) ~= "table" or #strokes == 0 then return false, "ink_empty" end
    if #strokes > AIRequest.MAX_INK_STROKES then return false, "ink_stroke_limit" end
    local total_points = 0
    for _, value in ipairs(strokes) do
        local stroke, err = InkStroke.fromTable(value.toTable and value:toTable() or value)
        if not stroke or stroke.coordinate_space ~= "screen-v1" then
            return false, err or "invalid_ink"
        end
        total_points = total_points + #stroke.points
        if total_points > AIRequest.MAX_INK_POINTS then return false, "ink_point_limit" end
    end
    return true
end

function AIRequest.createInk(reading_context, strokes, preferences, options)
    local valid, err = validateInk(strokes)
    if not valid then return nil, err end
    local request, request_err = baseRequest(reading_context, preferences, options)
    if not request then return nil, request_err end
    local stored = {}
    for _, stroke in ipairs(strokes) do
        table.insert(stored, SelectionService.deepCopy(stroke.toTable and stroke:toTable() or stroke))
    end
    request.question = {
        type = "ink",
        local_ink = { strokes = stored },
        recognized_text = options and options.recognized_text or nil,
    }
    return request
end


AIRequest.create = AIRequest.createText

function AIRequest.validate(request)
    if type(request) ~= "table"
            or (request.schema_version ~= AIRequest.SCHEMA_VERSION
                and request.schema_version ~= AIRequest.LEGACY_SCHEMA_VERSION)
            or type(request.request_id) ~= "string" or request.request_id == ""
            or type(request.created_at) ~= "number" or type(request.question) ~= "table" then
        return false, "invalid_request"
    end
    if request.question.type == "text" then
        local question, err = cleanQuestion(request.question.text)
        if not question then return false, err end
    elseif request.schema_version == AIRequest.SCHEMA_VERSION and request.question.type == "ink" then
        local valid, err = validateInk(request.question.local_ink and request.question.local_ink.strokes)
        if not valid then return false, err end
        if request.question.recognized_text ~= nil then
            local recognized, recognized_err = cleanQuestion(request.question.recognized_text)
            if not recognized then return false, recognized_err end
        end
    else
        return false, "unsupported_question_type"
    end
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
    if request.schema_version == AIRequest.SCHEMA_VERSION then
        local conversation = request.conversation
        if type(conversation) ~= "table" or type(conversation.id) ~= "string"
                or type(conversation.turn_id) ~= "string" or type(conversation.history) ~= "table"
                or #conversation.history > AIRequest.MAX_HISTORY_TURNS then
            return false, "invalid_conversation"
        end
        local history_bytes = 0
        for _, turn in ipairs(conversation.history) do
            if type(turn) ~= "table" or type(turn.question) ~= "string"
                    or type(turn.answer) ~= "string" then return false, "invalid_conversation" end
            history_bytes = history_bytes + #turn.question + #turn.answer
        end
        if history_bytes > AIRequest.MAX_HISTORY_BYTES then return false, "conversation_too_large" end
    end
    return true
end

AIRequest.cleanQuestion = cleanQuestion
AIRequest.validateInk = validateInk

return AIRequest
