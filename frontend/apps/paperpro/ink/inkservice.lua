local InkStroke = require("apps/paperpro/ink/inkstroke")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local time = require("ui/time")

local InkService = {}
InkService.__index = InkService

function InkService:new(options)
    options = options or {}
    assert(options.ui, "InkService requires ReaderUI")
    assert(options.input, "InkService requires Input")
    assert(options.canvas, "InkService requires InkCanvas")
    assert(options.anchor, "InkService requires InkAnchor")
    assert(options.store, "InkService requires InkStore")
    assert(options.renderer, "InkService requires InkRenderer")
    options.ui_manager = options.ui_manager or UIManager
    options.max_history = options.max_history or 50
    options.max_strokes = options.max_strokes or 5000
    options.strokes = {}
    options.undo_stack = {}
    options.redo_stack = {}
    options.sequence = 0
    options.purpose = options.purpose or "document_annotation"
    local service = setmetatable(options, self)
    service.canvas:setService(service)
    return service
end

local function eventTimestamp(slot)
    if type(slot.timev) == "number" then return time.to_number(slot.timev) end
    return os.time()
end

function InkService:_nextId(timestamp)
    self.sequence = self.sequence + 1
    return string.format("ink-%d-%d", math.floor(timestamp * 10000 + 0.5), self.sequence)
end

function InkService:attach()
    if self.attached then return true end
    local strokes, err = self.store:load()
    self.strokes = strokes or {}
    self:_rebuildIndex()
    self.load_error = err
    self.attached = true
    self.canvas:attach()
    return true, err
end

function InkService:_registerCallback()
    if self.input.stylus_callback and self.input.stylus_callback ~= self._stylus_callback then
        return false, "Stylus input is already in use"
    end
    self._stylus_callback = self._stylus_callback or function(input, slot)
        return self:onStylusEvent(input, slot)
    end
    self.input:registerStylusCallback(self._stylus_callback)
    return true
end

function InkService:activate()
    self:attach()
    if self.active then return true end
    local registered, err = self:_registerCallback()
    if not registered then return false, err end
    self.active = true
    self.canvas:setInkMode(true, self.eraser_mode)
    return true
end

function InkService:deactivate()
    if not self.active then return true end
    self:_finishActive(eventTimestamp{})
    if self.input.stylus_callback == self._stylus_callback then
        self.input:unregisterStylusCallback()
    end
    self.active = false
    self.eraser_contact = false
    self.canvas:setInkMode(false, false)
    return true
end

function InkService:toggle()
    if self.active then return self:deactivate() end
    return self:activate()
end

function InkService:setEraserMode(enabled)
    self:_finishActive(eventTimestamp{})
    self.eraser_mode = enabled and true or false
    if self.active then self.canvas:setInkMode(true, self.eraser_mode) end
end

function InkService:_toolName(tool)
    if self.eraser_mode or tool == self.input.TOOL_TYPE_ERASER then return "eraser" end
    if tool == self.input.TOOL_TYPE_HIGHLIGHTER then return "highlighter" end
    return "pen"
end

function InkService:_point(slot)
    return {
        x = slot.x,
        y = slot.y,
        timestamp = eventTimestamp(slot),
        pressure = type(slot.pressure) == "number" and slot.pressure or nil,
    }
end

function InkService:_beginStroke(slot)
    local point = self:_point(slot)
    if not self.canvas:isPointAllowed(point) then return false end
    local stroke = InkStroke:new{
        id = self:_nextId(point.timestamp),
        tool = self:_toolName(slot.tool),
        started_at = point.timestamp,
        coordinate_space = "screen-v1",
    }
    local added = stroke:addPoint(point, self.canvas:getDrawingBounds())
    if not added then return false end
    self.active_stroke = stroke
    self.active_contact_id = slot.id
    self.canvas:setActiveStroke(stroke)
    self.canvas:requestActiveSegment(stroke.points[1], stroke.points[1])
    return true
end

function InkService:_updateStroke(slot)
    if not self.active_stroke then return self:_beginStroke(slot) end
    local point = self:_point(slot)
    if not self.canvas:isPointAllowed(point) then return false end
    local previous = self.active_stroke.points[#self.active_stroke.points]
    local added = self.active_stroke:addPoint(point, self.canvas:getDrawingBounds())
    if added then
        self.canvas:requestActiveSegment(previous, self.active_stroke.points[#self.active_stroke.points])
    end
    return added
end

function InkService:_persist()
    local ok, err = self.store:save(self.strokes)
    self.last_persistence_error = ok and nil or err
    if not ok then logger.err("Paper Pro ink persistence failed:", err) end
    return ok, err
end

function InkService:_pushOperation(action)
    table.insert(self.undo_stack, action)
    while #self.undo_stack > self.max_history do table.remove(self.undo_stack, 1) end
    self.redo_stack = {}
end

function InkService:_finishActive(timestamp)
    local active = self.active_stroke
    if not active then return false end
    active:finish(timestamp)
    local stored, err = self.anchor:finalizeStroke(active)
    self.active_stroke, self.active_contact_id = nil, nil
    self.canvas:setActiveStroke(nil)
    if not stored then
        local region = self.renderer:boundsForStroke(active, self.canvas.dimen, 2)
        self.canvas:restoreRegion(region)
        logger.warn("Paper Pro ink stroke discarded:", err)
        return false, err
    end
    if #self.strokes >= self.max_strokes then
        local region = self.renderer:boundsForStroke(active, self.canvas.dimen, 2)
        self.canvas:restoreRegion(region)
        return false, "stroke_limit"
    end
    table.insert(self.strokes, stored)
    self:_rebuildIndex()
    self:_pushOperation({ kind = "add", records = {{ stroke = stored, index = #self.strokes }} })
    self:_persist()
    self.canvas:requestFinalStroke(self.anchor:projectStroke(stored) or active)
    return true, stored
end

function InkService:onStylusEvent(_, slot)
    if not self.active then return false end
    if type(slot) ~= "table" then return true end
    local is_down = type(slot.id) == "number" and slot.id >= 0
    local tool = self:_toolName(slot.tool)

    if tool == "eraser" then
        if is_down and not self.eraser_contact and type(slot.x) == "number"
                and type(slot.y) == "number" then
            self:_finishActive(eventTimestamp(slot))
            self:eraseAt({ x = slot.x, y = slot.y })
            self.eraser_contact = true
        elseif not is_down then
            self.eraser_contact = false
        end
        return true
    end

    if not is_down then
        if self.active_stroke and type(slot.x) == "number" and type(slot.y) == "number" then
            self:_updateStroke(slot)
        end
        self:_finishActive(eventTimestamp(slot))
        return true
    end
    if self.active_stroke and self.active_contact_id ~= slot.id then
        self:_finishActive(eventTimestamp(slot))
    end
    if type(slot.x) == "number" and type(slot.y) == "number" then
        self:_updateStroke(slot)
    end
    return true
end

function InkService:getRenderableStrokes()
    local visible = {}
    for _, key in ipairs(self.anchor:visibleKeys()) do
        for _, stroke in ipairs(self.stroke_index[key] or {}) do
            local projected = self.anchor:projectStroke(stroke)
            if projected then table.insert(visible, projected) end
        end
    end
    return visible
end

function InkService:_rebuildIndex()
    self.stroke_index = {}
    for _, stroke in ipairs(self.strokes) do
        local key = self.anchor:key(stroke)
        if key then
            self.stroke_index[key] = self.stroke_index[key] or {}
            table.insert(self.stroke_index[key], stroke)
        end
    end
end

function InkService:_recordRegion(records)
    local region
    for _, record in ipairs(records or {}) do
        local projected = self.anchor:projectStroke(record.stroke)
        local bounds = self.renderer:boundsForStroke(projected, self.canvas.dimen, 2)
        if bounds then region = region and region:combine(bounds) or bounds end
    end
    return region
end

function InkService:_removeRecord(record)
    for index, stroke in ipairs(self.strokes) do
        if stroke.id == record.stroke.id then
            record.index = record.index or index
            table.remove(self.strokes, index)
            return true
        end
    end
    return false
end

function InkService:_insertRecord(record)
    for _, stroke in ipairs(self.strokes) do
        if stroke.id == record.stroke.id then return false end
    end
    table.insert(self.strokes, math.min(record.index or (#self.strokes + 1), #self.strokes + 1), record.stroke)
    return true
end

function InkService:_applyOperation(action, undo)
    local region = self:_recordRegion(action.records)
    local insert = action.kind == "delete" and undo or action.kind == "add" and not undo
    for _, record in ipairs(action.records) do
        if insert then self:_insertRecord(record) else self:_removeRecord(record) end
    end
    self:_rebuildIndex()
    self:_persist()
    self.canvas:restoreRegion(region)
end

function InkService:canUndo() return #self.undo_stack > 0 end
function InkService:canRedo() return #self.redo_stack > 0 end

function InkService:undo()
    self:_finishActive(eventTimestamp{})
    local action = table.remove(self.undo_stack)
    if not action then return false end
    self:_applyOperation(action, true)
    table.insert(self.redo_stack, action)
    return true
end

function InkService:redo()
    local action = table.remove(self.redo_stack)
    if not action then return false end
    self:_applyOperation(action, false)
    table.insert(self.undo_stack, action)
    return true
end

function InkService:_deleteRecords(records)
    if #records == 0 then return false end
    local region = self:_recordRegion(records)
    table.sort(records, function(left, right) return left.index > right.index end)
    for _, record in ipairs(records) do self:_removeRecord(record) end
    self:_rebuildIndex()
    self:_pushOperation({ kind = "delete", records = records })
    self:_persist()
    self.canvas:restoreRegion(region)
    return true
end

function InkService:eraseAt(point)
    for index = #self.strokes, 1, -1 do
        local projected = self.anchor:projectStroke(self.strokes[index])
        if projected and self.renderer:hitTest(projected, point) then
            return self:_deleteRecords{{ stroke = self.strokes[index], index = index }}
        end
    end
    return false
end

function InkService:deleteLastVisible()
    for index = #self.strokes, 1, -1 do
        if self.anchor:isVisible(self.strokes[index]) then
            return self:_deleteRecords{{ stroke = self.strokes[index], index = index }}
        end
    end
    return false
end

function InkService:clearVisible()
    local records = {}
    for index, stroke in ipairs(self.strokes) do
        if self.anchor:isVisible(stroke) then
            table.insert(records, { stroke = stroke, index = index })
        end
    end
    return self:_deleteRecords(records)
end

function InkService:rasterizeVisible()
    if not self.rasterizer then return nil, "rasterizer_unavailable" end
    return self.rasterizer:rasterize(self:getRenderableStrokes())
end

function InkService:importScreenStrokes(strokes, conversation_id)
    local records = {}
    for _, source in ipairs(strokes or {}) do
        local raw, raw_err = InkStroke.fromTable(source.toTable and source:toTable() or source)
        if not raw or raw.coordinate_space ~= "screen-v1" then return false, raw_err or "invalid_stroke" end
        raw.id = self:_nextId(raw.started_at or os.time())
        local stored, err = self.anchor:finalizeStroke(raw)
        if not stored then return false, err end
        stored.purpose = "ai_question"
        stored.conversation_id = conversation_id
        table.insert(self.strokes, stored)
        table.insert(records, { stroke = stored, index = #self.strokes })
    end
    if #records == 0 then return false, "empty" end
    self:_rebuildIndex()
    self:_pushOperation({ kind = "add", records = records })
    self:_persist()
    for _, record in ipairs(records) do
        self.canvas:requestFinalStroke(self.anchor:projectStroke(record.stroke))
    end
    return true, records
end

function InkService:onLocationChanged()
    self:_finishActive(eventTimestamp{})
end

function InkService:close()
    self:_finishActive(eventTimestamp{})
    self:deactivate()
    if self.attached then self:_persist() end
    self.canvas:detach()
    self.attached = false
end

return InkService
