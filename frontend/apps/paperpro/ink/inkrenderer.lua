local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")

local InkRenderer = {}
InkRenderer.__index = InkRenderer

function InkRenderer:new(options)
    options = options or {}
    options.width = options.width or 3
    options.color = options.color or Blitbuffer.COLOR_BLACK
    return setmetatable(options, self)
end

local function segmentDistanceSquared(point, start_point, end_point)
    local dx, dy = end_point.x - start_point.x, end_point.y - start_point.y
    if dx == 0 and dy == 0 then
        local px, py = point.x - start_point.x, point.y - start_point.y
        return px * px + py * py
    end
    local t = ((point.x - start_point.x) * dx + (point.y - start_point.y) * dy)
        / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    local px = point.x - (start_point.x + t * dx)
    local py = point.y - (start_point.y + t * dy)
    return px * px + py * py
end

function InkRenderer:drawSegment(bb, start_point, end_point, offset_x, offset_y)
    offset_x, offset_y = offset_x or 0, offset_y or 0
    local dx, dy = end_point.x - start_point.x, end_point.y - start_point.y
    local distance = math.max(math.abs(dx), math.abs(dy))
    local radius = math.max(1, math.ceil(self.width / 2))
    local steps = math.max(1, math.ceil(distance / math.max(1, radius / 2)))
    for index = 0, steps do
        local ratio = index / steps
        bb:paintCircle(
            math.floor(offset_x + start_point.x + dx * ratio + 0.5),
            math.floor(offset_y + start_point.y + dy * ratio + 0.5),
            radius, self.color, radius)
    end
end

function InkRenderer:drawStroke(bb, stroke, offset_x, offset_y)
    if not (stroke and stroke.points and stroke.points[1]) or stroke.tool == "eraser" then return end
    if #stroke.points == 1 then
        local point = stroke.points[1]
        local radius = math.max(1, math.ceil(self.width / 2))
        bb:paintCircle(math.floor((offset_x or 0) + point.x + 0.5),
            math.floor((offset_y or 0) + point.y + 0.5), radius, self.color, radius)
        return
    end
    for index = 2, #stroke.points do
        self:drawSegment(bb, stroke.points[index - 1], stroke.points[index], offset_x, offset_y)
    end
end

function InkRenderer:boundsForPoints(points, clip_bounds, extra_padding)
    if not (points and points[1]) then return nil end
    local min_x, min_y, max_x, max_y
    for _, point in ipairs(points) do
        min_x = min_x and math.min(min_x, point.x) or point.x
        min_y = min_y and math.min(min_y, point.y) or point.y
        max_x = max_x and math.max(max_x, point.x) or point.x
        max_y = max_y and math.max(max_y, point.y) or point.y
    end
    local padding = math.ceil(self.width / 2) + (extra_padding or 2)
    local left, top = math.floor(min_x - padding), math.floor(min_y - padding)
    local right, bottom = math.ceil(max_x + padding), math.ceil(max_y + padding)
    if clip_bounds then
        left = math.max(left, clip_bounds.x)
        top = math.max(top, clip_bounds.y)
        right = math.min(right, clip_bounds.x + clip_bounds.w - 1)
        bottom = math.min(bottom, clip_bounds.y + clip_bounds.h - 1)
    end
    if right < left or bottom < top then return nil end
    return Geom:new{ x = left, y = top, w = right - left + 1, h = bottom - top + 1 }
end

function InkRenderer:boundsForStroke(stroke, clip_bounds, extra_padding)
    return self:boundsForPoints(stroke and stroke.points, clip_bounds, extra_padding)
end

function InkRenderer:hitTest(stroke, point, threshold)
    if not (stroke and stroke.points and stroke.points[1]) then return false end
    local radius = threshold or math.max(8, self.width * 2)
    local radius_squared = radius * radius
    if #stroke.points == 1 then
        return segmentDistanceSquared(point, stroke.points[1], stroke.points[1]) <= radius_squared
    end
    for index = 2, #stroke.points do
        if segmentDistanceSquared(point, stroke.points[index - 1], stroke.points[index])
                <= radius_squared then
            return true
        end
    end
    return false
end

return InkRenderer
