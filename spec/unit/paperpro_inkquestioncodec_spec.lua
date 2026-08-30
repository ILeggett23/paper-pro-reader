describe("Paper Pro InkQuestionCodec", function()
    local InkQuestionCodec, InkStroke, mime

    setup(function()
        require("commonrequire")
        InkQuestionCodec = require("apps/paperpro/ink/inkquestioncodec")
        InkStroke = require("apps/paperpro/ink/inkstroke")
        mime = require("mime")
    end)

    local function stroke()
        local value = InkStroke:new{ id = "q", tool = "pen", coordinate_space = "screen-v1" }
        value:addPoint{ x = 100, y = 100, timestamp = 1 }
        value:addPoint{ x = 220, y = 150, timestamp = 2 }
        value:finish(2)
        return value:toTable()
    end

    it("creates a tight bounded PNG transport artifact", function()
        local image = assert(InkQuestionCodec:new():encode({ stroke() }))
        assert.are.same("image/png", image.mime_type)
        assert.is_true(image.bytes <= InkQuestionCodec.MAX_IMAGE_BYTES)
        assert.is_true(image.width < InkQuestionCodec.MAX_WIDTH)
        assert.is_true(image.height < InkQuestionCodec.MAX_HEIGHT)
        local bytes = mime.unb64(image.data_base64)
        assert.are.same(image.bytes, #bytes)
        assert.are.same("\137PNG\r\n\26\n", bytes:sub(1, 8))
    end)

    it("rejects empty and excessive raw sessions", function()
        local image, err = InkQuestionCodec:new():encode({})
        assert.is_nil(image)
        assert.are.same("ink_empty", err)
    end)
end)
