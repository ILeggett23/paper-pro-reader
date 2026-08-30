local InkStroke = {}
InkStroke.__index = InkStroke

InkStroke.MAX_POINTS = 10000

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

function InkStroke:new(options)
    options = options or {}
    return setmetatable({
        id = options.id,
        tool = options.tool or "pen",
        started_at = options.started_at,
        ended_at = options.ended_at,
        coordinate_space = options.coordinate_space or "screen-v1",
        anchor = deepCopy(options.anchor),
        points = deepCopy(options.points) or {},
        max_points = options.max_points or self.MAX_POINTS,
    }, self)
end

function InkStroke:addPoint(point, bounds)
    if type(point) ~= "table" or not finite(point.x) or not finite(point.y)
            or not finite(point.timestamp) then
        return false, "invalid"
    end
    if point.pressure ~= nil and not finite(point.pressure) then
        return false, "invalid_pressure"
    end
    if #self.points >= self.max_points then return false, "limit" end

    local x, y = point.x, point.y
    if bounds then
        if not (finite(bounds.x) and finite(bounds.y) and finite(bounds.w)
                and finite(bounds.h) and bounds.w > 0 and bounds.h > 0) then
            return false, "invalid_bounds"
        end
        x = clamp(x, bounds.x, bounds.x + bounds.w - 1)
        y = clamp(y, bounds.y, bounds.y + bounds.h - 1)
    end
    local previous = self.points[#self.points]
    if previous and previous.x == x and previous.y == y then
        return false, "duplicate"
    end
    table.insert(self.points, {
        x = x,
        y = y,
        timestamp = point.timestamp,
        pressure = point.pressure,
    })
    self.started_at = self.started_at or point.timestamp
    return true, self.points[#self.points]
end

function InkStroke:finish(timestamp)
    if #self.points == 0 then return false, "empty" end
    self.ended_at = finite(timestamp) and timestamp
        or self.points[#self.points].timestamp
    return true
end

function InkStroke:toTable()
    return {
        id = self.id,
        tool = self.tool,
        started_at = self.started_at,
        ended_at = self.ended_at,
        coordinate_space = self.coordinate_space,
        anchor = deepCopy(self.anchor),
        points = deepCopy(self.points),
    }
end

function InkStroke.fromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == ""
            or type(data.tool) ~= "string" or type(data.coordinate_space) ~= "string"
            or type(data.points) ~= "table" or #data.points == 0
            or #data.points > InkStroke.MAX_POINTS then
        return nil, "invalid_stroke"
    end
    local stroke = InkStroke:new{
        id = data.id,
        tool = data.tool,
        started_at = data.started_at,
        ended_at = data.ended_at,
        coordinate_space = data.coordinate_space,
        anchor = data.anchor,
    }
    for _, point in ipairs(data.points) do
        local added, err = stroke:addPoint(point)
        if not added and err ~= "duplicate" then return nil, err end
    end
    if #stroke.points == 0 then return nil, "empty" end
    stroke.started_at = finite(data.started_at) and data.started_at
        or stroke.points[1].timestamp
    stroke.ended_at = finite(data.ended_at) and data.ended_at
        or stroke.points[#stroke.points].timestamp
    return stroke
end

InkStroke.deepCopy = deepCopy
InkStroke.isFinite = finite

return InkStroke
