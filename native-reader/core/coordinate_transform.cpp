#include "core/coordinate_transform.h"

#include <algorithm>
#include <cstdint>

namespace paperpro {

CoordinateTransform::CoordinateTransform(AxisRange raw_x, AxisRange raw_y,
    int display_width, int display_height, Rotation rotation) noexcept
    : raw_x_(raw_x)
    , raw_y_(raw_y)
    , display_width_(display_width)
    , display_height_(display_height)
    , rotation_(rotation) {
}

int CoordinateTransform::scale(int value, AxisRange input, int output_size) noexcept {
    value = std::clamp(value, input.minimum, input.maximum);
    const auto numerator = static_cast<std::int64_t>(value - input.minimum)
        * static_cast<std::int64_t>(output_size - 1);
    const auto denominator = static_cast<std::int64_t>(input.maximum - input.minimum);
    return static_cast<int>((numerator + denominator / 2) / denominator);
}

std::optional<Point> CoordinateTransform::normalize(int raw_x, int raw_y) const noexcept {
    if (!raw_x_.valid() || !raw_y_.valid() || display_width_ <= 0 || display_height_ <= 0) {
        return std::nullopt;
    }

    const auto normalized_x = scale(raw_x, raw_x_,
        rotation_ == Rotation::Degrees90 || rotation_ == Rotation::Degrees270
            ? display_height_ : display_width_);
    const auto normalized_y = scale(raw_y, raw_y_,
        rotation_ == Rotation::Degrees90 || rotation_ == Rotation::Degrees270
            ? display_width_ : display_height_);

    switch (rotation_) {
    case Rotation::Degrees0:
        return Point{normalized_x, normalized_y};
    case Rotation::Degrees90:
        return Point{display_width_ - 1 - normalized_y, normalized_x};
    case Rotation::Degrees180:
        return Point{display_width_ - 1 - normalized_x,
            display_height_ - 1 - normalized_y};
    case Rotation::Degrees270:
        return Point{normalized_y, display_height_ - 1 - normalized_x};
    }
    return std::nullopt;
}

} // namespace paperpro
