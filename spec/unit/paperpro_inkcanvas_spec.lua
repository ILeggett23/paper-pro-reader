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

    it("requests fast active, quality final, and bounded restore regions", function()
        local calls = {}
        local ui_manager = {
            show = function() end,
            close = function() end,
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
        assert.are.same("fast", calls[1].refresh)
        assert.is_true(active_region.w < 30 and active_region.h < 30)
        canvas:requestFinalStroke{ tool = "pen", points = {{ x = 100, y = 100 }, { x = 110, y = 105 }} }
        assert.are.same("ui", calls[2].refresh)
        canvas:restoreRegion(active_region)
        assert.are.same("partial", calls[3].refresh)
        assert.is_equal(reader_ui.dialog, calls[3].widget)
    end)
end)
