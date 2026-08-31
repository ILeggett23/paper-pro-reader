#include "core/systemd_watchdog.h"

#include <algorithm>
#include <cerrno>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <limits>

#if defined(__linux__)
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#endif

namespace paperpro {

SystemdWatchdog::SystemdWatchdog() noexcept {
#if defined(__linux__)
    const auto* notify = std::getenv("NOTIFY_SOCKET");
    if (!notify || !*notify) return;
    notify_socket_ = notify;
    socket_ = ::socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (socket_ < 0) notify_socket_.clear();

    const auto* watchdog = std::getenv("WATCHDOG_USEC");
    if (watchdog && *watchdog) {
        char* end = nullptr;
        const auto microseconds = std::strtoull(watchdog, &end, 10);
        if (end != watchdog && end && *end == '\0'
            && microseconds <= std::numeric_limits<MonotonicNs>::max() / 1000ULL) {
            // Ping at half the supervisor interval, with a 100 ms floor.
            ping_interval_ns_ = std::max<MonotonicNs>(100'000'000ULL,
                static_cast<MonotonicNs>(microseconds) * 500ULL);
        }
    }
#endif
}

SystemdWatchdog::~SystemdWatchdog() {
#if defined(__linux__)
    if (socket_ >= 0) ::close(socket_);
#endif
}

void SystemdWatchdog::sendMessage(const char* message) noexcept {
#if defined(__linux__)
    if (socket_ < 0 || notify_socket_.empty()) return;
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (notify_socket_.size() >= sizeof(address.sun_path)) return;
    std::size_t address_length = 0;
    if (notify_socket_.front() == '@') {
        address.sun_path[0] = '\0';
        std::memcpy(address.sun_path + 1, notify_socket_.data() + 1,
            notify_socket_.size() - 1);
        address_length = offsetof(sockaddr_un, sun_path) + notify_socket_.size();
    } else {
        std::memcpy(address.sun_path, notify_socket_.data(), notify_socket_.size());
        address.sun_path[notify_socket_.size()] = '\0';
        address_length = offsetof(sockaddr_un, sun_path) + notify_socket_.size() + 1;
    }
    (void)::sendto(socket_, message, std::strlen(message), MSG_DONTWAIT | MSG_NOSIGNAL,
        reinterpret_cast<const sockaddr*>(&address), static_cast<socklen_t>(address_length));
#else
    (void)message;
#endif
}

void SystemdWatchdog::ready() noexcept {
    sendMessage("READY=1\nSTATUS=Paper Pro native benchmark running");
}

void SystemdWatchdog::pingIfDue(MonotonicNs now_ns) noexcept {
    if (ping_interval_ns_ == 0) return;
    if (next_ping_ns_ == 0 || now_ns >= next_ping_ns_) {
        sendMessage("WATCHDOG=1");
        next_ping_ns_ = now_ns + ping_interval_ns_;
    }
}

} // namespace paperpro
