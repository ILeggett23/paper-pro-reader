local AISettings = {}
AISettings.__index = AISettings

AISettings.KEYS = {
    enabled = "paperpro_ai_enabled",
    backend_url = "paperpro_ai_backend_url",
    backend_token = "paperpro_ai_backend_token",
    context_mode = "paperpro_ai_context_mode",
    response_style = "paperpro_ai_response_style",
    input_mode = "paperpro_ai_input_mode",
}

local function trim(value)
    return type(value) == "string" and value:match("^%s*(.-)%s*$") or ""
end

local function validURL(url)
    url = trim(url):gsub("/+$", "")
    if url == "" then return nil, "Backend URL is required" end
    if #url > 512 then return nil, "Backend URL is too long" end
    if url:match("^https://[^/]+") then return url end
    if url:match("^http://localhost[:/]?") or url:match("^http://127%.0%.0%.1[:/]?")
            or url:match("^http://%[::1%][:/]?") then
        return url
    end
    return nil, "Remote backends must use HTTPS"
end

function AISettings:new(options)
    options = options or {}
    options.settings = options.settings or G_reader_settings
    return setmetatable(options, self)
end

function AISettings:isEnabled()
    return self.settings:isTrue(self.KEYS.enabled)
end

function AISettings:setEnabled(enabled)
    self.settings:saveSetting(self.KEYS.enabled, enabled and true or false)
end

function AISettings:getContextMode()
    local mode = self.settings:readSetting(self.KEYS.context_mode, "nearby")
    return mode == "minimal" and "minimal" or "nearby"
end

function AISettings:setContextMode(mode)
    if mode ~= "minimal" and mode ~= "nearby" then return false end
    self.settings:saveSetting(self.KEYS.context_mode, mode)
    return true
end

function AISettings:getResponseStyle()
    return self.settings:readSetting(self.KEYS.response_style, "text") == "handwriting"
        and "handwriting" or "text"
end

function AISettings:setResponseStyle(style)
    if style ~= "text" and style ~= "handwriting" then return false end
    self.settings:saveSetting(self.KEYS.response_style, style)
    return true
end

function AISettings:getInputMode()
    return self.settings:readSetting(self.KEYS.input_mode, self.default_input_mode or "type") == "write"
        and "write" or "type"
end

function AISettings:setInputMode(mode)
    if mode ~= "type" and mode ~= "write" then return false end
    self.settings:saveSetting(self.KEYS.input_mode, mode)
    return true
end

function AISettings:getConfig()
    return {
        enabled = self:isEnabled(),
        backend_url = trim(self.settings:readSetting(self.KEYS.backend_url, "")),
        backend_token = self.settings:readSetting(self.KEYS.backend_token, "") or "",
        context_mode = self:getContextMode(),
        response_style = self:getResponseStyle(),
        input_mode = self:getInputMode(),
    }
end

function AISettings:saveBackend(url, token)
    local normalized, err = validURL(url)
    if not normalized then return false, err end
    token = trim(token)
    if token == "" then return false, "Backend token is required" end
    if #token > 512 then return false, "Backend token is too long" end
    self.settings:saveSetting(self.KEYS.backend_url, normalized)
    self.settings:saveSetting(self.KEYS.backend_token, token)
    return true
end

function AISettings:isConfigured()
    local config = self:getConfig()
    return validURL(config.backend_url) ~= nil and config.backend_token ~= ""
end

AISettings.validURL = validURL

return AISettings
