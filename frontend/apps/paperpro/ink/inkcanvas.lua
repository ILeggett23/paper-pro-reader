local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local time = require("ui/time")
local _ = require("gettext")

local ACTIVE_REFRESH_HZ = 30

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
    -- Use KOReader's existing 30 Hz interactive maximum. The generic e-ink
    -- low-pan setting targets expensive quality refreshes and would reduce
    -- live A2 ink to 2 Hz, which cannot meet the physical latency requirement.
    self.active_refresh_interval = self.active_refresh_interval
        or 1 / ACTIVE_REFRESH_HZ
    self.paint_segments = {}
    self.pending_region = nil
    self.pending_restore_region = nil
    self.pending_started_at = nil
    self.active_refresh_scheduled = false
    self.active_refresh_requested = false
    self.presentation_outstanding = false
    self.presentation_started_at = nil
    self.deferred_cleanup_region = nil
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
    self.pending_restore_region = nil
    self.pending_started_at = nil
    self.presentation_outstanding = false
    self.presentation_started_at = nil
end

function InkCanvas:_flushActiveRefresh()
    self.active_refresh_scheduled = false
    if self.presentation_outstanding or not self.pending_region
            or not self:_readerSurfaceIsActive() then return false end
    self.active_refresh_requested = true
    self.presentation_outstanding = true
    self.presentation_started_at = time.now()
    if self.metric then self.metric("live_presentations_requested") end
    local target = self.pending_restore_region and self.reader_ui and self.reader_ui.dialog or self
    self.ui_manager:setDirty(target, "a2", self.pending_region)
    return true
end

function InkCanvas:_scheduleActiveRefresh()
    if self.presentation_outstanding or self.active_refresh_scheduled
            or not self.pending_region or not self:_readerSurfaceIsActive() then
        if self.metric and (self.presentation_outstanding or self.active_refresh_scheduled) then
            self.metric("live_presentations_coalesced")
        end
        return false
    end
    self.active_refresh_scheduled = true
    self.ui_manager:scheduleIn(self.active_refresh_interval, self._active_refresh_task)
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
    self.deferred_cleanup_region = nil
    return true
end

function InkCanvas:isPointAllowed(point)
    local inside_canvas = point.x >= self.dimen.x and point.y >= self.dimen.y
        and point.x < self.dimen.x + self.dimen.w
        and point.y < self.dimen.y + self.dimen.h
    if not inside_canvas then return false end
    for _, region in ipairs(self.excluded_regions or {}) do
        if point.x >= region.x and point.y >= region.y
                and point.x < region.x + region.w and point.y < region.y + region.h then
            return false
        end
    end
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
    if self.paint_segments[1] or self.pending_restore_region then
        local region = self.pending_region
        local restoring = self.pending_restore_region ~= nil
        local refresh_requested = self.active_refresh_requested
        self:_cancelActiveRefresh()
        for _, segment in ipairs(self.paint_segments) do
            self.renderer:drawSegment(bb, segment[1], segment[2], x, y)
        end
        if restoring and self.service then
            for _, stroke in ipairs(self.service:getRenderableStrokes()) do
                self.renderer:drawStroke(bb, stroke, x, y)
            end
        end
        self.paint_segments = {}
        self.pending_region = nil
        self.pending_restore_region = nil
        if self.pending_started_at and self.metric then
            self.metric("maximum_pending_region_age_ms",
                time.to_ms(time.now() - self.pending_started_at), true)
        end
        self.pending_started_at = nil
        if self.presentation_started_at then
            local duration = math.max(0, time.to_s(time.now() - self.presentation_started_at))
            self.active_refresh_interval = math.max(1 / ACTIVE_REFRESH_HZ,
                math.min(0.2, duration))
        end
        self.presentation_outstanding = false
        self.presentation_started_at = nil
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
    if self.deferred_cleanup_region then
        local region = self.deferred_cleanup_region
        self.deferred_cleanup_region = nil
        self.ui_manager:nextTick(function() self:requestQualityCleanup(region) end)
    end
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
        self.pending_started_at = self.pending_started_at or time.now()
        self:_scheduleActiveRefresh()
    end
    return region
end

function InkCanvas:finishActiveStroke(stroke)
    self.active_stroke = nil
    return self.renderer:boundsForStroke(stroke, self.dimen, 2)
end

function InkCanvas:requestLiveRestore(region)
    if not region then return false end
    self.pending_restore_region = self.pending_restore_region
        and self.pending_restore_region:combine(region) or region:copy()
    self.pending_region = self.pending_region
        and self.pending_region:combine(region) or region:copy()
    self.pending_started_at = self.pending_started_at or time.now()
    self:_scheduleActiveRefresh()
    return true
end

function InkCanvas:requestQualityCleanup(region)
    if not region then return false end
    if not self:_readerSurfaceIsActive() then
        self.deferred_cleanup_region = self.deferred_cleanup_region
            and self.deferred_cleanup_region:combine(region) or region:copy()
        return false
    end
    if self.deferred_cleanup_region then
        region = region:combine(self.deferred_cleanup_region)
        self.deferred_cleanup_region = nil
    end
    if self.metric then self.metric("quality_cleanups") end
    self.ui_manager:setDirty(self.reader_ui and self.reader_ui.dialog or self, "ui", region)
    return true
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
