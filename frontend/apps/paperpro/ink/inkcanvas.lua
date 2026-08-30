local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local InkCanvas = WidgetContainer:extend{}

function InkCanvas:init()
    self.ui_manager = self.ui_manager or UIManager
    self.dimen = self.dimen or Geom:new{ x = 0, y = 0, w = 600, h = 800 }
    self.status_bounds = Geom:new{
        x = self.dimen.x + self.dimen.w - math.min(96, math.floor(self.dimen.w * 0.2)),
        y = self.dimen.y,
        w = math.min(96, math.floor(self.dimen.w * 0.2)),
        h = math.min(42, math.floor(self.dimen.h * 0.07)),
    }
    self.show_status = self.show_status ~= false
end

function InkCanvas:setService(service)
    self.service = service
end

function InkCanvas:setDimensions(dimen)
    self.dimen = dimen:copy()
    self.status_bounds = Geom:new{
        x = self.dimen.x + self.dimen.w - math.min(96, math.floor(self.dimen.w * 0.2)),
        y = self.dimen.y,
        w = math.min(96, math.floor(self.dimen.w * 0.2)),
        h = math.min(42, math.floor(self.dimen.h * 0.07)),
    }
end

function InkCanvas:attach()
    if self.attached then return true end
    self.attached = true
    self.ui_manager:show(self)
    return true
end

function InkCanvas:detach()
    if not self.attached then return false end
    self.attached = false
    self.ui_manager:close(self)
    self.active_stroke = nil
    self.paint_segment = nil
    return true
end

function InkCanvas:isPointAllowed(point)
    local inside_canvas = point.x >= self.dimen.x and point.y >= self.dimen.y
        and point.x < self.dimen.x + self.dimen.w
        and point.y < self.dimen.y + self.dimen.h
    if not inside_canvas then return false end
    return not self.show_status or not (point.x >= self.status_bounds.x and point.y >= self.status_bounds.y
        and point.x < self.status_bounds.x + self.status_bounds.w
        and point.y < self.status_bounds.y + self.status_bounds.h)
end

function InkCanvas:getDrawingBounds()
    return self.dimen
end

function InkCanvas:_statusWidget()
    local label = self.eraser_mode and _("ERASE") or _("INK")
    if not self.status_widget or self.status_label ~= label then
        if self.status_widget then self.status_widget:free() end
        self.status_label = label
        self.status_widget = TextWidget:new{
            text = label,
            face = Font:getFace("xx_smallinfofont"),
        }
    end
    return self.status_widget
end

function InkCanvas:_paintStatus(bb, x, y)
    if not self.ink_mode or not self.show_status then return end
    local bounds = self.status_bounds
    bb:paintRect(x + bounds.x, y + bounds.y, bounds.w, bounds.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x + bounds.x, y + bounds.y, bounds.w, bounds.h, 2, Blitbuffer.COLOR_BLACK)
    local widget = self:_statusWidget()
    local size = widget:getSize()
    widget:paintTo(bb,
        x + bounds.x + math.floor((bounds.w - size.w) / 2),
        y + bounds.y + math.floor((bounds.h - size.h) / 2))
end

function InkCanvas:paintTo(bb, x, y)
    if self.paint_segment then
        self.renderer:drawSegment(bb, self.paint_segment[1], self.paint_segment[2], x, y)
        self.paint_segment = nil
        return
    end
    if self.service then
        for _, stroke in ipairs(self.service:getRenderableStrokes()) do
            self.renderer:drawStroke(bb, stroke, x, y)
        end
    end
    if self.active_stroke then self.renderer:drawStroke(bb, self.active_stroke, x, y) end
    self:_paintStatus(bb, x, y)
end

function InkCanvas:setInkMode(enabled, eraser_mode)
    local previous_bounds = self.status_bounds:copy()
    self.ink_mode = enabled and true or false
    self.eraser_mode = eraser_mode and true or false
    self.paint_segment = nil
    if self.ink_mode and self.show_status then
        self.ui_manager:setDirty(self, "ui", previous_bounds)
    elseif self.show_status and self.reader_ui then
        self.ui_manager:setDirty(self.reader_ui.dialog, "partial", previous_bounds)
    end
end

function InkCanvas:refreshStatus()
    if self.ink_mode and self.show_status then self.ui_manager:setDirty(self, "ui", self.status_bounds) end
end

function InkCanvas:setActiveStroke(stroke)
    self.active_stroke = stroke
end

function InkCanvas:requestActiveSegment(previous_point, point)
    self.paint_segment = { previous_point, point }
    local region = self.renderer:boundsForPoints(
        self.paint_segment, self.dimen, 1)
    if region then self.ui_manager:setDirty(self, "fast", region) end
    return region
end

function InkCanvas:requestFinalStroke(stroke)
    self.active_stroke = nil
    self.paint_segment = nil
    local region = self.renderer:boundsForStroke(stroke, self.dimen, 2)
    if region then self.ui_manager:setDirty(self, "ui", region) end
    return region
end

function InkCanvas:restoreRegion(region)
    self.active_stroke = nil
    self.paint_segment = nil
    if region and self.reader_ui then
        self.ui_manager:setDirty(self.reader_ui.dialog, "partial", region)
    end
end

function InkCanvas:onCloseWidget()
    if self.status_widget then
        self.status_widget:free()
        self.status_widget = nil
    end
end

return InkCanvas
