describe("Paper Pro InkRenderer", function()
    local Blitbuffer, InkRenderer

    setup(function()
        require("commonrequire")
        Blitbuffer = require("ffi/blitbuffer")
        InkRenderer = require("apps/paperpro/ink/inkrenderer")
    end)

    it("computes a bounded region for a small active segment", function()
        local renderer = InkRenderer:new{ width = 4 }
        local region = renderer:boundsForPoints({{ x = 100, y = 100 }, { x = 112, y = 108 }},
            { x = 0, y = 0, w = 1620, h = 2160 }, 1)
        assert.is_true(region.w < 40)
        assert.is_true(region.h < 40)
        assert.is_true(region.w * region.h < 1620 * 2160 / 1000)
    end)

    it("clips dirty bounds to an alternate canvas", function()
        local renderer = InkRenderer:new{ width = 3 }
        local region = renderer:boundsForPoints({{ x = -10, y = -10 }, { x = 5, y = 5 }},
            { x = 0, y = 0, w = 320, h = 480 })
        assert.are.same(0, region.x)
        assert.are.same(0, region.y)
        assert.is_true(region.w < 20 and region.h < 20)
    end)

    it("renders dots and multiple line segments", function()
        local renderer = InkRenderer:new{ width = 3 }
        local bb = Blitbuffer.new(80, 80, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        renderer:drawStroke(bb, { tool = "pen", points = {{ x = 5, y = 5 }} })
        renderer:drawStroke(bb, { tool = "pen", points = {
            { x = 10, y = 20 }, { x = 40, y = 20 }, { x = 50, y = 40 },
        }})
        assert.is_true(bb:getPixel(5, 5):getColor8().a < 255)
        assert.is_true(bb:getPixel(30, 20):getColor8().a < 255)
        bb:free()
    end)

    it("hit-tests whole strokes for erasing", function()
        local renderer = InkRenderer:new{ width = 3 }
        local stroke = { points = {{ x = 10, y = 10 }, { x = 100, y = 10 }} }
        assert.is_true(renderer:hitTest(stroke, { x = 50, y = 14 }, 8))
        assert.is_false(renderer:hitTest(stroke, { x = 50, y = 40 }, 8))
    end)
end)
