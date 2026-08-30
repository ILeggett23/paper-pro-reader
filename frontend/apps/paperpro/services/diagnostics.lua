local DataStorage = require("datastorage")
local Device = require("device")
local JSON = require("rapidjson")
local Release = require("apps/paperpro/release")
local Version = require("version")
local util = require("util")

local Diagnostics = {}
Diagnostics.__index = Diagnostics
Diagnostics.FILENAME = "paperpro-diagnostics.log"
Diagnostics.MAX_BYTES = 500000

local safe_fields = {
    request_id = true, state = true, category = true, points = true,
    duration_ms = true, bounds = true, mode = true,
}

local function firstLine(path, prefix)
    local content = util.readFromFile(path, "rb")
    if not content then return nil end
    for line in content:gmatch("[^\r\n]+") do
        if not prefix or line:match("^" .. prefix) then return line:gsub("^[^=]+=?", "") end
    end
end

function Diagnostics:new(options)
    options = options or {}
    options.settings = options.settings or G_reader_settings
    options.path = options.path or (DataStorage:getSettingsDir() .. "/" .. self.FILENAME)
    return setmetatable(options, self)
end

function Diagnostics:isEnabled()
    return self.settings:isTrue("paperpro_diagnostics_enabled")
end

function Diagnostics:setEnabled(value)
    self.settings:saveSetting("paperpro_diagnostics_enabled", value and true or false)
    self:record(value and "diagnostics_enabled" or "diagnostics_disabled")
end

function Diagnostics:record(event, fields)
    if not self:isEnabled() and event ~= "diagnostics_enabled" then return false end
    local safe = { timestamp = os.time(), event = tostring(event) }
    for key, value in pairs(fields or {}) do
        if safe_fields[key] and (type(value) == "string" or type(value) == "number"
                or type(value) == "boolean" or key == "bounds") then safe[key] = value end
    end
    local line = JSON.encode(safe)
    if not line then return false end
    local existing = util.readFromFile(self.path, "rb") or ""
    if #existing > self.MAX_BYTES then existing = existing:sub(-math.floor(self.MAX_BYTES * 0.75)) end
    return util.writeToFile(existing .. line .. "\n", self.path, true)
end

function Diagnostics:snapshot()
    local queue_states = {}
    if self.queue and self.queue.data then
        for _, item in ipairs(self.queue.data.items or {}) do
            queue_states[item.state] = (queue_states[item.state] or 0) + 1
        end
    end
    return {
        rc_version = Release.version,
        rc_stage = Release.stage,
        app_revision = Version:getCurrentRevision(),
        device_model = Device.model,
        machine = firstLine("/sys/devices/soc0/machine"),
        firmware = firstLine("/etc/os-release", "PRETTY_NAME="),
        screen = { width = Device.screen:getWidth(), height = Device.screen:getHeight(),
            dpi = Device.screen:getDPI() },
        qtfb = os.getenv("KO_USE_QTFB") and "enabled" or "not detected",
        qtfb_shim = os.getenv("LD_PRELOAD") and "configured" or "not detected",
        ai_enabled = self.ai_settings and self.ai_settings:isEnabled() or false,
        ai_backend_configured = self.ai_settings and self.ai_settings:isConfigured() or false,
        ink_mode = self.ink_service and self.ink_service.active or false,
        stylus_callback_registered = Device.input.stylus_callback ~= nil,
        touch_routing = "product-overlay-passthrough-v2",
        ink_live_refresh = "ui-batched-segments-v3",
        queue_states = queue_states,
        diagnostic_log = self.path,
    }
end

function Diagnostics:report()
    local value = self:snapshot()
    return JSON.encode(value) .. "\n\nLog file: " .. self.path
end

return Diagnostics
