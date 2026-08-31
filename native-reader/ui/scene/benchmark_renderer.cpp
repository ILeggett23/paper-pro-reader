#include "ui/scene/benchmark_renderer.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>

namespace paperpro {
namespace {

using Glyph = std::array<std::uint8_t, 7>;

Glyph glyph(char value) noexcept {
    switch (static_cast<char>(std::toupper(static_cast<unsigned char>(value)))) {
    case 'A': return {0x0e,0x11,0x11,0x1f,0x11,0x11,0x11};
    case 'B': return {0x1e,0x11,0x11,0x1e,0x11,0x11,0x1e};
    case 'C': return {0x0f,0x10,0x10,0x10,0x10,0x10,0x0f};
    case 'D': return {0x1e,0x11,0x11,0x11,0x11,0x11,0x1e};
    case 'E': return {0x1f,0x10,0x10,0x1e,0x10,0x10,0x1f};
    case 'F': return {0x1f,0x10,0x10,0x1e,0x10,0x10,0x10};
    case 'G': return {0x0f,0x10,0x10,0x13,0x11,0x11,0x0f};
    case 'H': return {0x11,0x11,0x11,0x1f,0x11,0x11,0x11};
    case 'I': return {0x1f,0x04,0x04,0x04,0x04,0x04,0x1f};
    case 'J': return {0x07,0x02,0x02,0x02,0x12,0x12,0x0c};
    case 'K': return {0x11,0x12,0x14,0x18,0x14,0x12,0x11};
    case 'L': return {0x10,0x10,0x10,0x10,0x10,0x10,0x1f};
    case 'M': return {0x11,0x1b,0x15,0x15,0x11,0x11,0x11};
    case 'N': return {0x11,0x19,0x15,0x13,0x11,0x11,0x11};
    case 'O': return {0x0e,0x11,0x11,0x11,0x11,0x11,0x0e};
    case 'P': return {0x1e,0x11,0x11,0x1e,0x10,0x10,0x10};
    case 'Q': return {0x0e,0x11,0x11,0x11,0x15,0x12,0x0d};
    case 'R': return {0x1e,0x11,0x11,0x1e,0x14,0x12,0x11};
    case 'S': return {0x0f,0x10,0x10,0x0e,0x01,0x01,0x1e};
    case 'T': return {0x1f,0x04,0x04,0x04,0x04,0x04,0x04};
    case 'U': return {0x11,0x11,0x11,0x11,0x11,0x11,0x0e};
    case 'V': return {0x11,0x11,0x11,0x11,0x11,0x0a,0x04};
    case 'W': return {0x11,0x11,0x11,0x15,0x15,0x15,0x0a};
    case 'X': return {0x11,0x11,0x0a,0x04,0x0a,0x11,0x11};
    case 'Y': return {0x11,0x11,0x0a,0x04,0x04,0x04,0x04};
    case 'Z': return {0x1f,0x01,0x02,0x04,0x08,0x10,0x1f};
    case '0': return {0x0e,0x11,0x13,0x15,0x19,0x11,0x0e};
    case '1': return {0x04,0x0c,0x04,0x04,0x04,0x04,0x0e};
    case '2': return {0x0e,0x11,0x01,0x02,0x04,0x08,0x1f};
    case '3': return {0x1e,0x01,0x01,0x0e,0x01,0x01,0x1e};
    case '4': return {0x02,0x06,0x0a,0x12,0x1f,0x02,0x02};
    case '5': return {0x1f,0x10,0x10,0x1e,0x01,0x01,0x1e};
    case '6': return {0x0e,0x10,0x10,0x1e,0x11,0x11,0x0e};
    case '7': return {0x1f,0x01,0x02,0x04,0x08,0x08,0x08};
    case '8': return {0x0e,0x11,0x11,0x0e,0x11,0x11,0x0e};
    case '9': return {0x0e,0x11,0x11,0x0f,0x01,0x01,0x0e};
    case '-': return {0x00,0x00,0x00,0x1f,0x00,0x00,0x00};
    case '/': return {0x01,0x02,0x02,0x04,0x08,0x08,0x10};
    case ':': return {0x00,0x04,0x04,0x00,0x04,0x04,0x00};
    default: return {};
    }
}

constexpr std::array<ControlButton, 5> kButtons{
    ControlButton::Pen, ControlButton::Eraser, ControlButton::Undo,
    ControlButton::Clear, ControlButton::Exit,
};

} // namespace

BenchmarkRenderer::BenchmarkRenderer(SurfaceView surface) noexcept : surface_(surface) {}

Rect BenchmarkRenderer::canvasBounds() const noexcept {
    const auto bounds = surface_.bounds();
    return {0, kStatusHeight, bounds.width,
        std::max(0, bounds.height - kStatusHeight - kToolbarHeight)};
}

Rect BenchmarkRenderer::toolbarBounds() const noexcept {
    const auto bounds = surface_.bounds();
    return {0, std::max(0, bounds.height - kToolbarHeight), bounds.width,
        std::min(kToolbarHeight, bounds.height)};
}

Rect BenchmarkRenderer::statusBounds() const noexcept {
    const auto bounds = surface_.bounds();
    return {0, 0, bounds.width, std::min(kStatusHeight, bounds.height)};
}

Rect BenchmarkRenderer::buttonBounds(ControlButton button) const noexcept {
    const auto toolbar = toolbarBounds();
    const auto found = std::find(kButtons.begin(), kButtons.end(), button);
    if (found == kButtons.end()) return {};
    const auto index = static_cast<int>(std::distance(kButtons.begin(), found));
    const auto nominal_width = toolbar.width / static_cast<int>(kButtons.size());
    const auto x = toolbar.x + index * nominal_width;
    const auto width = index == static_cast<int>(kButtons.size()) - 1
        ? toolbar.right() - x : nominal_width;
    return {x, toolbar.y, width, toolbar.height};
}

ControlButton BenchmarkRenderer::buttonAt(Point point) const noexcept {
    for (const auto button : kButtons) {
        if (buttonBounds(button).contains(point)) return button;
    }
    return ControlButton::None;
}

void BenchmarkRenderer::drawText(Point origin, std::string_view text, int scale,
    std::uint8_t gray, std::optional<Rect> clip) noexcept {
    const auto clip_bounds = clip.value_or(surface_.bounds());
    int cursor = origin.x;
    for (const auto character : text) {
        if (character == ' ') {
            cursor += 6 * scale;
            continue;
        }
        const auto pattern = glyph(character);
        for (int row = 0; row < 7; ++row) {
            for (int column = 0; column < 5; ++column) {
                if ((pattern[static_cast<std::size_t>(row)] & (1u << (4 - column))) == 0) continue;
                const Rect pixel{cursor + column * scale, origin.y + row * scale, scale, scale};
                surface_.fillRect(pixel.clippedTo(clip_bounds), gray);
            }
        }
        cursor += 6 * scale;
    }
}

void BenchmarkRenderer::drawButton(ControlButton button, std::string_view label, bool active) noexcept {
    const auto bounds = buttonBounds(button);
    const auto background = static_cast<std::uint8_t>(active ? 0 : 255);
    const auto foreground = static_cast<std::uint8_t>(active ? 255 : 0);
    surface_.fillRect(bounds, background);
    surface_.drawRect(bounds, 3, foreground);
    constexpr int scale = 4;
    const auto text_width = static_cast<int>(label.size()) * 6 * scale - scale;
    const Point origin{
        bounds.x + std::max(8, (bounds.width - text_width) / 2),
        bounds.y + (bounds.height - 7 * scale) / 2,
    };
    drawText(origin, label, scale, foreground, bounds);
}

void BenchmarkRenderer::drawInitial(std::string_view backend_name, Tool active_tool) noexcept {
    surface_.clear(255);
    const auto status = statusBounds();
    surface_.drawRect(status, 3, 0);
    drawText({20, 18}, "PAPER PRO NATIVE INK", 4, 0, status);
    const auto backend_x = std::max(20, status.width - 360);
    drawText({backend_x, 18}, backend_name, 4, 0, status);
    (void)drawControls(active_tool);
}

Rect BenchmarkRenderer::drawControls(Tool active_tool) noexcept {
    drawButton(ControlButton::Pen, "PEN", active_tool == Tool::Pen);
    drawButton(ControlButton::Eraser, "ERASER", active_tool == Tool::Eraser);
    drawButton(ControlButton::Undo, "UNDO", false);
    drawButton(ControlButton::Clear, "CLEAR", false);
    drawButton(ControlButton::Exit, "EXIT", false);
    return toolbarBounds();
}

Rect BenchmarkRenderer::drawSegment(Point start, Point end) noexcept {
    surface_.drawLine(start, end, kStrokeWidth, 0);
    return Rect{start.x, start.y, 1, 1}.united({end.x, end.y, 1, 1})
        .padded(kStrokeWidth + 3, canvasBounds());
}

Rect BenchmarkRenderer::drawPoint(Point point) noexcept {
    surface_.drawLine(point, point, kStrokeWidth, 0);
    return Rect{point.x, point.y, 1, 1}.padded(kStrokeWidth + 3, canvasBounds());
}

void BenchmarkRenderer::restoreInkRegion(Rect region, const InkModel& model) noexcept {
    region = region.padded(kStrokeWidth + 4, canvasBounds());
    if (region.empty()) return;
    surface_.fillRect(region, 255);
    model.forEachVisible([&](const StrokeView& stroke) {
        if (!stroke.bounds.padded(kStrokeWidth + 3, canvasBounds()).intersects(region)) return;
        if (stroke.points.empty()) return;
        if (stroke.points.size() == 1) {
            surface_.drawLine(stroke.points.front().position,
                stroke.points.front().position, kStrokeWidth, 0);
            return;
        }
        for (std::size_t index = 1; index < stroke.points.size(); ++index) {
            surface_.drawLine(stroke.points[index - 1].position,
                stroke.points[index].position, kStrokeWidth, 0);
        }
    });
}

} // namespace paperpro
