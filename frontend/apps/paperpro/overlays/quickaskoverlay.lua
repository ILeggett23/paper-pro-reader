local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HandwrittenResponseRenderer = require("apps/paperpro/overlays/handwrittenresponserenderer")
local InputDialog = require("ui/widget/inputdialog")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Screen = Device.screen

local QuickAskOverlay = {}
QuickAskOverlay.__index = QuickAskOverlay

local function excerpt(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #text > 180 then text = text:sub(1, 177) .. "…" end
    return text ~= "" and text or nil
end

function QuickAskOverlay:new(options)
    options = options or {}
    options.handwriting_renderer = options.handwriting_renderer or HandwrittenResponseRenderer:new()
    return setmetatable(options, self)
end

function QuickAskOverlay:_compose(model, close_func, handlers)
    local dialog
    local description = excerpt(model.source_text) or _("Selected passage")
    description = description .. "\n\n" .. (model.context_mode == "minimal"
        and _("Context: selected passage only") or _("Context: selected passage and nearby text"))
    if model.message then description = description .. "\n\n" .. model.message end
    dialog = InputDialog:new{
        title = _("Ask about this passage"),
        description = description,
        input = model.question or "",
        input_hint = _("What would you like to understand?"),
        allow_newline = true,
        add_scroll_buttons = true,
        is_movable = true,
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.84),
        text_height = math.floor(Screen:getHeight() * 0.14),
        buttons = {
            {
                { id = "paperpro_ai_type", text = _("Type"), enabled = false },
                { id = "paperpro_ai_write", text = _("Write"), callback = function() handlers.mode("write") end },
            },
            {
            { id = "paperpro_ai_cancel", text = _("Cancel"), callback = close_func },
            {
                id = "paperpro_ai_ask",
                text = _("Ask"),
                callback = function() handlers.submit(dialog:getInputText()) end,
            },
        }},
    }
    return dialog
end

function QuickAskOverlay:writingBounds()
    local width = math.min(math.floor(Screen:getWidth() * 0.78), Screen:scaleBySize(1200))
    local height = math.min(math.floor(Screen:getHeight() * 0.22), Screen:scaleBySize(440))
    return Geom:new{
        x = math.floor((Screen:getWidth() - width) / 2),
        y = math.floor(Screen:getHeight() * 0.30),
        w = width, h = height,
    }
end

function QuickAskOverlay:_writing(model, close_func, handlers)
    local dialog = ButtonDialog:new{
        title = _("Write your question"), title_align = "left", width_factor = 0.84,
        buttons = {
            {
                { id = "paperpro_ai_type", text = _("Type"), callback = function() handlers.mode("type") end },
                { id = "paperpro_ai_write", text = _("Write"), enabled = false },
            },
            {
                { id = "paperpro_ai_ink_undo", text = _("Undo"), callback = handlers.undo },
                { id = "paperpro_ai_ink_clear", text = _("Clear"), callback = handlers.clear },
            },
            {
                { id = "paperpro_ai_cancel", text = _("Cancel"), callback = close_func },
                { id = "paperpro_ai_ink_submit", text = _("Ask"), callback = handlers.submit_ink },
            },
        },
    }
    dialog:addWidget(VerticalSpan:new{ width = self:writingBounds().h })
    return dialog
end

function QuickAskOverlay:_body(model)
    if model.state == "sending" then return _("Thinking…") end
    if model.state == "queued" then
        return model.message or _("Saved. I'll answer when you're back online.")
    end
    if model.state == "success" then
        local prefix = model.recognized_question and
            (_("I read that as: ") .. '"' .. model.recognized_question .. '"\n\n') or ""
        return prefix .. model.answer
    end
    if model.state == "clarification" then
        return (model.recognized_question and (_("I read that as: ") .. '"'
            .. model.recognized_question .. '"\n\n') or "")
            .. (model.message or _("I couldn't confidently read part of this question."))
    end
    if model.state == "cancelled" then return _("Question cancelled") end
    return model.message or _("The reading assistant could not answer this question.")
end

function QuickAskOverlay:_buttons(model, close_func, handlers)
    if model.state == "success" then
        local rows = {{
            { id = "paperpro_ai_close", text = _("Close"), callback = close_func },
            { id = "paperpro_ai_followup", text = _("Follow-up"), callback = handlers.followup },
            { id = "paperpro_ai_expand", text = _("Expand"), callback = handlers.expand },
        }}
        if model.question_type == "ink" and not model.kept_in_book then
            table.insert(rows, {{ id = "paperpro_ai_keep_ink", text = _("Keep in book"), callback = handlers.keep_ink }})
        end
        table.insert(rows, {{
            id = "paperpro_ai_response_style",
            text = model.response_style == "handwriting" and _("Use text style") or _("Use handwriting style"),
            callback = handlers.toggle_style,
        }})
        return rows
    elseif model.state == "clarification" then
        return {
            {
                { id = "paperpro_ai_rewrite", text = _("Rewrite"), callback = handlers.rewrite },
                { id = "paperpro_ai_edit_text", text = _("Edit as text"), callback = handlers.edit_text },
            },
            {
                { id = "paperpro_ai_close", text = _("Cancel"), callback = close_func },
                { id = "paperpro_ai_ask_anyway", text = _("Ask anyway"), callback = handlers.ask_anyway },
            },
        }
    elseif model.state == "cancelled" then
        return {{ { id = "paperpro_ai_close", text = _("Close"), callback = close_func } }}
    elseif model.state == "queued" or model.state == "sending" then
        return {{
            { id = "paperpro_ai_close", text = _("Close"), callback = close_func },
            {
                id = "paperpro_ai_cancel_request",
                text = _("Cancel question"),
                callback = function() handlers.cancel(model.request_id) end,
            },
        }}
    end
    return {
        {{ id = "paperpro_ai_close", text = _("Close"), callback = close_func }},
        {{
            id = "paperpro_ai_retry",
            text = model.retryable and _("Retry") or _("Edit question"),
            callback = function() handlers.retry(model) end,
        }},
    }
end

function QuickAskOverlay:build(model, _anchor_func, close_func, handlers)
    handlers = handlers or {}
    if model.state == "compose" then return self:_compose(model, close_func, handlers) end
    if model.state == "write" then return self:_writing(model, close_func, handlers) end
    local dialog = ButtonDialog:new{
        title = model.state == "success" and _("Reading assistant") or _("Ask AI"),
        title_align = "left",
        width_factor = 0.82,
        buttons = self:_buttons(model, close_func, handlers),
    }
    local face = model.state == "success" and model.response_style == "handwriting"
        and self.handwriting_renderer:getFace() or Font:getFace("infofont")
    dialog:addWidget(ScrollTextWidget:new{
        text = self:_body(model),
        face = face,
        width = dialog:getAddedWidgetAvailableWidth(),
        height = math.max(Screen:scaleBySize(100),
            math.min(math.floor(Screen:getHeight() * 0.34), Screen:scaleBySize(300))),
        dialog = dialog,
        scroll_by_pan = true,
    })
    return dialog
end

return QuickAskOverlay
