#pragma once

#include "core/types.h"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace paperpro {

class LatencyRecorder {
public:
    void markerSampleReceived() noexcept;
    void markerSampleConsumed() noexcept;
    void observeMarkerRing(std::size_t high_water) noexcept;
    void markerSamplesDropped(std::uint64_t count) noexcept;
    void observeRenderPreparation(MonotonicNs duration_ns) noexcept;
    void observeInputToSubmission(MonotonicNs duration_ns) noexcept;
    void observeDisplayCompletion(MonotonicNs duration_ns) noexcept;
    void observeDirtyRegionAge(MonotonicNs duration_ns) noexcept;
    void displaySubmitted(bool coalesced, UpdateMode mode) noexcept;
    void idleCleanup() noexcept;

    [[nodiscard]] bool writeReport(const std::string& path, std::string_view backend,
        std::string_view shutdown_reason, bool xochitl_managed_externally,
        std::string& error) const;
    [[nodiscard]] static bool appendRestoration(const std::string& path,
        bool succeeded, std::string& error);

    [[nodiscard]] std::uint64_t received() const noexcept {
        return marker_received_.load(std::memory_order_relaxed);
    }
    [[nodiscard]] std::uint64_t consumed() const noexcept {
        return marker_consumed_.load(std::memory_order_relaxed);
    }
    [[nodiscard]] std::uint64_t dropped() const noexcept {
        return marker_dropped_.load(std::memory_order_relaxed);
    }

private:
    struct Aggregate {
        std::atomic<std::uint64_t> count{0};
        std::atomic<std::uint64_t> sum_ns{0};
        std::atomic<std::uint64_t> max_ns{0};

        void observe(std::uint64_t value) noexcept;
    };

    static void observeMaximum(std::atomic<std::uint64_t>& destination,
        std::uint64_t value) noexcept;

    std::atomic<std::uint64_t> marker_received_{0};
    std::atomic<std::uint64_t> marker_consumed_{0};
    std::atomic<std::uint64_t> marker_ring_high_water_{0};
    std::atomic<std::uint64_t> marker_dropped_{0};
    Aggregate render_preparation_;
    Aggregate input_to_submission_;
    Aggregate display_completion_;
    Aggregate dirty_region_age_;
    std::atomic<std::uint64_t> display_submissions_{0};
    std::atomic<std::uint64_t> coalesced_submissions_{0};
    std::atomic<std::uint64_t> full_screen_updates_{0};
    std::atomic<std::uint64_t> idle_cleanups_{0};
};

} // namespace paperpro
