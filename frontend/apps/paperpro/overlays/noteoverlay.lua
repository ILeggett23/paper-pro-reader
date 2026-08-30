local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen

local NoteOverlay = {}
NoteOverlay.__index = NoteOverlay

function NoteOverlay:new(options)
    return setmetatable(options or {}, self)
end

local function excerpt(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    if #text > 120 then text = text:sub(1, 117) .. "…" end
    return text
end

function NoteOverlay:build(model, _anchor_func, close_func, save_func)
    local dialog
    dialog = InputDialog:new{
        title = model.is_edit and _("Edit note") or _("Add note"),
        description = excerpt(model.source_text),
        input = model.note or "",
        input_hint = _("Write a note about this passage"),
        allow_newline = true,
        add_scroll_buttons = true,
        is_movable = true,
        width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.82),
        text_height = math.floor(Screen:getHeight() * 0.16),
        buttons = {
            {
                {
                    id = "paperpro_note_cancel",
                    text = _("Cancel"),
                    callback = close_func,
                },
                {
                    id = "paperpro_note_save",
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local ok, err = save_func(dialog:getInputText())
                        if not ok then
                            UIManager:show(InfoMessage:new{
                                text = err or _("Could not save note"),
                            })
                        end
                    end,
                },
            },
        },
    }
    return dialog
end

return NoteOverlay
