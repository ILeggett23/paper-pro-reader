local SelectionService = require("apps/paperpro/services/selectionservice")
local util = require("util")

local ContextResolver = {}
ContextResolver.__index = ContextResolver

ContextResolver.SCHEMA_VERSION = 1
ContextResolver.LIMITS = {
    selection_bytes = 8192,
    sentence_bytes = 4096,
    paragraph_bytes = 6144,
    side_bytes = 4096,
    source_bytes = 16384,
    nearby_words = 80,
    metadata_bytes = 512,
    selected_word_bytes = 256,
    max_authors = 8,
}

local function cleanText(text)
    if type(text) ~= "string" then return nil end
    text = util.fixUtf8(text, ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

local function prefixBytes(text, limit)
    text = cleanText(text)
    if not text or #text <= limit then return text, false end
    local trimmed = util.fixUtf8(text:sub(1, limit), ""):match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil, true
end

local function suffixBytes(text, limit)
    text = cleanText(text)
    if not text or #text <= limit then return text, false end
    local trimmed = util.fixUtf8(text:sub(-limit), ""):match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil, true
end

local function authorValue(author, limits)
    if type(author) == "table" then
        local values = {}
        for _, value in ipairs(author) do
            local normalized = prefixBytes(value, limits.metadata_bytes)
            if normalized then
                table.insert(values, normalized)
                if #values >= limits.max_authors then break end
            end
        end
        return #values > 0 and values or nil
    end
    return prefixBytes(author, limits.metadata_bytes)
end

function ContextResolver:new(options)
    options = options or {}
    local limits = {}
    for key, value in pairs(self.LIMITS) do limits[key] = value end
    for key, value in pairs(options.limits or {}) do limits[key] = value end
    options.limits = limits
    return setmetatable(options, self)
end

function ContextResolver:_epubSentence(ui, snapshot)
    local anchor = snapshot.anchor
    local document = ui and ui.document
    if not (anchor and anchor.kind == "xpointer" and document
            and document.extendXPointersToSentenceSegment) then
        return nil
    end
    local ok, result = pcall(document.extendXPointersToSentenceSegment,
        document, anchor.start, anchor.finish)
    if ok and type(result) == "table" then return cleanText(result.text) end
end

function ContextResolver:_epubParagraph(ui, snapshot)
    local anchor = snapshot.anchor
    local document = ui and ui.document
    if not (anchor and anchor.kind == "xpointer" and document
            and document.getHTMLFromXPointer) then
        return nil
    end
    local ok, html = pcall(document.getHTMLFromXPointer,
        document, anchor.start, 0x1001, true)
    if not ok or type(html) ~= "string" then return nil end
    local paragraph = cleanText(util.htmlToPlainTextIfHtml(html))
    if not paragraph then return nil end
    local needle = cleanText(snapshot.text)
    if needle and not paragraph:find(needle, 1, true) then return nil end
    return paragraph
end

function ContextResolver:_nearby(ui, snapshot)
    local document = ui and ui.document
    local anchor = snapshot.anchor
    if not (document and document.getSelectedWordContext and anchor) then
        return snapshot.before_context, snapshot.after_context
    end
    local ok, before, after
    if anchor.kind == "xpointer" then
        ok, before, after = pcall(document.getSelectedWordContext, document,
            snapshot.text, self.limits.nearby_words,
            anchor.start, anchor.finish, false)
    elseif anchor.kind == "fixed_page" then
        ok, before, after = pcall(document.getSelectedWordContext, document,
            snapshot.text, self.limits.nearby_words, anchor.pos0)
    end
    if not ok then return snapshot.before_context, snapshot.after_context end
    return before or snapshot.before_context, after or snapshot.after_context
end

function ContextResolver:_applyBudget(selection, sentence, paragraph, before, after, mode)
    local limits = self.limits
    local truncation = {}
    selection, truncation.selection = prefixBytes(selection, limits.selection_bytes)
    local used = #(selection or "")
    local remaining = math.max(0, limits.source_bytes - used)

    if mode == "nearby" then
        sentence, truncation.sentence = prefixBytes(sentence,
            math.min(limits.sentence_bytes, remaining))
        if sentence == selection then sentence = nil end
        used = used + #(sentence or "")
        remaining = math.max(0, limits.source_bytes - used)

        paragraph, truncation.paragraph = prefixBytes(paragraph,
            math.min(limits.paragraph_bytes, remaining))
        if paragraph == selection or paragraph == sentence then paragraph = nil end
        used = used + #(paragraph or "")
        remaining = math.max(0, limits.source_bytes - used)

        local side_budget = math.min(remaining, limits.side_bytes * 2)
        local before_budget = math.min(limits.side_bytes, math.floor(side_budget / 2))
        local after_budget = math.min(limits.side_bytes, side_budget - before_budget)
        before, truncation.before = suffixBytes(before, before_budget)
        after, truncation.after = prefixBytes(after, after_budget)
        local unused_before = before_budget - #(before or "")
        local unused_after = after_budget - #(after or "")
        if unused_before > 0 and after then
            after, truncation.after = prefixBytes(after,
                math.min(limits.side_bytes, after_budget + unused_before))
        elseif unused_after > 0 and before then
            before, truncation.before = suffixBytes(before,
                math.min(limits.side_bytes, before_budget + unused_after))
        end
    else
        sentence, paragraph, before, after = nil, nil, nil, nil
    end

    truncation.any = truncation.selection or truncation.sentence
        or truncation.paragraph or truncation.before or truncation.after or false
    return selection, sentence, paragraph, before, after, truncation
end

function ContextResolver:resolve(ui, snapshot, options)
    options = options or {}
    if type(snapshot) ~= "table" or type(snapshot.anchor) ~= "table"
            or type(snapshot.text) ~= "string" or not snapshot.text:match("%S") then
        return nil, "invalid_selection"
    end
    local mode = options.context_mode == "minimal" and "minimal" or "nearby"
    local is_epub = snapshot.anchor.kind == "xpointer"
    local sentence = is_epub and self:_epubSentence(ui, snapshot) or nil
    local paragraph = is_epub and self:_epubParagraph(ui, snapshot) or nil
    local before, after = self:_nearby(ui, snapshot)
    local selection, truncation
    selection, sentence, paragraph, before, after, truncation = self:_applyBudget(
        snapshot.text, sentence, paragraph, before, after, mode)

    local context = {
        schema_version = self.SCHEMA_VERSION,
        book = {
            document_id = snapshot.anchor.document_id,
            title = prefixBytes(snapshot.book_title, self.limits.metadata_bytes),
            author = authorValue(snapshot.author, self.limits),
        },
        location = {
            chapter = prefixBytes(snapshot.chapter, self.limits.metadata_bytes),
            anchor = SelectionService.deepCopy(snapshot.anchor),
        },
        selection = {
            text = selection,
            selected_word = prefixBytes(snapshot.selected_word, self.limits.selected_word_bytes),
        },
        context = {
            before = before,
            after = after,
            sentence = sentence,
            paragraph = paragraph,
        },
        context_mode = mode,
        truncation = truncation,
        capabilities = {
            precise_anchor = snapshot.anchor ~= nil,
            sentence = sentence ~= nil,
            paragraph = paragraph ~= nil,
            semantic_context = is_epub and (sentence ~= nil or paragraph ~= nil) or false,
            fixed_layout = snapshot.anchor.kind == "fixed_page",
            ocr_or_text_layer = snapshot.anchor.kind == "fixed_page"
                and cleanText(snapshot.text) ~= nil or nil,
        },
    }
    return context
end

ContextResolver.cleanText = cleanText
ContextResolver.prefixBytes = prefixBytes
ContextResolver.suffixBytes = suffixBytes

return ContextResolver
