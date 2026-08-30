local JSON = require("rapidjson")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")

local AtomicJSONStore = {}
AtomicJSONStore.__index = AtomicJSONStore

function AtomicJSONStore:new(options)
    options = options or {}
    assert(type(options.path) == "string", "AtomicJSONStore requires a path")
    assert(type(options.schema_version) == "number", "AtomicJSONStore requires a schema version")
    return setmetatable(options, self)
end

function AtomicJSONStore:_decode(content)
    local data, err = JSON.decode(content)
    if type(data) ~= "table" then return nil, err or "malformed" end
    if data.schema_version ~= self.schema_version then return nil, "unsupported_schema" end
    if self.validate then
        local valid, validation_err = self.validate(data)
        if not valid then return nil, validation_err or "invalid_data" end
    end
    return data
end

function AtomicJSONStore:load()
    local last_error
    for _, candidate in ipairs({ self.path, self.path .. ".old" }) do
        local content = util.readFromFile(candidate, "rb")
        if content then
            local data, err = self:_decode(content)
            if data then return data end
            last_error = err
            logger.warn("Paper Pro JSON store ignored", candidate, err)
            if err == "unsupported_schema" then return nil, err end
        end
    end
    local value = self.default_data and self.default_data() or {
        schema_version = self.schema_version,
    }
    return value, last_error
end

function AtomicJSONStore:save(data)
    if self.validate then
        local valid, validation_err = self.validate(data)
        if not valid then return false, validation_err or "invalid_data" end
    end
    data.schema_version = self.schema_version
    local content, encode_err = JSON.encode(data)
    if not content then return false, encode_err end
    local directory = self.path:match("^(.*)/[^/]+$")
    if not directory then return false, "invalid_path" end
    local existed = util.directoryExists(directory)
    local made, make_err = util.makePath(directory)
    if not made and not existed then return false, make_err or "directory_failed" end

    local temporary, backup = self.path .. ".tmp", self.path .. ".old"
    local written, write_err = util.writeToFile(content, temporary, true, false, not existed)
    if not written then return false, write_err end
    os.remove(backup)
    local had_primary = util.fileExists(self.path)
    if had_primary and not os.rename(self.path, backup) then
        os.remove(temporary)
        return false, "backup_failed"
    end
    if not os.rename(temporary, self.path) then
        if had_primary then os.rename(backup, self.path) end
        return false, "replace_failed"
    end
    ffiUtil.fsyncDirectory(self.path)
    return true
end

return AtomicJSONStore
