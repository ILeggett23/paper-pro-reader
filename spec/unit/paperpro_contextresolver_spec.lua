describe("Paper Pro ContextResolver", function()
    local ContextResolver, util

    setup(function()
        require("commonrequire")
        ContextResolver = require("apps/paperpro/services/contextresolver")
        util = require("util")
    end)

    local function snapshot(kind)
        local anchor = kind == "xpointer" and {
            kind = "xpointer", document_id = "book.epub", start = "/p.0", finish = "/p.8",
        } or {
            kind = "fixed_page", document_id = "book.pdf", page = 4,
            pos0 = { page = 4, x = 10, y = 20 }, pos1 = { page = 4, x = 80, y = 40 },
        }
        return {
            text = "selected passage", selected_word = nil, anchor = anchor,
            before_context = "short before", after_context = "short after",
            book_title = "A Book", author = { "An Author" }, chapter = "Chapter One",
        }
    end

    it("extracts detached EPUB sentence, paragraph, nearby text, and XPointer", function()
        local selected = snapshot("xpointer")
        local ui = { document = {
            extendXPointersToSentenceSegment = function(_, start, finish)
                assert.are.same("/p.0", start)
                assert.are.same("/p.8", finish)
                return { text = "A complete selected passage sentence." }
            end,
            getHTMLFromXPointer = function()
                return "<p>A complete selected passage sentence. More paragraph text.</p>"
            end,
            getSelectedWordContext = function() return "near before", "near after" end,
        } }
        local context = assert(ContextResolver:new():resolve(ui, selected, { context_mode = "nearby" }))
        selected.anchor.start = "changed"
        assert.are.same("A complete selected passage sentence.", context.context.sentence)
        assert.are.same("A complete selected passage sentence. More paragraph text.",
            context.context.paragraph)
        assert.are.same("near before", context.context.before)
        assert.are.same("/p.0", context.location.anchor.start)
        assert.is_true(context.capabilities.semantic_context)
        assert.is_true(context.capabilities.precise_anchor)
    end)

    it("uses Minimal mode without surrounding source", function()
        local context = assert(ContextResolver:new():resolve({ document = {} }, snapshot("xpointer"), {
            context_mode = "minimal",
        }))
        assert.are.same("selected passage", context.selection.text)
        assert.is_nil(context.context.before)
        assert.is_nil(context.context.sentence)
        assert.are.same("minimal", context.context_mode)
    end)

    it("degrades PDF context without inventing sentence or paragraph semantics", function()
        local ui = { document = {
            getSelectedWordContext = function(_, text, words, pos)
                assert.are.same("selected passage", text)
                assert.are.same(80, words)
                assert.are.same(4, pos.page)
                return "PDF words before", "PDF words after"
            end,
        } }
        local context = assert(ContextResolver:new():resolve(ui, snapshot("fixed")))
        assert.are.same("PDF words before", context.context.before)
        assert.is_nil(context.context.sentence)
        assert.is_false(context.capabilities.semantic_context)
        assert.is_true(context.capabilities.fixed_layout)
    end)

    it("gracefully keeps only selected OCR/text when nearby text is unavailable", function()
        local selected = snapshot("fixed")
        selected.before_context, selected.after_context = nil, nil
        local context = assert(ContextResolver:new():resolve({ document = {} }, selected))
        assert.are.same("selected passage", context.selection.text)
        assert.is_nil(context.context.before)
        assert.is_nil(context.context.after)
    end)

    it("trims valid UTF-8 at exact field and total source budgets", function()
        local limits = {
            selection_bytes = 12, sentence_bytes = 8, paragraph_bytes = 8,
            side_bytes = 8, source_bytes = 24, nearby_words = 80,
        }
        local selected = snapshot("xpointer")
        selected.text = "éééééééé"
        selected.before_context = "αααααααα"
        selected.after_context = "ββββββββ"
        local context = assert(ContextResolver:new{ limits = limits }:resolve({ document = {} }, selected))
        assert.is_true(context.truncation.any)
        assert.are.same(context.selection.text, util.fixUtf8(context.selection.text, ""))
        local total = #(context.selection.text or "") + #(context.context.before or "")
            + #(context.context.after or "") + #(context.context.sentence or "")
            + #(context.context.paragraph or "")
        assert.is_true(total <= limits.source_bytes)
    end)
end)
