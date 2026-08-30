local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local _ = require("gettext")

local Screen = Device.screen

local DefinitionOverlay = {}
DefinitionOverlay.__index = DefinitionOverlay

function DefinitionOverlay:new(options)
    return setmetatable(options or {}, self)
end

function DefinitionOverlay:_body(model)
    if model.status == "loading" then
        return _("Looking in local dictionaries…")
    elseif model.status == "no_definition" then
        return _("No local definition found")
    elseif model.status == "error" then
        return model.message or _("Local dictionary lookup failed")
    end

    local definitions = {}
    for _, definition in ipairs(model.definitions or {}) do
        local source = definition.dictionary_name and definition.dictionary_name ~= ""
            and ("\n" .. _("Source: ") .. definition.dictionary_name) or ""
        table.insert(definitions, definition.text .. source)
    end
    local body = table.concat(definitions, "\n\n")
    if model.is_phrase then
        body = body .. "\n\n" .. _("Phrase lookup uses the selected text as-is.")
    end
    local vocabulary_status = {
        added = _("✓ Added to Vocabulary"),
        already = _("Already in Vocabulary"),
        saving = _("Saving to Vocabulary…"),
        unavailable = _("Vocabulary is unavailable"),
        error = _("Could not save to Vocabulary"),
    }
    if model.vocabulary_status and vocabulary_status[model.vocabulary_status] then
        body = body .. "\n\n" .. vocabulary_status[model.vocabulary_status]
    end
    return body
end

function DefinitionOverlay:build(model, anchor_func, close_func)
    local dialog = ButtonDialog:new{
        title = model.display_word or model.query or _("Definition"),
        title_align = "left",
        width_factor = 0.76,
        anchor = anchor_func,
        buttons = {
            {
                {
                    id = "paperpro_definition_close",
                    text = _("Close"),
                    callback = close_func,
                },
            },
        },
    }
    local content_height = math.max(
        Screen:scaleBySize(90),
        math.min(math.floor(Screen:getHeight() * 0.32), Screen:scaleBySize(260))
    )
    dialog:addWidget(ScrollTextWidget:new{
        text = self:_body(model),
        face = Font:getFace("infofont"),
        width = dialog:getAddedWidgetAvailableWidth(),
        height = content_height,
        dialog = dialog,
        scroll_by_pan = true,
    })
    return dialog
end

return DefinitionOverlay
