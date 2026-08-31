describe("Paper Pro Write Mode toolbar", function()
    local Geom, Time, WriteToolbar

    setup(function()
        require("commonrequire")
        Geom = require("ui/geometry")
        Time = require("ui/time")
        WriteToolbar = require("apps/paperpro/ink/writetoolbar")
    end)

    local function gesture(kind, x, y)
        return { ges = kind, pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }
    end

    it("blocks page and selection gestures in strict Write Mode", function()
        local routed = 0
        local metrics = {}
        local toolbar = WriteToolbar:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 }, policy = "strict",
            route_gesture = function() routed = routed + 1; return true end,
            metric = function(name) metrics[name] = (metrics[name] or 0) + 1 end,
        }
        assert.is_true(toolbar:onGesture(gesture("swipe", 200, 200)))
        assert.is_true(toolbar:onGesture(gesture("hold", 200, 200)))
        assert.are.same(0, routed)
        assert.are.same(2, metrics.touch_suppressed_strict)
        assert.are.same(1, metrics.page_actions_blocked)
        assert.are.same(1, metrics.selection_attempts_suppressed)
    end)

    it("uses Marker contact plus a configurable guard in automatic mode", function()
        local now = Time.s(1)
        local routed = 0
        local toolbar = WriteToolbar:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 },
            policy = "automatic", guard_ms = 500,
            time_source = function() return now end,
            route_gesture = function() routed = routed + 1; return true end,
        }
        assert.is_true(toolbar:onGesture(gesture("swipe", 200, 200)))
        toolbar:onPenContact(true)
        assert.is_true(toolbar:onGesture(gesture("swipe", 200, 200)))
        toolbar:onPenContact(false)
        now = now + Time.ms(400)
        assert.is_true(toolbar:onGesture(gesture("tap", 200, 200)))
        now = now + Time.ms(200)
        assert.is_true(toolbar:onGesture(gesture("swipe", 200, 200)))
        assert.are.same(2, routed)
    end)

    it("enables deliberate navigation without leaking toolbar taps", function()
        local routed = 0
        local toolbar
        toolbar = WriteToolbar:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 }, policy = "strict",
            route_gesture = function() routed = routed + 1; return true end,
            on_navigate = function() toolbar:setMode("navigate") end,
        }
        local button = toolbar.button_bounds.navigate
        assert.is_true(toolbar:onGesture(gesture("tap",
            button.x + math.floor(button.w / 2), button.y + math.floor(button.h / 2))))
        assert.are.same(0, routed)
        assert.are.same("navigate", toolbar.mode)
        assert.is_true(toolbar:onGesture(gesture("swipe", 200, 200)))
        assert.are.same(1, routed)
    end)

    it("accepts toolbar controls from the Marker as one isolated contact", function()
        local undo = 0
        local toolbar = WriteToolbar:new{
            dimen = Geom:new{ x = 0, y = 0, w = 600, h = 800 },
            on_undo = function() undo = undo + 1 end,
        }
        local button = toolbar.button_bounds.undo
        local x, y = button.x + 5, button.y + 5
        assert.is_true(toolbar:onStylusEvent{ id = 4, x = x, y = y })
        assert.is_true(toolbar:onStylusEvent{ id = 4, x = 200, y = 200 })
        assert.is_true(toolbar:onStylusEvent{ id = -1, x = 200, y = 200 })
        assert.are.same(1, undo)
        assert.is_false(toolbar:onStylusEvent{ id = 5, x = 200, y = 200 })
    end)
end)
