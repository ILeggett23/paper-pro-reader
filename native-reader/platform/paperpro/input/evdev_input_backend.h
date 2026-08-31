#pragma once

#include "core/coordinate_transform.h"
#include "core/interfaces.h"

#include <memory>
#include <optional>
#include <string>

namespace paperpro {

class EvdevInputBackend final : public InputBackend {
public:
    struct Config {
        std::string input_directory = "/dev/input";
        std::optional<std::string> marker_device;
        std::optional<std::string> touch_device;
        std::optional<std::string> power_device;
        int display_width = 1620;
        int display_height = 2160;
        Rotation rotation = Rotation::Degrees0;
    };

    EvdevInputBackend();
    explicit EvdevInputBackend(Config config);
    ~EvdevInputBackend() override;

    bool start(std::string& error) override;
    bool waitForEvents(std::chrono::milliseconds timeout) override;
    std::size_t drain(std::span<InputEvent> destination) override;
    [[nodiscard]] std::uint64_t markerSamplesDropped() const noexcept override;
    [[nodiscard]] std::size_t markerRingHighWater() const noexcept override;
    [[nodiscard]] bool healthy() const noexcept override;
    void stop() noexcept override;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace paperpro
