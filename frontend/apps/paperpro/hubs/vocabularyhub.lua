local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local VocabularyHub = {}
VocabularyHub.__index = VocabularyHub

function VocabularyHub:new(options)
    options = options or {}
    assert(options.service, "VocabularyHub requires VocabularyService")
    return setmetatable(options, self)
end

local function displayDate(value)
    return value and os.date("%Y-%m-%d", value) or _("Unknown")
end

local function contextText(item)
    local parts = {}
    if item.prev_context and item.prev_context ~= "" then table.insert(parts, item.prev_context) end
    if item.source_text and item.source_text ~= "" then table.insert(parts, item.source_text) end
    if item.next_context and item.next_context ~= "" then table.insert(parts, item.next_context) end
    return table.concat(parts, " ")
end

function VocabularyHub:_itemsForMenu(items)
    local menu_items = {{
        text = _("Search vocabulary…"),
        mandatory = self.search_text ~= "" and self.search_text or nil,
        action = "search",
    }}
    if #items == 0 then
        table.insert(menu_items, {
            text = self.search_text ~= "" and _("No matching vocabulary") or _("No vocabulary yet"),
            select_enabled = false,
        })
        return menu_items
    end
    for _, item in ipairs(items) do
        self.service:decodeItem(item)
        table.insert(menu_items, {
            text = item.word,
            mandatory = item.definition or _("Definition unavailable"),
            vocabulary_item = item,
        })
    end
    return menu_items
end

function VocabularyHub:_setState(title, items)
    if self.menu then self.menu:switchItemTable(title, items) end
end

function VocabularyHub:refresh(search_text)
    self.search_text = search_text == nil and (self.search_text or "") or search_text
    self:_setState(_("Vocabulary"), {{ text = _("Loading…"), select_enabled = false }})
    self.service:getItems(self.search_text, function(items, err)
        if not self.menu then return end
        if not items then
            self:_setState(_("Vocabulary"), {{
                text = err or _("Vocabulary is unavailable"), select_enabled = false,
            }})
            return
        end
        self:_setState(_("Vocabulary"), self:_itemsForMenu(items))
    end)
end

function VocabularyHub:_showSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search vocabulary"),
        input = self.search_text or "",
        input_hint = _("Word"),
        buttons = {{
            {
                text = _("Cancel"),
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    local query = dialog:getInputText():match("^%s*(.-)%s*$")
                    UIManager:close(dialog)
                    self:refresh(query)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function VocabularyHub:_detailText(item)
    local definitions = {}
    if item.definitions and #item.definitions > 0 then
        for _, definition in ipairs(item.definitions) do
            local source = definition.dictionary_name and (" [" .. definition.dictionary_name .. "]") or ""
            table.insert(definitions, definition.text .. source)
        end
    elseif item.definition then
        local source = item.dictionary_source and (" [" .. item.dictionary_source .. "]") or ""
        table.insert(definitions, item.definition .. source)
    else
        table.insert(definitions, _("Definition unavailable"))
    end
    local learning = string.format(_("Reviews: %d  •  Streak: %d"),
        item.review_count or 0, item.streak_count or 0)
    local fields = {
        table.concat(definitions, "\n\n"),
        _("Source context") .. "\n" .. (contextText(item) ~= "" and contextText(item) or _("Unavailable")),
        _("Book") .. ": " .. (item.book_title or _("Unknown")),
    }
    if item.author and item.author ~= "" then table.insert(fields, _("Author") .. ": " .. item.author) end
    if item.chapter and item.chapter ~= "" then table.insert(fields, _("Chapter") .. ": " .. item.chapter) end
    table.insert(fields, _("Discovered") .. ": " .. displayDate(item.create_time))
    table.insert(fields, learning)
    return table.concat(fields, "\n\n")
end

function VocabularyHub:_showDetail(item)
    local viewer
    local can_navigate = self.service:canNavigate(item)
    viewer = TextViewer:new{
        title = item.word,
        text = self:_detailText(item),
        buttons_table = {{
            {
                text = _("Close"),
                callback = function() UIManager:close(viewer) end,
            },
            {
                text = _("Go to passage"),
                enabled = can_navigate,
                callback = function()
                    if self.service:goToPassage(item) then
                        UIManager:close(viewer)
                        self:close()
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("This passage is unavailable in the current book."),
                        })
                    end
                end,
            },
        }},
    }
    UIManager:show(viewer)
end

function VocabularyHub:open()
    if self.menu then return true end
    local hub = self
    self.search_text = ""
    self.menu = Menu:new{
        title = _("Vocabulary"),
        item_table = {},
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        close_callback = function() hub.menu = nil end,
    }
    function self.menu:onMenuSelect(item)
        if item.action == "search" then
            hub:_showSearch()
        elseif item.vocabulary_item then
            hub:_showDetail(item.vocabulary_item)
        end
        return true
    end
    UIManager:show(self.menu)
    self:refresh()
    return true
end

function VocabularyHub:close()
    if not self.menu then return false end
    local menu = self.menu
    self.menu = nil
    UIManager:close(menu)
    return true
end

function VocabularyHub:isOpen()
    return self.menu ~= nil
end

return VocabularyHub
