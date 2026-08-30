describe("Paper Pro AnnotationService", function()
    local AnnotationService

    setup(function()
        require("commonrequire")
        AnnotationService = require("apps/paperpro/services/annotationservice")
    end)

    local function makeUI(rolling)
        local annotations = {}
        local ui = {
            document = {
                file = rolling and "/books/book.epub" or "/books/book.pdf",
                isXPointerInDocument = function(_, xp) return xp == "/body/p[1].0" end,
                getPageCount = function() return 10 end,
            },
            annotation = { annotations = annotations },
            rolling = rolling and {} or nil,
            paging = rolling and nil or {},
            link = { calls = 0, addCurrentLocationToStack = function(self) self.calls = self.calls + 1 end },
            bookmark = {}, highlight = {},
        }
        ui.annotation.getItemIndex = function(_, candidate)
            for index, annotation in ipairs(annotations) do
                if annotation.datetime == candidate.datetime then return index end
            end
        end
        ui.bookmark.updateAnnotationNote = function(_, index, note)
            annotations[index].note = note ~= "" and note or nil
            return annotations[index]
        end
        ui.bookmark.gotoBookmark = function(_, page, marker)
            ui.goto_page, ui.goto_marker = page, marker
        end
        ui.highlight.commitNoteForCurrentSelection = function(_, note)
            local annotation = rolling and {
                datetime = "2026-08-29 10:00:00", page = "/body/p[1].0",
                pos0 = "/body/p[1].0", pos1 = "/body/p[1].4", text = "text", note = note,
            } or {
                datetime = "2026-08-29 10:00:00", page = 3,
                pos0 = { page = 3, x = 10, y = 20 }, pos1 = { page = 3, x = 40, y = 20 },
                text = "text", note = note,
            }
            table.insert(annotations, annotation)
            return annotation
        end
        return ui
    end

    it("creates, updates, and deletes one authoritative EPUB annotation", function()
        local ui = makeUI(true)
        local service = AnnotationService:new{ ui = ui }
        local reference = service:createFromCurrentSelection("First note")
        assert.is_truthy(reference)
        assert.are.same(1, #ui.annotation.annotations)
        assert.are.same("/body/p[1].0", reference.page)

        local updated_reference = service:update(reference, "Updated note")
        assert.is_truthy(updated_reference)
        assert.are.same(1, #ui.annotation.annotations)
        assert.are.same("Updated note", ui.annotation.annotations[1].note)
        assert.is_true(service:delete(updated_reference))
        assert.is_nil(ui.annotation.annotations[1].note)
    end)

    it("uses the existing back stack and bookmark navigation seam", function()
        local ui = makeUI(false)
        local service = AnnotationService:new{ ui = ui }
        local reference = service:createFromCurrentSelection("PDF note")
        assert.is_truthy(reference)
        assert.is_true(service:goToPassage(reference))
        assert.are.same(1, ui.link.calls)
        assert.are.same(3, ui.goto_page)
        assert.are.same(10, ui.goto_marker.x)
    end)

    it("fails safely for stale references and empty input", function()
        local service = AnnotationService:new{ ui = makeUI(true) }
        local reference, err = service:createFromCurrentSelection("   ")
        assert.is_nil(reference)
        assert.are.same("Note cannot be empty", err)
        assert.is_false(service:goToPassage{
            document_id = "/books/other.epub", datetime = "missing",
        })
    end)

    it("lists only annotations that contain user notes", function()
        local ui = makeUI(true)
        local service = AnnotationService:new{ ui = ui }
        service:createFromCurrentSelection("Saved note")
        table.insert(ui.annotation.annotations, {
            datetime = "2026-08-29 11:00:00", page = "/body/p[2].0",
            pos0 = "/body/p[2].0", pos1 = "/body/p[2].4", text = "highlight only",
        })
        local notes = service:listNotes()
        assert.are.same(1, #notes)
        assert.are.same("Saved note", notes[1].note)
    end)
end)
