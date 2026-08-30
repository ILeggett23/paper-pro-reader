local Geom = require("ui/geometry")
local InkStroke = require("apps/paperpro/ink/inkstroke")

local InkAnchor = {}
InkAnchor.__index = InkAnchor

function InkAnchor:new(options)
    options = options or {}
    assert(options.ui, "InkAnchor requires ReaderUI")
    assert(options.bounds, "InkAnchor requires canvas bounds")
    return setmetatable(options, self)
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function call(object, method, ...)
    if not (object and object[method]) then return nil end
    local ok, value = pcall(object[method], object, ...)
    return ok and value or nil
end

function InkAnchor:_layoutSignature()
    local configurable = self.ui.document.configurable or {}
    local font = self.ui.font and self.ui.font.configurable or {}
    return {
        screen_w = self.bounds.w,
        screen_h = self.bounds.h,
        rotation = self.ui.view.state and self.ui.view.state.rotation,
        view_mode = self.ui.view.view_mode,
        font_face = self.ui.font and self.ui.font.font_face,
        font_size = font.font_size or configurable.font_size,
        line_spacing = configurable.line_spacing,
        h_page_margins = InkStroke.deepCopy(configurable.h_page_margins),
        t_page_margin = configurable.t_page_margin,
        b_page_margin = configurable.b_page_margin,
    }
end

function InkAnchor:create(screen_point)
    local document_id = self.ui.document.file
    if self.ui.paging then
        local page_point = self.ui.view:screenToPageTransform(
            Geom:new{ x = screen_point.x, y = screen_point.y })
        if not (page_point and type(page_point.page) == "number") then return nil end
        return {
            kind = "fixed_page",
            document_id = document_id,
            page = page_point.page,
        }, "pdf-page-v1"
    elseif self.ui.rolling then
        local xpointer = call(self.ui.document, "getXPointer")
        if type(xpointer) ~= "string" or xpointer == "" then return nil end
        return {
            kind = "epub_layout",
            document_id = document_id,
            xpointer = xpointer,
            page = call(self.ui, "getCurrentPage"),
            layout = self:_layoutSignature(),
        }, "epub-layout-v1"
    end
end

function InkAnchor:finalizeStroke(active_stroke)
    local first = active_stroke and active_stroke.points[1]
    if not first then return nil, "empty" end
    local anchor, coordinate_space = self:create(first)
    if not anchor then return nil, "anchor_unavailable" end
    local stored = InkStroke:new{
        id = active_stroke.id,
        tool = active_stroke.tool,
        started_at = active_stroke.started_at,
        ended_at = active_stroke.ended_at,
        coordinate_space = coordinate_space,
        anchor = anchor,
    }
    for _, point in ipairs(active_stroke.points) do
        local converted
        if anchor.kind == "fixed_page" then
            converted = self.ui.view:screenToPageTransform(
                Geom:new{ x = point.x, y = point.y })
            if not converted or converted.page ~= anchor.page then
                return nil, "page_changed"
            end
        else
            converted = {
                x = (point.x - self.bounds.x) / self.bounds.w,
                y = (point.y - self.bounds.y) / self.bounds.h,
            }
        end
        local added, err = stored:addPoint{
            x = converted.x,
            y = converted.y,
            timestamp = point.timestamp,
            pressure = point.pressure,
        }
        if not added and err ~= "duplicate" then return nil, err end
    end
    if #stored.points == 0 then return nil, "empty" end
    stored:finish(active_stroke.ended_at)
    return stored
end

function InkAnchor:_pageVisible(page)
    for _, visible_page in ipairs(self.ui.view:getCurrentPageList() or {}) do
        if visible_page == page then return true end
    end
    return false
end

function InkAnchor:isVisible(stroke)
    local anchor = stroke and stroke.anchor
    if type(anchor) ~= "table" or anchor.document_id ~= self.ui.document.file then return false end
    if anchor.kind == "fixed_page" then
        return stroke.coordinate_space == "pdf-page-v1"
            and type(anchor.page) == "number" and self:_pageVisible(anchor.page)
    elseif anchor.kind == "epub_layout" then
        return stroke.coordinate_space == "epub-layout-v1"
            and type(anchor.xpointer) == "string"
            and anchor.xpointer == call(self.ui.document, "getXPointer")
            and equal(anchor.layout, self:_layoutSignature())
    end
    return false
end

function InkAnchor:projectStroke(stroke)
    if not self:isVisible(stroke) then return nil end
    local projected = {
        id = stroke.id,
        tool = stroke.tool,
        points = {},
    }
    for _, point in ipairs(stroke.points) do
        local screen_point
        if stroke.anchor.kind == "fixed_page" then
            screen_point = self.ui.view:pageToScreenTransform(stroke.anchor.page,
                Geom:new{ x = point.x, y = point.y, w = 1, h = 1 })
        else
            screen_point = {
                x = self.bounds.x + point.x * self.bounds.w,
                y = self.bounds.y + point.y * self.bounds.h,
            }
        end
        if not screen_point then return nil end
        table.insert(projected.points, {
            x = screen_point.x,
            y = screen_point.y,
            timestamp = point.timestamp,
            pressure = point.pressure,
        })
    end
    return projected
end

function InkAnchor:key(stroke)
    local anchor = stroke and stroke.anchor
    if not anchor then return nil end
    if anchor.kind == "fixed_page" then return "pdf:" .. tostring(anchor.page) end
    if anchor.kind == "epub_layout" then return "epub:" .. tostring(anchor.xpointer) end
end

function InkAnchor:visibleKeys()
    local keys = {}
    if self.ui.paging then
        for _, page in ipairs(self.ui.view:getCurrentPageList() or {}) do
            table.insert(keys, "pdf:" .. tostring(page))
        end
    elseif self.ui.rolling then
        local xpointer = call(self.ui.document, "getXPointer")
        if xpointer then table.insert(keys, "epub:" .. tostring(xpointer)) end
    end
    return keys
end

InkAnchor.equal = equal

return InkAnchor
