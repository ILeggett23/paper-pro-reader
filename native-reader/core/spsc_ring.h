#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <type_traits>

namespace paperpro {

template <typename T, std::size_t Capacity>
class SpscRing {
    static_assert(Capacity >= 2);
    static_assert(std::is_nothrow_copy_assignable_v<T>);

public:
    [[nodiscard]] bool push(const T& item) noexcept {
        const auto head = head_.load(std::memory_order_relaxed);
        const auto next = increment(head);
        if (next == tail_.load(std::memory_order_acquire)) {
            return false;
        }
        storage_[head] = item;
        head_.store(next, std::memory_order_release);
        const auto current_size = size();
        auto previous = high_water_.load(std::memory_order_relaxed);
        while (current_size > previous
            && !high_water_.compare_exchange_weak(previous, current_size,
                std::memory_order_relaxed, std::memory_order_relaxed)) {
        }
        return true;
    }

    [[nodiscard]] bool pop(T& item) noexcept {
        const auto tail = tail_.load(std::memory_order_relaxed);
        if (tail == head_.load(std::memory_order_acquire)) {
            return false;
        }
        item = storage_[tail];
        tail_.store(increment(tail), std::memory_order_release);
        return true;
    }

    [[nodiscard]] bool peek(T& item) const noexcept {
        const auto tail = tail_.load(std::memory_order_relaxed);
        if (tail == head_.load(std::memory_order_acquire)) return false;
        item = storage_[tail];
        return true;
    }

    [[nodiscard]] std::size_t size() const noexcept {
        const auto head = head_.load(std::memory_order_acquire);
        const auto tail = tail_.load(std::memory_order_acquire);
        return head >= tail ? head - tail : Capacity - tail + head;
    }

    [[nodiscard]] bool empty() const noexcept { return size() == 0; }
    [[nodiscard]] constexpr std::size_t usableCapacity() const noexcept { return Capacity - 1; }
    [[nodiscard]] std::size_t highWater() const noexcept {
        return high_water_.load(std::memory_order_relaxed);
    }

private:
    [[nodiscard]] static constexpr std::size_t increment(std::size_t value) noexcept {
        return (value + 1) % Capacity;
    }

    std::array<T, Capacity> storage_{};
    alignas(64) std::atomic<std::size_t> head_{0};
    alignas(64) std::atomic<std::size_t> tail_{0};
    std::atomic<std::size_t> high_water_{0};
};

} // namespace paperpro
