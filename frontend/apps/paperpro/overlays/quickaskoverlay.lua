local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
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
    return setmetatable(options or {}, self)
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
        buttons = {{
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

function QuickAskOverlay:_body(model)
    if model.state == "sending" then return _("Thinking…") end
    if model.state == "queued" then
        return model.message or _("Saved. I'll answer when you're back online.")
    end
    if model.state == "success" then return model.answer end
    if model.state == "cancelled" then return _("Question cancelled") end
    return model.message or _("The reading assistant could not answer this question.")
end

function QuickAskOverlay:_buttons(model, close_func, handlers)
    if model.state == "success" or model.state == "cancelled" then
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
    local dialog = ButtonDialog:new{
        title = model.state == "success" and _("Reading assistant") or _("Ask AI"),
        title_align = "left",
        width_factor = 0.82,
        buttons = self:_buttons(model, close_func, handlers),
    }
    dialog:addWidget(ScrollTextWidget:new{
        text = self:_body(model),
        face = Font:getFace("infofont"),
        width = dialog:getAddedWidgetAvailableWidth(),
        height = math.max(Screen:scaleBySize(100),
            math.min(math.floor(Screen:getHeight() * 0.34), Screen:scaleBySize(300))),
        dialog = dialog,
        scroll_by_pan = true,
    })
    return dialog
end

return QuickAskOverlay
