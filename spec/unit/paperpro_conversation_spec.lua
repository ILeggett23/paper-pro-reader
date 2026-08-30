describe("Paper Pro conversation surfaces", function()
    local ConversationHub, ConversationMarker, Geom

    setup(function()
        require("commonrequire")
        ConversationHub = require("apps/paperpro/hubs/conversationhub")
        ConversationMarker = require("apps/paperpro/overlays/conversationmarker")
        Geom = require("ui/geometry")
    end)

    local conversation = {
        conversation_id = "c1", document_id = "book.pdf", book_title = "Book",
        chapter = "Chapter", source_text = "Source passage",
        anchor = { kind = "fixed_page", document_id = "book.pdf", page = 2 },
        turns = {
            { question_type = "text", question_text = "Why?", answer = "First answer", status = "completed" },
            { question_type = "ink", recognized_question = "Example?", answer = "Second answer", status = "completed" },
        },
    }

    it("renders bounded multi-turn compact and Full Study text", function()
        local hub = ConversationHub:new{
            responses = { getConversation = function() return conversation end },
            navigator = { canNavigate = function() return true end },
        }
        local compact = hub:_text(conversation, false)
        local full = hub:_text(conversation, true)
        assert.matches("Why", compact)
        assert.matches("Example", compact)
        assert.matches("Source passage", compact)
        assert.matches("Book", full)
        assert.matches("Chapter", full)
    end)

    it("shows a subtle marker only on the anchored visible page", function()
        local page = 2
        local marker = ConversationMarker:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 },
            responses = { listConversationsForDocument = function() return { conversation } end },
            ui = {
                document = { file = "book.pdf" },
                view = { getCurrentPageList = function() return { page } end },
            },
        }
        assert.are.same("c1", marker:currentConversation().conversation_id)
        page = 3
        assert.is_nil(marker:currentConversation())
        marker:setDimensions(Geom:new{ x = 0, y = 0, w = 1620, h = 2160 })
        assert.are.same(1556, marker.bounds.x)
    end)

    it("consumes its marker tap and forwards unmatched reader gestures", function()
        local forwarded
        local opened
        local marker = ConversationMarker:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 },
            responses = { listConversationsForDocument = function() return {} end },
            ui = {
                handleEvent = function(_, event) forwarded = event; return true end,
                document = { file = "book.pdf" }, view = {},
            },
            on_open = function(id) opened = id end,
        }
        marker.currentConversation = function() return { conversation_id = "c1" } end

        assert.is_true(marker:onGesture{
            ges = "tap", pos = Geom:new{ x = 100, y = 100, w = 0, h = 0 },
        })
        assert.are.same("onGesture", forwarded.handler)
        assert.are.same("tap", forwarded.args[1].ges)

        forwarded = nil
        assert.is_true(marker:onGesture{
            ges = "tap", pos = Geom:new{ x = 550, y = 70, w = 0, h = 0 },
        })
        assert.are.same("c1", opened)
        assert.is_nil(forwarded)
    end)
end)
