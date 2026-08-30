local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local NotesHub = {}
NotesHub.__index = NotesHub

function NotesHub:new(options)
    options = options or {}
    assert(options.service, "NotesHub requires AnnotationService")
    return setmetatable(options, self)
end

local function excerpt(text)
    text = type(text) == "string" and text:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if #text > 140 then text = text:sub(1, 137) .. "…" end
    return text ~= "" and text or _("Passage text unavailable")
end

function NotesHub:_menuItems()
    local items = {}
    for _, note in ipairs(self.service:listNotes()) do
        local location = note.chapter or note.pageref
        if not location and type(note.page) == "number" then location = tostring(note.page) end
        local metadata = {}
        if location then table.insert(metadata, tostring(location)) end
        if note.datetime then table.insert(metadata, note.datetime) end
        table.insert(items, {
            text = "\u{F040} " .. excerpt(note.text) .. "\n" .. note.note,
            mandatory = table.concat(metadata, " • "),
            note_item = note,
        })
    end
    if #items == 0 then
        return {{ text = _("No notes in this book"), select_enabled = false }}
    end
    return items
end

function NotesHub:refreshIfOpen()
    if self.menu then
        self.menu:switchItemTable(_("Notes"), self:_menuItems())
    end
end

function NotesHub:_detailText(item)
    local fields = {
        _("Passage") .. "\n" .. excerpt(item.text),
        _("Note") .. "\n" .. item.note,
    }
    if item.chapter and item.chapter ~= "" then
        table.insert(fields, _("Chapter") .. ": " .. item.chapter)
    end
    if item.pageref then
        table.insert(fields, _("Page") .. ": " .. tostring(item.pageref))
    elseif type(item.page) == "number" then
        table.insert(fields, _("Page") .. ": " .. tostring(item.page))
    end
    if item.datetime then table.insert(fields, _("Date") .. ": " .. item.datetime) end
    if not item.can_navigate then
        table.insert(fields, item.navigation_reason or _("Passage navigation is unavailable"))
    end
    return table.concat(fields, "\n\n")
end

function NotesHub:_delete(item, viewer)
    UIManager:show(ConfirmBox:new{
        text = _("Delete this note? The highlight will remain."),
        ok_text = _("Delete"),
        ok_callback = function()
            local ok, err = self.service:delete(item.annotation_ref)
            if ok then
                UIManager:close(viewer)
                self:refreshIfOpen()
            else
                UIManager:show(InfoMessage:new{ text = err or _("Could not delete note") })
            end
        end,
    })
end

function NotesHub:_showDetail(item)
    local viewer
    viewer = TextViewer:new{
        title = _("Note"),
        text = self:_detailText(item),
        buttons_table = {
            {
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(viewer)
                        self:close()
                        if self.on_edit then self.on_edit(item) end
                    end,
                },
                {
                    text = _("Delete"),
                    callback = function() self:_delete(item, viewer) end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function() UIManager:close(viewer) end,
                },
                {
                    text = _("Go to passage"),
                    enabled = item.can_navigate,
                    callback = function()
                        local ok, err = self.service:goToPassage(item.annotation_ref)
                        if ok then
                            UIManager:close(viewer)
                            self:close()
                        else
                            UIManager:show(InfoMessage:new{
                                text = err or _("Passage navigation is unavailable"),
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function NotesHub:open()
    if self.menu then return true end
    local hub = self
    self.menu = Menu:new{
        title = _("Notes"),
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
    function self.menu:onMenuSelect(item)
        if item.note_item then hub:_showDetail(item.note_item) end
        return true
    end
    UIManager:show(self.menu)
    return true
end

function NotesHub:close()
    if not self.menu then return false end
    local menu = self.menu
    self.menu = nil
    UIManager:close(menu)
    return true
end

function NotesHub:isOpen()
    return self.menu ~= nil
end

return NotesHub
