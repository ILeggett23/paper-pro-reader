local AnnotationService = require("apps/paperpro/services/annotationservice")
local ContextualActions = require("apps/paperpro/overlays/contextualactions")
local DefinitionOverlay = require("apps/paperpro/overlays/definitionoverlay")
local DefinitionService = require("apps/paperpro/services/definitionservice")
local Device = require("device")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InkAnchor = require("apps/paperpro/ink/inkanchor")
local InkCanvas = require("apps/paperpro/ink/inkcanvas")
local InkRenderer = require("apps/paperpro/ink/inkrenderer")
local InkService = require("apps/paperpro/ink/inkservice")
local InkStore = require("apps/paperpro/ink/inkstore")
local NoteOverlay = require("apps/paperpro/overlays/noteoverlay")
local NotesHub = require("apps/paperpro/hubs/noteshub")
local Notification = require("ui/widget/notification")
local Rasterizer = require("apps/paperpro/ink/rasterizer")
local ReaderOverlay = require("apps/paperpro/overlays/readeroverlay")
local SelectionService = require("apps/paperpro/services/selectionservice")
local VocabularyHub = require("apps/paperpro/hubs/vocabularyhub")
local VocabularyService = require("apps/paperpro/services/vocabularyservice")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen

local PaperProReader = WidgetContainer:extend{
    name = "PaperProReader",
}

function PaperProReader:init()
    self.selection_service = self.selection_service or SelectionService:new()
    self.definition_service = self.definition_service or DefinitionService:new{
        dictionary = self.ui.dictionary,
    }
    self.contextual_actions = self.contextual_actions or ContextualActions:new()
    self.definition_overlay = self.definition_overlay or DefinitionOverlay:new()
    self.note_overlay = self.note_overlay or NoteOverlay:new()
    self.annotation_service = self.annotation_service or AnnotationService:new{ ui = self.ui }
    self.vocabulary_service = self.vocabulary_service or VocabularyService:new{ ui = self.ui }
    self.notes_hub = self.notes_hub or NotesHub:new{
        service = self.annotation_service,
        on_edit = function(item) self:_openExistingNote(item) end,
    }
    self.vocabulary_hub = self.vocabulary_hub or VocabularyHub:new{
        service = self.vocabulary_service,
    }
    if not self.ink_service then
        local bounds = (self.ui.dimen or Screen:getSize()):copy()
        self.ink_renderer = InkRenderer:new{ width = math.max(2, Screen:scaleBySize(2)) }
        self.ink_canvas = InkCanvas:new{
            dimen = bounds,
            renderer = self.ink_renderer,
            reader_ui = self.ui,
        }
        self.ink_anchor = InkAnchor:new{ ui = self.ui, bounds = bounds }
        self.ink_store = InkStore:new{
            document_id = self.ui.document.file,
            doc_settings = self.ui.doc_settings,
        }
        self.ink_rasterizer = Rasterizer:new{ renderer = self.ink_renderer }
        self.ink_service = InkService:new{
            ui = self.ui,
            input = Device.input,
            canvas = self.ink_canvas,
            anchor = self.ink_anchor,
            store = self.ink_store,
            renderer = self.ink_renderer,
            rasterizer = self.ink_rasterizer,
        }
    end
    self.overlay = self.overlay or ReaderOverlay:new{
        on_dismiss = function()
            self:_onOverlayDismissed()
        end,
    }
    self._lookup_sequence = 0
    self._reader_note_mark = self.ui.view and self.ui.view.highlight.note_mark
    if self.ui.menu then self.ui.menu:registerToMainMenu(self) end
end

function PaperProReader:_actionsFactory(snapshot)
    return function(anchor_func)
        return self.contextual_actions:build(snapshot, {
            highlight = function() self:performAction("highlight") end,
            define = function() self:performAction("define") end,
            note = function() self:performAction("note") end,
        }, anchor_func)
    end
end

function PaperProReader:_definitionFactory(model)
    return function(anchor_func, close_func)
        return self.definition_overlay:build(model, anchor_func, close_func)
    end
end

function PaperProReader:_onOverlayDismissed()
    self.active_lookup = nil
    self.current_snapshot = nil
    self.current_note = nil
    if self.ui and self.ui.highlight then
        self.ui.highlight:onClose()
    end
end

function PaperProReader:_noteFactory(model)
    return function(anchor_func, close_func)
        return self.note_overlay:build(model, anchor_func, close_func, function(text)
            return self:_saveNote(text)
        end)
    end
end

function PaperProReader:_showNoteEditor(model, boxes)
    self.current_note = model
    local shown
    if self.overlay:isOpen() then
        shown = self.overlay:update(self:_noteFactory(model), model)
    else
        shown = self.overlay:open(self:_noteFactory(model), boxes or {}, model)
    end
    if shown and self.overlay.widget and self.overlay.widget.onShowKeyboard then
        self.overlay.widget:onShowKeyboard()
    end
    return shown
end

function PaperProReader:_saveNote(text)
    local note = self.current_note
    if not note then return false, _("Note is no longer available") end
    local reference, err
    if note.is_edit then
        reference, err = self.annotation_service:update(note.annotation_ref, text)
    else
        reference, err = self.annotation_service:createFromCurrentSelection(text)
    end
    if not reference then return false, err end
    self.overlay:dismiss()
    return true
end

function PaperProReader:_openExistingNote(item)
    if not (item and item.annotation_ref) then return false end
    local annotation = item.annotation or self.annotation_service:resolve(item.annotation_ref)
    if not annotation or not annotation.note then return false end
    self.current_snapshot = nil
    return self:_showNoteEditor({
        is_edit = true,
        annotation_ref = item.annotation_ref,
        note = annotation.note,
        source_text = annotation.text,
    }, item.screen_boxes)
end

function PaperProReader:onShowSelectionActions(selection, is_word_selection)
    if self.ink_service.active then self.ink_service:deactivate() end
    local snapshot = self.selection_service:createSnapshot(self.ui, selection, {
        is_word_selection = is_word_selection,
    })
    if not snapshot then
        return false
    end
    self.active_lookup = nil
    self.current_snapshot = snapshot
    return self.overlay:open(self:_actionsFactory(snapshot), snapshot.screen_boxes, snapshot)
end

function PaperProReader:_showDefinition(model)
    return self.overlay:update(self:_definitionFactory(model), model)
end

function PaperProReader:performAction(action)
    local snapshot = self.current_snapshot
    if not snapshot then
        return false
    end

    if action == "highlight" then
        self.overlay:dismiss(true)
        self.current_snapshot = nil
        self.ui.highlight:showHighlightPrompt()
        return true
    elseif action == "note" then
        return self:_showNoteEditor({
            is_edit = false,
            source_text = snapshot.text,
            note = "",
        }, snapshot.screen_boxes)
    elseif action ~= "define" then
        return false
    end

    self._lookup_sequence = self._lookup_sequence + 1
    local lookup_id = self._lookup_sequence
    self.active_lookup = lookup_id
    self:_showDefinition({
        query = snapshot.selected_word or snapshot.text,
        display_word = snapshot.selected_word or snapshot.text,
        definitions = {},
        status = "loading",
        selection_anchor = snapshot.anchor,
    })
    self.definition_service:lookup(snapshot, function(model)
        if self.active_lookup == lookup_id and self.overlay:isOpen() then
            self:_showDefinition(model)
            if model.status == "success" and snapshot.selected_word
                    and G_reader_settings:nilOrTrue("paperpro_auto_add_vocabulary") then
                model.vocabulary_status = "saving"
                self:_showDefinition(model)
                self.vocabulary_service:recordDefinition(snapshot, model, function(status)
                    model.vocabulary_status = status
                    if self.active_lookup == lookup_id and self.overlay:isOpen() then
                        self:_showDefinition(model)
                    end
                end)
            end
        end
    end)
    return true
end

function PaperProReader:onShowAnnotationNote(payload)
    if not (payload and payload.has_note and payload.annotation and payload.annotation_ref) then
        return false
    end
    return self:_openExistingNote(payload)
end

function PaperProReader:onAnnotationsModified()
    self.notes_hub:refreshIfOpen()
end

function PaperProReader:onPageUpdate()
    self.ink_service:onLocationChanged()
end

function PaperProReader:onPosUpdate()
    self.ink_service:onLocationChanged()
end

function PaperProReader:onSetDimensions(dimen)
    self.ink_service:onLocationChanged()
    self.ink_canvas:setDimensions(dimen)
    self.ink_anchor.bounds = self.ink_canvas.dimen
end

function PaperProReader:_applyNoteMarkerPolicy(redraw)
    if not (self.ui.view and self.ui.view.highlight) then return end
    if G_reader_settings:nilOrTrue("paperpro_note_markers") then
        self.ui.view.highlight.note_mark = self._reader_note_mark or "sidemark"
    else
        self.ui.view.highlight.note_mark = nil
    end
    self.ui.view:setupNoteMarkPosition()
    if redraw then UIManager:setDirty(self.ui.dialog, "ui") end
end

function PaperProReader:onReaderReady()
    self:_applyNoteMarkerPolicy(false)
    self.ink_service:attach()
end

function PaperProReader:openNotesHub()
    self.ink_service:deactivate()
    self.overlay:dismiss(true)
    self.current_snapshot, self.current_note = nil, nil
    self.ui.highlight:onClose()
    return self.notes_hub:open()
end

function PaperProReader:openVocabularyHub()
    self.ink_service:deactivate()
    self.overlay:dismiss(true)
    self.current_snapshot, self.current_note = nil, nil
    self.ui.highlight:onClose()
    return self.vocabulary_hub:open()
end

function PaperProReader:addToMainMenu(menu_items)
    menu_items.paperpro_study = {
        text = _("Study"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Notes"),
                callback = function() self:openNotesHub() end,
            },
            {
                text = _("Vocabulary"),
                callback = function() self:openVocabularyHub() end,
                separator = true,
            },
            {
                text = _("Ink Mode"),
                checked_func = function() return self.ink_service.active end,
                callback = function()
                    local ok, err = self.ink_service:toggle()
                    if not ok then UIManager:show(InfoMessage:new{ text = err or _("Ink Mode unavailable") }) end
                end,
            },
            {
                text = _("Ink eraser"),
                enabled_func = function() return self.ink_service.active end,
                checked_func = function() return self.ink_service.eraser_mode end,
                callback = function()
                    self.ink_service:setEraserMode(not self.ink_service.eraser_mode)
                end,
            },
            {
                text = _("Undo ink"),
                enabled_func = function() return self.ink_service:canUndo() end,
                callback = function() self.ink_service:undo() end,
            },
            {
                text = _("Redo ink"),
                enabled_func = function() return self.ink_service:canRedo() end,
                callback = function() self.ink_service:redo() end,
            },
            {
                text = _("Delete last ink stroke"),
                enabled_func = function() return #self.ink_service:getRenderableStrokes() > 0 end,
                callback = function()
                    if not self.ink_service:deleteLastVisible() then
                        UIManager:show(Notification:new{ text = _("No ink on this page") })
                    end
                end,
            },
            {
                text = _("Clear ink on this page"),
                enabled_func = function() return #self.ink_service:getRenderableStrokes() > 0 end,
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Clear all ink at this reading location?"),
                        ok_text = _("Clear"),
                        ok_callback = function() self.ink_service:clearVisible() end,
                    })
                end,
                separator = true,
            },
            {
                text = _("Automatically save defined words"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("paperpro_auto_add_vocabulary")
                end,
                callback = function()
                    G_reader_settings:saveSetting("paperpro_auto_add_vocabulary",
                        not G_reader_settings:nilOrTrue("paperpro_auto_add_vocabulary"))
                end,
            },
            {
                text = _("Show note markers"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("paperpro_note_markers")
                end,
                callback = function()
                    G_reader_settings:saveSetting("paperpro_note_markers",
                        not G_reader_settings:nilOrTrue("paperpro_note_markers"))
                    self:_applyNoteMarkerPolicy(true)
                end,
            },
        },
    }
end

function PaperProReader:onCloseDocument()
    self.active_lookup = nil
    self.current_snapshot = nil
    self.current_note = nil
    self.ink_service:close()
    self.notes_hub:close()
    self.vocabulary_hub:close()
    self.overlay:dismiss(true)
end

return PaperProReader
