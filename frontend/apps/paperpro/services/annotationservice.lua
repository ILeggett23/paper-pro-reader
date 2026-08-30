local logger = require("logger")
local SelectionService = require("apps/paperpro/services/selectionservice")

local AnnotationService = {}
AnnotationService.__index = AnnotationService

local function usableText(value)
    return type(value) == "string" and value:match("%S") ~= nil
end

function AnnotationService:new(options)
    options = options or {}
    assert(options.ui, "AnnotationService requires ReaderUI")
    return setmetatable(options, self)
end

function AnnotationService:referenceFor(annotation)
    if type(annotation) ~= "table" then return nil end
    return {
        document_id = self.ui.document.file,
        datetime = annotation.datetime,
        page = SelectionService.deepCopy(annotation.page),
        pos0 = SelectionService.deepCopy(annotation.pos0),
        pos1 = SelectionService.deepCopy(annotation.pos1),
    }
end

function AnnotationService:resolve(reference)
    if type(reference) ~= "table" or reference.document_id ~= self.ui.document.file then
        return nil
    end
    local ok, index = pcall(self.ui.annotation.getItemIndex, self.ui.annotation, reference, true)
    if not ok or not index then return nil end
    return self.ui.annotation.annotations[index], index
end

function AnnotationService:createFromCurrentSelection(note_text)
    if not usableText(note_text) then return nil, "Note cannot be empty" end
    local ok, annotation = pcall(
        self.ui.highlight.commitNoteForCurrentSelection, self.ui.highlight, note_text
    )
    if not ok then
        logger.err("Paper Pro note creation failed:", annotation)
        return nil, "Could not save note"
    end
    if not annotation then return nil, "Selection is no longer available" end
    return self:referenceFor(annotation), annotation
end

function AnnotationService:update(reference, note_text)
    if not usableText(note_text) then return nil, "Note cannot be empty" end
    local annotation, index = self:resolve(reference)
    if not annotation then return nil, "Note is no longer available" end
    local ok, updated = pcall(self.ui.bookmark.updateAnnotationNote,
        self.ui.bookmark, index, note_text)
    if not ok then
        logger.err("Paper Pro note update failed:", updated)
        return nil, "Could not save note"
    end
    return self:referenceFor(updated), updated
end

function AnnotationService:delete(reference)
    local annotation, index = self:resolve(reference)
    if not annotation then return false, "Note is no longer available" end
    local ok, result = pcall(self.ui.bookmark.updateAnnotationNote,
        self.ui.bookmark, index, "")
    if not ok then
        logger.err("Paper Pro note deletion failed:", result)
        return false, "Could not delete note"
    end
    return true
end

function AnnotationService:canNavigate(reference)
    local annotation = self:resolve(reference)
    if not annotation then return false, "Note anchor is stale" end
    if self.ui.rolling then
        if type(annotation.page) ~= "string" then
            return false, "Passage anchor is no longer valid"
        end
        local ok, valid = pcall(self.ui.document.isXPointerInDocument,
            self.ui.document, annotation.page)
        if not ok or not valid then
            return false, "Passage anchor is no longer valid"
        end
    else
        if type(annotation.page) ~= "number" or annotation.page < 1
                or type(annotation.pos0) ~= "table" then
            return false, "Passage position is unavailable"
        end
        local ok, page_count = pcall(self.ui.document.getPageCount, self.ui.document)
        if not ok or annotation.page > page_count then
            return false, "Passage position is unavailable"
        end
    end
    return true
end

function AnnotationService:goToPassage(reference)
    local can_navigate, reason = self:canNavigate(reference)
    if not can_navigate then return false, reason end
    local annotation = self:resolve(reference)
    self.ui.link:addCurrentLocationToStack()
    self.ui.bookmark:gotoBookmark(annotation.page, annotation.pos0)
    return true
end

function AnnotationService:listNotes()
    local notes = {}
    for _, annotation in ipairs(self.ui.annotation.annotations or {}) do
        if usableText(annotation.note) then
            local reference = self:referenceFor(annotation)
            local can_navigate, navigation_reason = self:canNavigate(reference)
            table.insert(notes, {
                annotation_ref = reference,
                text = annotation.text or "",
                note = annotation.note,
                chapter = annotation.chapter,
                page = annotation.page,
                pageref = annotation.pageref,
                datetime = annotation.datetime_updated or annotation.datetime,
                can_navigate = can_navigate,
                navigation_reason = navigation_reason,
            })
        end
    end
    table.sort(notes, function(a, b)
        return (a.datetime or "") > (b.datetime or "")
    end)
    return notes
end

return AnnotationService
