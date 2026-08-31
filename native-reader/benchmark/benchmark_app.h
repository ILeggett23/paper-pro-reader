#pragma once

#include "core/ink_model.h"
#include "core/interaction_controller.h"
#include "core/interfaces.h"
#include "core/latency_recorder.h"

#include <atomic>
#include <memory>
#include <string>

namespace paperpro {

class BenchmarkApp {
public:
    struct Config {
        std::string report_path;
        bool xochitl_managed_externally = false;
        std::atomic<bool>* external_stop = nullptr;
    };

    BenchmarkApp(std::unique_ptr<DisplayBackend> display,
        std::unique_ptr<InputBackend> input, Config config);
    int run();

private:
    static MonotonicNs nowNs() noexcept;

    std::unique_ptr<DisplayBackend> display_;
    std::unique_ptr<InputBackend> input_;
    Config config_;
    LatencyRecorder recorder_;
    std::unique_ptr<InkModel> ink_;
};

} // namespace paperpro
