#pragma once

#include "core/types.h"

#include <cstdint>
#include <string>

namespace paperpro {

class SystemdWatchdog {
public:
    SystemdWatchdog() noexcept;
    ~SystemdWatchdog();

    SystemdWatchdog(const SystemdWatchdog&) = delete;
    SystemdWatchdog& operator=(const SystemdWatchdog&) = delete;

    void ready() noexcept;
    void pingIfDue(MonotonicNs now_ns) noexcept;
    [[nodiscard]] bool enabled() const noexcept { return socket_ >= 0; }

private:
    void sendMessage(const char* message) noexcept;

    int socket_ = -1;
    std::string notify_socket_;
    MonotonicNs ping_interval_ns_ = 0;
    MonotonicNs next_ping_ns_ = 0;
};

} // namespace paperpro
