local Placement = {}

local function clamp(value, minimum, maximum)
    if maximum < minimum then
        return minimum
    end
    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end
    return value
end

function Placement.combineBoxes(boxes)
    local left, top, right, bottom
    for _, box in ipairs(boxes or {}) do
        if box.x ~= nil and box.y ~= nil and box.w and box.h and box.w >= 0 and box.h >= 0 then
            left = left and math.min(left, box.x) or box.x
            top = top and math.min(top, box.y) or box.y
            right = right and math.max(right, box.x + box.w) or box.x + box.w
            bottom = bottom and math.max(bottom, box.y + box.h) or box.y + box.h
        end
    end
    if not left then
        return nil
    end
    return { x = left, y = top, w = right - left, h = bottom - top }
end

function Placement.calculate(boxes, overlay_size, viewport, gap)
    viewport = viewport or {}
    overlay_size = overlay_size or {}
    local viewport_w = math.max(0, viewport.w or 0)
    local viewport_h = math.max(0, viewport.h or 0)
    local overlay_w = math.max(0, overlay_size.w or 0)
    local overlay_h = math.max(0, overlay_size.h or 0)
    gap = math.max(0, gap or 0)

    local anchor = Placement.combineBoxes(boxes)
    if not anchor then
        return {
            placement = "center",
            x = clamp(math.floor((viewport_w - overlay_w) / 2), 0, viewport_w - overlay_w),
            y = clamp(math.floor((viewport_h - overlay_h) / 2), 0, viewport_h - overlay_h),
            w = overlay_w,
            h = overlay_h,
        }
    end

    local anchor_right = anchor.x + anchor.w
    local anchor_bottom = anchor.y + anchor.h
    local centered_x = anchor.x + math.floor((anchor.w - overlay_w) / 2)
    local centered_y = anchor.y + math.floor((anchor.h - overlay_h) / 2)
    local candidates = {
        { placement = "below", space = viewport_h - anchor_bottom - gap, needed = overlay_h,
          x = centered_x, y = anchor_bottom + gap },
        { placement = "above", space = anchor.y - gap, needed = overlay_h,
          x = centered_x, y = anchor.y - gap - overlay_h },
        { placement = "right", space = viewport_w - anchor_right - gap, needed = overlay_w,
          x = anchor_right + gap, y = centered_y },
        { placement = "left", space = anchor.x - gap, needed = overlay_w,
          x = anchor.x - gap - overlay_w, y = centered_y },
    }

    local selected
    for _, candidate in ipairs(candidates) do
        if candidate.space >= candidate.needed then
            selected = candidate
            break
        end
    end
    if not selected then
        local best_ratio = -math.huge
        for _, candidate in ipairs(candidates) do
            local ratio = candidate.needed > 0 and candidate.space / candidate.needed or candidate.space
            if ratio > best_ratio then
                best_ratio = ratio
                selected = candidate
            end
        end
    end

    return {
        placement = selected.placement,
        x = clamp(selected.x, 0, viewport_w - overlay_w),
        y = clamp(selected.y, 0, viewport_h - overlay_h),
        w = overlay_w,
        h = overlay_h,
        anchor_bounds = anchor,
    }
end

return Placement
