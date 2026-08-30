local ButtonDialog = require("ui/widget/buttondialog")
local _ = require("gettext")

local ContextualActions = {}
ContextualActions.__index = ContextualActions

function ContextualActions:new(options)
    return setmetatable(options or {}, self)
end

function ContextualActions:build(snapshot, callbacks, anchor_func)
    callbacks = callbacks or {}
    return ButtonDialog:new{
        title = snapshot.selected_word or snapshot.text,
        title_align = "left",
        width_factor = 0.78,
        shrink_unneeded_width = true,
        anchor = anchor_func,
        buttons = {
            {
                {
                    id = "paperpro_highlight",
                    text = _("Highlight"),
                    callback = callbacks.highlight or function() end,
                },
                {
                    id = "paperpro_define",
                    text = _("Define"),
                    callback = callbacks.define or function() end,
                },
            },
            {
                {
                    id = "paperpro_note",
                    text = _("Note"),
                    callback = callbacks.note or function() end,
                },
                {
                    id = "paperpro_ask_ai",
                    text = _("Ask AI — Coming later"),
                    enabled = false,
                    callback = function() end,
                },
            },
        },
    }
end

return ContextualActions
