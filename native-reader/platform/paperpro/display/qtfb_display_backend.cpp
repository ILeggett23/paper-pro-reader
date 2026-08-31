#include "platform/paperpro/display/qtfb_display_backend.h"

#include "platform/paperpro/display/qtfb_protocol.h"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <string>

#if defined(__linux__)
#include <cerrno>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#endif

namespace paperpro {

QtfbDisplayBackend::~QtfbDisplayBackend() {
    shutdown();
}

bool QtfbDisplayBackend::initialize(std::string& error) {
#if !defined(__linux__)
    error = "QTFB is available only on the Linux device runtime";
    return false;
#else
    if (surface_.valid()) return true;
    socket_ = ::socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    if (socket_ < 0) {
        error = "could not create QTFB socket: " + std::string(std::strerror(errno));
        return false;
    }
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    std::strncpy(address.sun_path, "/tmp/qtfb.sock", sizeof(address.sun_path) - 1);
    if (::connect(socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        error = "could not connect to /tmp/qtfb.sock: " + std::string(std::strerror(errno));
        shutdown();
        return false;
    }
    int key = 245209899;
    if (const auto* value = std::getenv("QTFB_KEY")) {
        char* end = nullptr;
        const auto parsed = std::strtol(value, &end, 10);
        if (end != value && end && *end == '\0') key = static_cast<int>(parsed);
    }
    qtfb::ClientMessage message{};
    message.type = qtfb::Initialize;
    message.init.framebuffer_key = key;
    message.init.framebuffer_type = 3; // FBFMT_RMPP_RGB565
    if (::send(socket_, &message, sizeof(message), MSG_NOSIGNAL)
        != static_cast<ssize_t>(sizeof(message))) {
        error = "could not initialize QTFB connection";
        shutdown();
        return false;
    }
    qtfb::ServerMessage response{};
    if (::recv(socket_, &response, sizeof(response), 0)
        != static_cast<ssize_t>(sizeof(response)) || response.type != qtfb::Initialize) {
        error = "QTFB returned an invalid initialization response";
        shutdown();
        return false;
    }
    mapping_size_ = response.init.shared_memory_size;
    const std::string shared_memory_name = "/qtfb_"
        + std::to_string(response.init.shared_memory_key);
    const auto shared_memory = ::shm_open(shared_memory_name.c_str(), O_RDWR | O_CLOEXEC, 0);
    if (shared_memory < 0) {
        error = "could not open QTFB shared memory";
        shutdown();
        return false;
    }
    mapping_ = ::mmap(nullptr, mapping_size_, PROT_READ | PROT_WRITE, MAP_SHARED,
        shared_memory, 0);
    ::close(shared_memory);
    constexpr std::size_t required_size = 1620ULL * 2160ULL * 2ULL;
    if (mapping_ == MAP_FAILED || mapping_size_ < required_size) {
        mapping_ = nullptr;
        error = "QTFB shared memory is missing or too small for Ferrari RGB565";
        shutdown();
        return false;
    }
    surface_ = {reinterpret_cast<std::byte*>(mapping_), 1620, 2160, 1620 * 2,
        PixelFormat::Rgb565};
    const auto flags = ::fcntl(socket_, F_GETFL, 0);
    if (flags >= 0) ::fcntl(socket_, F_SETFL, flags | O_NONBLOCK);
    return true;
#endif
}

std::chrono::nanoseconds QtfbDisplayBackend::estimatedDuration(UpdateMode mode) const noexcept {
    using namespace std::chrono_literals;
    switch (mode) {
    case UpdateMode::InteractiveMono: return 33ms;
    case UpdateMode::QualityMono: return 90ms;
    case UpdateMode::Ui: return 90ms;
    case UpdateMode::Full: return 350ms;
    }
    return 90ms;
}

bool QtfbDisplayBackend::sendRefreshMode(int mode, std::string& error) {
#if !defined(__linux__)
    (void)mode;
    error = "QTFB is unavailable";
    return false;
#else
    if (mode == current_refresh_mode_) return true;
    qtfb::ClientMessage message{};
    message.type = qtfb::SetRefreshMode;
    message.refresh_mode = mode;
    if (::send(socket_, &message, sizeof(message), MSG_NOSIGNAL)
        != static_cast<ssize_t>(sizeof(message))) {
        error = "failed to set QTFB refresh mode";
        return false;
    }
    current_refresh_mode_ = mode;
    return true;
#endif
}

bool QtfbDisplayBackend::sendUpdate(Rect region, std::string& error) {
#if !defined(__linux__)
    (void)region;
    error = "QTFB is unavailable";
    return false;
#else
    qtfb::ClientMessage message{};
    message.type = qtfb::Update;
    message.update.type = 1; // UPDATE_PARTIAL
    message.update.x = region.x;
    message.update.y = region.y;
    message.update.width = region.width;
    message.update.height = region.height;
    if (::send(socket_, &message, sizeof(message), MSG_NOSIGNAL)
        != static_cast<ssize_t>(sizeof(message))) {
        error = "failed to send QTFB dirty region";
        return false;
    }
    return true;
#endif
}

DisplaySubmission QtfbDisplayBackend::submit(const UpdateRequest& request,
    std::string& error) {
    if (!surface_.valid()) {
        error = "QTFB display is not initialized";
        return {};
    }
    const auto region = request.region.clippedTo(surface_.bounds());
    if (region.empty()) {
        error = "empty QTFB update region";
        return {};
    }
    int refresh_mode = qtfb::Ui;
    switch (request.mode) {
    case UpdateMode::InteractiveMono: refresh_mode = qtfb::Animate; break;
    case UpdateMode::QualityMono: refresh_mode = qtfb::Ui; break;
    case UpdateMode::Ui: refresh_mode = qtfb::Ui; break;
    case UpdateMode::Full: refresh_mode = qtfb::Content; break;
    }
    if (!sendRefreshMode(refresh_mode, error) || !sendUpdate(region, error)) return {};
#if defined(__linux__)
    if (request.mode == UpdateMode::Full) {
        qtfb::ClientMessage full{};
        full.type = qtfb::RequestFullRefresh;
        if (::send(socket_, &full, sizeof(full), MSG_NOSIGNAL)
            != static_cast<ssize_t>(sizeof(full))) {
            error = "failed to request QTFB full refresh";
            return {};
        }
    }
#endif
    return {true, ++submission_sequence_};
}

std::optional<DisplayCompletion> QtfbDisplayBackend::pollCompletion() {
#if defined(__linux__)
    // QTFB has no display acknowledgement. Drain its multiplexed input packets
    // because raw evdev is authoritative and an unread socket could fill.
    qtfb::ServerMessage message{};
    for (int count = 0; count < 32; ++count) {
        const auto received = ::recv(socket_, &message, sizeof(message), MSG_DONTWAIT);
        if (received <= 0) break;
    }
#endif
    return std::nullopt;
}

void QtfbDisplayBackend::shutdown() noexcept {
#if defined(__linux__)
    if (mapping_) {
        ::munmap(mapping_, mapping_size_);
        mapping_ = nullptr;
    }
    if (socket_ >= 0) {
        qtfb::ClientMessage message{};
        message.type = qtfb::Terminate;
        ::send(socket_, &message, sizeof(message), MSG_NOSIGNAL);
        ::close(socket_);
        socket_ = -1;
    }
#endif
    mapping_size_ = 0;
    surface_ = {};
}

} // namespace paperpro
