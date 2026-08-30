describe("Paper Pro InkStroke", function()
    local InkStroke

    setup(function()
        require("commonrequire")
        InkStroke = require("apps/paperpro/ink/inkstroke")
    end)

    it("preserves ordered points, timing, tool, and optional pressure", function()
        local stroke = InkStroke:new{ id = "one", tool = "pen", max_points = 10 }
        assert.is_true(stroke:addPoint({ x = 10, y = 20, timestamp = 1.1, pressure = 42 },
            { x = 0, y = 0, w = 100, h = 100 }))
        assert.is_true(stroke:addPoint({ x = 15, y = 25, timestamp = 1.2 },
            { x = 0, y = 0, w = 100, h = 100 }))
        assert.is_true(stroke:finish(1.3))
        assert.are.same("pen", stroke.tool)
        assert.are.same(42, stroke.points[1].pressure)
        assert.is_nil(stroke.points[2].pressure)
        assert.are.same(1.1, stroke.started_at)
        assert.are.same(1.3, stroke.ended_at)
        assert.are.same(15, stroke.points[2].x)
    end)

    it("clamps coordinates and rejects invalid or duplicate points", function()
        local stroke = InkStroke:new{ id = "two" }
        assert.is_true(stroke:addPoint({ x = -20, y = 120, timestamp = 1 },
            { x = 0, y = 0, w = 100, h = 100 }))
        assert.are.same(0, stroke.points[1].x)
        assert.are.same(99, stroke.points[1].y)
        assert.is_false(stroke:addPoint({ x = 0, y = 99, timestamp = 2 }))
        assert.is_false(stroke:addPoint({ x = 0/0, y = 2, timestamp = 3 }))
        assert.is_false(stroke:addPoint({ x = 2, y = 2, timestamp = math.huge }))
    end)

    it("bounds point accumulation and rejects an empty stroke", function()
        local stroke = InkStroke:new{ id = "three", max_points = 2 }
        assert.is_false(stroke:finish(1))
        assert.is_true(stroke:addPoint{ x = 1, y = 1, timestamp = 1 })
        assert.is_true(stroke:addPoint{ x = 2, y = 2, timestamp = 2 })
        local added, err = stroke:addPoint{ x = 3, y = 3, timestamp = 3 }
        assert.is_false(added)
        assert.are.same("limit", err)
    end)

    it("round trips detached persistence data", function()
        local stroke = InkStroke:new{
            id = "four", tool = "pen", coordinate_space = "pdf-page-v1",
            anchor = { kind = "fixed_page", document_id = "book", page = 3 },
        }
        stroke:addPoint{ x = 10, y = 20, timestamp = 1 }
        stroke:finish(2)
        local stored = stroke:toTable()
        local restored = InkStroke.fromTable(stored)
        stored.points[1].x = 999
        assert.are.same(10, restored.points[1].x)
        assert.are.same(3, restored.anchor.page)
    end)
end)
