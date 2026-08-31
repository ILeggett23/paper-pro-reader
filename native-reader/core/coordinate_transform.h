#pragma once

#include "core/types.h"

#include <cstdint>
#include <optional>

namespace paperpro {

enum class Rotation : std::uint16_t {
    Degrees0 = 0,
    Degrees90 = 90,
    Degrees180 = 180,
    Degrees270 = 270,
};

struct AxisRange {
    int minimum = 0;
    int maximum = 0;

    [[nodiscard]] bool valid() const noexcept { return maximum > minimum; }
};

class CoordinateTransform {
public:
    CoordinateTransform(AxisRange raw_x, AxisRange raw_y, int display_width,
        int display_height, Rotation rotation = Rotation::Degrees0) noexcept;

    [[nodiscard]] std::optional<Point> normalize(int raw_x, int raw_y) const noexcept;
    [[nodiscard]] int outputWidth() const noexcept { return display_width_; }
    [[nodiscard]] int outputHeight() const noexcept { return display_height_; }
    [[nodiscard]] Rotation rotation() const noexcept { return rotation_; }

private:
    [[nodiscard]] static int scale(int value, AxisRange input, int output_size) noexcept;

    AxisRange raw_x_;
    AxisRange raw_y_;
    int display_width_ = 0;
    int display_height_ = 0;
    Rotation rotation_ = Rotation::Degrees0;
};

} // namespace paperpro
