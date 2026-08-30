local Device = require("device")
local InkCanvas = require("apps/paperpro/ink/inkcanvas")
local InkRenderer = require("apps/paperpro/ink/inkrenderer")
local InkService = require("apps/paperpro/ink/inkservice")
local InkStroke = require("apps/paperpro/ink/inkstroke")
local Rasterizer = require("apps/paperpro/ink/rasterizer")

local InkQuestionSession = {}
InkQuestionSession.__index = InkQuestionSession

local TemporaryAnchor = {}
TemporaryAnchor.__index = TemporaryAnchor

function TemporaryAnchor:new(options) return setmetatable(options or {}, self) end
function TemporaryAnchor:finalizeStroke(active)
    local stored = InkStroke:new{
        id = active.id, tool = active.tool, started_at = active.started_at,
        ended_at = active.ended_at, coordinate_space = "screen-v1",
        anchor = { kind = "ai_question", document_id = self.document_id },
        purpose = "ai_question",
    }
    for _, point in ipairs(active.points) do stored:addPoint(point, self.bounds) end
    stored:finish(active.ended_at)
    return stored
end
function TemporaryAnchor:isVisible() return true end
function TemporaryAnchor:projectStroke(stroke) return stroke end
function TemporaryAnchor:key() return "session" end
function TemporaryAnchor:visibleKeys() return { "session" } end

local MemoryStore = {}
MemoryStore.__index = MemoryStore
function MemoryStore:new() return setmetatable({ strokes = {} }, self) end
function MemoryStore:load() return {} end
function MemoryStore:save(strokes) return strokes and true or false end

function InkQuestionSession:new(options)
    options = options or {}
    assert(options.ui and options.bounds, "InkQuestionSession requires ReaderUI and bounds")
    local renderer = options.renderer or InkRenderer:new{ width = 3 }
    local canvas = options.canvas or InkCanvas:new{
        dimen = options.bounds:copy(), renderer = renderer,
        reader_ui = options.ui, show_status = false,
    }
    local rasterizer = options.rasterizer or Rasterizer:new{ renderer = renderer }
    local service = options.service or InkService:new{
        ui = options.ui, input = options.input or Device.input,
        canvas = canvas,
        anchor = TemporaryAnchor:new{
            document_id = options.ui.document.file, bounds = options.bounds:copy(),
        },
        store = MemoryStore:new(), renderer = renderer, rasterizer = rasterizer,
        purpose = "ai_question", max_strokes = 32, max_history = 32,
    }
    options.renderer, options.canvas, options.rasterizer, options.service =
        renderer, canvas, rasterizer, service
    return setmetatable(options, self)
end

function InkQuestionSession:start()
    if self.started then return true end
    local ok, err = self.service:activate()
    self.started = ok and true or false
    return ok, err
end

function InkQuestionSession:undo() return self.service:undo() end
function InkQuestionSession:clear() return self.service:clearVisible() end
function InkQuestionSession:hasInk() return #self.service.strokes > 0 or self.service.active_stroke ~= nil end

function InkQuestionSession:submit()
    self.service:deactivate()
    if #self.service.strokes == 0 then return nil, "ink_empty" end
    local strokes = {}
    for _, stroke in ipairs(self.service.strokes) do table.insert(strokes, stroke:toTable()) end
    return strokes
end

function InkQuestionSession:close()
    if not self.service then return false end
    self.service:close()
    self.started = false
    return true
end

return InkQuestionSession
