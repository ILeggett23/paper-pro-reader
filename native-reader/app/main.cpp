#include "benchmark/benchmark_app.h"
#include "core/latency_recorder.h"
#include "platform/paperpro/display/qtfb_display_backend.h"
#include "platform/paperpro/display/quill_display_backend.h"
#include "platform/paperpro/input/evdev_input_backend.h"

#include <atomic>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace {

constexpr std::string_view kVersion = "0.1.0-phase1";
std::atomic<bool> stop_requested{false};

void signalHandler(int) {
    stop_requested.store(true, std::memory_order_relaxed);
}

std::string environment(const char* name, std::string fallback = {}) {
    const auto* value = std::getenv(name);
    return value && *value ? value : std::move(fallback);
}

void usage() {
    std::cout
        << "paper-pro-reader-benchmark " << kVersion << "\n"
        << "  --backend takeover|qtfb\n"
        << "  --quill-library PATH --quill-commit-file PATH\n"
        << "  --report PATH [--rotation 0|90|180|270]\n"
        << "  --marker-device PATH --touch-device PATH --power-device PATH\n"
        << "  --probe-input\n"
        << "  --append-restoration REPORT true|false\n";
}

std::optional<paperpro::Rotation> parseRotation(const std::string& value) {
    if (value == "0") return paperpro::Rotation::Degrees0;
    if (value == "90") return paperpro::Rotation::Degrees90;
    if (value == "180") return paperpro::Rotation::Degrees180;
    if (value == "270") return paperpro::Rotation::Degrees270;
    return std::nullopt;
}

} // namespace

int main(int argc, char** argv) {
    std::string backend = environment("PPR_DISPLAY_BACKEND", "qtfb");
    std::string quill_library = environment("PPR_QUILL_LIBRARY",
        "/home/root/.local/lib/paper-pro-reader/libquill.so");
    std::string quill_commit_file = environment("PPR_QUILL_COMMIT_FILE",
        "/home/root/.local/lib/paper-pro-reader/quill.commit");
    std::string report_path = environment("PPR_BENCHMARK_REPORT",
        "/home/root/.local/state/paper-pro-reader-native/benchmark.jsonl");
    paperpro::EvdevInputBackend::Config input_config;
    bool append_restoration = false;
    bool restoration_value = false;
    bool probe_input = false;

    for (int index = 1; index < argc; ++index) {
        const std::string argument = argv[index];
        const auto next = [&]() -> std::optional<std::string> {
            if (index + 1 >= argc) return std::nullopt;
            return std::string(argv[++index]);
        };
        if (argument == "--help") { usage(); return 0; }
        if (argument == "--version") { std::cout << kVersion << '\n'; return 0; }
        if (argument == "--backend") {
            const auto value = next(); if (!value) return 2; backend = *value;
        } else if (argument == "--quill-library") {
            const auto value = next(); if (!value) return 2; quill_library = *value;
        } else if (argument == "--quill-commit-file") {
            const auto value = next(); if (!value) return 2; quill_commit_file = *value;
        } else if (argument == "--report") {
            const auto value = next(); if (!value) return 2; report_path = *value;
        } else if (argument == "--rotation") {
            const auto value = next();
            const auto rotation = value ? parseRotation(*value) : std::nullopt;
            if (!rotation) { std::cerr << "Invalid rotation\n"; return 2; }
            input_config.rotation = *rotation;
        } else if (argument == "--marker-device") {
            const auto value = next(); if (!value) return 2; input_config.marker_device = *value;
        } else if (argument == "--touch-device") {
            const auto value = next(); if (!value) return 2; input_config.touch_device = *value;
        } else if (argument == "--power-device") {
            const auto value = next(); if (!value) return 2; input_config.power_device = *value;
        } else if (argument == "--append-restoration") {
            const auto path = next();
            const auto value = next();
            if (!path || !value || (*value != "true" && *value != "false")) return 2;
            report_path = *path;
            append_restoration = true;
            restoration_value = *value == "true";
        } else if (argument == "--probe-input") {
            probe_input = true;
        } else {
            std::cerr << "Unknown option: " << argument << '\n';
            usage();
            return 2;
        }
    }

    if (append_restoration) {
        std::string error;
        if (!paperpro::LatencyRecorder::appendRestoration(report_path,
                restoration_value, error)) {
            std::cerr << error << '\n';
            return 3;
        }
        return 0;
    }

    if (probe_input) {
        paperpro::EvdevInputBackend input(std::move(input_config));
        std::string error;
        if (!input.start(error)) {
            std::cerr << "Input probe failed: " << error << '\n';
            return 4;
        }
        input.stop();
        std::cout << "INPUT_PROBE_OK " << input.diagnosticSummary() << '\n';
        return 0;
    }

    std::unique_ptr<paperpro::DisplayBackend> display;
    bool xochitl_managed_externally = false;
    if (backend == "takeover") {
        if (environment("PPR_SUPERVISED_TAKEOVER") != "1") {
            std::cerr << "Direct takeover requires the supervised launch-takeover.sh path\n";
            return 2;
        }
        display = std::make_unique<paperpro::QuillDisplayBackend>(
            paperpro::QuillDisplayBackend::Config{quill_library, quill_commit_file});
        xochitl_managed_externally = true;
    } else if (backend == "qtfb") {
        display = std::make_unique<paperpro::QtfbDisplayBackend>();
    } else {
        std::cerr << "Unsupported backend: " << backend << '\n';
        return 2;
    }

    std::signal(SIGINT, signalHandler);
    std::signal(SIGTERM, signalHandler);

    auto input = std::make_unique<paperpro::EvdevInputBackend>(std::move(input_config));
    paperpro::BenchmarkApp app(std::move(display), std::move(input), {
        report_path, xochitl_managed_externally, &stop_requested,
    });
    return app.run();
}
