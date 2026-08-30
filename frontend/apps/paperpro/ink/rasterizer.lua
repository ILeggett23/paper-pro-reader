local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")

local Rasterizer = {}
Rasterizer.__index = Rasterizer

function Rasterizer:new(options)
    options = options or {}
    assert(options.renderer, "Rasterizer requires InkRenderer")
    options.padding = options.padding or 8
    return setmetatable(options, self)
end

function Rasterizer:_bounds(strokes)
    local bounds
    for _, stroke in ipairs(strokes or {}) do
        local stroke_bounds = self.renderer:boundsForStroke(stroke, nil, self.padding)
        if stroke_bounds then bounds = bounds and bounds:combine(stroke_bounds) or stroke_bounds end
    end
    return bounds
end

function Rasterizer:rasterize(strokes)
    local bounds = self:_bounds(strokes)
    if not bounds or bounds.w <= 0 or bounds.h <= 0 then return nil, "empty" end
    local bb = Blitbuffer.new(bounds.w, bounds.h, Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    for _, stroke in ipairs(strokes) do
        self.renderer:drawStroke(bb, stroke, -bounds.x, -bounds.y)
    end
    return {
        bb = bb,
        bounds = Geom:new{ x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h },
        width = bounds.w,
        height = bounds.h,
        mime_type = "image/png",
    }
end

function Rasterizer:writePNG(strokes, path)
    local raster, err = self:rasterize(strokes)
    if not raster then return false, err end
    local ok, write_err = pcall(raster.bb.writePNG, raster.bb, path)
    raster.bb:free()
    return ok, write_err
end

return Rasterizer
