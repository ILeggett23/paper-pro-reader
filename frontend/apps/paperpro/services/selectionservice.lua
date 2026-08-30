local SelectionService = {}
SelectionService.__index = SelectionService

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

local function copyBox(box)
    if not box or box.x == nil or box.y == nil or box.w == nil or box.h == nil then
        return nil
    end
    return { x = box.x, y = box.y, w = box.w, h = box.h }
end

local function copyBoxes(boxes)
    local copied = {}
    for _, box in ipairs(boxes or {}) do
        local copied_box = copyBox(box)
        if copied_box then
            table.insert(copied, copied_box)
        end
    end
    return copied
end

local function cleanText(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:match("^%s*(.-)%s*$")
    if text == "" then
        return nil
    end
    return text
end

local function getCurrentPage(ui, selection)
    if selection.pos0 and selection.pos0.page then
        return selection.pos0.page
    end
    if ui and ui.getCurrentPage then
        local ok, page = pcall(ui.getCurrentPage, ui)
        if ok then
            return page
        end
    end
end

local function getChapter(ui, position)
    if not (ui and ui.toc and ui.toc.getTocTitleByPage and position) then
        return nil
    end
    local ok, chapter = pcall(ui.toc.getTocTitleByPage, ui.toc, position)
    if ok and chapter and chapter ~= "" then
        return chapter
    end
end

function SelectionService:new(options)
    return setmetatable(options or {}, self)
end

function SelectionService:_getContext(ui)
    if not (ui and ui.highlight and ui.highlight.getSelectedWordContext) then
        return nil, nil
    end
    local ok, before_context, after_context = pcall(
        ui.highlight.getSelectedWordContext, ui.highlight, self.context_word_count or 15
    )
    if ok then
        return before_context, after_context
    end
end

function SelectionService:_getFixedScreenBoxes(ui, page, selection)
    local screen_boxes = {}
    local source_boxes = selection.sboxes or selection.pboxes or {}
    for _, box in ipairs(source_boxes) do
        local transformed
        if ui and ui.view and ui.view.pageToScreenTransform and page then
            local ok, result = pcall(ui.view.pageToScreenTransform, ui.view, page, box)
            if ok then
                transformed = result
            end
        end
        local copied_box = copyBox(transformed or box)
        if copied_box then
            table.insert(screen_boxes, copied_box)
        end
    end
    return screen_boxes
end

function SelectionService:createSnapshot(ui, selection, options)
    options = options or {}
    if type(selection) ~= "table" then
        return nil
    end

    local text = cleanText(selection.text)
    if not text then
        return nil
    end

    local kind = options.kind or (ui and ui.rolling and "xpointer" or "fixed_page")
    local document_id = ui and ui.document and ui.document.file or options.document_id
    local pos0 = deepCopy(selection.pos0)
    local pos1 = deepCopy(selection.pos1)
    local page = getCurrentPage(ui, selection)
    local page_boxes = copyBoxes(selection.pboxes or selection.sboxes)
    local screen_boxes
    local anchor

    if kind == "xpointer" then
        screen_boxes = copyBoxes(selection.sboxes)
        if pos0 and pos1 then
            anchor = {
                kind = "xpointer",
                document_id = document_id,
                start = pos0,
                finish = pos1,
            }
        end
    else
        kind = "fixed_page"
        screen_boxes = self:_getFixedScreenBoxes(ui, page, selection)
        if page and pos0 and pos1 then
            anchor = {
                kind = "fixed_page",
                document_id = document_id,
                page = page,
                pos0 = pos0,
                pos1 = pos1,
                page_boxes = deepCopy(page_boxes),
            }
        end
    end

    local before_context, after_context = self:_getContext(ui)
    local props = ui and ui.doc_props or {}
    local chapter_position = kind == "xpointer" and pos0 or page
    local selected_word = options.is_word_selection and text or nil

    return {
        text = text,
        selected_word = selected_word,
        before_context = before_context,
        after_context = after_context,
        screen_boxes = screen_boxes,
        page_boxes = page_boxes,
        anchor = anchor,
        book_title = props.display_title or props.title,
        author = deepCopy(props.authors or props.author),
        chapter = getChapter(ui, chapter_position),
        capabilities = {
            xpointer = kind == "xpointer",
            fixed_page = kind == "fixed_page",
            precise_anchor = anchor ~= nil,
            screen_boxes = #screen_boxes > 0,
            page_boxes = #page_boxes > 0,
            word_context = before_context ~= nil or after_context ~= nil,
            sentence = false,
            paragraph = false,
        },
    }
end

SelectionService.deepCopy = deepCopy

return SelectionService
