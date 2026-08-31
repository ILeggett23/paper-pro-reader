#include "ui/scene/raster_surface.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace paperpro {

void RasterSurface::clear(std::uint8_t gray) noexcept {
    fillRect(bounds(), gray);
}

void RasterSurface::setPixel(int x, int y, std::uint8_t gray) noexcept {
    if (x < 0 || y < 0 || x >= view_.width || y >= view_.height || !view_.pixels) return;
    auto* row = view_.pixels + static_cast<std::ptrdiff_t>(y) * view_.stride_bytes;
    if (view_.format == PixelFormat::Bgra8888) {
        auto* pixel = reinterpret_cast<std::uint8_t*>(row) + x * 4;
        pixel[0] = gray;
        pixel[1] = gray;
        pixel[2] = gray;
        pixel[3] = 0xff;
    } else {
        const auto red = static_cast<std::uint16_t>((gray * 31u + 127u) / 255u);
        const auto green = static_cast<std::uint16_t>((gray * 63u + 127u) / 255u);
        const auto blue = red;
        const auto value = static_cast<std::uint16_t>((red << 11) | (green << 5) | blue);
        auto* pixel = reinterpret_cast<std::uint8_t*>(row) + x * 2;
        pixel[0] = static_cast<std::uint8_t>(value & 0xff);
        pixel[1] = static_cast<std::uint8_t>(value >> 8);
    }
}

void RasterSurface::fillRect(Rect rect, std::uint8_t gray) noexcept {
    rect = rect.clippedTo(bounds());
    if (rect.empty()) return;
    if (view_.format == PixelFormat::Bgra8888) {
        for (int y = rect.y; y < rect.bottom(); ++y) {
            auto* row = reinterpret_cast<std::uint8_t*>(view_.pixels
                + static_cast<std::ptrdiff_t>(y) * view_.stride_bytes) + rect.x * 4;
            for (int x = 0; x < rect.width; ++x) {
                row[x * 4] = gray;
                row[x * 4 + 1] = gray;
                row[x * 4 + 2] = gray;
                row[x * 4 + 3] = 0xff;
            }
        }
        return;
    }
    const auto red = static_cast<std::uint16_t>((gray * 31u + 127u) / 255u);
    const auto green = static_cast<std::uint16_t>((gray * 63u + 127u) / 255u);
    const auto value = static_cast<std::uint16_t>((red << 11) | (green << 5) | red);
    for (int y = rect.y; y < rect.bottom(); ++y) {
        auto* row = reinterpret_cast<std::uint8_t*>(view_.pixels
            + static_cast<std::ptrdiff_t>(y) * view_.stride_bytes) + rect.x * 2;
        for (int x = 0; x < rect.width; ++x) {
            row[x * 2] = static_cast<std::uint8_t>(value & 0xff);
            row[x * 2 + 1] = static_cast<std::uint8_t>(value >> 8);
        }
    }
}

void RasterSurface::drawRect(Rect rect, int thickness, std::uint8_t gray) noexcept {
    if (thickness <= 0 || rect.empty()) return;
    fillRect({rect.x, rect.y, rect.width, thickness}, gray);
    fillRect({rect.x, rect.bottom() - thickness, rect.width, thickness}, gray);
    fillRect({rect.x, rect.y, thickness, rect.height}, gray);
    fillRect({rect.right() - thickness, rect.y, thickness, rect.height}, gray);
}

void RasterSurface::drawDisc(Point center, int radius, std::uint8_t gray) noexcept {
    radius = std::max(1, radius);
    const auto radius_squared = radius * radius;
    for (int y = -radius; y <= radius; ++y) {
        for (int x = -radius; x <= radius; ++x) {
            if (x * x + y * y <= radius_squared) {
                setPixel(center.x + x, center.y + y, gray);
            }
        }
    }
}

void RasterSurface::drawLine(Point start, Point end, int width, std::uint8_t gray) noexcept {
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    const auto steps = std::max(std::abs(dx), std::abs(dy));
    const auto radius = std::max(1, (width + 1) / 2);
    if (steps == 0) {
        drawDisc(start, radius, gray);
        return;
    }
    for (int index = 0; index <= steps; ++index) {
        const auto x = start.x + static_cast<int>(std::llround(
            static_cast<double>(dx) * index / steps));
        const auto y = start.y + static_cast<int>(std::llround(
            static_cast<double>(dy) * index / steps));
        drawDisc({x, y}, radius, gray);
    }
}

} // namespace paperpro
