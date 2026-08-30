describe("Readerdictionary module", function()
    local DocumentRegistry, ReaderUI, UIManager, Screen

    setup(function()
        require("commonrequire")
        disable_plugins()
        load_plugin("japanese.koplugin")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
    end)

    local readerui, dictionary
    setup(function()
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/sample.txt"),
        }
        dictionary = readerui.dictionary
    end)
    teardown(function()
        ReaderUI.instance = readerui
        readerui:closeDocument()
        readerui:onClose()
    end)
    before_each(function()
        ReaderUI.instance = readerui
        UIManager:show(readerui)
    end)
    after_each(function()
        UIManager:close(dictionary.dict_window)
        UIManager:close(readerui)
        UIManager:quit()
        UIManager._exit_code = nil
    end)
    it("should show quick lookup window", function()
        dictionary:onLookupWord("test")
        fastforward_ui_events()
        screenshot(Screen, "reader_dictionary.png")
    end)
    it("should attempt to deinflect (Japanese) word on lookup", function()

        local word = "喋っている"
        local s = spy.on(readerui.languagesupport, "extraDictionaryFormCandidates")

        -- We can't use onLookupWord because we need to check whether
        -- extraDictionaryFormCandidates was called synchronously.
        dictionary:stardictLookup(word)
        fastforward_ui_events()
        screenshot(Screen, "reader_dictionary_japanese.png")

        assert.spy(s).was_called()
        assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport), word)
        if readerui.languagesupport.plugins["japanese_support"] then
            --- @todo This should probably check against a set or sorted list
            --       of the candidates we'd expect.
            assert.spy(s).was_returned_with(match.is_not_nil())
        end
        readerui.languagesupport.extraDictionaryFormCandidates:revert()
    end)
    it("should return local results without choosing a presentation widget", function()
        local original_start_sdcv = dictionary.startSdcv
        local original_handle_event = readerui.handleEvent
        local original_enabled_dict_names = dictionary.enabled_dict_names
        local existing_window = dictionary.dict_window
        local looked_up_word, looked_up_title, result_word, results
        dictionary.startSdcv = function()
            return {
                { word = "test", dict = "Local test dictionary", definition = "A definition." },
            }
        end
        dictionary.enabled_dict_names = { "Local test dictionary" }
        readerui.handleEvent = function(this, event)
            if event.handler == "onWordLookedUp" then
                looked_up_word, looked_up_title = event.args[1], event.args[2]
                return true
            end
            return original_handle_event(this, event)
        end

        dictionary:lookupWordResults("test", false, function(word, lookup_results)
            result_word, results = word, lookup_results
        end)
        fastforward_ui_events()

        assert.are.same("test", looked_up_word)
        assert.are.same(readerui.doc_props.display_title, looked_up_title)
        assert.are.same("test", result_word)
        assert.are.same("A definition.", results[1].definition)
        assert.is_equal(existing_window, dictionary.dict_window)

        dictionary.startSdcv = original_start_sdcv
        dictionary.enabled_dict_names = original_enabled_dict_names
        readerui.handleEvent = original_handle_event
    end)
end)
