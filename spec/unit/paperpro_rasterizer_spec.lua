describe("Paper Pro ink Rasterizer", function()
    local InkRenderer, Rasterizer

    setup(function()
        require("commonrequire")
        InkRenderer = require("apps/paperpro/ink/inkrenderer")
        Rasterizer = require("apps/paperpro/ink/rasterizer")
    end)

    it("rejects empty input", function()
        local raster, err = Rasterizer:new{ renderer = InkRenderer:new() }:rasterize({})
        assert.is_nil(raster)
        assert.are.same("empty", err)
    end)

    it("crops multiple strokes with deterministic padding and aspect ratio", function()
        local rasterizer = Rasterizer:new{ renderer = InkRenderer:new{ width = 4 }, padding = 8 }
        local strokes = {
            { tool = "pen", points = {{ x = 10, y = 20 }, { x = 50, y = 20 }} },
            { tool = "pen", points = {{ x = 50, y = 20 }, { x = 70, y = 60 }} },
        }
        local first = rasterizer:rasterize(strokes)
        local second = rasterizer:rasterize(strokes)
        assert.are.same(first.width, second.width)
        assert.are.same(first.height, second.height)
        assert.is_true(first.width > first.height)
        assert.is_true(first.width < 100 and first.height < 100)
        assert.is_true(first.bb:getPixel(10 - first.bounds.x, 20 - first.bounds.y):getColor8().a < 255)
        first.bb:free()
        second.bb:free()
    end)
end)
