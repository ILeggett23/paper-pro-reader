#include "platform/paperpro/display/quill_display_backend.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <dlfcn.h>
#include <fstream>
#include <sstream>
#include <utility>

namespace paperpro {

QuillDisplayBackend::QuillDisplayBackend(Config config) : config_(std::move(config)) {}

QuillDisplayBackend::~QuillDisplayBackend() {
    shutdown();
}

template <typename Function>
bool QuillDisplayBackend::loadSymbol(const char* name, Function& function,
    std::string& error) {
    static_assert(sizeof(Function) == sizeof(void*));
    ::dlerror();
    void* symbol = ::dlsym(library_, name);
    if (const auto* dynamic_error = ::dlerror(); dynamic_error != nullptr || symbol == nullptr) {
        error = std::string("Quill is missing required symbol ") + name;
        return false;
    }
    std::memcpy(&function, &symbol, sizeof(function));
    return true;
}

bool QuillDisplayBackend::initialize(std::string& error) {
    if (surface_.valid()) return true;
    std::ifstream commit_input(config_.commit_file);
    std::string commit;
    std::getline(commit_input, commit);
    if (!commit_input && commit.empty()) {
        error = "Quill commit marker is missing; direct takeover refused";
        return false;
    }
    while (!commit.empty() && (commit.back() == '\r' || commit.back() == '\n'
        || commit.back() == ' ' || commit.back() == '\t')) {
        commit.pop_back();
    }
    if (commit != kRequiredCommit) {
        error = "Quill commit marker does not match the reviewed v0.1.0 pin";
        return false;
    }
    if (config_.library_path.empty()) {
        error = "PPR_QUILL_LIBRARY is empty";
        return false;
    }
    library_ = ::dlopen(config_.library_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (!library_) {
        const auto* message = ::dlerror();
        error = std::string("could not load user-supplied Quill library: ")
            + (message ? message : "unknown dynamic loader error");
        return false;
    }

    if (!loadSymbol("quill_init", init_, error)
        || !loadSymbol("quill_width", width_, error)
        || !loadSymbol("quill_height", height_, error)
        || !loadSymbol("quill_stride", stride_, error)
        || !loadSymbol("quill_format", format_, error)
        || !loadSymbol("quill_buffer", buffer_, error)
        || !loadSymbol("quill_swap_mono_fast", swap_mono_fast_, error)
        || !loadSymbol("quill_swap_mono_quality", swap_mono_quality_, error)
        || !loadSymbol("quill_swap_color", swap_color_, error)
        || !loadSymbol("quill_swap_color_full", swap_color_full_, error)
        || !loadSymbol("quill_process_events", process_events_, error)) {
        return false;
    }
    const auto init_result = init_();
    if (init_result != 0) {
        error = "Quill display initialization failed with code " + std::to_string(init_result);
        return false;
    }
    if (width_() != 1620 || height_() != 2160 || format_() != 4
        || stride_() < width_() * 4 || buffer_() == nullptr) {
        error = "Quill returned unsupported or ambiguous framebuffer geometry/format";
        return false;
    }
    surface_ = {
        reinterpret_cast<std::byte*>(buffer_()), width_(), height_(), stride_(),
        PixelFormat::Bgra8888,
    };
    return true;
}

std::chrono::nanoseconds QuillDisplayBackend::estimatedDuration(UpdateMode mode) const noexcept {
    using namespace std::chrono_literals;
    switch (mode) {
    case UpdateMode::InteractiveMono: return 12ms;
    case UpdateMode::QualityMono: return 45ms;
    case UpdateMode::Ui: return 55ms;
    case UpdateMode::Full: return 250ms;
    }
    return 50ms;
}

DisplaySubmission QuillDisplayBackend::submit(const UpdateRequest& request,
    std::string& error) {
    if (!surface_.valid()) {
        error = "Quill display is not initialized";
        return {};
    }
    const auto region = request.region.clippedTo(surface_.bounds());
    if (region.empty()) {
        error = "empty Quill update region";
        return {};
    }
    unsigned long vendor_token = 0;
    switch (request.mode) {
    case UpdateMode::InteractiveMono:
        vendor_token = swap_mono_fast_(region.x, region.y, region.width, region.height);
        break;
    case UpdateMode::QualityMono:
    case UpdateMode::Ui:
        vendor_token = swap_mono_quality_(region.x, region.y, region.width, region.height);
        break;
    case UpdateMode::Full:
        vendor_token = swap_color_full_(region.x, region.y, region.width, region.height);
        break;
    }
    process_events_();
    if (vendor_token == 0) {
        error = "Quill rejected the display update";
        return {};
    }
    ++submission_sequence_;
    return {true, submission_sequence_};
}

std::optional<DisplayCompletion> QuillDisplayBackend::pollCompletion() {
    if (process_events_) process_events_();
    // Quill v0.1.0 exposes submission tokens but no completion query. The
    // scheduler therefore keeps a conservative timed logical outstanding slot.
    return std::nullopt;
}

void QuillDisplayBackend::shutdown() noexcept {
    surface_ = {};
    // Quill v0.1.0 has no shutdown ABI and owns Qt/vendor objects until process
    // teardown. Deliberately do not dlclose an initialized adapter.
    if (library_ && !init_) {
        ::dlclose(library_);
        library_ = nullptr;
    }
}

} // namespace paperpro
