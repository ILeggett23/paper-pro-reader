describe("Paper Pro SelectionService", function()
    local SelectionService

    setup(function()
        require("commonrequire")
        SelectionService = require("apps/paperpro/services/selectionservice")
    end)

    it("normalizes an EPUB selection without retaining mutable selection state", function()
        local service = SelectionService:new()
        local selection = {
            text = "unprecedented",
            pos0 = "/body/DocFragment[1]/body/p[2]/text().0",
            pos1 = "/body/DocFragment[1]/body/p[2]/text().13",
            sboxes = { { x = 120, y = 310, w = 180, h = 42 } },
        }
        local ui = {
            rolling = {},
            document = { file = "/books/example.epub" },
            doc_props = { display_title = "Example", authors = "Reader" },
            toc = {
                getTocTitleByPage = function()
                    return "Chapter One"
                end,
            },
            highlight = {
                getSelectedWordContext = function()
                    return "completely ", " in the field"
                end,
            },
        }

        local snapshot = service:createSnapshot(ui, selection, { is_word_selection = true })
        selection.text = "changed"
        selection.sboxes[1].x = 999

        assert.are.same("unprecedented", snapshot.text)
        assert.are.same("unprecedented", snapshot.selected_word)
        assert.are.same("xpointer", snapshot.anchor.kind)
        assert.are.same(selection.pos0, snapshot.anchor.start)
        assert.are.same(120, snapshot.screen_boxes[1].x)
        assert.are.same("Example", snapshot.book_title)
        assert.are.same("Reader", snapshot.author)
        assert.are.same("Chapter One", snapshot.chapter)
        assert.are.same("completely ", snapshot.before_context)
        assert.is_true(snapshot.capabilities.precise_anchor)
        assert.is_false(snapshot.capabilities.sentence)
    end)

    it("normalizes a fixed-layout selection and screen coordinates", function()
        local service = SelectionService:new()
        local selection = {
            text = "fixed layout",
            pos0 = { page = 7, x = 10, y = 20 },
            pos1 = { page = 7, x = 90, y = 45 },
            sboxes = { { x = 10, y = 20, w = 80, h = 25 } },
            pboxes = { { x = 8, y = 18, w = 84, h = 29 } },
        }
        local ui = {
            paging = {},
            document = { file = "/books/example.pdf" },
            view = {
                pageToScreenTransform = function(_, page, box)
                    assert.are.same(7, page)
                    return { x = box.x + 100, y = box.y + 200, w = box.w, h = box.h }
                end,
            },
        }

        local snapshot = service:createSnapshot(ui, selection)

        assert.are.same("fixed_page", snapshot.anchor.kind)
        assert.are.same(7, snapshot.anchor.page)
        assert.are.same(8, snapshot.anchor.page_boxes[1].x)
        assert.are.same(110, snapshot.screen_boxes[1].x)
        assert.are.same(220, snapshot.screen_boxes[1].y)
        assert.is_nil(snapshot.selected_word)
        assert.is_true(snapshot.capabilities.fixed_page)
        assert.is_false(snapshot.capabilities.xpointer)
        assert.is_false(snapshot.capabilities.sentence)
        assert.is_false(snapshot.capabilities.paragraph)
    end)

    it("leaves unavailable anchors and context explicitly unavailable", function()
        local snapshot = SelectionService:new():createSnapshot({}, { text = "text" })

        assert.is_nil(snapshot.anchor)
        assert.is_nil(snapshot.before_context)
        assert.is_nil(snapshot.after_context)
        assert.is_false(snapshot.capabilities.precise_anchor)
        assert.is_false(snapshot.capabilities.word_context)
    end)
end)
