#include "benchmark/benchmark_app.h"

#include "core/refresh_scheduler.h"
#include "core/systemd_watchdog.h"
#include "ui/scene/benchmark_renderer.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <iostream>
#include <optional>
#include <string>
#include <thread>
#include <utility>

namespace paperpro {

BenchmarkApp::BenchmarkApp(std::unique_ptr<DisplayBackend> display,
    std::unique_ptr<InputBackend> input, Config config)
    : display_(std::move(display))
    , input_(std::move(input))
    , config_(std::move(config))
    , ink_(std::make_unique<InkModel>()) {
}

MonotonicNs BenchmarkApp::nowNs() noexcept {
    return static_cast<MonotonicNs>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

int BenchmarkApp::run() {
    std::string error;
    std::string shutdown_reason = "normal_exit";
    int exit_code = 0;

    if (!display_->initialize(error)) {
        std::cerr << "Display initialization failed: " << error << '\n';
        shutdown_reason = "display_initialization_failure";
        exit_code = 4;
        std::string report_error;
        (void)recorder_.writeReport(config_.report_path, display_->name(), shutdown_reason,
            config_.xochitl_managed_externally, report_error);
        return exit_code;
    }
    const auto surface = display_->surface();
    if (!surface.valid() || surface.width != 1620 || surface.height != 2160) {
        std::cerr << "Display backend did not provide the Paper Pro portrait surface\n";
        shutdown_reason = "unsupported_display_geometry";
        exit_code = 4;
        display_->shutdown();
        std::string report_error;
        (void)recorder_.writeReport(config_.report_path, display_->name(), shutdown_reason,
            config_.xochitl_managed_externally, report_error);
        return exit_code;
    }
    if (!input_->start(error)) {
        std::cerr << "Input initialization failed: " << error << '\n';
        shutdown_reason = "input_initialization_failure";
        exit_code = 5;
        display_->shutdown();
        std::string report_error;
        (void)recorder_.writeReport(config_.report_path, display_->name(), shutdown_reason,
            config_.xochitl_managed_externally, report_error);
        return exit_code;
    }

    BenchmarkRenderer renderer(surface);
    InteractionController interaction(renderer.canvasBounds(), renderer.toolbarBounds());
    RefreshScheduler scheduler(*display_, recorder_);
    SystemdWatchdog watchdog;
    renderer.drawInitial(display_->name(), interaction.selectedTool());
    auto now = nowNs();
    scheduler.requestUi(surface.bounds(), UpdateMode::Full, now);
    if (!scheduler.tick(now, error)) {
        std::cerr << "Initial display update failed: " << error << '\n';
        shutdown_reason = "display_submission_failure";
        exit_code = 6;
    }
    if (exit_code == 0) watchdog.ready();

    bool running = exit_code == 0;
    std::optional<Point> last_marker_point;
    std::array<InputEvent, 256> events{};

    const auto requestInkRefresh = [&](Rect region, MonotonicNs input_time,
                                       MonotonicNs request_time) {
        if (!region.empty()) scheduler.requestInteractive(region, input_time, request_time);
    };

    while (running) {
        now = nowNs();
        watchdog.pingIfDue(now);
        if (config_.external_stop
            && config_.external_stop->load(std::memory_order_relaxed)) {
            shutdown_reason = "signal";
            break;
        }

        auto wait_time = std::chrono::milliseconds(10);
        if (const auto deadline = scheduler.nextDeadline(); deadline && *deadline <= now) {
            wait_time = std::chrono::milliseconds(0);
        } else if (deadline) {
            const auto remaining = std::chrono::nanoseconds(*deadline - now);
            wait_time = std::min(wait_time,
                std::chrono::duration_cast<std::chrono::milliseconds>(remaining));
        }
        input_->waitForEvents(wait_time);

        const auto count = input_->drain(events);
        if (!input_->healthy()) {
            std::cerr << "Input backend stopped unexpectedly\n";
            shutdown_reason = "input_backend_failure";
            exit_code = 10;
            running = false;
        }
        for (std::size_t index = 0; index < count && running; ++index) {
            const auto& event = events[index];
            if (isMarkerEvent(event.type)) recorder_.markerSampleReceived();
            const auto decision = interaction.handle(event);
            const auto preparation_start = nowNs();
            const InkPoint ink_point{decision.point, decision.received_at_ns, decision.pressure};
            switch (decision.action) {
            case InteractionAction::BeginStroke:
                scheduler.beginInteractive();
                if (!ink_->beginStroke(ink_point)) {
                    shutdown_reason = "ink_capacity_failure";
                    exit_code = 7;
                    running = false;
                    break;
                }
                last_marker_point = decision.point;
                requestInkRefresh(renderer.drawPoint(decision.point),
                    decision.received_at_ns, preparation_start);
                break;
            case InteractionAction::ContinueStroke:
                if (last_marker_point && ink_->appendPoint(ink_point)) {
                    requestInkRefresh(renderer.drawSegment(*last_marker_point, decision.point),
                        decision.received_at_ns, preparation_start);
                    last_marker_point = decision.point;
                }
                break;
            case InteractionAction::EndStroke:
                if (last_marker_point && ink_->strokeActive()) {
                    if (ink_->appendPoint(ink_point)) {
                        requestInkRefresh(renderer.drawSegment(*last_marker_point, decision.point),
                            decision.received_at_ns, preparation_start);
                    }
                    (void)ink_->finishStroke();
                }
                last_marker_point.reset();
                scheduler.endInteractive(preparation_start);
                break;
            case InteractionAction::BeginErase:
                scheduler.beginInteractive();
                ink_->beginEraser();
                if (const auto dirty = ink_->eraseAt(decision.point, 20)) {
                    renderer.restoreInkRegion(*dirty, *ink_);
                    requestInkRefresh(dirty->padded(8, renderer.canvasBounds()),
                        decision.received_at_ns, preparation_start);
                }
                break;
            case InteractionAction::ContinueErase:
                if (const auto dirty = ink_->eraseAt(decision.point, 20)) {
                    renderer.restoreInkRegion(*dirty, *ink_);
                    requestInkRefresh(dirty->padded(8, renderer.canvasBounds()),
                        decision.received_at_ns, preparation_start);
                }
                break;
            case InteractionAction::EndErase:
                if (const auto dirty = ink_->eraseAt(decision.point, 20)) {
                    renderer.restoreInkRegion(*dirty, *ink_);
                    requestInkRefresh(dirty->padded(8, renderer.canvasBounds()),
                        decision.received_at_ns, preparation_start);
                }
                (void)ink_->finishEraser();
                scheduler.endInteractive(preparation_start);
                break;
            case InteractionAction::SelectPen:
            case InteractionAction::SelectEraser:
                scheduler.requestUi(renderer.drawControls(interaction.selectedTool()),
                    UpdateMode::Ui, preparation_start);
                break;
            case InteractionAction::Undo:
                if (const auto dirty = ink_->undo()) {
                    renderer.restoreInkRegion(*dirty, *ink_);
                    scheduler.requestUi(dirty->padded(8, renderer.canvasBounds()),
                        UpdateMode::QualityMono, preparation_start);
                }
                break;
            case InteractionAction::Clear:
                if (const auto dirty = ink_->clear()) {
                    renderer.restoreInkRegion(*dirty, *ink_);
                    scheduler.requestUi(dirty->padded(8, renderer.canvasBounds()),
                        UpdateMode::QualityMono, preparation_start);
                }
                break;
            case InteractionAction::Exit:
                shutdown_reason = "on_screen_exit";
                running = false;
                break;
            case InteractionAction::EmergencyExit:
                shutdown_reason = "emergency_exit";
                running = false;
                break;
            case InteractionAction::None:
                break;
            }
            if (isMarkerEvent(event.type)) {
                recorder_.markerSampleConsumed();
                const auto prepared = nowNs();
                if (prepared >= event.received_at_ns) {
                    recorder_.observeRenderPreparation(prepared - event.received_at_ns);
                }
            }
            if (ink_->capacityFailure()) {
                shutdown_reason = "ink_capacity_failure";
                exit_code = 7;
                running = false;
            }
        }

        now = nowNs();
        const auto emergency = interaction.tick(now);
        if (emergency.action == InteractionAction::EmergencyExit) {
            shutdown_reason = "five_finger_emergency_exit";
            running = false;
        }
        if (!scheduler.tick(now, error)) {
            std::cerr << "Display update failed: " << error << '\n';
            shutdown_reason = "display_submission_failure";
            exit_code = 6;
            running = false;
        }
        const auto dropped = input_->markerSamplesDropped();
        recorder_.markerSamplesDropped(dropped);
        recorder_.observeMarkerRing(input_->markerRingHighWater());
        if (dropped != 0) {
            std::cerr << "Marker ring overrun; benchmark invalid\n";
            shutdown_reason = "marker_ring_overrun";
            exit_code = 8;
            running = false;
        }
    }

    scheduler.cancel();
    input_->stop();
    display_->shutdown();
    std::string report_error;
    if (!recorder_.writeReport(config_.report_path, display_->name(), shutdown_reason,
            config_.xochitl_managed_externally, report_error)) {
        std::cerr << "Could not write benchmark report: " << report_error << '\n';
        if (exit_code == 0) exit_code = 9;
    }
    return exit_code;
}

} // namespace paperpro
