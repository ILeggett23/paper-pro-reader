local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local time = require("ui/time")
local _ = require("gettext")

local WriteToolbar = InputContainer:extend{
    name = "PaperProWriteToolbar",
}

local button_keys = { "write", "undo", "eraser", "navigate", "done" }

local function inside(point, bounds)
    return point and point.x and point.y
        and point.x >= bounds.x and point.y >= bounds.y
        and point.x < bounds.x + bounds.w and point.y < bounds.y + bounds.h
end

function WriteToolbar:init()
    self.ui_manager = self.ui_manager or UIManager
    self.time_source = self.time_source or time.now
    self.mode = self.mode or "write"
    self.policy = self.policy or "strict"
    self.guard_ms = self.guard_ms or 500
    self.pen_contact_active = false
    self.guard_until = 0
    self:_layout(self.dimen or Geom:new{ x = 0, y = 0, w = 600, h = 800 })
end

function WriteToolbar:_layout(dimen)
    self.dimen = dimen:copy()
    local height = math.max(80, math.floor(dimen.h * 0.06))
    self.bounds = Geom:new{ x = dimen.x, y = dimen.y + dimen.h - height,
        w = dimen.w, h = height }
    self.button_bounds = {}
    local width = math.floor(self.bounds.w / #button_keys)
    for index, key in ipairs(button_keys) do
        local x = self.bounds.x + (index - 1) * width
        self.button_bounds[key] = Geom:new{ x = x, y = self.bounds.y,
            w = index == #button_keys and self.bounds.x + self.bounds.w - x or width,
            h = self.bounds.h }
    end
end

function WriteToolbar:setDimensions(dimen)
    self:_layout(dimen)
    if self.attached then self:refresh() end
end

function WriteToolbar:setPolicy(policy, guard_ms)
    self.policy = policy == "automatic" and "automatic" or "strict"
    self.guard_ms = guard_ms or self.guard_ms
end

function WriteToolbar:setMode(mode)
    self.mode = mode == "navigate" and "navigate" or "write"
    self:refresh()
end

function WriteToolbar:setEraserMode(enabled)
    self.eraser_mode = enabled and true or false
    self:refresh()
end

function WriteToolbar:onPenContact(active)
    self.pen_contact_active = active and true or false
    if not active then
        self.guard_until = self.time_source() + time.ms(self.guard_ms)
    end
end

function WriteToolbar:_label(key)
    if key == "write" then return self.mode == "write" and _("INK") or _("WRITE") end
    if key == "undo" then return _("UNDO") end
    if key == "eraser" then return self.eraser_mode and _("ERASE ON") or _("ERASE") end
    if key == "navigate" then return self.mode == "navigate" and _("NAV ON") or _("NAVIGATE") end
    return _("DONE")
end

function WriteToolbar:paintTo(bb, x, y)
    local bounds = self.bounds
    bb:paintRect(x + bounds.x, y + bounds.y, bounds.w, bounds.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x + bounds.x, y + bounds.y, bounds.w, bounds.h, 2, Blitbuffer.COLOR_BLACK)
    for _, key in ipairs(button_keys) do
        local button = self.button_bounds[key]
        bb:paintBorder(x + button.x, y + button.y, button.w, button.h, 1, Blitbuffer.COLOR_GRAY)
        local label = TextWidget:new{ text = self:_label(key), face = Font:getFace("xx_smallinfofont") }
        local size = label:getSize()
        label:paintTo(bb, x + button.x + math.floor((button.w - size.w) / 2),
            y + button.y + math.floor((button.h - size.h) / 2))
        label:free()
    end
end

function WriteToolbar:_buttonAt(point)
    for _, key in ipairs(button_keys) do
        if inside(point, self.button_bounds[key]) then return key end
    end
end

function WriteToolbar:_invoke(key)
    if key == "write" and self.on_write then self.on_write()
    elseif key == "undo" and self.on_undo then self.on_undo()
    elseif key == "eraser" and self.on_eraser then self.on_eraser()
    elseif key == "navigate" and self.on_navigate then self.on_navigate()
    elseif key == "done" and self.on_done then self.on_done()
    else return false end
    if self.metric and (key == "write" or key == "navigate" or key == "done") then
        self.metric("deliberate_navigation_actions")
    end
    return true
end

function WriteToolbar:_suppress(reason, gesture)
    if self.metric then
        self.metric(reason == "strict" and "touch_suppressed_strict" or "touch_suppressed_pen_guard")
        if gesture and (gesture.ges == "hold" or gesture.ges == "hold_release"
                or gesture.ges == "hold_pan") then
            self.metric("selection_attempts_suppressed")
        elseif gesture then
            self.metric("page_actions_blocked")
        end
    end
    return true
end

function WriteToolbar:onGesture(gesture)
    if inside(gesture.pos, self.bounds) then
        if gesture.ges == "tap" then self:_invoke(self:_buttonAt(gesture.pos)) end
        return true
    end
    if self.mode == "write" then
        if self.policy == "strict" then return self:_suppress("strict", gesture) end
        if self.pen_contact_active or self.time_source() < self.guard_until then
            return self:_suppress("guard", gesture)
        end
    end
    return self.route_gesture and self.route_gesture(gesture) or false
end

function WriteToolbar:onStylusEvent(slot)
    local down = type(slot.id) == "number" and slot.id >= 0
    local point = type(slot.x) == "number" and type(slot.y) == "number"
        and { x = slot.x, y = slot.y } or nil
    if self.stylus_control_active then
        if not down then self.stylus_control_active = false end
        return true
    end
    if down and inside(point, self.bounds) then
        self.stylus_control_active = true
        self:_invoke(self:_buttonAt(point))
        return true
    end
    return false
end

function WriteToolbar:attach()
    if self.attached then return true end
    self.attached = true
    self.ui_manager:show(self, "ui", self.bounds)
    return true
end

function WriteToolbar:detach()
    if not self.attached then return false end
    self.attached = false
    self.stylus_control_active = false
    self.ui_manager:close(self, "ui", self.bounds)
    return true
end

function WriteToolbar:refresh()
    if self.attached then self.ui_manager:setDirty(self, "ui", self.bounds) end
end

WriteToolbar.inside = inside

return WriteToolbar
