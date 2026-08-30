describe("Paper Pro HandwrittenResponseRenderer", function()
    local Renderer

    setup(function()
        require("commonrequire")
        Renderer = require("apps/paperpro/overlays/handwrittenresponserenderer")
    end)

    it("uses an existing italic face with fallback and complete-response refresh", function()
        local renderer = Renderer:new{ font_size = 22 }
        local model = renderer:model("Punctuation, paragraphs — and UTF-8: café.\n\nSecond paragraph.",
            900, 420)
        assert.is_truthy(model.face)
        assert.are.same("NotoSerif-Italic.ttf", model.face.realname)
        assert.is_true(model.fallback_enabled)
        assert.are.same("complete", model.refresh_mode)
        assert.are.same(900, model.width)
        assert.matches("Second paragraph", model.text)
    end)
end)
