local JSON = require("json")

local AnchorCodec = {}

local function encode(value)
    if value == nil then return nil end
    local ok, result = pcall(JSON.encode, value)
    return ok and result or nil
end

local function decode(value)
    if not value or value == "" then return nil end
    local ok, result = pcall(JSON.decode, value)
    return ok and type(result) == "table" and result or nil
end

function AnchorCodec.toColumns(anchor)
    if type(anchor) ~= "table" then return {} end
    if anchor.kind == "xpointer" and type(anchor.start) == "string" and type(anchor.finish) == "string" then
        return {
            anchor_kind = "xpointer", document_id = anchor.document_id,
            anchor_start = anchor.start, anchor_finish = anchor.finish,
        }
    elseif anchor.kind == "fixed_page" and type(anchor.page) == "number" then
        return {
            anchor_kind = "fixed_page", document_id = anchor.document_id, anchor_page = anchor.page,
            anchor_pos0_json = encode(anchor.pos0), anchor_pos1_json = encode(anchor.pos1),
            anchor_page_boxes_json = encode(anchor.page_boxes),
        }
    end
    return {}
end

function AnchorCodec.fromColumns(item)
    if type(item) ~= "table" then return nil end
    if item.anchor_kind == "xpointer" and type(item.anchor_start) == "string"
            and type(item.anchor_finish) == "string" then
        return { kind = "xpointer", document_id = item.document_id,
            start = item.anchor_start, finish = item.anchor_finish }
    elseif item.anchor_kind == "fixed_page" and type(item.anchor_page) == "number" then
        local pos0, pos1 = decode(item.anchor_pos0_json), decode(item.anchor_pos1_json)
        if not (pos0 and pos1) then return nil end
        return { kind = "fixed_page", document_id = item.document_id, page = item.anchor_page,
            pos0 = pos0, pos1 = pos1, page_boxes = decode(item.anchor_page_boxes_json) or {} }
    end
end

return AnchorCodec
