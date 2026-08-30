describe("Paper Pro DefinitionService", function()
    local DefinitionOverlay, DefinitionService

    setup(function()
        require("commonrequire")
        DefinitionOverlay = require("apps/paperpro/overlays/definitionoverlay")
        DefinitionService = require("apps/paperpro/services/definitionservice")
    end)

    local function lookupWith(results, snapshot)
        local model
        local dictionary = {
            lookupWordResults = function(_, query, _, callback)
                callback(query, results)
                return true
            end,
        }
        DefinitionService:new{ dictionary = dictionary }:lookup(snapshot or {
            text = "word",
            selected_word = "word",
            anchor = { kind = "xpointer", start = "a", finish = "b" },
        }, function(result)
            model = result
        end)
        return model
    end

    it("normalizes a valid local definition", function()
        local model = lookupWith({
            { word = "word", dict = "Local dictionary", definition = "A unit of language." },
        })
        assert.are.same("success", model.status)
        assert.are.same("word", model.display_word)
        assert.are.same("Local dictionary", model.dictionary_name)
        assert.are.same("A unit of language.", model.definitions[1].text)
        assert.are.same("xpointer", model.selection_anchor.kind)
    end)

    it("normalizes no-result state", function()
        local model = lookupWith({
            { word = "missing", dict = "Not available", definition = "No results.", no_result = true },
        }, { text = "missing", selected_word = "missing" })
        assert.are.same("no_definition", model.status)
        assert.are.same(0, #model.definitions)
    end)

    it("retains multiple local results", function()
        local model = lookupWith({
            { word = "run", dict = "First", definition = "Move quickly." },
            { word = "run", dict = "Second", definition = "An act of running." },
        }, { text = "run", selected_word = "run" })
        assert.are.same("success", model.status)
        assert.are.same(2, #model.definitions)
        assert.are.same("First", model.dictionary_name)
    end)

    it("attributes every definition and shows persisted vocabulary status", function()
        local body = DefinitionOverlay:new():_body{
            status = "success", vocabulary_status = "added",
            definitions = {
                { text = "Move quickly.", dictionary_name = "First" },
                { text = "An act of running.", dictionary_name = "Second" },
            },
        }
        assert.is_truthy(body:find("First", 1, true))
        assert.is_truthy(body:find("Second", 1, true))
        assert.is_truthy(body:find("Added to Vocabulary", 1, true))
    end)

    it("normalizes dictionary failures", function()
        local model
        DefinitionService:new{
            dictionary = {
                lookupWordResults = function()
                    error("dictionary failed")
                end,
            },
        }:lookup({ text = "word", selected_word = "word" }, function(result)
            model = result
        end)
        assert.are.same("error", model.status)
        assert.are.same("Local dictionary lookup failed", model.message)
    end)

    it("passes a phrase through without choosing an arbitrary word", function()
        local received_query
        local model
        DefinitionService:new{
            dictionary = {
                lookupWordResults = function(_, query, _, callback)
                    received_query = query
                    callback(query, {})
                    return true
                end,
            },
        }:lookup({ text = "selected phrase" }, function(result)
            model = result
        end)
        assert.are.same("selected phrase", received_query)
        assert.is_true(model.is_phrase)
    end)
end)
