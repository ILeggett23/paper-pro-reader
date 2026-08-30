local Device = require("device")
local Geom = require("ui/geometry")
local Placement = require("apps/paperpro/overlays/placement")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")

local Screen = Device.screen

local ReaderOverlay = {}
ReaderOverlay.__index = ReaderOverlay

function ReaderOverlay:new(options)
    options = options or {}
    options.ui_manager = options.ui_manager or UIManager
    options.screen = options.screen or Screen
    options.gap = options.gap or Size.padding.small
    return setmetatable(options, self)
end

function ReaderOverlay:_anchor()
    if not (self.widget and self.widget.getContentSize) then
        return nil
    end
    local size = self.widget:getContentSize()
    if not size then
        return nil
    end
    local placement = Placement.calculate(self.anchor_boxes, size, {
        w = self.screen:getWidth(),
        h = self.screen:getHeight(),
    }, self.gap)
    self.placement = placement
    self.coverage = Geom:new{
        x = placement.x,
        y = placement.y,
        w = placement.w,
        h = placement.h,
    }
    return Geom:new{ x = placement.x, y = placement.y }, true
end

function ReaderOverlay:_finishDismiss()
    local callback = self.on_dismiss
    if callback then
        callback()
    end
end

function ReaderOverlay:_widgetDismissed(widget)
    if self.widget ~= widget then
        return
    end
    self.widget = nil
    self.coverage = nil
    self:_finishDismiss()
end

function ReaderOverlay:_show(widget_factory, model)
    local widget
    local anchor_func = function()
        return self:_anchor()
    end
    local close_func = function()
        self:dismiss()
    end
    widget = widget_factory(anchor_func, close_func, model)
    if not widget then
        return false
    end
    self.widget = widget
    widget.tap_close_callback = function()
        self:_widgetDismissed(widget)
    end
    self.ui_manager:show(widget)
    return true
end

function ReaderOverlay:open(widget_factory, anchor_boxes, model)
    if self.widget then
        self:dismiss(true)
    end
    self.anchor_boxes = anchor_boxes or {}
    self.model = model
    return self:_show(widget_factory, model)
end

function ReaderOverlay:update(widget_factory, model)
    if self.widget then
        local old_widget = self.widget
        self.widget = nil
        self.ui_manager:close(old_widget)
    end
    self.model = model
    return self:_show(widget_factory, model)
end

function ReaderOverlay:dismiss(silent)
    if not self.widget then
        return false
    end
    local widget = self.widget
    self.widget = nil
    self.coverage = nil
    self.ui_manager:close(widget)
    if not silent then
        self:_finishDismiss()
    end
    return true
end

function ReaderOverlay:isOpen()
    return self.widget ~= nil
end

function ReaderOverlay:getCoverageBounds()
    if self.widget and self.widget.movable and self.widget.movable.dimen then
        return self.widget.movable.dimen:copy()
    end
    return self.coverage and self.coverage:copy() or nil
end

function ReaderOverlay:getRefreshRegion()
    return self:getCoverageBounds()
end

ReaderOverlay.calculatePlacement = Placement.calculate

return ReaderOverlay
