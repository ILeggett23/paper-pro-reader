describe("Paper Pro overlay placement", function()
    local Placement

    setup(function()
        require("commonrequire")
        Placement = require("apps/paperpro/overlays/placement")
    end)

    it("places below an anchor near the top", function()
        local result = Placement.calculate(
            { { x = 200, y = 100, w = 100, h = 30 } },
            { w = 240, h = 120 }, { w = 600, h = 800 }, 12)
        assert.are.same("below", result.placement)
        assert.are.same(142, result.y)
    end)

    it("places above an anchor near the bottom", function()
        local result = Placement.calculate(
            { { x = 200, y = 740, w = 100, h = 30 } },
            { w = 240, h = 160 }, { w = 600, h = 800 }, 12)
        assert.are.same("above", result.placement)
        assert.are.same(568, result.y)
    end)

    it("uses the right side when vertical space is insufficient near the left", function()
        local result = Placement.calculate(
            { { x = 8, y = 85, w = 20, h = 20 } },
            { w = 80, h = 120 }, { w = 300, h = 200 }, 8)
        assert.are.same("right", result.placement)
        assert.are.same(36, result.x)
    end)

    it("uses the left side when vertical space is insufficient near the right", function()
        local result = Placement.calculate(
            { { x = 270, y = 85, w = 20, h = 20 } },
            { w = 80, h = 120 }, { w = 300, h = 200 }, 8)
        assert.are.same("left", result.placement)
        assert.are.same(182, result.x)
    end)

    it("clamps an overlay inside a small viewport", function()
        local result = Placement.calculate(
            { { x = 5, y = 5, w = 10, h = 10 } },
            { w = 110, h = 90 }, { w = 120, h = 100 }, 20)
        assert.is_true(result.x >= 0)
        assert.is_true(result.y >= 0)
        assert.is_true(result.x + result.w <= 120)
        assert.is_true(result.y + result.h <= 100)
    end)

    it("handles a Paper Pro-sized viewport", function()
        local result = Placement.calculate(
            { { x = 600, y = 900, w = 300, h = 70 } },
            { w = 900, h = 500 }, { w = 1620, h = 2160 }, 32)
        assert.are.same("below", result.placement)
        assert.is_true(result.x >= 0 and result.x + result.w <= 1620)
        assert.is_true(result.y >= 0 and result.y + result.h <= 2160)
    end)

    it("centers when there are no anchor boxes", function()
        local result = Placement.calculate({}, { w = 200, h = 100 }, { w = 600, h = 800 }, 12)
        assert.are.same("center", result.placement)
        assert.are.same(200, result.x)
        assert.are.same(350, result.y)
    end)
end)
