describe("Paper Pro NativeBridge", function()
    local NativeBridge

    setup(function()
        require("commonrequire")
        NativeBridge = require("apps/paperpro/ink/nativebridge")
    end)

    local function makeBridge(messages)
        local transport = {
            messages = messages,
            connect = function(self) self.connected = true; return true end,
            receive = function(self)
                if #self.messages == 0 then return nil, "again" end
                return table.remove(self.messages, 1)
            end,
            close = function(self) self.connected = false end,
        }
        local ink_service = {
            imported = {}, erase_points = {},
            importNativeStroke = function(self, stroke)
                table.insert(self.imported, stroke)
                return true
            end,
            beginNativeErase = function(self) self.erase_started = true; return true end,
            nativeEraseAt = function(self, point) table.insert(self.erase_points, point); return true end,
            finishNativeErase = function(self) self.erase_finished = true; return true end,
        }
        local bridge = NativeBridge:new{
            ink_service = ink_service,
            transport = transport,
            ui_manager = { scheduleIn = function() end, unschedule = function() end },
        }
        return bridge, ink_service
    end

    it("commits a bounded completed stroke only on stroke end", function()
        local bridge, ink_service = makeBridge({
            { type = NativeBridge.TYPE.HELLO, sequence = 1, timestamp_ns = 1, stroke_id = 0 },
            { type = NativeBridge.TYPE.STROKE_BEGIN, sequence = 2,
                timestamp_ns = 1000000000, stroke_id = 7 },
            { type = NativeBridge.TYPE.STROKE_POINTS, sequence = 3,
                timestamp_ns = 2000000000, stroke_id = 7,
                points = {
                    { x = 10, y = 20, timestamp = 1, pressure = 100 },
                    { x = 30, y = 40, timestamp = 2, pressure = 200 },
                } },
            { type = NativeBridge.TYPE.STROKE_END, sequence = 4,
                timestamp_ns = 2000000000, stroke_id = 7 },
        })
        local ok, count = bridge:pollOnce()
        assert.is_true(ok)
        assert.are.same(4, count)
        assert.are.same(1, #ink_service.imported)
        assert.are.same(2, #ink_service.imported[1].points)
        assert.are.same("native-1000000-7", ink_service.imported[1].id)
        assert.are.same(0, bridge.protocol_errors)
    end)

    it("groups a rear-eraser transaction and retains only aggregate diagnostics", function()
        local bridge, ink_service = makeBridge({
            { type = NativeBridge.TYPE.ERASE_BEGIN, sequence = 1,
                timestamp_ns = 1, stroke_id = 8 },
            { type = NativeBridge.TYPE.ERASE_POINTS, sequence = 2,
                timestamp_ns = 2, stroke_id = 8,
                points = {{ x = 10, y = 10, timestamp = 1 }} },
            { type = NativeBridge.TYPE.ERASE_END, sequence = 3,
                timestamp_ns = 3, stroke_id = 8 },
            { type = NativeBridge.TYPE.METRICS, sequence = 4,
                timestamp_ns = 4, stroke_id = 0,
                metrics = { raw_samples_received = 20, dropped_samples = 0 } },
        })
        assert.is_true(bridge:pollOnce())
        assert.is_true(ink_service.erase_started)
        assert.is_true(ink_service.erase_finished)
        assert.are.same(1, #ink_service.erase_points)
        assert.are.same(20, bridge.metrics.raw_samples_received)
        assert.is_nil(bridge:report():match("x="))
    end)

    it("rejects out-of-order messages", function()
        local bridge = makeBridge({
            { type = NativeBridge.TYPE.HELLO, sequence = 2, timestamp_ns = 1, stroke_id = 0 },
            { type = NativeBridge.TYPE.HELLO, sequence = 2, timestamp_ns = 2, stroke_id = 0 },
        })
        assert.is_true(bridge:pollOnce())
        assert.are.same(1, bridge.protocol_errors)
        assert.are.same("out_of_order", bridge.last_error)
    end)
end)
