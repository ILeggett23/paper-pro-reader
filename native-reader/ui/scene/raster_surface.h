#pragma once

#include "core/types.h"

#include <cstdint>

namespace paperpro {

class RasterSurface {
public:
    explicit RasterSurface(SurfaceView view) noexcept : view_(view) {}

    [[nodiscard]] bool valid() const noexcept { return view_.valid(); }
    [[nodiscard]] Rect bounds() const noexcept { return view_.bounds(); }
    [[nodiscard]] SurfaceView view() const noexcept { return view_; }

    void clear(std::uint8_t gray = 255) noexcept;
    void setPixel(int x, int y, std::uint8_t gray) noexcept;
    void fillRect(Rect rect, std::uint8_t gray) noexcept;
    void drawRect(Rect rect, int thickness, std::uint8_t gray) noexcept;
    void drawLine(Point start, Point end, int width, std::uint8_t gray) noexcept;

private:
    void drawDisc(Point center, int radius, std::uint8_t gray) noexcept;

    SurfaceView view_;
};

} // namespace paperpro
