#pragma once

#include "core/interfaces.h"

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <optional>
#include <string>
#include <vector>

namespace paperpro {

class FakeDisplayBackend final : public DisplayBackend {
public:
    struct RecordedSubmission {
        std::uint64_t token = 0;
        UpdateRequest request;
    };

    explicit FakeDisplayBackend(int width = 1620, int height = 2160)
        : width_(width), height_(height) {}

    bool initialize(std::string& error) override {
        (void)error;
        pixels_.assign(static_cast<std::size_t>(width_)
            * static_cast<std::size_t>(height_) * 4, std::byte{0xff});
        initialized_ = true;
        return true;
    }
    [[nodiscard]] SurfaceView surface() noexcept override {
        return initialized_ ? SurfaceView{pixels_.data(), width_, height_, width_ * 4,
            PixelFormat::Bgra8888} : SurfaceView{};
    }
    [[nodiscard]] std::string_view name() const noexcept override { return "FAKE DISPLAY"; }
    [[nodiscard]] CompletionModel completionModel() const noexcept override {
        return CompletionModel::Explicit;
    }
    [[nodiscard]] std::chrono::nanoseconds estimatedDuration(UpdateMode) const noexcept override {
        return std::chrono::milliseconds(10);
    }
    DisplaySubmission submit(const UpdateRequest& request, std::string& error) override {
        if (reject_submissions_) {
            error = "fake rejection";
            return {};
        }
        const auto token = ++sequence_;
        submissions_.push_back({token, request});
        ++outstanding_count_;
        max_outstanding_count_ = std::max(max_outstanding_count_, outstanding_count_);
        return {true, token};
    }
    std::optional<DisplayCompletion> pollCompletion() override {
        if (completions_.empty()) return std::nullopt;
        const auto completion = completions_.front();
        completions_.pop_front();
        if (outstanding_count_ > 0) --outstanding_count_;
        return completion;
    }
    void shutdown() noexcept override { initialized_ = false; }

    void complete(std::uint64_t token, MonotonicNs completed_at_ns) {
        completions_.push_back({token, completed_at_ns});
    }
    void completeLast(MonotonicNs completed_at_ns) {
        if (!submissions_.empty()) complete(submissions_.back().token, completed_at_ns);
    }
    void setRejectSubmissions(bool reject) noexcept { reject_submissions_ = reject; }
    [[nodiscard]] const std::vector<RecordedSubmission>& submissions() const noexcept {
        return submissions_;
    }
    [[nodiscard]] std::size_t maxOutstandingCount() const noexcept {
        return max_outstanding_count_;
    }

private:
    int width_;
    int height_;
    std::vector<std::byte> pixels_;
    std::vector<RecordedSubmission> submissions_;
    std::deque<DisplayCompletion> completions_;
    std::uint64_t sequence_ = 0;
    std::size_t outstanding_count_ = 0;
    std::size_t max_outstanding_count_ = 0;
    bool initialized_ = false;
    bool reject_submissions_ = false;
};

} // namespace paperpro
