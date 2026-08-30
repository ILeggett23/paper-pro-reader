local AnchorCodec = require("apps/paperpro/services/anchorcodec")
local Event = require("ui/event")
local JSON = require("rapidjson")

local VocabularyService = {}
VocabularyService.__index = VocabularyService

function VocabularyService:new(options)
    return setmetatable(options or {}, self)
end

local function authorText(author)
    if type(author) == "table" then
        local authors = {}
        for _, value in ipairs(author) do
            if type(value) == "string" and value ~= "" then table.insert(authors, value) end
        end
        return #authors > 0 and table.concat(authors, ", ") or nil
    end
    return type(author) == "string" and author or nil
end

function VocabularyService:recordDefinition(snapshot, model, callback)
    callback = callback or function() end
    if not (snapshot and type(snapshot.selected_word) == "string"
            and snapshot.selected_word:match("%S") and model and model.status == "success"
            and model.definitions and model.definitions[1]
            and type(model.definitions[1].text) == "string"
            and model.definitions[1].text:match("%S")) then
        callback("ineligible")
        return false
    end
    local anchor = AnchorCodec.toColumns(snapshot.anchor)
    local definitions_json = JSON.encode(model.definitions)
    local normalized_definitions = definitions_json and JSON.decode(definitions_json) or nil
    local discovery_time = os.time()
    local entry = {
        word = snapshot.selected_word,
        display_word = model.display_word or snapshot.selected_word,
        definitions = normalized_definitions,
        book_title = snapshot.book_title or "",
        time = discovery_time, discovery_time = discovery_time, updated_time = discovery_time,
        prev_context = snapshot.before_context, next_context = snapshot.after_context,
        highlight = snapshot.text, source_text = snapshot.text,
        definition = model.definitions[1].text,
        dictionary_source = model.definitions[1].dictionary_name,
        definitions_json = definitions_json,
        author = authorText(snapshot.author), chapter = snapshot.chapter,
        document_id = anchor.document_id,
        anchor_kind = anchor.anchor_kind, anchor_start = anchor.anchor_start,
        anchor_finish = anchor.anchor_finish, anchor_page = anchor.anchor_page,
        anchor_pos0_json = anchor.anchor_pos0_json, anchor_pos1_json = anchor.anchor_pos1_json,
        anchor_page_boxes_json = anchor.anchor_page_boxes_json,
    }
    local handled = self.ui:handleEvent(Event:new("DefinitionResolved", entry,
        function(status, err) callback(status or "error", err) end))
    if not handled then callback("unavailable") end
    return handled and true or false
end

function VocabularyService:getItems(search_text, callback)
    local handled = self.ui:handleEvent(Event:new("GetVocabularyItems", search_text or "", callback))
    if not handled then callback(nil, "Vocabulary Builder unavailable") end
    return handled
end

function VocabularyService:decodeItem(item)
    if not item then return nil end
    item.anchor = AnchorCodec.fromColumns(item)
    if item.definitions_json then
        local definitions = JSON.decode(item.definitions_json)
        if type(definitions) == "table" then item.definitions = definitions end
    end
    return item
end

function VocabularyService:goToPassage(item)
    item = self:decodeItem(item)
    local can_navigate = self:canNavigate(item)
    if not can_navigate then return false end
    self.ui.link:addCurrentLocationToStack()
    if item.anchor.kind == "xpointer" then
        self.ui.rolling:onGotoXPointer(item.anchor.start, item.anchor.start)
        return true
    elseif item.anchor.kind == "fixed_page" then
        self.ui.paging:onGotoPage(item.anchor.page, item.anchor.pos0)
        return true
    end
    return false
end

function VocabularyService:canNavigate(item)
    item = self:decodeItem(item)
    if not (item and item.anchor and item.document_id == self.ui.document.file) then
        return false
    end
    if item.anchor.kind == "xpointer" then
        if not self.ui.rolling then return false end
        local ok, valid = pcall(self.ui.document.isXPointerInDocument,
            self.ui.document, item.anchor.start)
        return ok and valid or false
    elseif item.anchor.kind == "fixed_page" then
        if not self.ui.paging or type(item.anchor.page) ~= "number"
                or item.anchor.page < 1 or type(item.anchor.pos0) ~= "table" then
            return false
        end
        local ok, page_count = pcall(self.ui.document.getPageCount, self.ui.document)
        return ok and item.anchor.page <= page_count
    end
    return false
end

return VocabularyService
