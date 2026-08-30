local AIRequest = require("apps/paperpro/services/airequest")
local HTTPTransport = require("apps/paperpro/services/httptransport")
local JSON = require("rapidjson")
local NetworkMgr = require("ui/network/manager")
local SelectionService = require("apps/paperpro/services/selectionservice")

local AIProvider = {}
AIProvider.__index = AIProvider

AIProvider.PROTOCOL_VERSION = 1
AIProvider.MAX_ANSWER_BYTES = 32768

local function callbackFor(callbacks)
    if type(callbacks) == "function" then return callbacks end
    callbacks = callbacks or {}
    return function(response, err)
        if response and callbacks.on_complete then callbacks.on_complete(response) end
        if err and callbacks.on_error then callbacks.on_error(err) end
    end
end

function AIProvider:new(options)
    options = options or {}
    assert(options.settings, "AIProvider requires AISettings")
    options.transport = options.transport or HTTPTransport:new()
    options.network_manager = options.network_manager or NetworkMgr
    options.inflight = {}
    return setmetatable(options, self)
end

function AIProvider:isConfigured()
    return self.settings:isConfigured()
end

function AIProvider:isAvailable()
    if not self.settings:isEnabled() or not self:isConfigured() then return false end
    local ok, online = pcall(self.network_manager.isOnline, self.network_manager)
    return ok and online or false
end

function AIProvider:_url(path)
    local base = self.settings:getConfig().backend_url:gsub("/+$", "")
    return base .. path
end

function AIProvider:_headers()
    return { Authorization = "Bearer " .. self.settings:getConfig().backend_token }
end

function AIProvider:submit(request, callbacks)
    local valid, validation_err = AIRequest.validate(request)
    local callback = callbackFor(callbacks)
    if not valid then
        callback(nil, { category = validation_err, retryable = false })
        return false, validation_err
    end
    if not self.settings:isEnabled() then
        callback(nil, { category = "disabled", retryable = false })
        return false, "disabled"
    elseif not self:isConfigured() then
        callback(nil, { category = "not_configured", retryable = false })
        return false, "not_configured"
    elseif not self:isAvailable() then
        callback(nil, { category = "offline", retryable = true })
        return false, "offline"
    elseif self.inflight[request.request_id] then
        return false, "duplicate_request"
    end

    local outbound = SelectionService.deepCopy(request)
    -- Navigation anchors and local file identities are durable device state, not
    -- model context. Keep them in the queue/response stores but off the wire.
    outbound.reading_context.book.document_id = nil
    outbound.reading_context.location.anchor = nil
    local body, encode_err = JSON.encode(outbound)
    if not body then
        callback(nil, { category = "serialization", retryable = false })
        return false, encode_err
    end
    self.inflight[request.request_id] = true
    local started, err = self.transport:request({
        id = request.request_id,
        url = self:_url("/v1/reading/answer"),
        method = "POST",
        headers = self:_headers(),
        body = body,
    }, function(result)
        self.inflight[request.request_id] = nil
        if not result or not result.ok then
            callback(nil, result and result.error
                or { category = "network_failure", retryable = true })
            return
        end
        local response = result.body
        if type(response) ~= "table" or response.request_id ~= request.request_id
                or response.status ~= "completed" or type(response.response_id) ~= "string"
                or type(response.answer) ~= "string" or response.answer == ""
                or #response.answer > self.MAX_ANSWER_BYTES then
            callback(nil, { category = "malformed_response", retryable = false })
            return
        end
        callback(response)
    end)
    if not started then
        self.inflight[request.request_id] = nil
        callback(nil, { category = err or "network_failure", retryable = true })
        return false, err
    end
    return true, request.request_id
end

function AIProvider:cancel(request_id)
    if not self.inflight[request_id] then return false end
    return self.transport:cancel(request_id)
end

function AIProvider:testConnection(callback)
    if not self:isConfigured() then
        callback(nil, { category = "not_configured", retryable = false })
        return false
    end
    local id = "health-" .. tostring(os.time()) .. "-" .. tostring(math.random(1000000))
    return self.transport:request({
        id = id,
        url = self:_url("/v1/config"),
        method = "GET",
        headers = self:_headers(),
    }, function(result)
        if not result or not result.ok then
            callback(nil, result and result.error or { category = "network_failure", retryable = true })
        elseif type(result.body) ~= "table" or result.body.protocol_version ~= self.PROTOCOL_VERSION then
            callback(nil, { category = "unsupported_schema", retryable = false })
        else
            callback(result.body)
        end
    end)
end

return AIProvider
