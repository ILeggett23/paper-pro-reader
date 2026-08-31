local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen

local InkCanvas = WidgetContainer:extend{
    -- Ink is a paint-only surface. UIManager's toast contract keeps it in the
    -- paint stack while allowing finger gestures to reach the active reader or
    -- dialog below it. Marker events are consumed earlier by InkService's
    -- stylus callback while Ink Mode is active.
    toast = true,
}

function InkCanvas:init()
    self.ui_manager = self.ui_manager or UIManager
    self.dimen = self.dimen or Geom:new{ x = 0, y = 0, w = 600, h = 800 }
    -- Match KOReader's existing interactive pan ceiling: 30 Hz normally, or
    -- 2 Hz only on devices already classified as low-pan-rate.
    self.active_refresh_interval = self.active_refresh_interval
        or 1 / (Screen.low_pan_rate and 2 or 30)
    self.paint_segments = {}
    self.pending_region = nil
    self.active_refresh_scheduled = false
    self.active_refresh_requested = false
    self._active_refresh_task = function() self:_flushActiveRefresh() end
    self.status_bounds = Geom:new{
        x = self.dimen.x + self.dimen.w - math.min(96, math.floor(self.dimen.w * 0.2)),
        y = self.dimen.y,
        w = math.min(96, math.floor(self.dimen.w * 0.2)),
        h = math.min(42, math.floor(self.dimen.h * 0.07)),
    }
    self.show_status = self.show_status ~= false
end

function InkCanvas:_readerSurfaceIsActive()
    return not self.is_reader_surface_active or self.is_reader_surface_active()
end

function InkCanvas:_cancelActiveRefresh()
    if self.active_refresh_scheduled and self.ui_manager.unschedule then
        self.ui_manager:unschedule(self._active_refresh_task)
    end
    self.active_refresh_scheduled = false
    self.active_refresh_requested = false
end

function InkCanvas:_clearPendingSegments()
    self:_cancelActiveRefresh()
    self.paint_segments = {}
    self.pending_region = nil
end

function InkCanvas:_flushActiveRefresh()
    self.active_refresh_scheduled = false
    if not self.pending_region or not self:_readerSurfaceIsActive() then return false end
    self.active_refresh_requested = true
    self.ui_manager:setDirty(self, "a2", self.pending_region)
    return true
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
    self:_clearPendingSegments()
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
    if not self:_readerSurfaceIsActive() then return end
    if self.paint_segments[1] then
        local region = self.pending_region
        local refresh_requested = self.active_refresh_requested
        self:_cancelActiveRefresh()
        for _, segment in ipairs(self.paint_segments) do
            self.renderer:drawSegment(bb, segment[1], segment[2], x, y)
        end
        self.paint_segments = {}
        self.pending_region = nil
        -- A menu/modal may have deferred the scheduled paint. When it closes,
        -- UIManager repaints the uncovered stack; request the accumulated A2
        -- region here so those deferred samples become visible exactly once.
        if region and not refresh_requested then
            self.ui_manager:setDirty(nil, "a2", region)
        end
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
    self:_clearPendingSegments()
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
    local segment = { previous_point, point }
    table.insert(self.paint_segments, segment)
    local region = self.renderer:boundsForPoints(
        segment, self.dimen, 1)
    if region then
        self.pending_region = self.pending_region
            and self.pending_region:combine(region) or region:copy()
        if self:_readerSurfaceIsActive() and not self.active_refresh_scheduled then
            self.active_refresh_scheduled = true
            self.ui_manager:scheduleIn(self.active_refresh_interval, self._active_refresh_task)
        end
    end
    return region
end

function InkCanvas:requestFinalStroke(stroke)
    self.active_stroke = nil
    self:_clearPendingSegments()
    local region = self.renderer:boundsForStroke(stroke, self.dimen, 2)
    if region then self.ui_manager:setDirty(self, "ui", region) end
    return region
end

function InkCanvas:restoreRegion(region)
    self.active_stroke = nil
    self:_clearPendingSegments()
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
