local InkStroke = require("apps/paperpro/ink/inkstroke")
local JSON = require("rapidjson")
local ffiUtil = require("ffi/util")
local logger = require("logger")
local util = require("util")

local InkStore = {}
InkStore.__index = InkStore

InkStore.SCHEMA_VERSION = 1
InkStore.FILENAME = "paperpro-ink.json"
InkStore.MAX_STROKES = 5000

function InkStore:new(options)
    options = options or {}
    assert(options.document_id, "InkStore requires a document id")
    return setmetatable(options, self)
end

function InkStore:_candidateDirs()
    if self.candidate_dirs then return self.candidate_dirs end
    if self.doc_settings and self.doc_settings.getCustomLocationCandidates then
        return self.doc_settings:getCustomLocationCandidates(self.document_id)
    end
    return {}
end

function InkStore:_validateStroke(stroke)
    local anchor = stroke.anchor
    if type(anchor) ~= "table" or anchor.document_id ~= self.document_id then return false end
    if anchor.kind == "fixed_page" then
        return stroke.coordinate_space == "pdf-page-v1" and type(anchor.page) == "number"
            and anchor.page >= 1
    elseif anchor.kind == "epub_layout" then
        if stroke.coordinate_space ~= "epub-layout-v1" or type(anchor.xpointer) ~= "string"
                or anchor.xpointer == "" or type(anchor.layout) ~= "table" then
            return false
        end
        for _, point in ipairs(stroke.points) do
            if point.x < 0 or point.x > 1 or point.y < 0 or point.y > 1 then return false end
        end
        return true
    end
    return false
end

function InkStore:_decode(content)
    local data, err = JSON.decode(content)
    if type(data) ~= "table" then return nil, err or "malformed" end
    if data.schema_version ~= self.SCHEMA_VERSION then return nil, "unsupported_schema" end
    if data.document_id ~= self.document_id or type(data.strokes) ~= "table"
            or #data.strokes > self.MAX_STROKES then
        return nil, "wrong_document"
    end
    local strokes = {}
    for _, stored_stroke in ipairs(data.strokes) do
        local stroke, stroke_err = InkStroke.fromTable(stored_stroke)
        if not stroke or not self:_validateStroke(stroke) then
            return nil, stroke_err or "invalid_anchor"
        end
        table.insert(strokes, stroke)
    end
    self.created_at = data.created_at
    return strokes
end

function InkStore:load()
    local last_error
    for _, directory in ipairs(self:_candidateDirs()) do
        local path = directory .. "/" .. self.FILENAME
        for _, candidate in ipairs({ path, path .. ".old" }) do
            local content = util.readFromFile(candidate, "rb")
            if content then
                local strokes, err = self:_decode(content)
                if strokes then
                    self.path = path
                    return strokes
                end
                last_error = err
                logger.warn("Paper Pro ink store ignored", candidate, err)
                if err == "unsupported_schema" then return {}, err end
            end
        end
    end
    return {}, last_error
end

function InkStore:_write(path, content, directory_created)
    local temporary, backup = path .. ".tmp", path .. ".old"
    local written, err = util.writeToFile(content, temporary, true, false, directory_created)
    if not written then return false, err end
    os.remove(backup)
    local had_primary = util.fileExists(path)
    if had_primary and not os.rename(path, backup) then
        os.remove(temporary)
        return false, "backup_failed"
    end
    if not os.rename(temporary, path) then
        if had_primary then os.rename(backup, path) end
        return false, "replace_failed"
    end
    ffiUtil.fsyncDirectory(path)
    return true
end

function InkStore:save(strokes)
    if #(strokes or {}) > self.MAX_STROKES then return false, "stroke_limit" end
    local serialized = {}
    for _, stroke in ipairs(strokes or {}) do
        table.insert(serialized, stroke.toTable and stroke:toTable() or stroke)
    end
    local now = os.time()
    local content, encode_err = JSON.encode({
        schema_version = self.SCHEMA_VERSION,
        document_id = self.document_id,
        coordinate_space_version = 1,
        created_at = self.created_at or now,
        updated_at = now,
        strokes = serialized,
    })
    if not content then return false, encode_err end

    local directories = self.path and { self.path:match("^(.*)/[^/]+$") }
        or self:_candidateDirs()
    for _, directory in ipairs(directories) do
        local existed = util.directoryExists(directory)
        local made, make_err = util.makePath(directory)
        if made or existed then
            local path = directory .. "/" .. self.FILENAME
            local saved, save_err = self:_write(path, content, not existed)
            if saved then
                self.path = path
                self.created_at = self.created_at or now
                return true
            end
            logger.warn("Paper Pro ink store could not write", path, save_err)
        else
            logger.warn("Paper Pro ink store could not create", directory, make_err)
        end
    end
    return false, "no_writable_sidecar"
end

function InkStore:purge()
    local removed = false
    for _, directory in ipairs(self:_candidateDirs()) do
        local path = directory .. "/" .. self.FILENAME
        for _, candidate in ipairs({ path, path .. ".old", path .. ".tmp" }) do
            if util.fileExists(candidate) then
                removed = os.remove(candidate) and true or removed
            end
        end
    end
    self.path = nil
    return removed
end

return InkStore
