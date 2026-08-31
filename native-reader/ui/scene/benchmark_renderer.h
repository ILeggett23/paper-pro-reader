#pragma once

#include "core/ink_model.h"
#include "core/types.h"
#include "ui/scene/raster_surface.h"

#include <array>
#include <string_view>

namespace paperpro {

class BenchmarkRenderer {
public:
    static constexpr int kStatusHeight = 72;
    static constexpr int kToolbarHeight = 180;
    static constexpr int kStrokeWidth = 4;

    explicit BenchmarkRenderer(SurfaceView surface) noexcept;

    [[nodiscard]] Rect canvasBounds() const noexcept;
    [[nodiscard]] Rect toolbarBounds() const noexcept;
    [[nodiscard]] Rect statusBounds() const noexcept;
    [[nodiscard]] Rect buttonBounds(ControlButton button) const noexcept;
    [[nodiscard]] ControlButton buttonAt(Point point) const noexcept;

    void drawInitial(std::string_view backend_name, Tool active_tool) noexcept;
    [[nodiscard]] Rect drawControls(Tool active_tool) noexcept;
    [[nodiscard]] Rect drawSegment(Point start, Point end) noexcept;
    [[nodiscard]] Rect drawPoint(Point point) noexcept;
    void restoreInkRegion(Rect region, const InkModel& model) noexcept;

private:
    void drawText(Point origin, std::string_view text, int scale,
        std::uint8_t gray, std::optional<Rect> clip = std::nullopt) noexcept;
    void drawButton(ControlButton button, std::string_view label, bool active) noexcept;

    RasterSurface surface_;
};

} // namespace paperpro
