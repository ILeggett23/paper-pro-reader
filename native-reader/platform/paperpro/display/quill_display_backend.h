#pragma once

#include "core/interfaces.h"

#include <cstdint>
#include <string>

namespace paperpro {

class QuillDisplayBackend final : public DisplayBackend {
public:
    static constexpr const char* kRequiredCommit =
        "39262ee0bef69915e3ead3ac218d5973916f422a";

    struct Config {
        std::string library_path;
        std::string commit_file;
    };

    explicit QuillDisplayBackend(Config config);
    ~QuillDisplayBackend() override;

    bool initialize(std::string& error) override;
    [[nodiscard]] SurfaceView surface() noexcept override { return surface_; }
    [[nodiscard]] std::string_view name() const noexcept override { return "QUILL DIRECT"; }
    [[nodiscard]] CompletionModel completionModel() const noexcept override {
        return CompletionModel::Estimated;
    }
    [[nodiscard]] std::chrono::nanoseconds estimatedDuration(UpdateMode mode) const noexcept override;
    DisplaySubmission submit(const UpdateRequest& request, std::string& error) override;
    std::optional<DisplayCompletion> pollCompletion() override;
    void shutdown() noexcept override;

private:
    using InitFn = int (*)();
    using IntFn = int (*)();
    using BufferFn = unsigned char* (*)();
    using SwapFn = unsigned long (*)(int, int, int, int);
    using ProcessEventsFn = void (*)();

    template <typename Function>
    bool loadSymbol(const char* name, Function& function, std::string& error);

    Config config_;
    void* library_ = nullptr;
    SurfaceView surface_;
    InitFn init_ = nullptr;
    IntFn width_ = nullptr;
    IntFn height_ = nullptr;
    IntFn stride_ = nullptr;
    IntFn format_ = nullptr;
    BufferFn buffer_ = nullptr;
    SwapFn swap_mono_fast_ = nullptr;
    SwapFn swap_mono_quality_ = nullptr;
    SwapFn swap_color_ = nullptr;
    SwapFn swap_color_full_ = nullptr;
    ProcessEventsFn process_events_ = nullptr;
    std::uint64_t submission_sequence_ = 0;
};

} // namespace paperpro
