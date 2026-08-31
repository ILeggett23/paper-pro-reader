describe("Paper Pro InkService", function()
    local Geom, InkRenderer, InkService, InkStroke, Time

    setup(function()
        require("commonrequire")
        Geom = require("ui/geometry")
        InkRenderer = require("apps/paperpro/ink/inkrenderer")
        InkService = require("apps/paperpro/ink/inkservice")
        InkStroke = require("apps/paperpro/ink/inkstroke")
        Time = require("ui/time")
    end)

    local function makeService()
        local input = {
            TOOL_TYPE_FINGER = 0, TOOL_TYPE_PEN = 1, TOOL_TYPE_ERASER = 2,
            TOOL_TYPE_HIGHLIGHTER = 3,
            registerStylusCallback = function(self, callback) self.stylus_callback = callback end,
            unregisterStylusCallback = function(self) self.stylus_callback = nil end,
        }
        local canvas = {
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 },
            segments = {}, finals = {}, completed = {}, restores = {}, cleanups = {},
            setService = function(self, service) self.service = service end,
            attach = function(self) self.attached = true end,
            detach = function(self) self.attached = false end,
            setInkMode = function(self, enabled, eraser) self.mode, self.eraser = enabled, eraser end,
            isPointAllowed = function(_, point)
                return point.x >= 0 and point.x < 600 and point.y >= 0 and point.y < 800
            end,
            getDrawingBounds = function(self) return self.dimen end,
            setActiveStroke = function(self, stroke) self.active_stroke = stroke end,
            requestActiveSegment = function(self, previous, point)
                table.insert(self.segments, { previous, point })
            end,
            finishActiveStroke = function(self, stroke)
                table.insert(self.completed, stroke)
                return Geom:new{ x = 0, y = 0, w = 100, h = 100 }
            end,
            requestFinalStroke = function(self, stroke)
                table.insert(self.finals, stroke)
                return Geom:new{ x = 0, y = 0, w = 100, h = 100 }
            end,
            requestLiveRestore = function(self, region) table.insert(self.restores, region) end,
            requestQualityCleanup = function(self, region) table.insert(self.cleanups, region) end,
            restoreRegion = function(self, region) table.insert(self.restores, region) end,
        }
        local current_page = 1
        local anchor = {}
        anchor.finalizeStroke = function(_, active)
            local stored = InkStroke:new{
                id = active.id, tool = active.tool, started_at = active.started_at,
                coordinate_space = "pdf-page-v1",
                anchor = { kind = "fixed_page", document_id = "book.pdf", page = current_page },
            }
            for _, point in ipairs(active.points) do stored:addPoint(point) end
            stored:finish(active.ended_at)
            return stored
        end
        anchor.isVisible = function(_, stroke) return stroke.anchor.page == current_page end
        anchor.key = function(_, stroke) return "pdf:" .. tostring(stroke.anchor.page) end
        anchor.visibleKeys = function() return { "pdf:" .. tostring(current_page) } end
        anchor.projectStroke = function(self, stroke)
            if not self:isVisible(stroke) then return nil end
            return { id = stroke.id, tool = stroke.tool, points = InkStroke.deepCopy(stroke.points) }
        end
        local store = {
            load = function(self) return self.loaded or {} end,
            save = function(self, strokes)
                self.saved = strokes
                self.save_count = (self.save_count or 0) + 1
                return true
            end,
        }
        local renderer = InkRenderer:new{ width = 3 }
        local scheduled = {}
        local ui_manager = {
            show = function() end, close = function() end,
            scheduleIn = function(_, delay, task) scheduled[task] = delay end,
            unschedule = function(_, task) scheduled[task] = nil end,
        }
        local service = InkService:new{
            ui = {}, input = input, canvas = canvas, anchor = anchor,
            store = store, renderer = renderer,
            ui_manager = ui_manager,
        }
        local function runScheduled()
            local tasks = {}
            for task in pairs(scheduled) do table.insert(tasks, task) end
            for _, task in ipairs(tasks) do scheduled[task] = nil; task() end
        end
        return service, input, canvas, store,
            function(page) current_page = page; service:invalidateVisibleCache() end,
            runScheduled
    end

    local function slot(id, x, y, timestamp, pressure, tool)
        return {
            slot = 4, id = id, x = x, y = y,
            timev = Time.s(timestamp), pressure = pressure, tool = tool or 1,
        }
    end

    it("activates and removes only its own stylus callback", function()
        local service, input, canvas = makeService()
        assert.is_true(service:activate())
        assert.is_function(input.stylus_callback)
        assert.is_true(canvas.mode)
        assert.is_true(service:deactivate())
        assert.is_nil(input.stylus_callback)
        assert.is_false(canvas.mode)
        assert.is_false(service:onStylusEvent(input, slot(1, 1, 1, 1)))
    end)

    it("routes pen down/move/up into separate ordered raw strokes", function()
        local service, input, canvas, store, _, runScheduled = makeService()
        service:activate()
        assert.is_true(input.stylus_callback(input, slot(7, 10, 20, 1, 20)))
        input.stylus_callback(input, slot(7, 20, 30, 2, 30))
        input.stylus_callback(input, slot(-1, 30, 40, 3, 0))
        assert.are.same(1, #service.strokes)
        assert.are.same(3, #service.strokes[1].points)
        assert.are.same(20, service.strokes[1].points[1].pressure)
        assert.are.same(30, service.strokes[1].points[2].pressure)
        assert.are.same(1, #canvas.completed)
        assert.is_nil(store.save_count)

        input.stylus_callback(input, slot(8, 50, 60, 4, nil))
        input.stylus_callback(input, slot(-1, 60, 70, 5, nil))
        assert.are.same(2, #service.strokes)
        assert.is_nil(service.strokes[2].points[1].pressure)
        runScheduled()
        assert.are.same(1, store.save_count)
        assert.are.same(1, #canvas.cleanups)
    end)

    it("undoes, redoes, erases, and clears whole strokes", function()
        local service, input, canvas = makeService()
        service:activate()
        input.stylus_callback(input, slot(1, 10, 10, 1))
        input.stylus_callback(input, slot(-1, 50, 10, 2))
        input.stylus_callback(input, slot(2, 100, 100, 3))
        input.stylus_callback(input, slot(-1, 130, 100, 4))
        assert.are.same(2, #service.strokes)
        assert.is_true(service:undo())
        assert.are.same(1, #service.strokes)
        assert.is_true(service:redo())
        assert.are.same(2, #service.strokes)
        assert.is_true(service:eraseAt{ x = 110, y = 103 })
        assert.are.same(1, #service.strokes)
        assert.is_true(service:clearVisible())
        assert.are.same(0, #service.strokes)
        assert.is_true(#canvas.restores >= 3)
    end)

    it("routes a source-visible eraser tool to whole-stroke deletion", function()
        local service, input = makeService()
        service:activate()
        input.stylus_callback(input, slot(1, 10, 10, 1))
        input.stylus_callback(input, slot(-1, 80, 10, 2))
        assert.are.same(1, #service.strokes)
        input.stylus_callback(input, slot(3, 40, 12, 3, nil, input.TOOL_TYPE_ERASER))
        input.stylus_callback(input, slot(-1, 40, 12, 4, nil, input.TOOL_TYPE_ERASER))
        assert.are.same(0, #service.strokes)
    end)

    it("continuously erases multiple strokes as one undo operation", function()
        local service, input = makeService()
        service:activate()
        input.stylus_callback(input, slot(1, 10, 10, 1))
        input.stylus_callback(input, slot(-1, 40, 10, 2))
        input.stylus_callback(input, slot(2, 100, 100, 3))
        input.stylus_callback(input, slot(-1, 130, 100, 4))
        input.stylus_callback(input, slot(3, 200, 200, 5))
        input.stylus_callback(input, slot(-1, 230, 200, 6))
        input.stylus_callback(input, slot(4, 20, 10, 7, nil, input.TOOL_TYPE_ERASER))
        input.stylus_callback(input, slot(4, 115, 100, 8, nil, input.TOOL_TYPE_ERASER))
        input.stylus_callback(input, slot(-1, 115, 100, 9, nil, input.TOOL_TYPE_ERASER))
        assert.are.same(1, #service.strokes)
        assert.are.same("delete", service.undo_stack[#service.undo_stack].kind)
        assert.are.same(2, #service.undo_stack[#service.undo_stack].records)
        assert.is_true(service:undo())
        assert.are.same(3, #service.strokes)
    end)

    it("renders only strokes for the current page", function()
        local service, input, _, _, setPage = makeService()
        service:activate()
        input.stylus_callback(input, slot(1, 10, 10, 1))
        input.stylus_callback(input, slot(-1, 20, 20, 2))
        setPage(2)
        input.stylus_callback(input, slot(2, 30, 30, 3))
        input.stylus_callback(input, slot(-1, 40, 40, 4))
        assert.are.same(1, #service:getRenderableStrokes())
        setPage(1)
        assert.are.same(1, #service:getRenderableStrokes())
    end)

    it("finalizes and persists before document-close cleanup", function()
        local service, input, canvas, store = makeService()
        service:activate()
        input.stylus_callback(input, slot(1, 10, 10, 1))
        service:close()
        assert.are.same(1, #service.strokes)
        assert.is_nil(input.stylus_callback)
        assert.is_false(canvas.attached)
        assert.is_true(store.save_count >= 1)
    end)

    it("keeps an explicit AI question in document ink through the existing authority", function()
        local service = makeService()
        local raw = InkStroke:new{
            id = "question", tool = "pen", coordinate_space = "screen-v1",
        }
        raw:addPoint{ x = 20, y = 30, timestamp = 1 }
        raw:addPoint{ x = 80, y = 60, timestamp = 2 }
        raw:finish(2)
        assert.is_true(service:importScreenStrokes({ raw:toTable() }, "conversation-1"))
        assert.are.same(1, #service.strokes)
        assert.are.same("ai_question", service.strokes[1].purpose)
        assert.are.same("conversation-1", service.strokes[1].conversation_id)
        assert.is_true(service:undo())
        assert.are.same(0, #service.strokes)
    end)

    it("persists completed native strokes without scheduling a live repaint", function()
        local service, _, canvas, store = makeService()
        local ok = service:importNativeStroke{
            id = "native-1-1", started_at = 1, ended_at = 2,
            points = {
                { x = 10, y = 20, timestamp = 1, pressure = 100 },
                { x = 30, y = 40, timestamp = 2, pressure = 200 },
            },
        }
        assert.is_true(ok)
        assert.are.same(1, #service.strokes)
        assert.are.same(2, #service.strokes[1].points)
        assert.are.same(1, store.save_count)
        assert.are.same(0, #canvas.segments)
        assert.are.same(0, #canvas.finals)
        assert.are.same(0, #canvas.cleanups)
    end)

    it("groups native rear-eraser points without per-point KOReader repaint", function()
        local service, _, canvas, store = makeService()
        assert.is_true(service:importNativeStroke{
            id = "native-1-1", started_at = 1, ended_at = 2,
            points = {
                { x = 10, y = 10, timestamp = 1 },
                { x = 50, y = 10, timestamp = 2 },
            },
        })
        assert.is_true(service:beginNativeErase())
        assert.is_true(service:nativeEraseAt{ x = 30, y = 12 })
        assert.is_true(service:finishNativeErase())
        assert.are.same(0, #service.strokes)
        assert.are.same(2, store.save_count)
        assert.are.same(0, #canvas.restores)
        assert.are.same(0, #canvas.cleanups)
        assert.are.same("delete", service.undo_stack[#service.undo_stack].kind)
    end)
end)
