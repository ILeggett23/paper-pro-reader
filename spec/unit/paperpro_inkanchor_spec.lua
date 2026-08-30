describe("Paper Pro InkAnchor", function()
    local Geom, InkAnchor, InkStroke

    setup(function()
        require("commonrequire")
        Geom = require("ui/geometry")
        InkAnchor = require("apps/paperpro/ink/inkanchor")
        InkStroke = require("apps/paperpro/ink/inkstroke")
    end)

    local function activeStroke(points)
        local stroke = InkStroke:new{ id = "stroke", tool = "pen", coordinate_space = "screen-v1" }
        for index, point in ipairs(points) do
            stroke:addPoint{ x = point.x, y = point.y, timestamp = index }
        end
        stroke:finish(#points + 1)
        return stroke
    end

    it("round trips PDF screen points through page coordinates", function()
        local ui = { paging = {}, document = { file = "/books/test.pdf" }, view = {} }
        ui.view.screenToPageTransform = function(_, point)
            return { x = (point.x - 10) / 2, y = (point.y - 20) / 2, page = 4 }
        end
        ui.view.pageToScreenTransform = function(_, page, point)
            if page ~= 4 then return nil end
            return Geom:new{ x = point.x * 2 + 10, y = point.y * 2 + 20, w = 2, h = 2 }
        end
        ui.view.getCurrentPageList = function() return { 4 } end
        local anchor = InkAnchor:new{ ui = ui, bounds = Geom:new{ x = 0, y = 0, w = 1620, h = 2160 } }
        local stored = anchor:finalizeStroke(activeStroke{{ x = 110, y = 220 }, { x = 210, y = 320 }})
        assert.is_truthy(stored)
        assert.are.same("pdf-page-v1", stored.coordinate_space)
        assert.are.same(4, stored.anchor.page)
        assert.are.same(50, stored.points[1].x)
        local projected = anchor:projectStroke(stored)
        assert.are.same(110, projected.points[1].x)
        assert.are.same(320, projected.points[2].y)
        ui.view.getCurrentPageList = function() return { 5 } end
        assert.is_nil(anchor:projectStroke(stored))
    end)

    it("restores EPUB ink only at the same XPointer and layout", function()
        local current_xpointer = "/body/p[1].0"
        local ui = {
            rolling = {},
            document = {
                file = "/books/test.epub",
                configurable = { line_spacing = 100, h_page_margins = { 10, 10 } },
                getXPointer = function() return current_xpointer end,
            },
            view = { state = { rotation = 0 }, view_mode = "page" },
            font = { font_face = "Noto Serif", configurable = { font_size = 22 } },
            getCurrentPage = function() return 7 end,
        }
        local bounds = Geom:new{ x = 0, y = 0, w = 600, h = 800 }
        local anchor = InkAnchor:new{ ui = ui, bounds = bounds }
        local stored = anchor:finalizeStroke(activeStroke{{ x = 60, y = 80 }, { x = 300, y = 400 }})
        assert.is_truthy(stored)
        assert.are.same("epub-layout-v1", stored.coordinate_space)
        assert.are.same(0.1, stored.points[1].x)
        assert.are.same(0.5, stored.points[2].y)
        assert.is_truthy(anchor:projectStroke(stored))

        ui.font.configurable.font_size = 24
        assert.is_nil(anchor:projectStroke(stored))
        ui.font.configurable.font_size = 22
        current_xpointer = "/body/p[2].0"
        assert.is_nil(anchor:projectStroke(stored))
    end)

    it("supports an alternate viewport without assuming Paper Pro dimensions", function()
        local ui = {
            rolling = {},
            document = {
                file = "book.epub", configurable = {},
                getXPointer = function() return "xp" end,
            },
            view = { state = { rotation = 0 }, view_mode = "page" },
            getCurrentPage = function() return 1 end,
        }
        local anchor = InkAnchor:new{
            ui = ui, bounds = Geom:new{ x = 0, y = 0, w = 320, h = 480 },
        }
        local stored = anchor:finalizeStroke(activeStroke{{ x = 319, y = 479 }})
        assert.is_truthy(stored)
        local projected = anchor:projectStroke(stored)
        assert.are.same(319, projected.points[1].x)
        assert.are.same(479, projected.points[1].y)
    end)
end)
