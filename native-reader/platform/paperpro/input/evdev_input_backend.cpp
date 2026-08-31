#include "platform/paperpro/input/evdev_input_backend.h"

#include "core/spsc_ring.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#if defined(__linux__)
#include <cerrno>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#endif

namespace paperpro {
namespace {

#if defined(__linux__)
MonotonicNs monotonicNow() noexcept {
    timespec value{};
    ::clock_gettime(CLOCK_MONOTONIC, &value);
    return static_cast<MonotonicNs>(value.tv_sec) * 1'000'000'000ULL
        + static_cast<MonotonicNs>(value.tv_nsec);
}

constexpr std::size_t bitsToLongs(std::size_t count) {
    return (count + sizeof(unsigned long) * 8 - 1) / (sizeof(unsigned long) * 8);
}

template <std::size_t Size>
bool bitSet(const std::array<unsigned long, Size>& bits, int bit) {
    if (bit < 0) return false;
    const auto index = static_cast<std::size_t>(bit) / (sizeof(unsigned long) * 8);
    const auto offset = static_cast<std::size_t>(bit) % (sizeof(unsigned long) * 8);
    return index < bits.size() && (bits[index] & (1UL << offset)) != 0;
}

struct Capability {
    bool marker = false;
    bool touch = false;
    bool power = false;
};

Capability capabilityFor(int descriptor) {
    std::array<unsigned long, bitsToLongs(EV_MAX + 1)> event_bits{};
    std::array<unsigned long, bitsToLongs(KEY_MAX + 1)> key_bits{};
    std::array<unsigned long, bitsToLongs(ABS_MAX + 1)> absolute_bits{};
    if (::ioctl(descriptor, EVIOCGBIT(0, sizeof(event_bits)), event_bits.data()) < 0) return {};
    if (bitSet(event_bits, EV_KEY)) {
        ::ioctl(descriptor, EVIOCGBIT(EV_KEY, sizeof(key_bits)), key_bits.data());
    }
    if (bitSet(event_bits, EV_ABS)) {
        ::ioctl(descriptor, EVIOCGBIT(EV_ABS, sizeof(absolute_bits)), absolute_bits.data());
    }
    const bool marker = bitSet(absolute_bits, ABS_X) && bitSet(absolute_bits, ABS_Y)
        && (bitSet(key_bits, BTN_TOOL_PEN) || bitSet(key_bits, BTN_TOOL_RUBBER));
    const bool touch = bitSet(absolute_bits, ABS_MT_POSITION_X)
        && bitSet(absolute_bits, ABS_MT_POSITION_Y)
        && bitSet(absolute_bits, ABS_MT_TRACKING_ID);
    return {marker, touch, bitSet(key_bits, KEY_POWER)};
}

bool queryRange(int descriptor, int code, AxisRange& range) {
    input_absinfo info{};
    if (::ioctl(descriptor, EVIOCGABS(code), &info) < 0 || info.maximum <= info.minimum) {
        return false;
    }
    range = {info.minimum, info.maximum};
    return true;
}
#endif

} // namespace

struct EvdevInputBackend::Impl {
    explicit Impl(Config value) : config(std::move(value)) {}

    Config config;
    SpscRing<InputEvent, 8193> marker_ring;
    SpscRing<InputEvent, 1025> touch_ring;
    SpscRing<InputEvent, 129> control_ring;
    std::atomic<std::uint64_t> marker_dropped{0};
    std::atomic<std::uint64_t> touch_dropped{0};
    std::atomic<bool> stopping{false};
    std::atomic<bool> healthy{true};
    std::thread worker;
    std::mutex wait_mutex;
    std::condition_variable wait_condition;
    std::uint32_t sequence = 0;

#if defined(__linux__)
    int epoll_descriptor = -1;
    int wake_descriptor = -1;
    int marker_descriptor = -1;
    int touch_descriptor = -1;
    int power_descriptor = -1;
    std::optional<CoordinateTransform> marker_transform;
    std::optional<CoordinateTransform> touch_transform;

    struct MarkerState {
        int raw_x = 0;
        int raw_y = 0;
        int pressure = 0;
        bool have_x = false;
        bool have_y = false;
        bool contact = false;
        bool previous_contact = false;
        Tool tool = Tool::Pen;
    } marker_state;

    struct TouchSlot {
        int tracking_id = -1;
        int raw_x = 0;
        int raw_y = 0;
        bool active = false;
        bool was_active = false;
        bool have_x = false;
        bool have_y = false;
        bool changed = false;
    };
    std::array<TouchSlot, 16> touch_slots{};
    int current_touch_slot = 0;

    static void closeDescriptor(int& descriptor) noexcept {
        if (descriptor >= 0) {
            ::close(descriptor);
            descriptor = -1;
        }
    }

    bool chooseDevices(std::string& marker_path, std::string& touch_path,
        std::string& power_path, std::string& error) {
        std::vector<std::string> marker_candidates;
        std::vector<std::string> touch_candidates;
        std::vector<std::string> power_candidates;
        std::error_code filesystem_error;
        for (const auto& entry : std::filesystem::directory_iterator(
                config.input_directory, filesystem_error)) {
            if (filesystem_error) break;
            const auto filename = entry.path().filename().string();
            if (!filename.starts_with("event")) continue;
            const auto path = entry.path().string();
            const auto descriptor = ::open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
            if (descriptor < 0) continue;
            const auto capability = capabilityFor(descriptor);
            ::close(descriptor);
            if (capability.marker) marker_candidates.push_back(path);
            if (capability.touch) touch_candidates.push_back(path);
            if (capability.power) power_candidates.push_back(path);
        }
        if (filesystem_error) {
            error = "could not enumerate evdev devices: " + filesystem_error.message();
            return false;
        }
        std::sort(marker_candidates.begin(), marker_candidates.end());
        std::sort(touch_candidates.begin(), touch_candidates.end());
        std::sort(power_candidates.begin(), power_candidates.end());
        const auto choose = [&error](const std::optional<std::string>& override,
            const std::vector<std::string>& candidates, const char* role,
            std::string& destination, bool required) {
            if (override) {
                destination = *override;
                return true;
            }
            if (candidates.size() == 1) {
                destination = candidates.front();
                return true;
            }
            if (!required && candidates.empty()) return true;
            error = std::string("evdev ") + role + " discovery found "
                + std::to_string(candidates.size()) + " candidates; refusing ambiguity";
            return false;
        };
        return choose(config.marker_device, marker_candidates, "Marker", marker_path, true)
            && choose(config.touch_device, touch_candidates, "touch", touch_path, true)
            && choose(config.power_device, power_candidates, "power", power_path, false);
    }

    bool addToEpoll(int descriptor, std::uint32_t tag, std::string& error) {
        epoll_event event{};
        event.events = EPOLLIN;
        event.data.u32 = tag;
        if (::epoll_ctl(epoll_descriptor, EPOLL_CTL_ADD, descriptor, &event) != 0) {
            error = "could not register evdev descriptor with epoll";
            return false;
        }
        return true;
    }

    bool initializeLinux(std::string& error) {
        std::string marker_path;
        std::string touch_path;
        std::string power_path;
        if (!chooseDevices(marker_path, touch_path, power_path, error)) return false;
        marker_descriptor = ::open(marker_path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        touch_descriptor = ::open(touch_path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (marker_descriptor < 0 || touch_descriptor < 0) {
            error = "could not open discovered Marker/touch evdev devices";
            return false;
        }
        if (!power_path.empty()) {
            power_descriptor = ::open(power_path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        }
        AxisRange marker_x;
        AxisRange marker_y;
        AxisRange touch_x;
        AxisRange touch_y;
        if (!queryRange(marker_descriptor, ABS_X, marker_x)
            || !queryRange(marker_descriptor, ABS_Y, marker_y)
            || !queryRange(touch_descriptor, ABS_MT_POSITION_X, touch_x)
            || !queryRange(touch_descriptor, ABS_MT_POSITION_Y, touch_y)) {
            error = "evdev devices did not expose valid ABS coordinate ranges";
            return false;
        }
        marker_transform.emplace(marker_x, marker_y, config.display_width,
            config.display_height, config.rotation);
        touch_transform.emplace(touch_x, touch_y, config.display_width,
            config.display_height, config.rotation);

        int clock_id = CLOCK_MONOTONIC;
        ::ioctl(marker_descriptor, EVIOCSCLOCKID, &clock_id);
        ::ioctl(touch_descriptor, EVIOCSCLOCKID, &clock_id);
        if (power_descriptor >= 0) ::ioctl(power_descriptor, EVIOCSCLOCKID, &clock_id);

        epoll_descriptor = ::epoll_create1(EPOLL_CLOEXEC);
        wake_descriptor = ::eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
        if (epoll_descriptor < 0 || wake_descriptor < 0
            || !addToEpoll(wake_descriptor, 0, error)
            || !addToEpoll(marker_descriptor, 1, error)
            || !addToEpoll(touch_descriptor, 2, error)
            || (power_descriptor >= 0 && !addToEpoll(power_descriptor, 3, error))) {
            if (error.empty()) error = "could not initialize evdev epoll loop";
            return false;
        }
        return true;
    }

    void notify() {
        wait_condition.notify_one();
    }

    void emitMarker(InputEventType type, Point point, MonotonicNs receipt) noexcept {
        const auto pressure = static_cast<std::uint16_t>(
            std::clamp(marker_state.pressure, 0, 65535));
        const InputEvent event{type, point, receipt, ++sequence, 0,
            pressure, marker_state.tool};
        if (!marker_ring.push(event)) {
            marker_dropped.fetch_add(1, std::memory_order_relaxed);
        }
        notify();
    }

    void flushMarkerFrame(MonotonicNs receipt) noexcept {
        if (!marker_state.have_x || !marker_state.have_y || !marker_transform) return;
        const auto point = marker_transform->normalize(marker_state.raw_x, marker_state.raw_y);
        if (!point) return;
        if (marker_state.contact) {
            emitMarker(marker_state.previous_contact ? InputEventType::MarkerMove
                                                     : InputEventType::MarkerDown,
                *point, receipt);
        } else if (marker_state.previous_contact) {
            emitMarker(InputEventType::MarkerUp, *point, receipt);
        }
        marker_state.previous_contact = marker_state.contact;
    }

    void handleMarker(const input_event& event, MonotonicNs receipt) noexcept {
        if (event.type == EV_ABS) {
            if (event.code == ABS_X) {
                marker_state.raw_x = event.value;
                marker_state.have_x = true;
            } else if (event.code == ABS_Y) {
                marker_state.raw_y = event.value;
                marker_state.have_y = true;
            } else if (event.code == ABS_PRESSURE) {
                marker_state.pressure = event.value;
            }
        } else if (event.type == EV_KEY) {
            if (event.code == BTN_TOUCH) marker_state.contact = event.value != 0;
            if (event.code == BTN_TOOL_RUBBER && event.value != 0) marker_state.tool = Tool::Eraser;
            if (event.code == BTN_TOOL_PEN && event.value != 0) marker_state.tool = Tool::Pen;
        } else if (event.type == EV_SYN && event.code == SYN_REPORT) {
            flushMarkerFrame(receipt);
        }
    }

    void emitTouch(InputEventType type, int slot, Point point, MonotonicNs receipt) noexcept {
        const InputEvent event{type, point, receipt, ++sequence, slot, 0, Tool::Pen};
        if (!touch_ring.push(event)) touch_dropped.fetch_add(1, std::memory_order_relaxed);
        notify();
    }

    void flushTouchFrame(MonotonicNs receipt) noexcept {
        if (!touch_transform) return;
        for (std::size_t index = 0; index < touch_slots.size(); ++index) {
            auto& slot = touch_slots[index];
            if (!slot.changed) continue;
            const auto point = slot.have_x && slot.have_y
                ? touch_transform->normalize(slot.raw_x, slot.raw_y) : std::nullopt;
            if (point) {
                if (slot.active && !slot.was_active) {
                    emitTouch(InputEventType::TouchDown, static_cast<int>(index), *point, receipt);
                } else if (slot.active) {
                    emitTouch(InputEventType::TouchMove, static_cast<int>(index), *point, receipt);
                } else if (slot.was_active) {
                    emitTouch(InputEventType::TouchUp, static_cast<int>(index), *point, receipt);
                }
            }
            slot.was_active = slot.active;
            slot.changed = false;
        }
    }

    void handleTouch(const input_event& event, MonotonicNs receipt) noexcept {
        if (event.type == EV_ABS) {
            if (event.code == ABS_MT_SLOT) {
                current_touch_slot = std::clamp(event.value, 0,
                    static_cast<int>(touch_slots.size()) - 1);
                return;
            }
            auto& slot = touch_slots[static_cast<std::size_t>(current_touch_slot)];
            if (event.code == ABS_MT_TRACKING_ID) {
                slot.tracking_id = event.value;
                slot.active = event.value >= 0;
                slot.changed = true;
            } else if (event.code == ABS_MT_POSITION_X) {
                slot.raw_x = event.value;
                slot.have_x = true;
                slot.changed = true;
            } else if (event.code == ABS_MT_POSITION_Y) {
                slot.raw_y = event.value;
                slot.have_y = true;
                slot.changed = true;
            }
        } else if (event.type == EV_SYN && event.code == SYN_REPORT) {
            flushTouchFrame(receipt);
        }
    }

    void handlePower(const input_event& event, MonotonicNs receipt) noexcept {
        if (event.type == EV_KEY && event.code == KEY_POWER && event.value == 1) {
            const InputEvent power{InputEventType::PowerPressed, {}, receipt,
                ++sequence, -1, 0, Tool::Pen};
            control_ring.push(power);
            notify();
        }
    }

    bool readDevice(int descriptor, std::uint32_t tag) noexcept {
        std::array<input_event, 64> events{};
        while (true) {
            const auto bytes = ::read(descriptor, events.data(), sizeof(events));
            if (bytes == 0) return false;
            if (bytes < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                if (errno == EINTR) continue;
                return false;
            }
            const auto receipt = monotonicNow();
            const auto count = static_cast<std::size_t>(bytes) / sizeof(input_event);
            for (std::size_t index = 0; index < count; ++index) {
                if (tag == 1) handleMarker(events[index], receipt);
                else if (tag == 2) handleTouch(events[index], receipt);
                else if (tag == 3) handlePower(events[index], receipt);
            }
        }
        return true;
    }

    void workerLoop() noexcept {
        std::array<epoll_event, 4> events{};
        while (!stopping.load(std::memory_order_acquire)) {
            const auto count = ::epoll_wait(epoll_descriptor, events.data(),
                static_cast<int>(events.size()), -1);
            if (count < 0) {
                if (errno == EINTR) continue;
                healthy.store(false, std::memory_order_release);
                notify();
                break;
            }
            for (int index = 0; index < count; ++index) {
                const auto tag = events[static_cast<std::size_t>(index)].data.u32;
                if (tag == 0) return;
                bool read_ok = true;
                if (tag == 1) read_ok = readDevice(marker_descriptor, tag);
                else if (tag == 2) read_ok = readDevice(touch_descriptor, tag);
                else if (tag == 3) read_ok = readDevice(power_descriptor, tag);
                if (!read_ok) {
                    healthy.store(false, std::memory_order_release);
                    notify();
                    return;
                }
            }
        }
    }

    void closeLinux() noexcept {
        closeDescriptor(marker_descriptor);
        closeDescriptor(touch_descriptor);
        closeDescriptor(power_descriptor);
        closeDescriptor(wake_descriptor);
        closeDescriptor(epoll_descriptor);
    }
#endif
};

EvdevInputBackend::EvdevInputBackend() : EvdevInputBackend(Config{}) {}

EvdevInputBackend::EvdevInputBackend(Config config)
    : impl_(std::make_unique<Impl>(std::move(config))) {
}

EvdevInputBackend::~EvdevInputBackend() {
    stop();
}

bool EvdevInputBackend::start(std::string& error) {
#if !defined(__linux__)
    error = "raw evdev input is available only on the Linux device runtime";
    return false;
#else
    if (impl_->worker.joinable()) return true;
    if (!impl_->initializeLinux(error)) {
        impl_->closeLinux();
        return false;
    }
    impl_->stopping.store(false, std::memory_order_release);
    impl_->healthy.store(true, std::memory_order_release);
    impl_->worker = std::thread([implementation = impl_.get()] {
        implementation->workerLoop();
    });
    return true;
#endif
}

bool EvdevInputBackend::waitForEvents(std::chrono::milliseconds timeout) {
    if (!impl_->marker_ring.empty() || !impl_->control_ring.empty()
        || !impl_->touch_ring.empty()) return true;
    std::unique_lock lock(impl_->wait_mutex);
    return impl_->wait_condition.wait_for(lock, timeout, [this] {
        return impl_->stopping.load(std::memory_order_acquire)
            || !impl_->healthy.load(std::memory_order_acquire)
            || !impl_->marker_ring.empty() || !impl_->control_ring.empty()
            || !impl_->touch_ring.empty();
    });
}

std::size_t EvdevInputBackend::drain(std::span<InputEvent> destination) {
    std::size_t count = 0;
    InputEvent event;
    // Power is an out-of-band emergency and may preempt queued pointer data.
    while (count < destination.size() && impl_->control_ring.pop(event)) {
        destination[count++] = event;
    }
    // Marker and touch share one producer sequence. Merge the two rings by
    // sequence so a palm contact cannot be delivered after its MarkerUp.
    while (count < destination.size()) {
        InputEvent marker;
        InputEvent touch;
        const auto has_marker = impl_->marker_ring.peek(marker);
        const auto has_touch = impl_->touch_ring.peek(touch);
        if (!has_marker && !has_touch) break;
        if (has_marker && (!has_touch || marker.sequence < touch.sequence)) {
            (void)impl_->marker_ring.pop(event);
        } else {
            (void)impl_->touch_ring.pop(event);
        }
        destination[count++] = event;
    }
    return count;
}

std::uint64_t EvdevInputBackend::markerSamplesDropped() const noexcept {
    return impl_->marker_dropped.load(std::memory_order_relaxed);
}

std::size_t EvdevInputBackend::markerRingHighWater() const noexcept {
    return impl_->marker_ring.highWater();
}

bool EvdevInputBackend::healthy() const noexcept {
    return impl_->healthy.load(std::memory_order_acquire);
}

void EvdevInputBackend::stop() noexcept {
    if (!impl_) return;
    impl_->stopping.store(true, std::memory_order_release);
#if defined(__linux__)
    if (impl_->wake_descriptor >= 0) {
        const std::uint64_t value = 1;
        ::write(impl_->wake_descriptor, &value, sizeof(value));
    }
#endif
    impl_->wait_condition.notify_all();
    if (impl_->worker.joinable()) impl_->worker.join();
#if defined(__linux__)
    impl_->closeLinux();
#endif
}

} // namespace paperpro
