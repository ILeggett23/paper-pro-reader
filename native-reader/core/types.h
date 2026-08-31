#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

namespace paperpro {

using MonotonicNs = std::uint64_t;

struct Point {
    int x = 0;
    int y = 0;

    friend constexpr bool operator==(const Point&, const Point&) = default;
};

struct Rect {
    int x = 0;
    int y = 0;
    int width = 0;
    int height = 0;

    [[nodiscard]] constexpr bool empty() const noexcept {
        return width <= 0 || height <= 0;
    }

    [[nodiscard]] constexpr int right() const noexcept { return x + width; }
    [[nodiscard]] constexpr int bottom() const noexcept { return y + height; }

    [[nodiscard]] constexpr bool contains(Point point) const noexcept {
        return !empty() && point.x >= x && point.y >= y
            && point.x < right() && point.y < bottom();
    }

    [[nodiscard]] constexpr bool intersects(const Rect& other) const noexcept {
        return !empty() && !other.empty() && x < other.right() && right() > other.x
            && y < other.bottom() && bottom() > other.y;
    }

    [[nodiscard]] Rect clippedTo(const Rect& bounds) const noexcept {
        const auto left = std::max(x, bounds.x);
        const auto top = std::max(y, bounds.y);
        const auto clipped_right = std::min(right(), bounds.right());
        const auto clipped_bottom = std::min(bottom(), bounds.bottom());
        if (clipped_right <= left || clipped_bottom <= top) {
            return {};
        }
        return {left, top, clipped_right - left, clipped_bottom - top};
    }

    [[nodiscard]] Rect united(const Rect& other) const noexcept {
        if (empty()) return other;
        if (other.empty()) return *this;
        const auto left = std::min(x, other.x);
        const auto top = std::min(y, other.y);
        const auto united_right = std::max(right(), other.right());
        const auto united_bottom = std::max(bottom(), other.bottom());
        return {left, top, united_right - left, united_bottom - top};
    }

    [[nodiscard]] Rect padded(int amount, const Rect& bounds) const noexcept {
        if (empty()) return {};
        const std::int64_t left = static_cast<std::int64_t>(x) - amount;
        const std::int64_t top = static_cast<std::int64_t>(y) - amount;
        const std::int64_t padded_right = static_cast<std::int64_t>(right()) + amount;
        const std::int64_t padded_bottom = static_cast<std::int64_t>(bottom()) + amount;
        const Rect expanded{
            static_cast<int>(std::max<std::int64_t>(left, -1'000'000)),
            static_cast<int>(std::max<std::int64_t>(top, -1'000'000)),
            static_cast<int>(std::min<std::int64_t>(padded_right - left, 2'000'000)),
            static_cast<int>(std::min<std::int64_t>(padded_bottom - top, 2'000'000)),
        };
        return expanded.clippedTo(bounds);
    }

    friend constexpr bool operator==(const Rect&, const Rect&) = default;
};

enum class PixelFormat : std::uint8_t {
    Bgra8888,
    Rgb565,
};

struct SurfaceView {
    std::byte* pixels = nullptr;
    int width = 0;
    int height = 0;
    std::ptrdiff_t stride_bytes = 0;
    PixelFormat format = PixelFormat::Bgra8888;

    [[nodiscard]] bool valid() const noexcept {
        const auto minimum_stride = format == PixelFormat::Bgra8888 ? width * 4 : width * 2;
        return pixels != nullptr && width > 0 && height > 0 && stride_bytes >= minimum_stride;
    }

    [[nodiscard]] Rect bounds() const noexcept { return {0, 0, width, height}; }
};

enum class UpdateMode : std::uint8_t {
    InteractiveMono,
    QualityMono,
    Ui,
    Full,
};

enum class CompletionModel : std::uint8_t {
    Explicit,
    Estimated,
};

struct UpdateRequest {
    Rect region;
    UpdateMode mode = UpdateMode::InteractiveMono;
    MonotonicNs submitted_at_ns = 0;
};

struct DisplaySubmission {
    bool accepted = false;
    std::uint64_t token = 0;
};

struct DisplayCompletion {
    std::uint64_t token = 0;
    MonotonicNs completed_at_ns = 0;
};

enum class Tool : std::uint8_t {
    Pen,
    Eraser,
};

enum class ControlButton : std::uint8_t {
    None,
    Pen,
    Eraser,
    Undo,
    Clear,
    Exit,
};

enum class InputEventType : std::uint8_t {
    MarkerDown,
    MarkerMove,
    MarkerUp,
    TouchDown,
    TouchMove,
    TouchUp,
    PowerPressed,
};

struct InputEvent {
    InputEventType type = InputEventType::MarkerMove;
    Point point;
    MonotonicNs received_at_ns = 0;
    std::uint32_t sequence = 0;
    std::int32_t contact_id = -1;
    std::uint16_t pressure = 0;
    Tool tool = Tool::Pen;
};

[[nodiscard]] constexpr bool isMarkerEvent(InputEventType type) noexcept {
    return type == InputEventType::MarkerDown || type == InputEventType::MarkerMove
        || type == InputEventType::MarkerUp;
}

[[nodiscard]] constexpr std::string_view updateModeName(UpdateMode mode) noexcept {
    switch (mode) {
    case UpdateMode::InteractiveMono: return "interactive_mono";
    case UpdateMode::QualityMono: return "quality_mono";
    case UpdateMode::Ui: return "ui";
    case UpdateMode::Full: return "full";
    }
    return "unknown";
}

} // namespace paperpro
