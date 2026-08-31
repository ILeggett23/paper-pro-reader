#include "core/ink_model.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace paperpro {

Rect InkModel::pointBounds(Point point) noexcept {
    return {point.x, point.y, 1, 1};
}

bool InkModel::beginStroke(const InkPoint& point) noexcept {
    if (active_) return false;
    if (stroke_count_ >= kMaxStrokes || used_points_ >= kMaxPointsTotal) {
        capacity_failure_ = true;
        return false;
    }
    active_ = true;
    active_offset_ = used_points_;
    active_count_ = 1;
    points_[used_points_++] = point;
    active_bounds_ = pointBounds(point.position);
    return true;
}

std::optional<Rect> InkModel::appendPoint(const InkPoint& point) noexcept {
    if (!active_) return std::nullopt;
    if (active_count_ >= kMaxPointsPerStroke || used_points_ >= kMaxPointsTotal) {
        capacity_failure_ = true;
        return std::nullopt;
    }
    const auto previous = points_[used_points_ - 1].position;
    points_[used_points_++] = point;
    ++active_count_;
    const auto segment_bounds = pointBounds(previous).united(pointBounds(point.position));
    active_bounds_ = active_bounds_.united(segment_bounds);
    return segment_bounds;
}

std::optional<Rect> InkModel::finishStroke() noexcept {
    if (!active_) return std::nullopt;
    active_ = false;
    if (active_count_ == 0 || stroke_count_ >= kMaxStrokes) {
        capacity_failure_ = true;
        return std::nullopt;
    }

    const auto index = stroke_count_++;
    strokes_[index] = StrokeDescriptor{
        next_id_++,
        static_cast<std::uint32_t>(active_offset_),
        static_cast<std::uint32_t>(active_count_),
        active_bounds_,
        true,
    };
    UndoOperation operation{UndoKind::Add};
    operation.count = 1;
    operation.stroke_indices[0] = static_cast<std::uint16_t>(index);
    pushUndo(operation);
    active_count_ = 0;
    return active_bounds_;
}

void InkModel::cancelStroke() noexcept {
    if (!active_) return;
    used_points_ = active_offset_;
    active_ = false;
    active_count_ = 0;
    active_bounds_ = {};
}

void InkModel::beginEraser() noexcept {
    eraser_active_ = true;
    eraser_operation_ = UndoOperation{UndoKind::Delete};
    erased_in_gesture_.fill(false);
}

std::int64_t InkModel::segmentDistanceSquared(Point point, Point start, Point end) noexcept {
    const auto dx = static_cast<double>(end.x - start.x);
    const auto dy = static_cast<double>(end.y - start.y);
    if (dx == 0.0 && dy == 0.0) {
        const auto px = static_cast<std::int64_t>(point.x - start.x);
        const auto py = static_cast<std::int64_t>(point.y - start.y);
        return px * px + py * py;
    }
    const auto projection = ((point.x - start.x) * dx + (point.y - start.y) * dy)
        / (dx * dx + dy * dy);
    const auto t = std::clamp(projection, 0.0, 1.0);
    const auto projected_x = start.x + t * dx;
    const auto projected_y = start.y + t * dy;
    const auto px = point.x - projected_x;
    const auto py = point.y - projected_y;
    return static_cast<std::int64_t>(std::llround(px * px + py * py));
}

bool InkModel::hitTest(const StrokeDescriptor& stroke, Point point, int radius) const noexcept {
    const Rect expanded = {
        stroke.bounds.x - radius,
        stroke.bounds.y - radius,
        stroke.bounds.width + radius * 2,
        stroke.bounds.height + radius * 2,
    };
    if (!expanded.contains(point)) return false;
    const auto radius_squared = static_cast<std::int64_t>(radius) * radius;
    const auto* samples = points_.data() + stroke.offset;
    if (stroke.count == 1) {
        return segmentDistanceSquared(point, samples[0].position, samples[0].position)
            <= radius_squared;
    }
    for (std::size_t index = 1; index < stroke.count; ++index) {
        if (segmentDistanceSquared(point, samples[index - 1].position,
                samples[index].position) <= radius_squared) {
            return true;
        }
    }
    return false;
}

std::optional<Rect> InkModel::eraseAt(Point point, int radius) noexcept {
    if (!eraser_active_) beginEraser();
    Rect dirty;
    bool erased = false;
    for (std::size_t index = 0; index < stroke_count_; ++index) {
        auto& stroke = strokes_[index];
        if (!stroke.visible || erased_in_gesture_[index]) continue;
        if (!hitTest(stroke, point, radius)) continue;
        stroke.visible = false;
        erased_in_gesture_[index] = true;
        if (eraser_operation_.count < kMaxStrokes) {
            eraser_operation_.stroke_indices[eraser_operation_.count++]
                = static_cast<std::uint16_t>(index);
        }
        dirty = dirty.united(stroke.bounds);
        erased = true;
    }
    return erased ? std::optional<Rect>{dirty} : std::nullopt;
}

bool InkModel::finishEraser() noexcept {
    if (!eraser_active_) return false;
    eraser_active_ = false;
    if (eraser_operation_.count == 0) return false;
    pushUndo(eraser_operation_);
    return true;
}

void InkModel::pushUndo(const UndoOperation& operation) noexcept {
    if (operation.count == 0) return;
    if (undo_count_ == kMaxUndo) {
        std::move(undo_.begin() + 1, undo_.end(), undo_.begin());
        --undo_count_;
    }
    undo_[undo_count_++] = operation;
}

Rect InkModel::operationBounds(const UndoOperation& operation) const noexcept {
    Rect bounds;
    for (std::size_t index = 0; index < operation.count; ++index) {
        const auto stroke_index = operation.stroke_indices[index];
        if (stroke_index < stroke_count_) bounds = bounds.united(strokes_[stroke_index].bounds);
    }
    return bounds;
}

std::optional<Rect> InkModel::undo() noexcept {
    if (active_) cancelStroke();
    finishEraser();
    if (undo_count_ == 0) return std::nullopt;
    const auto operation = undo_[--undo_count_];
    const auto bounds = operationBounds(operation);
    for (std::size_t index = 0; index < operation.count; ++index) {
        const auto stroke_index = operation.stroke_indices[index];
        if (stroke_index >= stroke_count_) continue;
        strokes_[stroke_index].visible = operation.kind != UndoKind::Add;
    }
    return bounds.empty() ? std::nullopt : std::optional<Rect>{bounds};
}

std::optional<Rect> InkModel::clear() noexcept {
    if (active_) cancelStroke();
    finishEraser();
    UndoOperation operation{UndoKind::Clear};
    Rect bounds;
    for (std::size_t index = 0; index < stroke_count_; ++index) {
        if (!strokes_[index].visible) continue;
        strokes_[index].visible = false;
        operation.stroke_indices[operation.count++] = static_cast<std::uint16_t>(index);
        bounds = bounds.united(strokes_[index].bounds);
    }
    if (operation.count == 0) return std::nullopt;
    pushUndo(operation);
    return bounds;
}

std::size_t InkModel::visibleStrokeCount() const noexcept {
    std::size_t count = 0;
    for (std::size_t index = 0; index < stroke_count_; ++index) {
        if (strokes_[index].visible) ++count;
    }
    return count;
}

} // namespace paperpro
