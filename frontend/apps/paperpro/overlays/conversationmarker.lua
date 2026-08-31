local Blitbuffer = require("ffi/blitbuffer")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local ConversationMarker = InputContainer:extend{}

function ConversationMarker:init()
    self.dimen = self.dimen or Geom:new{ x = 0, y = 0, w = 600, h = 800 }
    self.bounds = Geom:new{
        x = self.dimen.x + self.dimen.w - 64,
        y = self.dimen.y + 64, w = 48, h = 36,
    }
    self.ges_events.TapConversation = {
        GestureRange:new{ ges = "tap", range = self.bounds },
    }
end

function ConversationMarker:_visible(conversation)
    local anchor = conversation and conversation.anchor
    if not anchor or anchor.document_id ~= self.ui.document.file then return false end
    if anchor.kind == "fixed_page" and self.ui.view.getCurrentPageList then
        for _, page in ipairs(self.ui.view:getCurrentPageList() or {}) do
            if page == anchor.page then return true end
        end
    elseif anchor.kind == "xpointer" and self.ui.rolling then
        local ok, page = pcall(self.ui.document.getPageFromXPointer,
            self.ui.document, anchor.start)
        return ok and page == self.ui:getCurrentPage()
    end
    return false
end

function ConversationMarker:currentConversation()
    for _, conversation in ipairs(self.responses:listConversationsForDocument(self.ui.document.file)) do
        if self:_visible(conversation) then return conversation end
    end
end

function ConversationMarker:paintTo(bb, x, y)
    if not self:currentConversation() then return end
    local b = self.bounds
    bb:paintRect(x + b.x, y + b.y, b.w, b.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x + b.x, y + b.y, b.w, b.h, 2, Blitbuffer.COLOR_BLACK)
    self.label = self.label or TextWidget:new{ text = "AI", face = Font:getFace("xx_smallinfofont") }
    local size = self.label:getSize()
    self.label:paintTo(bb, x + b.x + math.floor((b.w - size.w) / 2),
        y + b.y + math.floor((b.h - size.h) / 2))
end

function ConversationMarker:onTapConversation()
    local conversation = self:currentConversation()
    if conversation and self.on_open then self.on_open(conversation.conversation_id) end
    return conversation ~= nil
end

function ConversationMarker:onGesture(gesture)
    if self.on_touch_route then self.on_touch_route("touch_detected", gesture.ges) end
    if InputContainer.onGesture(self, gesture) then
        if self.on_touch_route then self.on_touch_route("conversation_marker", gesture.ges) end
        return true
    end

    -- This marker is a small painted window above ReaderUI. An unmatched
    -- gesture must be explicitly returned to the reader because UIManager only
    -- dispatches normal input to the topmost non-toast window.
    if self.on_touch_route then self.on_touch_route("reader_forwarded", gesture.ges) end
    local handled = self.ui:handleEvent(Event:new("Gesture", gesture))
    if self.on_touch_route then
        self.on_touch_route(handled and "reader_handled" or "reader_unhandled", gesture.ges)
    end
    return handled
end

function ConversationMarker:attach()
    if self.attached then return true end
    self.attached = true
    UIManager:show(self)
    return true
end

function ConversationMarker:setDimensions(dimen)
    self.dimen = dimen:copy()
    self.bounds = Geom:new{ x = dimen.x + dimen.w - 64,
        y = dimen.y + 64, w = 48, h = 36 }
    self.ges_events.TapConversation[1].range = self.bounds
end

function ConversationMarker:refresh()
    if self.attached then UIManager:setDirty(self, "ui", self.bounds) end
end

function ConversationMarker:detach()
    if not self.attached then return false end
    self.attached = false
    UIManager:close(self)
    return true
end

function ConversationMarker:onCloseWidget()
    if self.label then self.label:free(); self.label = nil end
end

return ConversationMarker
