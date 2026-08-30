local ContextualActions = require("apps/paperpro/overlays/contextualactions")
local DefinitionOverlay = require("apps/paperpro/overlays/definitionoverlay")
local DefinitionService = require("apps/paperpro/services/definitionservice")
local ReaderOverlay = require("apps/paperpro/overlays/readeroverlay")
local SelectionService = require("apps/paperpro/services/selectionservice")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

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
    self.overlay = self.overlay or ReaderOverlay:new{
        on_dismiss = function()
            self:_onOverlayDismissed()
        end,
    }
    self._lookup_sequence = 0
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
    if self.ui and self.ui.highlight then
        self.ui.highlight:onClose()
    end
end

function PaperProReader:onShowSelectionActions(selection, is_word_selection)
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
        self.overlay:dismiss(true)
        self.current_snapshot = nil
        self.ui.highlight:addNote()
        return true
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
        end
    end)
    return true
end

function PaperProReader:onCloseDocument()
    self.active_lookup = nil
    self.current_snapshot = nil
    self.overlay:dismiss(true)
end

return PaperProReader
