local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local AIHistory = {}
AIHistory.__index = AIHistory

local labels = {
    queued = _("Queued"), sending = _("Sending"), failed = _("Failed"),
    cancelled = _("Cancelled"), completed = _("Completed"),
}

local function excerpt(text, limit)
    text = type(text) == "string" and text:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    limit = limit or 140
    if #text > limit then text = text:sub(1, limit - 3) .. "…" end
    return text
end

function AIHistory:new(options)
    options = options or {}
    assert(options.queue and options.responses and options.navigator,
        "AIHistory requires queue, responses, and navigator")
    return setmetatable(options, self)
end

function AIHistory:_items()
    local document_id = self.navigator.ui.document.file
    local items, completed, by_conversation = {}, {}, {}
    if self.responses.listConversationsForDocument then
        for _, conversation in ipairs(self.responses:listConversationsForDocument(document_id)) do
            local turn = conversation.turns[#conversation.turns]
            local item = {
                kind = "conversation", conversation_id = conversation.conversation_id,
                question = turn.question_text or turn.recognized_question or _("Handwritten question"),
                answer = turn.answer, source_text = conversation.source_text,
                chapter = conversation.chapter, anchor = conversation.anchor,
                created_at = conversation.created_at, updated_at = conversation.updated_at,
                display_status = turn.status == "clarification_required" and "failed" or "completed",
                turn_count = #conversation.turns,
            }
            by_conversation[conversation.conversation_id] = item
            table.insert(items, item)
            for _, saved_turn in ipairs(conversation.turns) do completed[saved_turn.request_id] = true end
        end
    else
        for _, response in ipairs(self.responses:listForDocument(document_id)) do
            response.kind = "response"
            response.display_status = "completed"
            completed[response.request_id] = true
            table.insert(items, response)
        end
    end
    for _, queued in ipairs(self.queue:listForDocument(document_id)) do
        if not completed[queued.id] then
            local context = queued.request.reading_context
            local conversation_id = queued.request.conversation and queued.request.conversation.id
            local existing = conversation_id and by_conversation[conversation_id]
            if existing then
                existing.display_status = queued.state
                existing.request_id = queued.id
                existing.last_error_category = queued.last_error_category
                existing.updated_at = queued.updated_at
            else table.insert(items, {
                kind = "queue",
                conversation_id = conversation_id,
                request_id = queued.id,
                question = queued.request.question.text or _("Handwritten question"),
                source_text = context.selection.text,
                chapter = context.location.chapter,
                anchor = context.location.anchor,
                created_at = queued.created_at,
                updated_at = queued.updated_at,
                display_status = queued.state,
                last_error_category = queued.last_error_category,
            }) end
        end
    end
    table.sort(items, function(a, b)
        return (a.completed_at or a.updated_at or a.created_at or 0)
            > (b.completed_at or b.updated_at or b.created_at or 0)
    end)
    return items
end

function AIHistory:_menuItems()
    local rows = {}
    for _, item in ipairs(self:_items()) do
        local status = labels[item.display_status] or item.display_status
        local location = item.chapter
        if not location and item.anchor and item.anchor.page then
            location = _("Page") .. " " .. tostring(item.anchor.page)
        end
        local metadata = status
        if item.turn_count then metadata = metadata .. " • " .. tostring(item.turn_count) .. " " .. _("turns") end
        if location then metadata = metadata .. " • " .. tostring(location) end
        table.insert(rows, {
            text = excerpt(item.question) .. (item.answer and ("\n" .. excerpt(item.answer, 110)) or ""),
            mandatory = metadata,
            ai_item = item,
        })
    end
    if #rows == 0 then return {{ text = _("No AI questions for this book"), select_enabled = false }} end
    return rows
end

function AIHistory:refreshIfOpen()
    if self.menu then self.menu:switchItemTable(_("AI Questions"), self:_menuItems()) end
end

function AIHistory:_detailText(item)
    local parts = {
        _("Passage") .. "\n" .. (excerpt(item.source_text, 800) ~= ""
            and excerpt(item.source_text, 800) or _("Passage text unavailable")),
        _("Question") .. "\n" .. item.question,
        _("Status") .. ": " .. (labels[item.display_status] or item.display_status),
    }
    if item.answer then table.insert(parts, 3, _("Answer") .. "\n" .. item.answer) end
    if item.last_error_category then
        table.insert(parts, _("Error category") .. ": " .. item.last_error_category)
    end
    local can_navigate, reason = self.navigator:canNavigate(item.anchor)
    if not can_navigate then table.insert(parts, reason or _("Passage navigation is unavailable")) end
    return table.concat(parts, "\n\n"), can_navigate
end

function AIHistory:_showDetail(item)
    if item.kind == "conversation" and self.on_open_conversation then
        self:close()
        self.on_open_conversation(item.conversation_id)
        return
    end
    local text, can_navigate = self:_detailText(item)
    local viewer
    local buttons = {{
        { text = _("Close"), callback = function() UIManager:close(viewer) end },
        {
            text = _("Go to passage"), enabled = can_navigate,
            callback = function()
                local ok, err = self.navigator:goToPassage(item.anchor)
                if ok then UIManager:close(viewer); self:close()
                else UIManager:show(InfoMessage:new{ text = err }) end
            end,
        },
    }}
    if item.kind == "queue" and (item.display_status == "queued" or item.display_status == "sending") then
        table.insert(buttons, {{
            text = _("Cancel question"),
            callback = function()
                if self.on_cancel then self.on_cancel(item.request_id) end
                UIManager:close(viewer)
                self:refreshIfOpen()
            end,
        }})
    elseif item.kind == "queue" and item.display_status == "failed" then
        table.insert(buttons, {{
            text = _("Retry"),
            callback = function()
                if self.on_retry then self.on_retry(item.request_id) end
                UIManager:close(viewer)
                self:refreshIfOpen()
            end,
        }})
    end
    viewer = TextViewer:new{ title = _("AI Question"), text = text, buttons_table = buttons }
    UIManager:show(viewer)
end

function AIHistory:open()
    if self.menu then return true end
    local hub = self
    self.menu = Menu:new{
        title = _("AI Questions"),
        item_table = self:_menuItems(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        multilines_forced = true,
        items_max_lines = 3,
        close_callback = function() hub.menu = nil end,
    }
    function self.menu:onMenuSelect(row)
        if row.ai_item then hub:_showDetail(row.ai_item) end
        return true
    end
    UIManager:show(self.menu)
    return true
end

function AIHistory:close()
    if not self.menu then return false end
    local menu = self.menu
    self.menu = nil
    UIManager:close(menu)
    return true
end

return AIHistory
