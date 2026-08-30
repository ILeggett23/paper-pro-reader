local Font = require("ui/font")

local HandwrittenResponseRenderer = {}
HandwrittenResponseRenderer.__index = HandwrittenResponseRenderer

function HandwrittenResponseRenderer:new(options)
    return setmetatable(options or {}, self)
end

function HandwrittenResponseRenderer:getFace()
    return Font:getFace("NotoSerif-Italic.ttf", self.font_size or 24)
        or Font:getFace("infofont")
end

function HandwrittenResponseRenderer:model(text, width, height)
    return {
        text = text,
        face = self:getFace(),
        width = width,
        height = height,
        refresh_mode = "complete",
        fallback_enabled = true,
    }
end

return HandwrittenResponseRenderer
