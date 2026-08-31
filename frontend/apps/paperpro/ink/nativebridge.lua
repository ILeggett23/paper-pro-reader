local bit = require("bit")
local ffi = require("ffi")
local UIManager = require("ui/uimanager")

require("ffi/posix_h")

ffi.cdef[[
typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t protocolMajor;
    uint16_t protocolMinor;
    uint16_t messageType;
    uint16_t headerBytes;
    uint32_t payloadBytes;
    uint64_t sequence;
    uint64_t timestampNs;
    uint64_t strokeId;
    uint32_t flags;
    uint32_t pointCount;
} paperpro_nativeink_header;

typedef struct __attribute__((packed)) {
    float x;
    float y;
    uint64_t timestampNs;
    uint16_t pressure;
    int16_t tiltX;
    int16_t tiltY;
    uint16_t tool;
} paperpro_nativeink_point;

typedef struct __attribute__((packed)) {
    uint64_t rawSamplesReceived;
    uint64_t samplesRendered;
    uint64_t samplesHandedToClient;
    uint64_t samplesDropped;
    uint64_t displayUpdatesSubmitted;
    uint64_t displayUpdatesCoalesced;
    uint64_t paintCalls;
    uint64_t paintTimeUs;
    uint64_t rawToReceiptUs;
    uint64_t rawToReceiptCount;
    uint64_t receiptToSubmitUs;
    uint64_t receiptToSubmitCount;
    uint64_t eventToSubmitUs;
    uint64_t eventToSubmitCount;
} paperpro_nativeink_metrics;
]]

local MAGIC = 0x314B4E49
local PROTOCOL_MAJOR = 1
local HEADER_SIZE = ffi.sizeof("paperpro_nativeink_header")
local POINT_SIZE = ffi.sizeof("paperpro_nativeink_point")
local MAX_PACKET = HEADER_SIZE + 32 * 1024
local MAX_POINTS_PER_PACKET = 128
local MAX_POINTS_PER_STROKE = 10000

assert(HEADER_SIZE == 48, "native ink header ABI mismatch")
assert(POINT_SIZE == 24, "native ink point ABI mismatch")

local TYPE = {
    HELLO = 1,
    STROKE_BEGIN = 2,
    STROKE_POINTS = 3,
    STROKE_END = 4,
    ERASE_BEGIN = 5,
    ERASE_POINTS = 6,
    ERASE_END = 7,
    METRICS = 8,
    GOODBYE = 9,
}

local NativeTransport = {}
NativeTransport.__index = NativeTransport

function NativeTransport:new(options)
    options = options or {}
    options.fd = -1
    options.buffer = ffi.new("uint8_t[?]", MAX_PACKET)
    options.buffer_size = MAX_PACKET
    return setmetatable(options, self)
end

function NativeTransport:_socketPath()
    local key = tonumber(os.getenv("QTFB_KEY") or "")
    if not key then return nil, "qtfb_key_missing" end
    return string.format("/tmp/appload-native-ink-%d.sock", key)
end

function NativeTransport:connect()
    if self.fd and self.fd >= 0 then return true end
    local path, path_err = self:_socketPath()
    if not path then return false, path_err end
    local fd = ffi.C.socket(ffi.C.AF_UNIX,
        bit.bor(ffi.C.SOCK_SEQPACKET, ffi.C.SOCK_CLOEXEC), 0)
    if fd < 0 then return false, "socket_failed" end
    local address = ffi.new("struct sockaddr_un", ffi.C.AF_UNIX, path)
    if ffi.C.connect(fd, ffi.cast("const struct sockaddr *", address), ffi.sizeof(address)) ~= 0 then
        ffi.C.close(fd)
        return false, "connect_pending"
    end
    self.fd = fd
    return true
end

function NativeTransport:close()
    if self.fd and self.fd >= 0 then ffi.C.close(self.fd) end
    self.fd = -1
end

local function decodePacket(buffer, bytes)
    if bytes < HEADER_SIZE then return nil, "short_header" end
    local header = ffi.cast("paperpro_nativeink_header *", buffer)[0]
    local magic = tonumber(header.magic)
    local major = tonumber(header.protocolMajor)
    local header_size = tonumber(header.headerBytes)
    local payload_size = tonumber(header.payloadBytes)
    local message_type = tonumber(header.messageType)
    local point_count = tonumber(header.pointCount)
    if magic ~= MAGIC or major ~= PROTOCOL_MAJOR or header_size ~= HEADER_SIZE then
        return nil, "protocol_mismatch"
    end
    if payload_size > 32 * 1024 or header_size + payload_size ~= bytes then
        return nil, "invalid_length"
    end
    if point_count > MAX_POINTS_PER_PACKET then return nil, "point_batch_limit" end
    if (message_type == TYPE.STROKE_POINTS or message_type == TYPE.ERASE_POINTS)
            and payload_size ~= point_count * POINT_SIZE then
        return nil, "invalid_point_payload"
    end

    local message = {
        type = message_type,
        sequence = tonumber(header.sequence),
        timestamp_ns = tonumber(header.timestampNs),
        stroke_id = tonumber(header.strokeId),
        flags = tonumber(header.flags),
        points = {},
    }
    if point_count > 0 then
        local points = ffi.cast("paperpro_nativeink_point *", buffer + HEADER_SIZE)
        for index = 0, point_count - 1 do
            local point = points[index]
            table.insert(message.points, {
                x = tonumber(point.x),
                y = tonumber(point.y),
                timestamp = tonumber(point.timestampNs) / 1000000000,
                pressure = tonumber(point.pressure),
                tilt_x = tonumber(point.tiltX),
                tilt_y = tonumber(point.tiltY),
                tool = tonumber(point.tool),
            })
        end
    elseif message_type == TYPE.METRICS and payload_size == ffi.sizeof("paperpro_nativeink_metrics") then
        local metrics = ffi.cast("paperpro_nativeink_metrics *", buffer + HEADER_SIZE)[0]
        message.metrics = {
            raw_samples_received = tonumber(metrics.rawSamplesReceived),
            samples_rendered = tonumber(metrics.samplesRendered),
            samples_handed_to_koreader = tonumber(metrics.samplesHandedToClient),
            dropped_samples = tonumber(metrics.samplesDropped),
            display_updates_submitted = tonumber(metrics.displayUpdatesSubmitted),
            display_updates_coalesced = tonumber(metrics.displayUpdatesCoalesced),
            paint_calls = tonumber(metrics.paintCalls),
            paint_time_us = tonumber(metrics.paintTimeUs),
            raw_to_receipt_us = tonumber(metrics.rawToReceiptUs),
            raw_to_receipt_count = tonumber(metrics.rawToReceiptCount),
            receipt_to_submit_us = tonumber(metrics.receiptToSubmitUs),
            receipt_to_submit_count = tonumber(metrics.receiptToSubmitCount),
            event_to_submit_us = tonumber(metrics.eventToSubmitUs),
            event_to_submit_count = tonumber(metrics.eventToSubmitCount),
        }
    end
    return message
end

function NativeTransport:receive()
    if not (self.fd and self.fd >= 0) then return nil, "not_connected" end
    local pollfd = ffi.new("struct pollfd[1]")
    pollfd[0].fd = self.fd
    pollfd[0].events = ffi.C.POLLIN
    local ready = ffi.C.poll(pollfd, 1, 0)
    if ready == 0 then return nil, "again" end
    if ready < 0 then return nil, "poll_failed" end
    local bytes = ffi.C.recv(self.fd, self.buffer, self.buffer_size, 0)
    if bytes == 0 then self:close(); return nil, "closed" end
    if bytes < 0 then return nil, "receive_failed" end
    return decodePacket(self.buffer, tonumber(bytes))
end

local NativeBridge = {}
NativeBridge.__index = NativeBridge
NativeBridge.TYPE = TYPE
NativeBridge.decodePacket = decodePacket

function NativeBridge:new(options)
    options = options or {}
    assert(options.ink_service, "NativeBridge requires InkService")
    options.ui_manager = options.ui_manager or UIManager
    options.transport = options.transport or NativeTransport:new()
    options.poll_interval = options.poll_interval or 0.01
    options.retry_interval = options.retry_interval or 0.25
    options.max_messages_per_poll = options.max_messages_per_poll or 32
    options._poll_task = function() options:_poll() end
    options.metrics = {}
    options.sequence_gaps = 0
    options.protocol_errors = 0
    return setmetatable(options, self)
end

function NativeBridge:_schedule(delay)
    if self.closed then return end
    self.ui_manager:scheduleIn(delay, self._poll_task)
    self.poll_scheduled = true
end

function NativeBridge:start()
    if self.started then return true end
    self.started = true
    self.closed = false
    self:_schedule(0)
    return true
end

function NativeBridge:_record(name, value)
    if self.metric then self.metric(name, value) end
end

function NativeBridge:_connect()
    local ok, err = self.transport:connect()
    if ok then
        if not self.connected then self:_record("native_bridge_connected") end
        self.connected = true
        return true
    end
    self.connected = false
    self.last_error = err
    return false
end

function NativeBridge:_appendPoints(message)
    if not self.current_stroke or self.current_stroke.id ~= message.stroke_id then
        self.protocol_errors = self.protocol_errors + 1
        return false, "stroke_not_started"
    end
    if #self.current_stroke.points + #message.points > MAX_POINTS_PER_STROKE then
        self.current_stroke = nil
        self.protocol_errors = self.protocol_errors + 1
        return false, "stroke_point_limit"
    end
    for _, point in ipairs(message.points) do table.insert(self.current_stroke.points, point) end
    return true
end

function NativeBridge:_handle(message)
    if self.last_sequence and message.sequence > self.last_sequence + 1 then
        self.sequence_gaps = self.sequence_gaps + message.sequence - self.last_sequence - 1
        if self.current_stroke then self.current_stroke.invalid = true end
    end
    if self.last_sequence and message.sequence <= self.last_sequence then
        self.protocol_errors = self.protocol_errors + 1
        return false, "out_of_order"
    end
    self.last_sequence = message.sequence

    if message.type == TYPE.HELLO then
        self:_record("native_bridge_hello")
    elseif message.type == TYPE.STROKE_BEGIN then
        self.current_stroke = {
            id = message.stroke_id,
            storage_id = string.format("native-%d-%d",
                math.floor(message.timestamp_ns / 1000), message.stroke_id),
            tool = "pen",
            started_at = message.timestamp_ns / 1000000000,
            points = {},
        }
    elseif message.type == TYPE.STROKE_POINTS then
        return self:_appendPoints(message)
    elseif message.type == TYPE.STROKE_END then
        local stroke = self.current_stroke
        self.current_stroke = nil
        if not stroke or stroke.id ~= message.stroke_id then
            self.protocol_errors = self.protocol_errors + 1
            return false, "stroke_end_without_begin"
        end
        if stroke.invalid then
            self.protocol_errors = self.protocol_errors + 1
            return false, "stroke_sequence_gap"
        end
        stroke.id = stroke.storage_id
        stroke.storage_id = nil
        stroke.ended_at = message.timestamp_ns / 1000000000
        local ok, err = self.ink_service:importNativeStroke(stroke)
        if ok then self:_record("native_strokes_persisted") end
        return ok, err
    elseif message.type == TYPE.ERASE_BEGIN then
        self.ink_service:beginNativeErase()
    elseif message.type == TYPE.ERASE_POINTS then
        for _, point in ipairs(message.points) do self.ink_service:nativeEraseAt(point) end
    elseif message.type == TYPE.ERASE_END then
        local ok = self.ink_service:finishNativeErase()
        if ok then self:_record("native_erase_gestures_persisted") end
    elseif message.type == TYPE.METRICS then
        self.metrics = message.metrics or {}
        self:_record("native_metrics_received")
    elseif message.type == TYPE.GOODBYE then
        self.connected = false
        self.transport:close()
    else
        self.protocol_errors = self.protocol_errors + 1
        return false, "unknown_message"
    end
    return true
end

function NativeBridge:pollOnce()
    if not self:_connect() then return false, self.last_error end
    local processed = 0
    while processed < self.max_messages_per_poll do
        local message, err = self.transport:receive()
        if not message then
            if err ~= "again" then self.last_error = err end
            break
        end
        processed = processed + 1
        local ok, handle_err = self:_handle(message)
        if not ok then self.last_error = handle_err end
    end
    return true, processed
end

function NativeBridge:_poll()
    self.poll_scheduled = false
    if self.closed then return end
    local connected = self:_connect()
    if connected then self:pollOnce() end
    self:_schedule(connected and self.poll_interval or self.retry_interval)
end

function NativeBridge:report()
    local parts = {
        "connected=" .. tostring(self.connected == true),
        "sequence_gaps=" .. tostring(self.sequence_gaps),
        "protocol_errors=" .. tostring(self.protocol_errors),
    }
    for key, value in pairs(self.metrics or {}) do
        table.insert(parts, tostring(key) .. "=" .. tostring(value))
    end
    table.sort(parts)
    return table.concat(parts, " ")
end

function NativeBridge:close()
    self.closed = true
    if self.poll_scheduled and self.ui_manager.unschedule then self.ui_manager:unschedule(self._poll_task) end
    self.poll_scheduled = false
    self.transport:close()
    self.connected = false
    self.current_stroke = nil
end

NativeBridge.NativeTransport = NativeTransport

return NativeBridge
