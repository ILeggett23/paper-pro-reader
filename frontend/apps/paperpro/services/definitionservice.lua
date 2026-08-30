local DefinitionService = {}
DefinitionService.__index = DefinitionService

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(item, seen)
    end
    return copy
end

local function cleanQuery(query)
    if type(query) ~= "string" then
        return nil
    end
    query = query:match("^%s*(.-)%s*$")
    if query == "" then
        return nil
    end
    return query
end

function DefinitionService:new(options)
    options = options or {}
    assert(options.dictionary, "DefinitionService requires a dictionary adapter")
    return setmetatable(options, self)
end

function DefinitionService:_baseModel(snapshot, query)
    return {
        query = query,
        display_word = query,
        definitions = {},
        dictionary_name = nil,
        phonetic_or_pronunciation = nil,
        status = "loading",
        selection_anchor = deepCopy(snapshot and snapshot.anchor),
        is_phrase = snapshot and snapshot.selected_word == nil and query:find("%s") ~= nil or false,
    }
end

function DefinitionService:_normalize(snapshot, query, display_query, results)
    local model = self:_baseModel(snapshot, query)
    model.display_word = cleanQuery(display_query) or query

    if type(results) ~= "table" then
        model.status = "error"
        model.message = "Local dictionary lookup failed"
        return model
    end
    if results.lookup_cancelled then
        model.status = "error"
        model.message = "Local dictionary lookup was interrupted"
        return model
    end

    local first_result = results[1]
    if first_result and first_result.no_dictionaries then
        model.status = "error"
        model.message = "No local dictionaries installed"
        return model
    end

    for _, result in ipairs(results) do
        if not result.no_result and type(result.definition) == "string" and result.definition ~= "" then
            table.insert(model.definitions, {
                text = result.definition,
                dictionary_name = result.dict,
                display_word = result.word,
            })
        end
    end

    if #model.definitions == 0 then
        model.status = "no_definition"
        model.message = "No local definition found"
        if first_result and first_result.word then
            model.display_word = first_result.word
        end
        return model
    end

    model.status = "success"
    model.display_word = model.definitions[1].display_word or model.display_word
    model.dictionary_name = model.definitions[1].dictionary_name
    return model
end

function DefinitionService:lookup(snapshot, callback)
    assert(type(callback) == "function", "DefinitionService requires a callback")
    local query = cleanQuery(snapshot and (snapshot.selected_word or snapshot.text))
    if not query then
        callback({
            query = "",
            display_word = "",
            definitions = {},
            status = "error",
            message = "No selected text to define",
            selection_anchor = deepCopy(snapshot and snapshot.anchor),
        })
        return false
    end

    local ok, handled = pcall(self.dictionary.lookupWordResults, self.dictionary, query, false,
        function(display_query, results)
            callback(self:_normalize(snapshot, query, display_query, results))
        end)
    if not ok or handled == false then
        callback(self:_normalize(snapshot, query, query, nil))
        return false
    end
    return true
end

DefinitionService.deepCopy = deepCopy

return DefinitionService
