#pragma once

#include "core/interfaces.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace paperpro {

class QtfbDisplayBackend final : public DisplayBackend {
public:
    QtfbDisplayBackend() = default;
    ~QtfbDisplayBackend() override;

    bool initialize(std::string& error) override;
    [[nodiscard]] SurfaceView surface() noexcept override { return surface_; }
    [[nodiscard]] std::string_view name() const noexcept override { return "QTFB FALLBACK"; }
    [[nodiscard]] CompletionModel completionModel() const noexcept override {
        return CompletionModel::Estimated;
    }
    [[nodiscard]] std::chrono::nanoseconds estimatedDuration(UpdateMode mode) const noexcept override;
    DisplaySubmission submit(const UpdateRequest& request, std::string& error) override;
    std::optional<DisplayCompletion> pollCompletion() override;
    void shutdown() noexcept override;

private:
    bool sendRefreshMode(int mode, std::string& error);
    bool sendUpdate(Rect region, std::string& error);

    [[maybe_unused]] int socket_ = -1;
    [[maybe_unused]] void* mapping_ = nullptr;
    std::size_t mapping_size_ = 0;
    SurfaceView surface_;
    [[maybe_unused]] int current_refresh_mode_ = -1;
    std::uint64_t submission_sequence_ = 0;
};

} // namespace paperpro
