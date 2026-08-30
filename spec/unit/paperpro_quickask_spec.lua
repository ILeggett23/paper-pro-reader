describe("Paper Pro Quick Ask and AI History surfaces", function()
    local AIHistory, QuickAskOverlay

    setup(function()
        require("commonrequire")
        AIHistory = require("apps/paperpro/hubs/aihistory")
        QuickAskOverlay = require("apps/paperpro/overlays/quickaskoverlay")
    end)

    it("builds typed compose, static sending, queued, success, and error states", function()
        local overlay = QuickAskOverlay:new()
        local submitted
        local compose = overlay:build({
            state = "compose", source_text = "A passage", context_mode = "nearby",
        }, nil, function() end, { submit = function(value) submitted = value end })
        assert.is_truthy(compose.button_table:getButtonById("paperpro_ai_ask"))
        compose:setInputText("My question")
        compose.button_table:getButtonById("paperpro_ai_ask").callback()
        assert.are.same("My question", submitted)

        local sending = overlay:build({ state = "sending", request_id = "q" }, nil,
            function() end, { cancel = function() end })
        assert.is_truthy(sending:getButtonById("paperpro_ai_cancel_request"))
        assert.are.same("Thinking…", sending._added_widgets[1].text)
        local queued = overlay:build({ state = "queued", request_id = "q" }, nil,
            function() end, { cancel = function() end })
        assert.matches("Saved", queued._added_widgets[1].text)
        local success = overlay:build({ state = "success", answer = string.rep("answer ", 100) }, nil,
            function() end, {})
        assert.is_truthy(success:getButtonById("paperpro_ai_close"))
        local failed = overlay:build({ state = "error", retryable = true }, nil,
            function() end, { retry = function() end })
        assert.is_truthy(failed:getButtonById("paperpro_ai_retry"))
    end)

    it("lists completed and queued current-book questions and disables stale anchors", function()
        local queue = {
            listForDocument = function(_, document_id)
                assert.are.same("book.epub", document_id)
                return {{
                    id = "queued", state = "queued", created_at = 20, updated_at = 20,
                    request = {
                        question = { text = "Queued question?" },
                        reading_context = {
                            book = { document_id = "book.epub" },
                            location = { anchor = { kind = "xpointer", document_id = "book.epub", start = "/stale" } },
                            selection = { text = "Queued source" },
                        },
                    },
                }}
            end,
        }
        local responses = {
            listForDocument = function()
                return {{
                    request_id = "done", question = "Completed question?", answer = "Offline answer",
                    source_text = "Completed source", completed_at = 30,
                    anchor = { kind = "xpointer", document_id = "book.epub", start = "/good" },
                }}
            end,
        }
        local navigator = {
            ui = { document = { file = "book.epub" } },
            canNavigate = function(_, anchor)
                return anchor.start == "/good", anchor.start == "/good" and nil or "Passage anchor is stale"
            end,
        }
        local history = AIHistory:new{ queue = queue, responses = responses, navigator = navigator }
        local items = history:_items()
        assert.are.same(2, #items)
        assert.are.same("Completed question?", items[1].question)
        local detail, can_navigate = history:_detailText(items[2])
        assert.is_false(can_navigate)
        assert.matches("Passage anchor is stale", detail)
    end)
end)
