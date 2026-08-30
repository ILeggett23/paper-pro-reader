local AnnotationService = require("apps/paperpro/services/annotationservice")
local AIHistory = require("apps/paperpro/hubs/aihistory")
local AIProvider = require("apps/paperpro/services/aiprovider")
local AIRequest = require("apps/paperpro/services/airequest")
local AISettings = require("apps/paperpro/services/aisettings")
local AnchorNavigator = require("apps/paperpro/services/anchornavigator")
local ContextResolver = require("apps/paperpro/services/contextresolver")
local ConversationHub = require("apps/paperpro/hubs/conversationhub")
local ConversationService = require("apps/paperpro/services/conversationservice")
local ConversationMarker = require("apps/paperpro/overlays/conversationmarker")
local ContextualActions = require("apps/paperpro/overlays/contextualactions")
local DefinitionOverlay = require("apps/paperpro/overlays/definitionoverlay")
local DefinitionService = require("apps/paperpro/services/definitionservice")
local Diagnostics = require("apps/paperpro/services/diagnostics")
local Device = require("device")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InkAnchor = require("apps/paperpro/ink/inkanchor")
local InkCanvas = require("apps/paperpro/ink/inkcanvas")
local InkRenderer = require("apps/paperpro/ink/inkrenderer")
local InkService = require("apps/paperpro/ink/inkservice")
local InkStore = require("apps/paperpro/ink/inkstore")
local InkQuestionSession = require("apps/paperpro/ink/inkquestionsession")
local NoteOverlay = require("apps/paperpro/overlays/noteoverlay")
local NotesHub = require("apps/paperpro/hubs/noteshub")
local Notification = require("ui/widget/notification")
local OfflineQueue = require("apps/paperpro/services/offlinequeue")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local QuickAskOverlay = require("apps/paperpro/overlays/quickaskoverlay")
local Rasterizer = require("apps/paperpro/ink/rasterizer")
local ReaderOverlay = require("apps/paperpro/overlays/readeroverlay")
local ResponseStore = require("apps/paperpro/services/responsestore")
local SelectionService = require("apps/paperpro/services/selectionservice")
local VocabularyHub = require("apps/paperpro/hubs/vocabularyhub")
local VocabularyService = require("apps/paperpro/services/vocabularyservice")
local UIManager = require("ui/uimanager")
local TextViewer = require("ui/widget/textviewer")
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
    self.ai_settings = self.ai_settings or AISettings:new{
        default_input_mode = Device.model == "reMarkable Ferrari" and "write" or "type",
    }
    self.context_resolver = self.context_resolver or ContextResolver:new()
    self.response_store = self.response_store or ResponseStore:new()
    self.offline_queue = self.offline_queue or OfflineQueue:new()
    self.ai_provider = self.ai_provider or AIProvider:new{ settings = self.ai_settings }
    self.anchor_navigator = self.anchor_navigator or AnchorNavigator:new{ ui = self.ui }
    self.conversation_service = self.conversation_service or ConversationService:new{
        responses = self.response_store,
    }
    self.conversation_hub = self.conversation_hub or ConversationHub:new{
        responses = self.response_store, navigator = self.anchor_navigator,
        on_followup = function(conversation) self:_followupConversation(conversation) end,
        on_keep_ink = function(conversation, turn)
            if not self.conversation_marker:_visible(conversation) then
                UIManager:show(InfoMessage:new{ text = _("Go to the source passage before keeping this handwriting") })
                return false
            end
            local ok, err = self.ink_service:importScreenStrokes(
                turn.question_ink and turn.question_ink.strokes,
                conversation.conversation_id)
            if not ok then
                UIManager:show(InfoMessage:new{ text = err or _("Could not keep handwriting in book") })
                return false
            end
            self.response_store:markKeptInBook(conversation.conversation_id, turn.request_id)
            return true
        end,
    }
    self.conversation_marker = self.conversation_marker or ConversationMarker:new{
        ui = self.ui, responses = self.response_store,
        dimen = (self.ui.dimen or Screen:getSize()):copy(),
        on_open = function(id) self.conversation_hub:open(id, false) end,
    }
    self.quick_ask_overlay = self.quick_ask_overlay or QuickAskOverlay:new()
    self.ai_history = self.ai_history or AIHistory:new{
        queue = self.offline_queue,
        responses = self.response_store,
        navigator = self.anchor_navigator,
        on_cancel = function(request_id) self:_cancelAIRequest(request_id) end,
        on_retry = function(request_id) self:_retryQueuedAIRequest(request_id) end,
        on_open_conversation = function(conversation_id)
            self.conversation_hub:open(conversation_id, false)
        end,
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
    self.diagnostics = self.diagnostics or Diagnostics:new{
        ai_settings = self.ai_settings, queue = self.offline_queue,
        ink_service = self.ink_service,
    }
    self.conversation_marker.on_touch_route = function(state, mode)
        self.diagnostics:record("touch_route", { state = state, mode = mode })
    end
    self.overlay = self.overlay or ReaderOverlay:new{
        on_dismiss = function()
            self:_onOverlayDismissed()
        end,
    }
    self._lookup_sequence = 0
    self.document_closed = false
    self._ai_queue_listener = self.offline_queue:addListener(function(item)
        self:_onAIQueueItem(item)
    end)
    if self.ai_settings:isEnabled() then
        UIManager:nextTick(function()
            if not self.document_closed then
                self.offline_queue:processBatch(self.ai_provider, self.response_store)
            end
        end)
    end
    self._reader_note_mark = self.ui.view and self.ui.view.highlight.note_mark
    if self.ui.menu then self.ui.menu:registerToMainMenu(self) end
end

function PaperProReader:_actionsFactory(snapshot)
    return function(anchor_func)
        return self.contextual_actions:build(snapshot, {
            highlight = function() self:performAction("highlight") end,
            define = function() self:performAction("define") end,
            note = function() self:performAction("note") end,
            ask_ai = function() self:performAction("ask_ai") end,
        }, anchor_func, { ai_enabled = self.ai_settings:isEnabled() })
    end
end

function PaperProReader:_quickAskFactory(model)
    return function(anchor_func, close_func)
        return self.quick_ask_overlay:build(model, anchor_func, close_func, {
            submit = function(question) self:_submitQuickAsk(question) end,
            cancel = function(request_id) self:_cancelAIRequest(request_id) end,
            retry = function(retry_model) self:_retryQuickAsk(retry_model) end,
            mode = function(mode) self:_setQuickAskMode(mode) end,
            undo = function() if self.ink_question_session then self.ink_question_session:undo() end end,
            clear = function() if self.ink_question_session then self.ink_question_session:clear() end end,
            submit_ink = function() self:_submitInkQuestion() end,
            followup = function() self:_followupCurrentConversation() end,
            expand = function() self:_expandCurrentConversation() end,
            keep_ink = function() self:_keepQuestionInBook() end,
            toggle_style = function() self:_toggleResponseStyle() end,
            rewrite = function() self:_setQuickAskMode("write") end,
            edit_text = function() self:_editRecognizedQuestion() end,
            ask_anyway = function() self:_askRecognizedQuestion() end,
        })
    end
end

function PaperProReader:_showQuickAsk(model)
    if self.diagnostics then self.diagnostics:record("overlay_state", { state = model.state }) end
    if model.state ~= "write" then self:_closeInkQuestionSession() end
    self.current_ai_model = model
    local shown = self.overlay:update(self:_quickAskFactory(model), model)
    if shown and model.state == "compose" and self.overlay.widget.onShowKeyboard then
        self.overlay.widget:onShowKeyboard()
    end
    if shown and model.state == "write" and not self.ink_question_session then
        self.ink_question_session = InkQuestionSession:new{
            ui = self.ui, bounds = self.quick_ask_overlay:writingBounds(),
        }
        local ok, err = self.ink_question_session:start()
        if not ok then
            self.ink_question_session = nil
            return self:_showQuickAsk{
                state = "error", message = err or _("Marker input is unavailable"),
                question = model.question, source_text = model.source_text,
                context_mode = model.context_mode, retryable = false,
            }
        end
    end
    return shown
end

function PaperProReader:_closeInkQuestionSession()
    if not self.ink_question_session then return false end
    self.ink_question_session:close()
    self.ink_question_session = nil
    return true
end

function PaperProReader:_setQuickAskMode(mode)
    self.ai_settings:setInputMode(mode)
    local model = self.current_ai_model or {}
    if mode == "write" then
        self:_closeInkQuestionSession()
        return self:_showQuickAsk{
            state = "write", source_text = model.source_text,
            context_mode = model.context_mode or self.ai_settings:getContextMode(),
            conversation_id = model.conversation_id or self.active_conversation_id,
        }
    end
    return self:_showQuickAsk{
        state = "compose", question = model.question or model.recognized_question or "",
        source_text = model.source_text,
        context_mode = model.context_mode or self.ai_settings:getContextMode(),
        conversation_id = model.conversation_id or self.active_conversation_id,
    }
end

function PaperProReader:_openQuickAsk()
    local snapshot = self.current_snapshot
    if not snapshot then return false end
    self.active_ai_request = nil
    self.active_conversation_id = nil
    local mode = self.ai_settings:getInputMode()
    return self:_showQuickAsk{
        state = mode == "write" and "write" or "compose",
        question = "",
        source_text = snapshot.text,
        context_mode = self.ai_settings:getContextMode(),
    }
end

function PaperProReader:_friendlyAIError(category)
    local messages = {
        disabled = _("AI questions are disabled"),
        not_configured = _("Configure the reading assistant backend in Study"),
        offline = _("You are offline"),
        dns_failure = _("The backend address could not be found"),
        timeout = _("The backend took too long to respond"),
        tls_failure = _("The secure connection could not be verified"),
        authentication = _("The backend token was rejected"),
        backend_unavailable = _("The reading assistant is temporarily unavailable"),
        rate_limited = _("The reading assistant is busy; try again shortly"),
        malformed_response = _("The backend returned an unsupported response"),
        unsupported_schema = _("The backend protocol is not compatible"),
        question_empty = _("Enter a question"),
        question_too_long = _("That question is too long"),
        storage_failure = _("The question could not be saved locally"),
        ink_empty = _("Write a question first"),
        image_dimensions = _("The handwritten question is too large"),
        invalid_image_dimensions = _("The handwritten question dimensions are invalid"),
        image_too_large = _("The handwritten question image is too large"),
        invalid_image = _("The handwritten question image is invalid"),
        model_capability = _("The configured AI model does not support handwriting images"),
    }
    return messages[category] or _("The reading assistant could not answer this question")
end

function PaperProReader:_submitQuickAsk(question)
    local snapshot = self.current_snapshot
    local source_text = snapshot and snapshot.text
        or self.current_ai_context and self.current_ai_context.selection.text
    if not source_text then return false end
    if not self.ai_settings:isEnabled() then
        return self:_showQuickAsk{
            state = "error", question = question, source_text = source_text,
            context_mode = self.ai_settings:getContextMode(),
            message = self:_friendlyAIError("disabled"), retryable = false,
        }
    elseif not self.ai_provider:isConfigured() then
        return self:_showQuickAsk{
            state = "error", question = question, source_text = source_text,
            context_mode = self.ai_settings:getContextMode(),
            message = self:_friendlyAIError("not_configured"), retryable = false,
        }
    end
    local context, context_err
    if self.current_ai_context then
        context = SelectionService.deepCopy(self.current_ai_context)
    else
        context, context_err = self.context_resolver:resolve(self.ui, snapshot, {
            context_mode = self.ai_settings:getContextMode(),
        })
    end
    if not context then
        return self:_showQuickAsk{
            state = "compose", question = question, source_text = source_text,
            context_mode = self.ai_settings:getContextMode(),
            message = self:_friendlyAIError(context_err),
        }
    end
    local request_options = self.conversation_service:requestOptions(self.active_conversation_id)
    local request, request_err = AIRequest.createText(context, question, {
        response_length = "concise", context_mode = context.context_mode,
    }, request_options)
    if not request then
        return self:_showQuickAsk{
            state = "compose", question = question, source_text = source_text,
            context_mode = context.context_mode,
            message = self:_friendlyAIError(request_err),
        }
    end
    return self:_enqueueAIRequest(request, context)
end

function PaperProReader:_submitInkQuestion()
    if not self.ink_question_session then return false end
    local strokes, stroke_err = self.ink_question_session:submit()
    if not strokes then
        UIManager:show(InfoMessage:new{ text = stroke_err == "ink_empty"
            and _("Write a question first") or _("Could not capture handwriting") })
        return false
    end
    self:_closeInkQuestionSession()
    local context, context_err
    if self.current_ai_context then context = SelectionService.deepCopy(self.current_ai_context)
    elseif self.current_snapshot then
        context, context_err = self.context_resolver:resolve(self.ui, self.current_snapshot, {
            context_mode = self.ai_settings:getContextMode(),
        })
    end
    if not context then
        return self:_showQuickAsk{ state = "error",
            message = self:_friendlyAIError(context_err), retryable = false }
    end
    if not self.ai_settings:isEnabled() or not self.ai_provider:isConfigured() then
        return self:_showQuickAsk{
            state = "error", source_text = context.selection.text,
            context_mode = context.context_mode,
            message = self:_friendlyAIError(self.ai_settings:isEnabled()
                and "not_configured" or "disabled"), retryable = false,
        }
    end
    local options = self.conversation_service:requestOptions(self.active_conversation_id)
    local request, request_err = AIRequest.createInk(context, strokes, {
        response_length = "concise", context_mode = context.context_mode,
    }, options)
    if not request then
        return self:_showQuickAsk{ state = "error",
            message = self:_friendlyAIError(request_err), retryable = false }
    end
    return self:_enqueueAIRequest(request, context)
end

function PaperProReader:_enqueueAIRequest(request, context)
    local queued, queue_err = self.offline_queue:enqueue(request)
    if not queued then
        return self:_showQuickAsk{
            state = "error", question = request.question.text,
            source_text = context.selection.text,
            context_mode = context.context_mode, message = self:_friendlyAIError(queue_err),
            retryable = false,
        }
    end
    self.active_ai_request = request.request_id
    self.active_conversation_id = request.conversation and request.conversation.id
    if self.ai_provider:isAvailable() then
        self:_showQuickAsk{
            state = "sending", request_id = request.request_id,
            question = request.question.text, source_text = context.selection.text,
            context_mode = context.context_mode, question_type = request.question.type,
            conversation_id = self.active_conversation_id,
        }
        self.offline_queue:processBatch(self.ai_provider, self.response_store, {
            preferred_id = request.request_id, max_count = 1,
        })
    else
        self:_showQuickAsk{
            state = "queued", request_id = request.request_id,
            question = request.question.text, source_text = context.selection.text,
            context_mode = context.context_mode, question_type = request.question.type,
            conversation_id = self.active_conversation_id,
            message = _("Saved. I'll answer when you're back online."),
        }
    end
    return true
end

function PaperProReader:_onAIQueueItem(item)
    if self.diagnostics then self.diagnostics:record("ai_queue", {
        request_id = item.id, state = item.state, category = item.last_error_category,
    }) end
    self.ai_history:refreshIfOpen()
    self.conversation_marker:refresh()
    if self.document_closed or item.id ~= self.active_ai_request or not self.overlay:isOpen() then
        return
    end
    local request = item.request
    self.current_ai_context = SelectionService.deepCopy(request.reading_context)
    self.active_conversation_id = request.conversation and request.conversation.id
    local model = {
        state = item.state,
        request_id = item.id,
        question = request.question.text,
        question_type = request.question.type,
        ink_strokes = request.question.local_ink and request.question.local_ink.strokes,
        source_text = request.reading_context.selection.text,
        context_mode = request.preferences.context_mode,
        conversation_id = request.conversation and request.conversation.id,
        response_style = self.ai_settings:getResponseStyle(),
    }
    if item.state == "completed" then
        local response = self.response_store:getByRequestId(item.id)
        if not response then return end
        model.answer = response.answer
        model.recognized_question = response.recognized_question
        model.recognition_status = response.recognition_status
        model.state = response.clarification_required and "clarification" or "success"
        model.message = response.clarification_required
            and _("I couldn't confidently read part of this question.") or nil
    elseif item.state == "failed" then
        model.state = "error"
        model.message = self:_friendlyAIError(item.last_error_category)
        model.retryable = item.last_error_category ~= "authentication"
            and item.last_error_category ~= "unsupported_schema"
    elseif item.state == "queued" then
        model.message = _("Saved. I'll answer when you're back online.")
    end
    self:_showQuickAsk(model)
end

function PaperProReader:_followupConversation(conversation)
    if not conversation then return false end
    self.active_conversation_id = conversation.conversation_id
    self.current_ai_context = SelectionService.deepCopy(conversation.reading_context)
    return self:_showQuickAsk{
        state = "compose", question = "", source_text = conversation.source_text,
        context_mode = conversation.context_mode or self.ai_settings:getContextMode(),
        conversation_id = conversation.conversation_id,
    }
end

function PaperProReader:_followupCurrentConversation()
    local conversation = self.response_store:getConversation(self.active_conversation_id)
    return conversation and self:_followupConversation(conversation) or false
end

function PaperProReader:_expandCurrentConversation()
    if not self.active_conversation_id then return false end
    self.overlay:dismiss(true)
    return self.conversation_hub:open(self.active_conversation_id, false)
end

function PaperProReader:_toggleResponseStyle()
    local style = self.ai_settings:getResponseStyle() == "text" and "handwriting" or "text"
    self.ai_settings:setResponseStyle(style)
    local model = SelectionService.deepCopy(self.current_ai_model)
    if not model then return false end
    model.response_style = style
    return self:_showQuickAsk(model)
end

function PaperProReader:_keepQuestionInBook()
    local model = self.current_ai_model
    if not (model and model.ink_strokes and model.conversation_id) then return false end
    local ok, err = self.ink_service:importScreenStrokes(model.ink_strokes, model.conversation_id)
    if not ok then
        UIManager:show(InfoMessage:new{ text = err or _("Could not keep handwriting in book") })
        return false
    end
    self.response_store:markKeptInBook(model.conversation_id, model.request_id)
    model.kept_in_book = true
    self:_showQuickAsk(model)
    return true
end

function PaperProReader:_editRecognizedQuestion()
    local model = self.current_ai_model or {}
    return self:_showQuickAsk{
        state = "compose", question = model.recognized_question or "",
        source_text = model.source_text, context_mode = model.context_mode,
        conversation_id = model.conversation_id,
    }
end

function PaperProReader:_askRecognizedQuestion()
    local model = self.current_ai_model or {}
    if not model.recognized_question then return self:_editRecognizedQuestion() end
    return self:_submitQuickAsk(model.recognized_question)
end

function PaperProReader:_cancelAIRequest(request_id)
    if not request_id then return false end
    self.ai_provider:cancel(request_id)
    local cancelled = self.offline_queue:cancel(request_id)
    if cancelled and self.active_ai_request == request_id and self.overlay:isOpen() then
        self:_showQuickAsk{ state = "cancelled", request_id = request_id }
    end
    return cancelled
end

function PaperProReader:_retryQueuedAIRequest(request_id)
    if not self.offline_queue:retry(request_id) then return false end
    self.offline_queue:processBatch(self.ai_provider, self.response_store, {
        preferred_id = request_id, max_count = 1,
    })
    return true
end

function PaperProReader:_retryQuickAsk(model)
    if model.retryable and model.request_id and self:_retryQueuedAIRequest(model.request_id) then
        model.state, model.message = "sending", nil
        return self:_showQuickAsk(model)
    end
    return self:_showQuickAsk{
        state = "compose", question = model.question or "",
        source_text = model.source_text,
        context_mode = model.context_mode or self.ai_settings:getContextMode(),
    }
end

function PaperProReader:_definitionFactory(model)
    return function(anchor_func, close_func)
        return self.definition_overlay:build(model, anchor_func, close_func)
    end
end

function PaperProReader:_onOverlayDismissed()
    self:_closeInkQuestionSession()
    self.active_lookup = nil
    self.current_snapshot = nil
    self.current_note = nil
    self.current_ai_model = nil
    self.active_ai_request = nil
    self.current_ai_context = nil
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
    elseif action == "ask_ai" then
        return self:_openQuickAsk()
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

function PaperProReader:onNetworkConnected()
    if self.ai_settings:isEnabled() then
        self.offline_queue:processBatch(self.ai_provider, self.response_store)
    end
end

function PaperProReader:onPageUpdate()
    self.ink_service:onLocationChanged()
    self.conversation_marker:refresh()
end

function PaperProReader:onPosUpdate()
    self.ink_service:onLocationChanged()
    self.conversation_marker:refresh()
end

function PaperProReader:onSetDimensions(dimen)
    self.ink_service:onLocationChanged()
    self.ink_canvas:setDimensions(dimen)
    self.ink_anchor.bounds = self.ink_canvas.dimen
    self.conversation_marker:setDimensions(dimen)
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
end

function PaperProReader:onShow()
    self.conversation_marker:attach()
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

function PaperProReader:openAIHistory()
    self.ink_service:deactivate()
    self.overlay:dismiss(true)
    self.current_snapshot, self.current_note = nil, nil
    self.ui.highlight:onClose()
    return self.ai_history:open()
end

function PaperProReader:openAIBackendSettings()
    local config = self.ai_settings:getConfig()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Reading assistant backend"),
        fields = {
            { text = config.backend_url, hint = _("https://reader.example.com") },
            { text = config.backend_token, text_type = "password", hint = _("Device access token") },
        },
        buttons = {{
            { text = _("Cancel"), callback = function() UIManager:close(dialog) end },
            {
                text = _("Save"),
                callback = function()
                    local fields = dialog:getFields()
                    local ok, err = self.ai_settings:saveBackend(fields[1], fields[2])
                    if ok then
                        UIManager:close(dialog)
                        if self.ai_settings:isEnabled() then
                            self.offline_queue:processBatch(self.ai_provider, self.response_store)
                        end
                    else UIManager:show(InfoMessage:new{ text = err }) end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function PaperProReader:testAIConnection()
    UIManager:show(Notification:new{ text = _("Testing reading assistant…") })
    self.ai_provider:testConnection(function(result, err)
        if self.document_closed then return end
        UIManager:show(InfoMessage:new{
            text = result and _("Reading assistant connected")
                or self:_friendlyAIError(err and err.category),
        })
    end)
end

function PaperProReader:showDiagnostics()
    local viewer
    viewer = TextViewer:new{
        title = _("Paper Pro diagnostics"),
        text = self.diagnostics:report(),
        buttons_table = {{
            { text = _("Close"), callback = function() UIManager:close(viewer) end },
        }},
    }
    UIManager:show(viewer)
    return true
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
            },
            {
                text = _("AI Questions"),
                callback = function() self:openAIHistory() end,
            },
            {
                text = _("AI assistant"),
                sub_item_table = {
                    {
                        text = _("Enabled"),
                        checked_func = function() return self.ai_settings:isEnabled() end,
                        callback = function()
                            local enabled = not self.ai_settings:isEnabled()
                            self.ai_settings:setEnabled(enabled)
                            if enabled then
                                self.offline_queue:processBatch(self.ai_provider, self.response_store)
                            end
                        end,
                    },
                    {
                        text = _("Backend settings"),
                        callback = function() self:openAIBackendSettings() end,
                    },
                    {
                        text = _("Default context"),
                        sub_item_table = {
                            {
                                text = _("Nearby"),
                                checked_func = function()
                                    return self.ai_settings:getContextMode() == "nearby"
                                end,
                                callback = function() self.ai_settings:setContextMode("nearby") end,
                            },
                            {
                                text = _("Minimal"),
                                checked_func = function()
                                    return self.ai_settings:getContextMode() == "minimal"
                                end,
                                callback = function() self.ai_settings:setContextMode("minimal") end,
                            },
                        },
                    },
                    {
                        text = _("Default question input"),
                        sub_item_table = {
                            { text = _("Write"), checked_func = function()
                                return self.ai_settings:getInputMode() == "write" end,
                                callback = function() self.ai_settings:setInputMode("write") end },
                            { text = _("Type"), checked_func = function()
                                return self.ai_settings:getInputMode() == "type" end,
                                callback = function() self.ai_settings:setInputMode("type") end },
                        },
                    },
                    {
                        text = _("AI response style"),
                        sub_item_table = {
                            { text = _("Text"), checked_func = function()
                                return self.ai_settings:getResponseStyle() == "text" end,
                                callback = function() self.ai_settings:setResponseStyle("text") end },
                            { text = _("Handwriting"), checked_func = function()
                                return self.ai_settings:getResponseStyle() == "handwriting" end,
                                callback = function() self.ai_settings:setResponseStyle("handwriting") end },
                        },
                    },
                    {
                        text = _("Test connection"),
                        enabled_func = function() return self.ai_settings:isConfigured() end,
                        callback = function() self:testAIConnection() end,
                    },
                    {
                        text = _("Allow private-LAN HTTP for testing"),
                        checked_func = function() return self.ai_settings:allowInsecureLAN() end,
                        callback = function()
                            self.ai_settings:setAllowInsecureLAN(not self.ai_settings:allowInsecureLAN())
                        end,
                    },
                },
                separator = true,
            },
            {
                text = _("Diagnostics"),
                sub_item_table = {
                    {
                        text = _("Enable diagnostic log"),
                        checked_func = function() return self.diagnostics:isEnabled() end,
                        callback = function()
                            self.diagnostics:setEnabled(not self.diagnostics:isEnabled())
                        end,
                    },
                    {
                        text = _("View diagnostic report"),
                        callback = function() self:showDiagnostics() end,
                    },
                },
                separator = true,
            },
            {
                text = _("Ink Mode"),
                checked_func = function() return self.ink_service.active end,
                check_callback_closes_menu = true,
                callback = function(touchmenu_instance)
                    local ok, err = self.ink_service:toggle()
                    if not ok then UIManager:show(InfoMessage:new{ text = err or _("Ink Mode unavailable") }) end
                    if touchmenu_instance then touchmenu_instance:closeMenu() end
                    if ok and self.ink_service.active then
                        UIManager:nextTick(function() self.ink_canvas:refreshStatus() end)
                    end
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
    if self.diagnostics then self.diagnostics:record("document_close") end
    self.document_closed = true
    self.active_lookup = nil
    self.current_snapshot = nil
    self.current_note = nil
    self:_closeInkQuestionSession()
    if self._ai_queue_listener then
        self.offline_queue:removeListener(self._ai_queue_listener)
        self._ai_queue_listener = nil
    end
    self.ink_service:close()
    self.notes_hub:close()
    self.vocabulary_hub:close()
    self.ai_history:close()
    self.conversation_hub:close()
    self.conversation_marker:detach()
    self.overlay:dismiss(true)
end

return PaperProReader
