describe("Paper Pro diagnostics", function()
    local Diagnostics, JSON, util
    local paths = {}

    setup(function()
        require("commonrequire")
        Diagnostics = require("apps/paperpro/services/diagnostics")
        JSON = require("rapidjson")
        util = require("util")
    end)

    teardown(function()
        for _, path in ipairs(paths) do os.remove(path) end
    end)

    it("records only safe lifecycle metadata and exposes RC identity", function()
        local values = {}
        local settings = {
            isTrue = function(_, key) return values[key] == true end,
            saveSetting = function(_, key, value) values[key] = value end,
        }
        local path = os.tmpname() .. "-paperpro-diagnostics.log"
        table.insert(paths, path)
        local diagnostics = Diagnostics:new{
            path = path, settings = settings,
            ai_settings = { isEnabled = function() return true end,
                isConfigured = function() return true end },
            queue = { data = { items = {{ state = "queued" }} } },
            ink_service = { active = false },
        }
        diagnostics:setEnabled(true)
        diagnostics:record("ai_queue", {
            request_id = "request", state = "queued",
            question = "PRIVATE QUESTION", token = "SECRET",
        })
        diagnostics:increment("marker_samples_received", 3)
        diagnostics:observeMaximum("maximum_pending_region_age_ms", 42)
        diagnostics:increment("not_allowed", 99)
        local content = assert(util.readFromFile(path, "rb"))
        assert.matches("request", content)
        assert.matches("queued", content)
        assert.is_nil(content:find("PRIVATE QUESTION", 1, true))
        assert.is_nil(content:find("SECRET", 1, true))
        local snapshot = diagnostics:snapshot()
        assert.are.same("0.6.0-rc5", snapshot.rc_version)
        assert.are.same("product-overlay-passthrough-v2", snapshot.touch_routing)
        assert.are.same("adaptive-a2-idle-cleanup-v5", snapshot.ink_live_refresh)
        assert.are.same("reader-surface-only-v5", snapshot.ink_layer_policy)
        assert.are.same("exclusive-write-v5", snapshot.write_mode_policy)
        assert.are.same(3, snapshot.counters.marker_samples_received)
        assert.are.same(42, snapshot.counters.maximum_pending_region_age_ms)
        assert.is_nil(snapshot.counters.not_allowed)
        assert.is_true(snapshot.ai_backend_configured)
        assert.are.same(1, snapshot.queue_states.queued)
        assert.is_truthy(JSON.decode(diagnostics:report():match("^(.-)\n\n")))
    end)
end)
