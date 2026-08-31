#include "core/latency_recorder.h"

#include <cerrno>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <system_error>

#include <sys/resource.h>
#include <sys/stat.h>

namespace paperpro {
namespace {

double milliseconds(std::uint64_t nanoseconds) {
    return static_cast<double>(nanoseconds) / 1'000'000.0;
}

double averageMilliseconds(std::uint64_t sum, std::uint64_t count) {
    return count == 0 ? 0.0 : milliseconds(sum / count);
}

std::string jsonString(std::string_view value) {
    std::string escaped;
    escaped.reserve(value.size() + 2);
    escaped.push_back('"');
    for (const auto character : value) {
        switch (character) {
        case '"': escaped += "\\\""; break;
        case '\\': escaped += "\\\\"; break;
        case '\n': escaped += "\\n"; break;
        case '\r': escaped += "\\r"; break;
        case '\t': escaped += "\\t"; break;
        default:
            if (static_cast<unsigned char>(character) >= 0x20) escaped.push_back(character);
            break;
        }
    }
    escaped.push_back('"');
    return escaped;
}

} // namespace

void LatencyRecorder::observeMaximum(std::atomic<std::uint64_t>& destination,
    std::uint64_t value) noexcept {
    auto previous = destination.load(std::memory_order_relaxed);
    while (value > previous
        && !destination.compare_exchange_weak(previous, value,
            std::memory_order_relaxed, std::memory_order_relaxed)) {
    }
}

void LatencyRecorder::Aggregate::observe(std::uint64_t value) noexcept {
    count.fetch_add(1, std::memory_order_relaxed);
    sum_ns.fetch_add(value, std::memory_order_relaxed);
    LatencyRecorder::observeMaximum(max_ns, value);
}

void LatencyRecorder::markerSampleReceived() noexcept {
    marker_received_.fetch_add(1, std::memory_order_relaxed);
}

void LatencyRecorder::markerSampleConsumed() noexcept {
    marker_consumed_.fetch_add(1, std::memory_order_relaxed);
}

void LatencyRecorder::observeMarkerRing(std::size_t high_water) noexcept {
    observeMaximum(marker_ring_high_water_, high_water);
}

void LatencyRecorder::markerSamplesDropped(std::uint64_t count) noexcept {
    marker_dropped_.store(count, std::memory_order_relaxed);
}

void LatencyRecorder::observeRenderPreparation(MonotonicNs duration_ns) noexcept {
    render_preparation_.observe(duration_ns);
}

void LatencyRecorder::observeInputToSubmission(MonotonicNs duration_ns) noexcept {
    input_to_submission_.observe(duration_ns);
}

void LatencyRecorder::observeDisplayCompletion(MonotonicNs duration_ns) noexcept {
    display_completion_.observe(duration_ns);
}

void LatencyRecorder::observeDirtyRegionAge(MonotonicNs duration_ns) noexcept {
    dirty_region_age_.observe(duration_ns);
}

void LatencyRecorder::displaySubmitted(bool coalesced, UpdateMode mode) noexcept {
    display_submissions_.fetch_add(1, std::memory_order_relaxed);
    if (coalesced) coalesced_submissions_.fetch_add(1, std::memory_order_relaxed);
    if (mode == UpdateMode::Full) full_screen_updates_.fetch_add(1, std::memory_order_relaxed);
}

void LatencyRecorder::idleCleanup() noexcept {
    idle_cleanups_.fetch_add(1, std::memory_order_relaxed);
}

bool LatencyRecorder::writeReport(const std::string& path, std::string_view backend,
    std::string_view shutdown_reason, bool xochitl_managed_externally,
    std::string& error) const {
    std::error_code filesystem_error;
    const auto parent = std::filesystem::path(path).parent_path();
    if (!parent.empty()) {
        std::filesystem::create_directories(parent, filesystem_error);
        if (filesystem_error) {
            error = "could not create report directory: " + filesystem_error.message();
            return false;
        }
        ::chmod(parent.c_str(), 0700);
    }

    struct rusage usage {};
    ::getrusage(RUSAGE_SELF, &usage);
    const auto cpu_microseconds = static_cast<std::uint64_t>(usage.ru_utime.tv_sec
        + usage.ru_stime.tv_sec) * 1'000'000ULL
        + static_cast<std::uint64_t>(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec);
#if defined(__APPLE__)
    const auto peak_resident_bytes = static_cast<std::uint64_t>(usage.ru_maxrss);
#else
    const auto peak_resident_bytes = static_cast<std::uint64_t>(usage.ru_maxrss) * 1024ULL;
#endif

    const auto render_count = render_preparation_.count.load(std::memory_order_relaxed);
    const auto submission_count = input_to_submission_.count.load(std::memory_order_relaxed);
    const auto completion_count = display_completion_.count.load(std::memory_order_relaxed);
    const auto age_count = dirty_region_age_.count.load(std::memory_order_relaxed);

    std::ostringstream report;
    report << std::fixed << std::setprecision(3)
        << "{\"schema_version\":1,\"event\":\"benchmark_metrics\""
        << ",\"backend\":" << jsonString(backend)
        << ",\"marker_samples_received\":" << marker_received_.load()
        << ",\"marker_samples_consumed\":" << marker_consumed_.load()
        << ",\"marker_ring_high_water\":" << marker_ring_high_water_.load()
        << ",\"dropped_sample_count\":" << marker_dropped_.load()
        << ",\"render_preparation_ms_avg\":"
        << averageMilliseconds(render_preparation_.sum_ns.load(), render_count)
        << ",\"render_preparation_ms_max\":"
        << milliseconds(render_preparation_.max_ns.load())
        << ",\"input_to_submission_ms_avg\":"
        << averageMilliseconds(input_to_submission_.sum_ns.load(), submission_count)
        << ",\"input_to_submission_ms_max\":"
        << milliseconds(input_to_submission_.max_ns.load())
        << ",\"display_completion_ms_avg\":"
        << averageMilliseconds(display_completion_.sum_ns.load(), completion_count)
        << ",\"display_completion_ms_max\":"
        << milliseconds(display_completion_.max_ns.load())
        << ",\"dirty_region_age_ms_avg\":"
        << averageMilliseconds(dirty_region_age_.sum_ns.load(), age_count)
        << ",\"dirty_region_age_ms_max\":"
        << milliseconds(dirty_region_age_.max_ns.load())
        << ",\"display_submissions\":" << display_submissions_.load()
        << ",\"coalesced_submissions\":" << coalesced_submissions_.load()
        << ",\"full_screen_updates\":" << full_screen_updates_.load()
        << ",\"idle_cleanups\":" << idle_cleanups_.load()
        << ",\"cpu_time_ms\":" << static_cast<double>(cpu_microseconds) / 1000.0
        << ",\"peak_resident_memory_bytes\":" << peak_resident_bytes
        << ",\"shutdown_reason\":" << jsonString(shutdown_reason)
        << ",\"xochitl_restoration_succeeded\":"
        << (xochitl_managed_externally ? "null" : "true")
        << "}\n";

    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) {
        error = "could not open benchmark report";
        return false;
    }
    output << report.str();
    output.close();
    ::chmod(path.c_str(), 0600);
    if (!output) {
        error = "could not write benchmark report";
        return false;
    }
    return true;
}

bool LatencyRecorder::appendRestoration(const std::string& path,
    bool succeeded, std::string& error) {
    std::ofstream output(path, std::ios::binary | std::ios::app);
    if (!output) {
        error = "could not open benchmark report for lifecycle result";
        return false;
    }
    output << "{\"schema_version\":1,\"event\":\"lifecycle\","
        << "\"xochitl_restoration_succeeded\":" << (succeeded ? "true" : "false")
        << "}\n";
    output.close();
    ::chmod(path.c_str(), 0600);
    if (!output) {
        error = "could not append lifecycle result";
        return false;
    }
    return true;
}

} // namespace paperpro
