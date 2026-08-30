describe("Paper Pro InkQuestionSession", function()
    local Geom, InkQuestionSession, Time

    setup(function()
        require("commonrequire")
        Geom = require("ui/geometry")
        InkQuestionSession = require("apps/paperpro/ink/inkquestionsession")
        Time = require("ui/time")
    end)

    local function session()
        local bounds = Geom:new{ x = 50, y = 100, w = 400, h = 220 }
        local input = {
            TOOL_TYPE_PEN = 1, TOOL_TYPE_ERASER = 2, TOOL_TYPE_HIGHLIGHTER = 3,
            registerStylusCallback = function(self, callback) self.stylus_callback = callback end,
            unregisterStylusCallback = function(self) self.stylus_callback = nil end,
        }
        local canvas = {
            dimen = bounds:copy(), segments = {}, finals = {},
            setService = function(self, value) self.service = value end,
            attach = function(self) self.attached = true end,
            detach = function(self) self.attached = false end,
            setInkMode = function(self, value) self.ink_mode = value end,
            isPointAllowed = function(_, point)
                return point.x >= bounds.x and point.x < bounds.x + bounds.w
                    and point.y >= bounds.y and point.y < bounds.y + bounds.h
            end,
            getDrawingBounds = function() return bounds end,
            setActiveStroke = function(self, value) self.active_stroke = value end,
            requestActiveSegment = function(self, a, b) table.insert(self.segments, { a, b }) end,
            requestFinalStroke = function(self, value) table.insert(self.finals, value) end,
            restoreRegion = function() end,
        }
        return InkQuestionSession:new{
            ui = { document = { file = "book.epub" } }, bounds = bounds,
            input = input, canvas = canvas,
        }, input, canvas
    end

    local function slot(id, x, y, value)
        return { id = id, x = x, y = y, tool = 1, timev = Time.s(value) }
    end

    it("captures multiple temporary strokes without a document InkStore", function()
        local value, input, canvas = session()
        assert.is_true(value:start())
        input.stylus_callback(input, slot(1, 60, 120, 1))
        input.stylus_callback(input, slot(-1, 100, 150, 2))
        input.stylus_callback(input, slot(2, 150, 170, 3))
        input.stylus_callback(input, slot(-1, 210, 190, 4))
        local strokes = assert(value:submit())
        assert.are.same(2, #strokes)
        assert.are.same("screen-v1", strokes[1].coordinate_space)
        assert.are.same("ai_question", strokes[1].purpose)
        value:close()
        assert.is_false(canvas.attached)
        assert.is_nil(input.stylus_callback)
    end)

    it("supports Undo, Clear, empty rejection, and cleanup", function()
        local value, input = session()
        value:start()
        input.stylus_callback(input, slot(1, 60, 120, 1))
        input.stylus_callback(input, slot(-1, 100, 150, 2))
        assert.is_true(value:undo())
        local strokes, err = value:submit()
        assert.is_nil(strokes)
        assert.are.same("ink_empty", err)
        value:close()
    end)
end)
