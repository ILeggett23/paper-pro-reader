local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ConversationHub = {}
ConversationHub.__index = ConversationHub

function ConversationHub:new(options)
    options = options or {}
    assert(options.responses and options.navigator,
        "ConversationHub requires ResponseStore and AnchorNavigator")
    return setmetatable(options, self)
end

function ConversationHub:_text(conversation, full_study)
    local parts = {}
    if full_study then
        table.insert(parts, conversation.book_title or _("Current book"))
        if conversation.chapter then table.insert(parts, conversation.chapter) end
    end
    table.insert(parts, _("Source passage") .. "\n" .. conversation.source_text)
    for index, turn in ipairs(conversation.turns) do
        local question = turn.question_text or turn.recognized_question or _("Handwritten question")
        local kind = turn.question_type == "ink" and _("Written question") or _("Typed question")
        table.insert(parts, string.format("%d. %s\n%s\n\n%s\n%s",
            index, kind, question, _("Answer"), turn.answer))
        if turn.status ~= "completed" then table.insert(parts, _("Status") .. ": " .. turn.status) end
    end
    return table.concat(parts, "\n\n")
end

function ConversationHub:open(conversation_id, full_study)
    local conversation = self.responses:getConversation(conversation_id)
    if not conversation then return false, "Conversation is unavailable" end
    if self.viewer then UIManager:close(self.viewer) end
    local viewer
    local can_navigate = self.navigator:canNavigate(conversation.anchor)
    local latest = conversation.turns[#conversation.turns]
    local buttons = {
        {
            { text = _("Close"), callback = function() self:close() end },
            {
                text = _("Go to passage"), enabled = can_navigate,
                callback = function()
                    local ok, err = self.navigator:goToPassage(conversation.anchor)
                    if ok then self:close()
                    else UIManager:show(InfoMessage:new{ text = err }) end
                end,
            },
        },
        {
            {
                text = _("Follow-up"),
                callback = function()
                    self:close()
                    if self.on_followup then self.on_followup(conversation) end
                end,
            },
            {
                text = full_study and _("Compact") or _("Full Study"),
                callback = function() self:open(conversation_id, not full_study) end,
            },
        },
    }
    if latest.question_ink and not latest.kept_in_book and self.on_keep_ink then
        table.insert(buttons, {{ text = _("Keep question in book"), callback = function()
            if self.on_keep_ink(conversation, latest) then self:open(conversation_id, full_study) end
        end }})
    end
    viewer = TextViewer:new{
        title = full_study and _("Full Study") or _("Conversation"),
        text = self:_text(conversation, full_study),
        buttons_table = buttons,
    }
    self.viewer = viewer
    UIManager:show(viewer)
    return true
end

function ConversationHub:close()
    if not self.viewer then return false end
    local viewer = self.viewer
    self.viewer = nil
    UIManager:close(viewer)
    return true
end

return ConversationHub
