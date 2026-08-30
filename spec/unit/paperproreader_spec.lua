describe("Paper Pro Reader composition", function()
    local DocumentRegistry, Geom, ReaderUI, Screen, UIManager
    local readerui

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        Geom = require("ui/geometry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument("spec/front/unit/data/juliet.epub"),
        }
    end)

    teardown(function()
        readerui:onClose()
    end)

    before_each(function()
        UIManager:show(readerui)
        readerui.rolling:onGotoPage(10)
    end)

    after_each(function()
        readerui.paperpro:onCloseDocument()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
        UIManager:quit()
    end)

    local function selectWord()
        readerui.highlight:onHold(nil, { pos = Geom:new{ x = 400, y = 70 } })
        readerui.highlight:onHoldRelease()
        fastforward_ui_events()
        assert.is_true(readerui.paperpro.overlay:isOpen())
        return readerui.paperpro.current_snapshot
    end

    it("shows all contextual actions with Ask AI disabled", function()
        local snapshot = selectWord()
        local dialog = readerui.paperpro.overlay.widget
        assert.are.same("xpointer", snapshot.anchor.kind)
        assert.is_truthy(dialog:getButtonById("paperpro_highlight"))
        assert.is_truthy(dialog:getButtonById("paperpro_define"))
        assert.is_truthy(dialog:getButtonById("paperpro_note"))
        assert.is_false(dialog:getButtonById("paperpro_ask_ai").enabled)
    end)

    it("uses the existing highlight annotation authority", function()
        selectWord()
        assert.is_true(readerui.paperpro:performAction("highlight"))
        assert.are.same(1, #readerui.annotation.annotations)
        assert.is_truthy(readerui.annotation.annotations[1].text)
    end)

    it("delegates Note to ReaderHighlight", function()
        selectWord()
        stub(readerui.highlight, "addNote")
        assert.is_true(readerui.paperpro:performAction("note"))
        assert.stub(readerui.highlight.addNote).was_called_with(match.is_ref(readerui.highlight))
        readerui.highlight.addNote:revert()
    end)

    it("shows normalized definition results without changing location", function()
        local snapshot = selectWord()
        local page_before = readerui:getCurrentPage()
        local original_lookup = readerui.dictionary.lookupWordResults
        readerui.dictionary.lookupWordResults = function(_, query, _, callback)
            callback(query, {
                { word = query, dict = "Local test dictionary", definition = "A local definition." },
            })
            return true
        end

        assert.is_true(readerui.paperpro:performAction("define"))
        assert.are.same("success", readerui.paperpro.overlay.model.status)
        assert.are.same("Local test dictionary", readerui.paperpro.overlay.model.dictionary_name)
        assert.are.same(snapshot.anchor.start, readerui.paperpro.overlay.model.selection_anchor.start)
        assert.are.same(page_before, readerui:getCurrentPage())

        readerui.paperpro.overlay:dismiss()
        assert.are.same(page_before, readerui:getCurrentPage())
        readerui.dictionary.lookupWordResults = original_lookup
    end)
end)
