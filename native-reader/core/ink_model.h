#pragma once

#include "core/types.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace paperpro {

struct InkPoint {
    Point position;
    MonotonicNs received_at_ns = 0;
    std::uint16_t pressure = 0;
};

struct StrokeView {
    std::uint32_t id = 0;
    std::span<const InkPoint> points;
    Rect bounds;
};

class InkModel {
public:
    static constexpr std::size_t kMaxStrokes = 512;
    static constexpr std::size_t kMaxPointsPerStroke = 8192;
    static constexpr std::size_t kMaxPointsTotal = 262144;
    static constexpr std::size_t kMaxUndo = 64;

    bool beginStroke(const InkPoint& point) noexcept;
    [[nodiscard]] std::optional<Rect> appendPoint(const InkPoint& point) noexcept;
    [[nodiscard]] std::optional<Rect> finishStroke() noexcept;
    void cancelStroke() noexcept;

    void beginEraser() noexcept;
    [[nodiscard]] std::optional<Rect> eraseAt(Point point, int radius) noexcept;
    bool finishEraser() noexcept;

    [[nodiscard]] std::optional<Rect> undo() noexcept;
    [[nodiscard]] std::optional<Rect> clear() noexcept;

    [[nodiscard]] bool strokeActive() const noexcept { return active_; }
    [[nodiscard]] bool eraserActive() const noexcept { return eraser_active_; }
    [[nodiscard]] bool capacityFailure() const noexcept { return capacity_failure_; }
    [[nodiscard]] std::size_t strokeCount() const noexcept { return stroke_count_; }
    [[nodiscard]] std::size_t visibleStrokeCount() const noexcept;
    [[nodiscard]] std::size_t totalPoints() const noexcept { return used_points_; }

    template <typename Visitor>
    void forEachVisible(Visitor&& visitor) const {
        for (std::size_t index = 0; index < stroke_count_; ++index) {
            const auto& descriptor = strokes_[index];
            if (!descriptor.visible) continue;
            visitor(StrokeView{
                descriptor.id,
                std::span<const InkPoint>{points_.data() + descriptor.offset, descriptor.count},
                descriptor.bounds,
            });
        }
    }

private:
    enum class UndoKind : std::uint8_t { Add, Delete, Clear };

    struct StrokeDescriptor {
        std::uint32_t id = 0;
        std::uint32_t offset = 0;
        std::uint32_t count = 0;
        Rect bounds;
        bool visible = false;
    };

    struct UndoOperation {
        UndoKind kind = UndoKind::Add;
        std::uint16_t count = 0;
        std::array<std::uint16_t, kMaxStrokes> stroke_indices{};
    };

    [[nodiscard]] static Rect pointBounds(Point point) noexcept;
    [[nodiscard]] static std::int64_t segmentDistanceSquared(
        Point point, Point start, Point end) noexcept;
    [[nodiscard]] bool hitTest(const StrokeDescriptor& stroke, Point point, int radius) const noexcept;
    void pushUndo(const UndoOperation& operation) noexcept;
    [[nodiscard]] Rect operationBounds(const UndoOperation& operation) const noexcept;

    std::array<InkPoint, kMaxPointsTotal> points_{};
    std::array<StrokeDescriptor, kMaxStrokes> strokes_{};
    std::array<UndoOperation, kMaxUndo> undo_{};
    std::size_t used_points_ = 0;
    std::size_t stroke_count_ = 0;
    std::size_t undo_count_ = 0;
    std::uint32_t next_id_ = 1;

    bool active_ = false;
    std::size_t active_offset_ = 0;
    std::size_t active_count_ = 0;
    Rect active_bounds_;

    bool eraser_active_ = false;
    UndoOperation eraser_operation_{UndoKind::Delete};
    std::array<bool, kMaxStrokes> erased_in_gesture_{};
    bool capacity_failure_ = false;
};

} // namespace paperpro
