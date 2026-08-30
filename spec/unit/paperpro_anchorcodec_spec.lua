describe("Paper Pro AnchorCodec", function()
    local AnchorCodec

    setup(function()
        require("commonrequire")
        AnchorCodec = require("apps/paperpro/services/anchorcodec")
    end)

    it("round trips an EPUB XPointer range", function()
        local anchor = {
            kind = "xpointer", document_id = "/books/book.epub",
            start = "/body/p[1].0", finish = "/body/p[1].8",
        }
        local decoded = AnchorCodec.fromColumns(AnchorCodec.toColumns(anchor))
        assert.are.same(anchor, decoded)
    end)

    it("round trips a fixed-page PDF range", function()
        local anchor = {
            kind = "fixed_page", document_id = "/books/book.pdf", page = 4,
            pos0 = { page = 4, x = 10, y = 20 },
            pos1 = { page = 4, x = 80, y = 45 },
            page_boxes = {{ x = 10, y = 20, w = 70, h = 25 }},
        }
        local decoded = AnchorCodec.fromColumns(AnchorCodec.toColumns(anchor))
        assert.are.same(anchor, decoded)
    end)

    it("rejects malformed stored anchors without executing data", function()
        assert.is_nil(AnchorCodec.fromColumns{
            anchor_kind = "fixed_page", anchor_page = 2,
            anchor_pos0_json = "not json", anchor_pos1_json = "{}",
        })
        assert.is_nil(AnchorCodec.fromColumns{
            anchor_kind = "xpointer", anchor_start = "/body/p[1].0",
        })
    end)
end)
