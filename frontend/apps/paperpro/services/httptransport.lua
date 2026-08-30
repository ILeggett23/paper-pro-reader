local JSON = require("rapidjson")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")

local HTTPTransport = {}
HTTPTransport.__index = HTTPTransport

HTTPTransport.MAX_RESPONSE_BYTES = 49152
HTTPTransport.POLL_INTERVAL = 0.15

local function errorResult(category, retryable, message, status)
    return {
        ok = false,
        error = {
            category = category,
            retryable = retryable and true or false,
            message = message,
            status = status,
        },
    }
end

local function transportCategory(message)
    message = tostring(message or ""):lower()
    if message:find("timeout", 1, true) or message:find("wantread", 1, true) then
        return "timeout"
    elseif message:find("certificate", 1, true) or message:find("ssl", 1, true)
            or message:find("tls", 1, true) then
        return "tls_failure"
    elseif message:find("resolve", 1, true) or message:find("host", 1, true)
            or message:find("dns", 1, true) then
        return "dns_failure"
    end
    return "network_failure"
end

local function dnsPatternMatches(pattern, hostname)
    pattern, hostname = pattern:lower(), hostname:lower()
    if pattern == hostname then return true end
    local suffix = pattern:match("^%*%.(.+)$")
    if not suffix or hostname:sub(-#suffix) ~= suffix then return false end
    local prefix = hostname:sub(1, #hostname - #suffix)
    return prefix:sub(-1) == "." and not prefix:sub(1, -2):find("%.")
end

local function certificateMatchesHost(certificate, hostname)
    local extensions = certificate and certificate:extensions()
    local names = extensions and extensions["2.5.29.17"]
    if names then
        for _, pattern in ipairs(names.dNSName or {}) do
            if dnsPatternMatches(pattern, hostname) then return true end
        end
        for _, address in ipairs(names.iPAddress or {}) do
            if address == hostname then return true end
        end
        return false
    end
    local subject = certificate and certificate:subject()
    for _, item in ipairs(subject or {}) do
        if item.name == "commonName" and dnsPatternMatches(item.value, hostname) then return true end
    end
    return false
end

local function secureCreate(hostname, cafile)
    local socket = require("socket")
    local ssl = require("ssl")
    return function()
        local connection = { sock = assert(socket.tcp()) }
        local settimeout = getmetatable(connection.sock).__index.settimeout
        function connection:settimeout(...)
            return settimeout(self.sock, ...)
        end
        function connection:connect(host, port)
            local connected, connect_err = self.sock:connect(host, port)
            if not connected then return nil, connect_err end
            local wrapped, wrap_err = ssl.wrap(self.sock, {
                mode = "client",
                protocol = "any",
                options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
                verify = "peer",
                cafile = cafile,
            })
            if not wrapped then return nil, wrap_err end
            self.sock = wrapped
            self.sock:sni(hostname)
            self.sock:settimeout(10)
            local handshook, handshake_err = self.sock:dohandshake()
            if not handshook then return nil, handshake_err end
            if not certificateMatchesHost(self.sock:getpeercertificate(), hostname) then
                self.sock:close()
                return nil, "certificate hostname mismatch"
            end
            local methods = getmetatable(self.sock).__index
            for name, method in pairs(methods) do
                if type(method) == "function" then
                    connection[name] = function(inner, ...)
                        return method(inner.sock, ...)
                    end
                end
            end
            return 1
        end
        return connection
    end
end

function HTTPTransport.perform(spec)
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    local http = require("socket.http")
    local url = require("socket.url")
    local is_https = spec.url:match("^https://") ~= nil
    local parsed = url.parse(spec.url)
    if is_https and not parsed.port then
        parsed.port = 443
        spec.url = url.build(parsed)
    end
    local chunks, size = {}, 0
    local sink = function(chunk)
        if chunk then
            size = size + #chunk
            if size > HTTPTransport.MAX_RESPONSE_BYTES then
                return nil, "response too large"
            end
            table.insert(chunks, chunk)
        end
        return 1
    end
    local body = spec.body or ""
    local headers = spec.headers or {}
    headers["Content-Length"] = tostring(#body)
    headers["Content-Type"] = headers["Content-Type"] or "application/json"
    headers["Accept"] = "application/json"
    socketutil:set_timeout(spec.block_timeout or 10, spec.total_timeout or 30)
    local request = {
            url = spec.url,
            method = spec.method or "GET",
            headers = headers,
            source = body ~= "" and ltn12.source.string(body) or nil,
            sink = sink,
            redirect = false,
        }
    if is_https then
        request.create = secureCreate(parsed.host, spec.cafile or "data/ca-bundle.crt")
    end
    local request_ok, code, response_headers, status = pcall(function()
        return socket.skip(1, http.request(request))
    end)
    socketutil:reset_timeout()
    if not request_ok then
        local category = transportCategory(code)
        return errorResult(category, true, "Request failed")
    end
    if type(code) ~= "number" then
        local category = transportCategory(code or status)
        return errorResult(category, true, "Request failed")
    end
    local response_body = table.concat(chunks)
    local decoded = response_body ~= "" and JSON.decode(response_body) or {}
    if code < 200 or code >= 300 then
        local server_error = type(decoded) == "table" and decoded.error or nil
        local category = type(server_error) == "table" and server_error.category
            or (code == 401 and "authentication" or code == 429 and "rate_limited"
                or code >= 500 and "backend_unavailable" or "request_rejected")
        local retryable = type(server_error) == "table" and server_error.retryable
            or code == 429 or code >= 500
        return errorResult(category, retryable,
            type(server_error) == "table" and server_error.message or "Backend rejected request", code)
    end
    if type(decoded) ~= "table" then
        return errorResult("malformed_response", false, "Backend returned malformed JSON", code)
    end
    return { ok = true, status = code, body = decoded, headers = response_headers }
end

HTTPTransport.dnsPatternMatches = dnsPatternMatches
HTTPTransport.certificateMatchesHost = certificateMatchesHost

function HTTPTransport:new(options)
    options = options or {}
    options.ui_manager = options.ui_manager or UIManager
    options.jobs = {}
    return setmetatable(options, self)
end

function HTTPTransport:_finish(job, result)
    if self.jobs[job.id] ~= job then return end
    self.jobs[job.id] = nil
    local callback = job.callback
    job.callback = nil
    if callback then callback(result) end
end

function HTTPTransport:_poll(job)
    if self.jobs[job.id] ~= job then return end
    local has_output = job.fd and ffiUtil.getNonBlockingReadSize(job.fd) ~= 0
    local done = ffiUtil.isSubProcessDone(job.pid)
    if has_output or done then
        local encoded = job.fd and ffiUtil.readAllFromFD(job.fd) or nil
        job.fd = nil
        if job.cancelled then
            self:_finish(job, errorResult("cancelled", false, "Request cancelled"))
            return
        end
        local result = encoded and encoded ~= "" and JSON.decode(encoded) or nil
        self:_finish(job, type(result) == "table" and result
            or errorResult("network_failure", true, "Request process ended unexpectedly"))
        return
    end
    self.ui_manager:scheduleIn(self.POLL_INTERVAL, function() self:_poll(job) end)
end

function HTTPTransport:request(spec, callback)
    assert(type(spec) == "table" and type(spec.id) == "string", "HTTP request requires id")
    if self.jobs[spec.id] then return false, "duplicate_request" end
    local immutable = {
        url = spec.url,
        method = spec.method,
        headers = spec.headers,
        body = spec.body,
        block_timeout = spec.block_timeout,
        total_timeout = spec.total_timeout,
    }
    local pid, fd = ffiUtil.runInSubProcess(function(_, child_fd)
        local ok, result = pcall(HTTPTransport.perform, immutable)
        if not ok then result = errorResult("network_failure", true, "Request process failed") end
        local encoded = JSON.encode(result) or ""
        ffiUtil.writeToFD(child_fd, encoded, true)
    end, true)
    if not pid then return false, fd or "subprocess_failed" end
    local job = { id = spec.id, pid = pid, fd = fd, callback = callback }
    self.jobs[spec.id] = job
    self.ui_manager:nextTick(function() self:_poll(job) end)
    return true
end

function HTTPTransport:cancel(id)
    local job = self.jobs[id]
    if not job then return false end
    job.cancelled = true
    ffiUtil.terminateSubProcess(job.pid)
    return true
end

return HTTPTransport
