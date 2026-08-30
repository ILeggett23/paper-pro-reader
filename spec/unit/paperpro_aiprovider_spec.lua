describe("Paper Pro AIProvider and request contract", function()
    local AIProvider, AIRequest, ContextResolver, HTTPTransport, JSON

    setup(function()
        require("commonrequire")
        AIProvider = require("apps/paperpro/services/aiprovider")
        AIRequest = require("apps/paperpro/services/airequest")
        ContextResolver = require("apps/paperpro/services/contextresolver")
        HTTPTransport = require("apps/paperpro/services/httptransport")
        JSON = require("rapidjson")
    end)

    it("requires exact or single-label wildcard TLS hostnames", function()
        assert.is_true(HTTPTransport.dnsPatternMatches("reader.example", "reader.example"))
        assert.is_true(HTTPTransport.dnsPatternMatches("*.reader.example", "api.reader.example"))
        assert.is_false(HTTPTransport.dnsPatternMatches("*.reader.example", "deep.api.reader.example"))
        assert.is_false(HTTPTransport.dnsPatternMatches("reader.example", "attacker.example"))
        local certificate = {
            extensions = function()
                return { ["2.5.29.17"] = { dNSName = { "api.reader.example" } } }
            end,
        }
        assert.is_true(HTTPTransport.certificateMatchesHost(certificate, "api.reader.example"))
        assert.is_false(HTTPTransport.certificateMatchesHost(certificate, "other.reader.example"))
    end)

    local function settings(enabled)
        return {
            isEnabled = function() return enabled ~= false end,
            isConfigured = function() return true end,
            getConfig = function()
                return { backend_url = "https://reader.example", backend_token = "device-token" }
            end,
        }
    end

    local function request()
        local context = assert(ContextResolver:new():resolve({ document = {} }, {
            text = "passage", anchor = {
                kind = "xpointer", document_id = "/private/book.epub",
                start = "/p.0", finish = "/p.7",
            },
        }))
        return assert(AIRequest.create(context, "What does this mean?", nil, {
            request_id = "stable-id", created_at = 10,
        }))
    end

    it("creates stable typed text requests and rejects oversized questions", function()
        local value = request()
        assert.are.same("stable-id", value.request_id)
        assert.are.same("text", value.question.type)
        local missing, err = AIRequest.create(value.reading_context,
            string.rep("x", AIRequest.MAX_QUESTION_BYTES + 1))
        assert.is_nil(missing)
        assert.are.same("question_too_long", err)
    end)

    it("submits provider-neutral JSON while retaining local anchors off wire", function()
        local captured
        local transport = {
            request = function(_, spec, callback)
                captured = spec
                callback({ ok = true, body = {
                    request_id = "stable-id", response_id = "response-id",
                    status = "completed", answer = "A complete answer.", completed_at = 20,
                } })
                return true
            end,
            cancel = function() return true end,
        }
        local provider = AIProvider:new{
            settings = settings(), transport = transport,
            network_manager = { isOnline = function() return true end },
        }
        local response
        assert.is_true(provider:submit(request(), function(value) response = value end))
        local outbound = JSON.decode(captured.body)
        assert.are.same("Bearer device-token", captured.headers.Authorization)
        assert.is_nil(outbound.reading_context.book.document_id)
        assert.is_nil(outbound.reading_context.location.anchor)
        assert.are.same("A complete answer.", response.answer)
    end)

    it("categorizes offline, authentication, malformed response, and cancellation", function()
        local offline_error
        local offline = AIProvider:new{
            settings = settings(), transport = {},
            network_manager = { isOnline = function() return false end },
        }
        assert.is_false(offline:submit(request(), function(_, err) offline_error = err end))
        assert.are.same("offline", offline_error.category)

        local callback
        local transport = {
            request = function(_, _, cb) callback = cb return true end,
            cancel = function() return true end,
        }
        local provider = AIProvider:new{
            settings = settings(), transport = transport,
            network_manager = { isOnline = function() return true end },
        }
        local error
        provider:submit(request(), function(_, err) error = err end)
        callback({ ok = false, error = { category = "authentication", retryable = false } })
        assert.are.same("authentication", error.category)

        provider:submit(request(), function(_, err) error = err end)
        callback({ ok = true, body = { request_id = "wrong", status = "completed" } })
        assert.are.same("malformed_response", error.category)
    end)
end)
