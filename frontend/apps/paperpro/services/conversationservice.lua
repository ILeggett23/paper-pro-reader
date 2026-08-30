local AIRequest = require("apps/paperpro/services/airequest")

local ConversationService = {}
ConversationService.__index = ConversationService

function ConversationService:new(options)
    options = options or {}
    assert(options.responses, "ConversationService requires ResponseStore")
    return setmetatable(options, self)
end

function ConversationService:history(conversation_id)
    local conversation = conversation_id and self.responses:getConversation(conversation_id)
    if not conversation then return {}, false end
    local history, bytes, trimmed = {}, 0, false
    for index = #conversation.turns, 1, -1 do
        local turn = conversation.turns[index]
        local question = turn.question_text or turn.recognized_question
        if question and turn.answer then
            local size = #question + #turn.answer
            if #history >= AIRequest.MAX_HISTORY_TURNS
                    or bytes + size > AIRequest.MAX_HISTORY_BYTES then
                trimmed = true
                break
            end
            table.insert(history, 1, { question = question, answer = turn.answer })
            bytes = bytes + size
        end
    end
    return history, trimmed
end

function ConversationService:requestOptions(conversation_id)
    local history, trimmed = self:history(conversation_id)
    return { conversation_id = conversation_id, history = history, history_truncated = trimmed }
end

return ConversationService
