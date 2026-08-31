#pragma once

#include "core/interfaces.h"
#include "core/latency_recorder.h"
#include "core/types.h"

#include <optional>
#include <string>

namespace paperpro {

class RefreshScheduler {
public:
    struct Config {
        MonotonicNs minimum_cadence_ns = 8'000'000ULL;
        MonotonicNs maximum_cadence_ns = 50'000'000ULL;
        MonotonicNs maximum_pending_age_ns = 40'000'000ULL;
        MonotonicNs idle_cleanup_delay_ns = 350'000'000ULL;
    };

    RefreshScheduler(DisplayBackend& display, LatencyRecorder& recorder) noexcept;
    RefreshScheduler(DisplayBackend& display, LatencyRecorder& recorder,
        Config config) noexcept;

    void beginInteractive() noexcept;
    void requestInteractive(Rect region, MonotonicNs input_received_ns,
        MonotonicNs now_ns) noexcept;
    void endInteractive(MonotonicNs now_ns) noexcept;
    void requestUi(Rect region, UpdateMode mode, MonotonicNs now_ns) noexcept;
    bool tick(MonotonicNs now_ns, std::string& error);
    void cancel() noexcept;

    [[nodiscard]] bool hasOutstandingUpdate() const noexcept { return outstanding_.has_value(); }
    [[nodiscard]] std::optional<Rect> pendingRegion() const noexcept { return pending_region_; }
    [[nodiscard]] std::optional<MonotonicNs> nextDeadline() const noexcept;
    [[nodiscard]] MonotonicNs adaptiveCadence() const noexcept { return adaptive_cadence_ns_; }

private:
    struct Outstanding {
        std::uint64_t token = 0;
        MonotonicNs submitted_at_ns = 0;
        MonotonicNs estimated_completion_ns = 0;
        UpdateMode mode = UpdateMode::InteractiveMono;
    };

    void completeOutstanding(MonotonicNs completed_at_ns,
        bool completion_observed) noexcept;
    void mergePending(Rect region, UpdateMode mode, MonotonicNs input_received_ns,
        MonotonicNs now_ns) noexcept;
    [[nodiscard]] static UpdateMode stronger(UpdateMode left, UpdateMode right) noexcept;

    DisplayBackend& display_;
    LatencyRecorder& recorder_;
    Config config_;
    std::optional<Rect> pending_region_;
    UpdateMode pending_mode_ = UpdateMode::InteractiveMono;
    MonotonicNs pending_started_ns_ = 0;
    MonotonicNs pending_oldest_input_ns_ = 0;
    std::size_t pending_damage_count_ = 0;
    std::optional<Rect> cleanup_region_;
    MonotonicNs cleanup_due_ns_ = 0;
    MonotonicNs next_submission_ns_ = 0;
    MonotonicNs adaptive_cadence_ns_ = 8'000'000ULL;
    bool interactive_ = false;
    bool cancelled_ = false;
    std::optional<Outstanding> outstanding_;
};

} // namespace paperpro
