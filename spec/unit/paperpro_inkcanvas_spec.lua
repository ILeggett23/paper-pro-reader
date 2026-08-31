describe("Paper Pro InkCanvas", function()
    local Blitbuffer, Geom, InkCanvas, InkRenderer

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        Geom = require("ui/geometry")
        InkCanvas = require("apps/paperpro/ink/inkcanvas")
        InkRenderer = require("apps/paperpro/ink/inkrenderer")
    end)

    it("paints the visible Ink Mode badge", function()
        local ui_manager = { show = function() end, close = function() end, setDirty = function() end }
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = InkRenderer:new(), ui_manager = ui_manager,
        }
        canvas:setService{ getRenderableStrokes = function() return {} end }
        canvas:setInkMode(true, false)
        local bb = Blitbuffer.new(320, 480, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        canvas:paintTo(bb, 0, 0)
        assert.is_true(bb:getPixel(canvas.status_bounds.x, canvas.status_bounds.y):getColor8().a < 255)
        bb:free()
    end)

    it("is a paint-only window that cannot block finger gestures", function()
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = InkRenderer:new(),
            ui_manager = { show = function() end, close = function() end, setDirty = function() end },
        }
        assert.is_true(canvas.toast)
    end)

    it("excludes its status badge while keeping a resolution-aware drawing surface", function()
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 1620, h = 2160 },
            renderer = InkRenderer:new(),
            ui_manager = { show = function() end, close = function() end, setDirty = function() end },
        }
        assert.is_true(canvas:isPointAllowed{ x = 100, y = 100 })
        assert.is_false(canvas:isPointAllowed{ x = 1610, y = 10 })
        assert.is_false(canvas:isPointAllowed{ x = -1, y = 20 })
        canvas:setDimensions(Geom:new{ x = 0, y = 0, w = 320, h = 480 })
        assert.are.same(320, canvas:getDrawingBounds().w)
    end)

    it("coalesces active samples into one bounded A2 refresh", function()
        local calls = {}
        local scheduled = {}
        local ui_manager = {
            show = function() end,
            close = function() end,
            scheduleIn = function(_, delay, task)
                table.insert(scheduled, { delay = delay, task = task })
            end,
            unschedule = function() end,
            setDirty = function(_, widget, refresh, region)
                table.insert(calls, { widget = widget, refresh = refresh, region = region })
            end,
        }
        local reader_ui = { dialog = {} }
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 },
            renderer = InkRenderer:new{ width = 3 },
            reader_ui = reader_ui,
            ui_manager = ui_manager,
        }
        local active_region = canvas:requestActiveSegment({ x = 100, y = 100 }, { x = 110, y = 105 })
        canvas:requestActiveSegment({ x = 110, y = 105 }, { x = 120, y = 110 })
        assert.are.same(1, #scheduled)
        assert.is_true(math.abs(scheduled[1].delay - 1 / 30) < 0.0001)
        assert.are.same(0, #calls)
        scheduled[1].task()
        assert.are.same("a2", calls[1].refresh)
        assert.is_equal(canvas, calls[1].widget)
        assert.is_true(active_region.w < 30 and active_region.h < 30)
        canvas:requestFinalStroke{ tool = "pen", points = {{ x = 100, y = 100 }, { x = 110, y = 105 }} }
        assert.are.same("ui", calls[2].refresh)
        canvas:restoreRegion(active_region)
        assert.are.same("partial", calls[3].refresh)
        assert.is_equal(reader_ui.dialog, calls[3].widget)
    end)

    it("retains every active segment received before the next paint", function()
        local drawn = {}
        local scheduled
        local renderer = {
            boundsForPoints = function()
                return Geom:new{ x = 8, y = 8, w = 24, h = 8 }
            end,
            drawSegment = function(_, first, second)
                table.insert(drawn, { first, second })
            end,
        }
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = renderer,
            ui_manager = {
                show = function() end, close = function() end,
                scheduleIn = function(_, _, task) scheduled = task end,
                unschedule = function() end, setDirty = function() end,
            },
        }
        canvas:requestActiveSegment({ x = 10, y = 10 }, { x = 20, y = 10 })
        canvas:requestActiveSegment({ x = 20, y = 10 }, { x = 30, y = 10 })
        assert.are.same(2, #canvas.paint_segments)

        scheduled()
        canvas:paintTo({}, 0, 0)
        assert.are.same(2, #drawn)
        assert.are.same(0, #canvas.paint_segments)
    end)

    it("allows only one live presentation outstanding while retaining new samples", function()
        local scheduled = {}
        local dirty = 0
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = InkRenderer:new(),
            ui_manager = {
                show = function() end, close = function() end,
                scheduleIn = function(_, _, task) table.insert(scheduled, task) end,
                unschedule = function() end,
                setDirty = function() dirty = dirty + 1 end,
            },
        }
        canvas:requestActiveSegment({ x = 10, y = 10 }, { x = 20, y = 10 })
        scheduled[1]()
        assert.is_true(canvas.presentation_outstanding)
        canvas:requestActiveSegment({ x = 20, y = 10 }, { x = 30, y = 10 })
        assert.are.same(1, #scheduled)
        assert.are.same(2, #canvas.paint_segments)
        assert.are.same(1, dirty)
    end)

    it("cancels pending live presentation before final quality cleanup", function()
        local scheduled
        local unscheduled
        local calls = {}
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = InkRenderer:new(),
            ui_manager = {
                show = function() end, close = function() end,
                scheduleIn = function(_, _, task) scheduled = task end,
                unschedule = function(_, task) unscheduled = task end,
                setDirty = function(_, widget, refresh, region)
                    table.insert(calls, { widget = widget, refresh = refresh, region = region })
                end,
            },
        }
        canvas:requestActiveSegment({ x = 10, y = 10 }, { x = 30, y = 10 })
        canvas:requestFinalStroke{
            tool = "pen", points = {{ x = 10, y = 10 }, { x = 30, y = 10 }},
        }
        assert.is_equal(scheduled, unscheduled)
        assert.are.same(0, #canvas.paint_segments)
        assert.is_nil(canvas.pending_region)
        assert.are.same("ui", calls[1].refresh)
    end)

    it("does not paint page ink above a menu or modal", function()
        local active = false
        local strokes_drawn = 0
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = {
                drawStroke = function() strokes_drawn = strokes_drawn + 1 end,
            },
            is_reader_surface_active = function() return active end,
            ui_manager = { show = function() end, close = function() end },
        }
        canvas:setService{ getRenderableStrokes = function()
            return {{ tool = "pen", points = {{ x = 10, y = 10 }} }}
        end }
        canvas:paintTo({}, 0, 0)
        assert.are.same(0, strokes_drawn)
        active = true
        canvas:paintTo({}, 0, 0)
        assert.are.same(1, strokes_drawn)
    end)

    it("excludes the Write Mode toolbar from the drawing surface", function()
        local toolbar = Geom:new{ x = 0, y = 420, w = 320, h = 60 }
        local canvas = InkCanvas:new{
            dimen = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
            renderer = InkRenderer:new(), excluded_regions = { toolbar },
            ui_manager = { show = function() end, close = function() end },
        }
        assert.is_true(canvas:isPointAllowed{ x = 100, y = 300 })
        assert.is_false(canvas:isPointAllowed{ x = 100, y = 450 })
    end)
end)
