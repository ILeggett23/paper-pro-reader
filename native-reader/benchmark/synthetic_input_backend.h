#pragma once

#include "core/interfaces.h"
#include "core/spsc_ring.h"

#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>

namespace paperpro {

class SyntheticInputBackend final : public InputBackend {
public:
    bool start(std::string& error) override {
        (void)error;
        started_ = true;
        return true;
    }

    bool waitForEvents(std::chrono::milliseconds timeout) override {
        if (!ring_.empty()) return true;
        std::unique_lock lock(mutex_);
        return condition_.wait_for(lock, timeout, [this] { return !ring_.empty() || !started_; });
    }

    std::size_t drain(std::span<InputEvent> destination) override {
        std::size_t count = 0;
        InputEvent event;
        while (count < destination.size() && ring_.pop(event)) destination[count++] = event;
        return count;
    }

    [[nodiscard]] std::uint64_t markerSamplesDropped() const noexcept override { return dropped_; }
    [[nodiscard]] std::size_t markerRingHighWater() const noexcept override { return ring_.highWater(); }
    [[nodiscard]] bool healthy() const noexcept override { return true; }

    void stop() noexcept override {
        started_ = false;
        condition_.notify_all();
    }

    bool push(const InputEvent& event) noexcept {
        if (!ring_.push(event)) {
            if (isMarkerEvent(event.type)) ++dropped_;
            return false;
        }
        condition_.notify_one();
        return true;
    }

private:
    SpscRing<InputEvent, 1025> ring_;
    std::mutex mutex_;
    std::condition_variable condition_;
    std::uint64_t dropped_ = 0;
    bool started_ = false;
};

} // namespace paperpro
