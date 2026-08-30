describe("Paper Pro Reader composition", function()
    local DocumentRegistry, Geom, ReaderUI, Screen, Time, UIManager
    local readerui

    setup(function()
        require("commonrequire")
        disable_plugins()
        DocumentRegistry = require("document/documentregistry")
        Geom = require("ui/geometry")
        ReaderUI = require("apps/reader/readerui")
        Screen = require("device").screen
        Time = require("ui/time")
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
        G_reader_settings:saveSetting("paperpro_auto_add_vocabulary", true)
        G_reader_settings:saveSetting("paperpro_note_markers", true)
        G_reader_settings:saveSetting("paperpro_ai_enabled", false)
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

    it("shows all contextual actions with Ask AI disabled by default", function()
        local snapshot = selectWord()
        local dialog = readerui.paperpro.overlay.widget
        assert.are.same("xpointer", snapshot.anchor.kind)
        assert.is_truthy(dialog:getButtonById("paperpro_highlight"))
        assert.is_truthy(dialog:getButtonById("paperpro_define"))
        assert.is_truthy(dialog:getButtonById("paperpro_note"))
        assert.is_false(dialog:getButtonById("paperpro_ask_ai").enabled)
    end)

    it("enables typed Quick Ask without changing the reading location", function()
        G_reader_settings:saveSetting("paperpro_ai_enabled", true)
        local page_before = readerui:getCurrentPage()
        selectWord()
        local actions = readerui.paperpro.overlay.widget
        assert.is_true(actions:getButtonById("paperpro_ask_ai").enabled)
        assert.is_true(readerui.paperpro:performAction("ask_ai"))
        assert.are.same("compose", readerui.paperpro.overlay.model.state)
        assert.is_truthy(readerui.paperpro.overlay.widget.button_table:getButtonById("paperpro_ai_ask"))
        assert.is_true(readerui.paperpro:_submitQuickAsk("What does this mean?"))
        assert.are.same("error", readerui.paperpro.overlay.model.state)
        assert.matches("Configure", readerui.paperpro.overlay.model.message)
        assert.is_nil(readerui.paperpro.overlay.model.request_id)
        readerui.paperpro.overlay:dismiss()
        assert.are.same(page_before, readerui:getCurrentPage())
    end)

    it("registers a compact Study menu for both hubs", function()
        local menu_items = {}
        readerui.paperpro:addToMainMenu(menu_items)
        assert.are.same("Study", menu_items.paperpro_study.text)
        assert.are.same("tools", menu_items.paperpro_study.sorting_hint)
        assert.are.same("Notes", menu_items.paperpro_study.sub_item_table[1].text)
        assert.are.same("Vocabulary", menu_items.paperpro_study.sub_item_table[2].text)
        assert.are.same("AI Questions", menu_items.paperpro_study.sub_item_table[3].text)
        assert.are.same("AI assistant", menu_items.paperpro_study.sub_item_table[4].text)
        assert.are.same("Diagnostics", menu_items.paperpro_study.sub_item_table[5].text)
        assert.are.same("Ink Mode", menu_items.paperpro_study.sub_item_table[6].text)
        assert.is_true(menu_items.paperpro_study.sub_item_table[6].check_callback_closes_menu)
    end)

    it("attaches InkCanvas above ReaderUI on the reader Show event", function()
        readerui.paperpro.ink_service:close()
        readerui.paperpro:onShow()
        assert.is_true(readerui.paperpro.ink_canvas.attached)
        assert.is_equal(readerui.paperpro.ink_canvas,
            UIManager._window_stack[#UIManager._window_stack].widget)
    end)

    it("uses the existing highlight annotation authority", function()
        selectWord()
        assert.is_true(readerui.paperpro:performAction("highlight"))
        assert.are.same(1, #readerui.annotation.annotations)
        assert.is_truthy(readerui.annotation.annotations[1].text)
    end)

    it("opens NoteOverlay and saves one authoritative annotation in place", function()
        selectWord()
        local page_before = readerui:getCurrentPage()
        assert.is_true(readerui.paperpro:performAction("note"))
        assert.is_truthy(readerui.paperpro.overlay.widget.button_table:getButtonById("paperpro_note_save"))
        assert.are.same(0, #readerui.annotation.annotations)
        assert.is_true(readerui.paperpro:_saveNote("A contextual note."))
        assert.are.same(1, #readerui.annotation.annotations)
        assert.are.same("A contextual note.", readerui.annotation.annotations[1].note)
        assert.are.same(page_before, readerui:getCurrentPage())
        assert.are.same("sidemark", readerui.view.highlight.note_mark)
    end)

    it("cancels NoteOverlay without creating an annotation", function()
        selectWord()
        assert.is_true(readerui.paperpro:performAction("note"))
        readerui.paperpro.overlay:dismiss()
        assert.are.same(0, #readerui.annotation.annotations)
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

    it("updates DefinitionOverlay only after vocabulary persistence succeeds", function()
        selectWord()
        readerui.paperpro.current_snapshot.selected_word = readerui.paperpro.current_snapshot.text
        local original_lookup = readerui.dictionary.lookupWordResults
        local original_record = readerui.paperpro.vocabulary_service.recordDefinition
        readerui.dictionary.lookupWordResults = function(_, query, _, callback)
            callback(query, {
                { word = query, dict = "First", definition = "One." },
                { word = query, dict = "Second", definition = "Two." },
            })
            return true
        end
        readerui.paperpro.vocabulary_service.recordDefinition = function(_, snapshot, model, callback)
            assert.is_truthy(snapshot.selected_word)
            assert.are.same("Second", model.definitions[2].dictionary_name)
            callback("added")
            return true
        end

        assert.is_true(readerui.paperpro:performAction("define"))
        assert.are.same("added", readerui.paperpro.overlay.model.vocabulary_status)

        readerui.dictionary.lookupWordResults = original_lookup
        readerui.paperpro.vocabulary_service.recordDefinition = original_record
    end)

    it("opens an existing note in the product editor", function()
        selectWord()
        readerui.paperpro:performAction("note")
        readerui.paperpro:_saveNote("Existing note")
        local annotation = readerui.annotation.annotations[1]
        local payload = {
            annotation = require("util").tableDeepCopy(annotation),
            annotation_ref = readerui.paperpro.annotation_service:referenceFor(annotation),
            screen_boxes = {}, has_note = true,
        }
        assert.is_true(readerui.paperpro:onShowAnnotationNote(payload))
        assert.is_true(readerui.paperpro.current_note.is_edit)
        assert.are.same("Existing note", readerui.paperpro.current_note.note)
    end)

    it("emits a detached product event when a saved note is tapped", function()
        selectWord()
        readerui.paperpro:performAction("note")
        readerui.paperpro:_saveNote("Tapped note")
        readerui.view.highlight.visible_boxes = {{
            index = 1,
            rect = Geom:new{ x = -10000, y = -10000, w = 20000, h = 20000 },
        }}
        local captured
        local original_handle_event = readerui.handleEvent
        readerui.handleEvent = function(self, event)
            if event.handler == "onShowAnnotationNote" then
                captured = event.args[1]
                return true
            end
            return original_handle_event(self, event)
        end

        local handled = readerui.highlight:onTap(nil, { pos = Geom:new{ x = 1, y = 1 } })
        readerui.handleEvent = original_handle_event
        readerui.view.highlight.visible_boxes = {}
        assert.is_true(handled)
        assert.is_true(captured.has_note)
        assert.are.same("Tapped note", captured.annotation.note)
        assert.are.same(readerui.document.file, captured.annotation_ref.document_id)
    end)

    it("captures, restores, and rasterizes Marker-only ink through Ink Mode", function()
        local service = readerui.paperpro.ink_service
        local original_store = service.store
        service.store = {
            load = function() return {} end,
            save = function(self, strokes) self.saved = strokes return true end,
        }
        service.strokes, service.undo_stack, service.redo_stack = {}, {}, {}
        service:_rebuildIndex()
        service.attached = true
        service.canvas:attach()
        assert.is_true(service:activate())
        local input = require("device").input
        assert.is_function(input.stylus_callback)
        input.stylus_callback(input, {
            slot = input.pen_slot, id = 7, x = 150, y = 200,
            tool = input.TOOL_TYPE_PEN, timev = Time.s(1), pressure = 20,
        })
        input.stylus_callback(input, {
            slot = input.pen_slot, id = 7, x = 180, y = 220,
            tool = input.TOOL_TYPE_PEN, timev = Time.s(2), pressure = 30,
        })
        input.stylus_callback(input, {
            slot = input.pen_slot, id = -1, x = 190, y = 230,
            tool = input.TOOL_TYPE_PEN, timev = Time.s(3), pressure = 0,
        })
        assert.are.same(1, #service.strokes)
        assert.are.same("epub-layout-v1", service.strokes[1].coordinate_space)
        assert.are.same(20, service.strokes[1].points[1].pressure)
        assert.are.same(1, #service:getRenderableStrokes())
        local raster = service:rasterizeVisible()
        assert.is_truthy(raster)
        assert.is_true(raster.width < Screen:getWidth())
        raster.bb:free()
        service:deactivate()
        service.strokes = {}
        service:_rebuildIndex()
        service.store = original_store
    end)
end)
