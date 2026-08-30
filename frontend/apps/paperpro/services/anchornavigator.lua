local AnchorNavigator = {}
AnchorNavigator.__index = AnchorNavigator

function AnchorNavigator:new(options)
    options = options or {}
    assert(options.ui, "AnchorNavigator requires ReaderUI")
    return setmetatable(options, self)
end

function AnchorNavigator:canNavigate(anchor)
    if type(anchor) ~= "table" or anchor.document_id ~= self.ui.document.file then
        return false, "Passage belongs to another document"
    end
    if anchor.kind == "xpointer" then
        if not self.ui.rolling or type(anchor.start) ~= "string" then
            return false, "Passage anchor is unavailable"
        end
        local ok, valid = pcall(self.ui.document.isXPointerInDocument,
            self.ui.document, anchor.start)
        if not ok or not valid then return false, "Passage anchor is stale" end
        return true
    elseif anchor.kind == "fixed_page" then
        if not self.ui.paging or type(anchor.page) ~= "number" or anchor.page < 1 then
            return false, "Page anchor is unavailable"
        end
        local ok, page_count = pcall(self.ui.document.getPageCount, self.ui.document)
        if not ok or anchor.page > page_count then return false, "Page anchor is stale" end
        return true
    end
    return false, "Unsupported passage anchor"
end

function AnchorNavigator:goToPassage(anchor)
    local valid, err = self:canNavigate(anchor)
    if not valid then return false, err end
    self.ui.link:addCurrentLocationToStack()
    if anchor.kind == "xpointer" then
        self.ui.rolling:onGotoXPointer(anchor.start, anchor.start)
    else
        self.ui.paging:onGotoPage(anchor.page, anchor.pos0)
    end
    return true
end

return AnchorNavigator
