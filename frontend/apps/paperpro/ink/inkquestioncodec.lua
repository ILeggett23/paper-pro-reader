local AIRequest = require("apps/paperpro/services/airequest")
local InkRenderer = require("apps/paperpro/ink/inkrenderer")
local Rasterizer = require("apps/paperpro/ink/rasterizer")
local mime = require("mime")
local util = require("util")

local InkQuestionCodec = {}
InkQuestionCodec.__index = InkQuestionCodec

InkQuestionCodec.MIME_TYPE = "image/png"
InkQuestionCodec.MAX_IMAGE_BYTES = 256 * 1024
InkQuestionCodec.MAX_WIDTH = 1200
InkQuestionCodec.MAX_HEIGHT = 512
InkQuestionCodec.MAX_PIXELS = 600000

function InkQuestionCodec:new(options)
    options = options or {}
    options.renderer = options.renderer or InkRenderer:new{ width = 3 }
    options.rasterizer = options.rasterizer or Rasterizer:new{ renderer = options.renderer }
    return setmetatable(options, self)
end

function InkQuestionCodec:encode(strokes)
    local valid, err = AIRequest.validateInk(strokes)
    if not valid then return nil, err end
    local raster, raster_err = self.rasterizer:rasterize(strokes)
    if not raster then return nil, raster_err end
    if raster.width > self.MAX_WIDTH or raster.height > self.MAX_HEIGHT
            or raster.width * raster.height > self.MAX_PIXELS then
        raster.bb:free()
        return nil, "image_dimensions"
    end
    local path = os.tmpname() .. "-paperpro-question.png"
    local wrote, write_err = pcall(raster.bb.writePNG, raster.bb, path)
    raster.bb:free()
    if not wrote then return nil, write_err or "image_encode" end
    local data = util.readFromFile(path, "rb")
    os.remove(path)
    if not data or #data == 0 then return nil, "image_encode" end
    if #data > self.MAX_IMAGE_BYTES then return nil, "image_too_large" end
    return {
        mime_type = self.MIME_TYPE,
        bytes = #data,
        width = raster.width,
        height = raster.height,
        data_base64 = mime.b64(data),
    }
end

return InkQuestionCodec
