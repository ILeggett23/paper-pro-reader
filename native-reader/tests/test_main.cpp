#include "benchmark/fake_display_backend.h"
#include "benchmark/synthetic_input_backend.h"
#include "core/coordinate_transform.h"
#include "core/ink_model.h"
#include "core/interaction_controller.h"
#include "core/latency_recorder.h"
#include "core/refresh_scheduler.h"
#include "core/spsc_ring.h"
#include "platform/paperpro/display/qtfb_protocol.h"
#include "ui/scene/benchmark_renderer.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <span>
#include <sstream>
#include <string>
#include <vector>

namespace {

int failures = 0;

void expect(bool condition, const char* expression, const char* test, int line) {
    if (condition) return;
    std::cerr << test << ':' << line << " expected " << expression << '\n';
    ++failures;
}

#define EXPECT(test_name, expression) expect((expression), #expression, test_name, __LINE__)

paperpro::InkPoint inkPoint(int x, int y, paperpro::MonotonicNs time = 1) {
    return {{x, y}, time, 100};
}

void addStroke(paperpro::InkModel& model, paperpro::Point start, paperpro::Point end,
    paperpro::MonotonicNs time) {
    model.beginStroke(inkPoint(start.x, start.y, time));
    (void)model.appendPoint(inkPoint(end.x, end.y, time + 1));
    (void)model.finishStroke();
}

void testCoordinateTransform() {
    constexpr auto test = "coordinate_transform";
    paperpro::CoordinateTransform upright({0, 1000}, {0, 2000}, 1620, 2160);
    EXPECT(test, (upright.normalize(0, 0) == paperpro::Point{0, 0}));
    EXPECT(test, (upright.normalize(1000, 2000) == paperpro::Point{1619, 2159}));
    const auto middle = upright.normalize(500, 1000);
    EXPECT(test, middle && middle->x == 810 && middle->y == 1080);

    paperpro::CoordinateTransform rotated({0, 1000}, {0, 2000}, 1620, 2160,
        paperpro::Rotation::Degrees90);
    EXPECT(test, (rotated.normalize(0, 0) == paperpro::Point{1619, 0}));
    EXPECT(test, (rotated.normalize(1000, 2000) == paperpro::Point{0, 2159}));

    paperpro::CoordinateTransform upside_down({0, 1000}, {0, 2000}, 1620, 2160,
        paperpro::Rotation::Degrees180);
    EXPECT(test, (upside_down.normalize(0, 0) == paperpro::Point{1619, 2159}));
    EXPECT(test, (upside_down.normalize(1000, 2000) == paperpro::Point{0, 0}));

    paperpro::CoordinateTransform counter_clockwise({0, 1000}, {0, 2000}, 1620, 2160,
        paperpro::Rotation::Degrees270);
    EXPECT(test, (counter_clockwise.normalize(0, 0) == paperpro::Point{0, 2159}));
    EXPECT(test, (counter_clockwise.normalize(1000, 2000) == paperpro::Point{1619, 0}));

    paperpro::CoordinateTransform invalid({0, 0}, {0, 10}, 10, 10);
    EXPECT(test, !invalid.normalize(0, 0));
}

void testRingBuffer() {
    constexpr auto test = "ring_buffer";
    paperpro::SpscRing<int, 4> ring;
    EXPECT(test, ring.push(1));
    EXPECT(test, ring.push(2));
    EXPECT(test, ring.push(3));
    EXPECT(test, !ring.push(4));
    EXPECT(test, ring.highWater() == 3);
    int value = 0;
    EXPECT(test, ring.pop(value) && value == 1);
    EXPECT(test, ring.push(4));
    EXPECT(test, ring.pop(value) && value == 2);
    EXPECT(test, ring.pop(value) && value == 3);
    EXPECT(test, ring.pop(value) && value == 4);
    EXPECT(test, ring.empty());
}

void testPalmAndControls() {
    constexpr auto test = "palm_and_controls";
    paperpro::InteractionController controller({0, 72, 1620, 1908},
        {0, 1980, 1620, 180});
    auto page_touch = paperpro::InputEvent{paperpro::InputEventType::TouchDown,
        {100, 100}, 10, 1, 0};
    const auto page_decision = controller.handle(page_touch);
    EXPECT(test, page_decision.consumed);
    EXPECT(test, page_decision.action == paperpro::InteractionAction::None);

    const auto eraser_x = 1620 / 5 + 20;
    (void)controller.handle({paperpro::InputEventType::TouchDown,
        {eraser_x, 2050}, 20, 2, 0});
    const auto eraser = controller.handle({paperpro::InputEventType::TouchUp,
        {eraser_x, 2050}, 30, 3, 0});
    EXPECT(test, eraser.action == paperpro::InteractionAction::SelectEraser);
    EXPECT(test, controller.selectedTool() == paperpro::Tool::Eraser);

    for (int contact = 0; contact < 5; ++contact) {
        (void)controller.handle({paperpro::InputEventType::TouchDown,
            {200 + contact * 20, 500}, 100, static_cast<std::uint32_t>(contact), contact});
    }
    EXPECT(test, controller.tick(100 + paperpro::InteractionController::kEmergencyHoldNs - 1).action
        == paperpro::InteractionAction::None);
    EXPECT(test, controller.tick(100 + paperpro::InteractionController::kEmergencyHoldNs).action
        == paperpro::InteractionAction::EmergencyExit);
}

void testMarkerControlIsolation() {
    constexpr auto test = "marker_control_isolation";
    paperpro::InteractionController controller({0, 72, 1620, 1908},
        {0, 1980, 1620, 180});
    const auto down = controller.handle({paperpro::InputEventType::MarkerDown,
        {1000, 2050}, 1, 1, 0, 100, paperpro::Tool::Pen});
    EXPECT(test, down.action == paperpro::InteractionAction::Clear);
    const auto move = controller.handle({paperpro::InputEventType::MarkerMove,
        {500, 500}, 2, 2, 0, 100, paperpro::Tool::Pen});
    EXPECT(test, move.action == paperpro::InteractionAction::None);
    const auto up = controller.handle({paperpro::InputEventType::MarkerUp,
        {500, 500}, 3, 3, 0, 0, paperpro::Tool::Pen});
    EXPECT(test, up.action == paperpro::InteractionAction::None);
}

void testPalmControlsSuppressedDuringMarker() {
    constexpr auto test = "palm_controls_suppressed_during_marker";
    paperpro::InteractionController controller({0, 72, 1620, 1908},
        {0, 1980, 1620, 180});
    const auto marker = controller.handle({paperpro::InputEventType::MarkerDown,
        {400, 400}, 1, 1, 0, 100, paperpro::Tool::Pen});
    EXPECT(test, marker.action == paperpro::InteractionAction::BeginStroke);
    (void)controller.handle({paperpro::InputEventType::TouchDown,
        {1500, 2050}, 2, 2, 0});
    const auto palm_lift = controller.handle({paperpro::InputEventType::TouchUp,
        {1500, 2050}, 3, 3, 0});
    EXPECT(test, palm_lift.action == paperpro::InteractionAction::None);
    EXPECT(test, controller.markerContactActive());
}

void testMarkerLiftOutsideCanvasIsClipped() {
    constexpr auto test = "marker_lift_outside_canvas";
    paperpro::InteractionController controller({0, 72, 1620, 1908},
        {0, 1980, 1620, 180});
    const paperpro::Point last_canvas_point{100, 1970};
    const auto down = controller.handle({paperpro::InputEventType::MarkerDown,
        last_canvas_point, 1, 1, 0, 100, paperpro::Tool::Pen});
    EXPECT(test, down.action == paperpro::InteractionAction::BeginStroke);
    const auto outside_move = controller.handle({paperpro::InputEventType::MarkerMove,
        {100, 2050}, 2, 2, 0, 100, paperpro::Tool::Pen});
    EXPECT(test, outside_move.action == paperpro::InteractionAction::None);
    const auto up = controller.handle({paperpro::InputEventType::MarkerUp,
        {100, 2050}, 3, 3, 0, 0, paperpro::Tool::Pen});
    EXPECT(test, up.action == paperpro::InteractionAction::EndStroke);
    EXPECT(test, up.point == last_canvas_point);

    paperpro::InteractionController in_bounds({0, 72, 1620, 1908},
        {0, 1980, 1620, 180});
    (void)in_bounds.handle({paperpro::InputEventType::MarkerDown,
        {100, 100}, 4, 4, 0, 100, paperpro::Tool::Pen});
    const auto in_bounds_up = in_bounds.handle({paperpro::InputEventType::MarkerUp,
        {120, 120}, 5, 5, 0, 0, paperpro::Tool::Pen});
    EXPECT(test, (in_bounds_up.point == paperpro::Point{120, 120}));
}

void testInkAndContinuousEraser() {
    constexpr auto test = "continuous_eraser";
    paperpro::InkModel model;
    addStroke(model, {10, 10}, {60, 10}, 1);
    addStroke(model, {100, 100}, {160, 100}, 3);
    addStroke(model, {300, 300}, {360, 300}, 5);
    EXPECT(test, model.visibleStrokeCount() == 3);
    model.beginEraser();
    EXPECT(test, model.eraseAt({30, 10}, 12).has_value());
    EXPECT(test, model.eraseAt({130, 100}, 12).has_value());
    EXPECT(test, model.finishEraser());
    EXPECT(test, model.visibleStrokeCount() == 1);
    EXPECT(test, model.undo().has_value());
    EXPECT(test, model.visibleStrokeCount() == 3);
}

void testClearUndoGrouping() {
    constexpr auto test = "clear_undo";
    paperpro::InkModel model;
    addStroke(model, {10, 10}, {20, 20}, 1);
    addStroke(model, {30, 30}, {40, 40}, 3);
    EXPECT(test, model.clear().has_value());
    EXPECT(test, model.visibleStrokeCount() == 0);
    EXPECT(test, model.undo().has_value());
    EXPECT(test, model.visibleStrokeCount() == 2);
}

void testDirtyBounds() {
    constexpr auto test = "dirty_bounds";
    std::vector<std::byte> pixels(1620ULL * 2160ULL * 4ULL);
    paperpro::BenchmarkRenderer renderer({pixels.data(), 1620, 2160, 1620 * 4,
        paperpro::PixelFormat::Bgra8888});
    const auto left = renderer.drawSegment({0, 73}, {5, 73});
    const auto right = renderer.drawSegment({1619, 1979}, {1610, 1979});
    EXPECT(test, left.x >= 0 && left.y >= 72 && left.right() <= 1620);
    EXPECT(test, right.x >= 0 && right.bottom() <= 1980 && right.right() <= 1620);
    EXPECT(test, !left.intersects(renderer.toolbarBounds()));
    EXPECT(test, !right.intersects(renderer.toolbarBounds()));
}

void testRefreshCoalescingAndOutstanding() {
    constexpr auto test = "refresh_coalescing";
    paperpro::FakeDisplayBackend display;
    std::string error;
    EXPECT(test, display.initialize(error));
    paperpro::LatencyRecorder recorder;
    paperpro::RefreshScheduler::Config config{1, 100, 20, 50};
    paperpro::RefreshScheduler scheduler(display, recorder, config);
    scheduler.beginInteractive();
    scheduler.requestInteractive({10, 10, 10, 10}, 90, 100);
    scheduler.requestInteractive({25, 10, 10, 10}, 91, 100);
    EXPECT(test, (scheduler.pendingRegion() == paperpro::Rect{10, 10, 25, 10}));
    EXPECT(test, scheduler.tick(100, error));
    EXPECT(test, display.submissions().size() == 1);
    EXPECT(test, (display.submissions()[0].request.region == paperpro::Rect{10, 10, 25, 10}));
    scheduler.requestInteractive({40, 10, 5, 5}, 101, 101);
    EXPECT(test, scheduler.tick(110, error));
    EXPECT(test, display.submissions().size() == 1);
    display.completeLast(125);
    EXPECT(test, scheduler.tick(125, error));
    EXPECT(test, display.submissions().size() == 2);
    EXPECT(test, (display.submissions()[1].request.region == paperpro::Rect{40, 10, 5, 5}));
    EXPECT(test, display.maxOutstandingCount() == 1);
    EXPECT(test, scheduler.adaptiveCadence() == 25);
}

void testCoalescingPreservesEveryInkSample() {
    constexpr auto test = "coalescing_preserves_samples";
    paperpro::InkModel model;
    paperpro::FakeDisplayBackend display;
    std::string error;
    (void)display.initialize(error);
    paperpro::LatencyRecorder recorder;
    paperpro::RefreshScheduler scheduler(display, recorder,
        paperpro::RefreshScheduler::Config{1, 100, 20, 50});

    EXPECT(test, model.beginStroke(inkPoint(10, 100, 1)));
    scheduler.beginInteractive();
    for (int index = 1; index <= 100; ++index) {
        const auto point = inkPoint(10 + index, 100 + index % 3,
            static_cast<paperpro::MonotonicNs>(index + 1));
        EXPECT(test, model.appendPoint(point).has_value());
        scheduler.requestInteractive({10 + index - 1, 98, 2, 6},
            point.received_at_ns, point.received_at_ns);
    }
    EXPECT(test, model.totalPoints() == 101);
    EXPECT(test, display.submissions().empty());
    EXPECT(test, scheduler.tick(102, error));
    EXPECT(test, display.submissions().size() == 1);
    EXPECT(test, model.totalPoints() == 101);
    EXPECT(test, display.submissions().front().request.region.width >= 100);
}

void testMaximumPendingRegionAge() {
    constexpr auto test = "maximum_pending_region_age";
    paperpro::FakeDisplayBackend display;
    std::string error;
    (void)display.initialize(error);
    paperpro::LatencyRecorder recorder;
    paperpro::RefreshScheduler scheduler(display, recorder,
        paperpro::RefreshScheduler::Config{1000, 1000, 20, 50});

    scheduler.requestUi({1, 1, 4, 4}, paperpro::UpdateMode::Ui, 1);
    EXPECT(test, scheduler.tick(1, error));
    display.completeLast(2);
    EXPECT(test, scheduler.tick(2, error));
    scheduler.requestUi({20, 20, 4, 4}, paperpro::UpdateMode::Ui, 3);
    EXPECT(test, scheduler.tick(22, error));
    EXPECT(test, display.submissions().size() == 1);
    EXPECT(test, scheduler.tick(23, error));
    EXPECT(test, display.submissions().size() == 2);
}

void testIdleCleanupAndCancellation() {
    constexpr auto test = "idle_cleanup_and_cancel";
    paperpro::FakeDisplayBackend display;
    std::string error;
    display.initialize(error);
    paperpro::LatencyRecorder recorder;
    paperpro::RefreshScheduler::Config config{1, 100, 20, 50};
    paperpro::RefreshScheduler scheduler(display, recorder, config);
    scheduler.beginInteractive();
    scheduler.requestInteractive({10, 10, 20, 20}, 1, 1);
    scheduler.tick(1, error);
    display.completeLast(5);
    scheduler.endInteractive(5);
    scheduler.tick(5, error);
    EXPECT(test, display.submissions().size() == 1);
    scheduler.tick(55, error);
    EXPECT(test, display.submissions().size() == 2);
    EXPECT(test, display.submissions().back().request.mode == paperpro::UpdateMode::QualityMono);

    paperpro::RefreshScheduler cancelled(display, recorder, config);
    cancelled.requestUi({1, 1, 4, 4}, paperpro::UpdateMode::Ui, 100);
    cancelled.cancel();
    EXPECT(test, cancelled.tick(200, error));
    EXPECT(test, display.submissions().size() == 2);
}

void testNewStrokeCancelsWaitingCleanup() {
    constexpr auto test = "new_stroke_cancels_waiting_cleanup";
    paperpro::FakeDisplayBackend display;
    std::string error;
    (void)display.initialize(error);
    paperpro::LatencyRecorder recorder;
    paperpro::RefreshScheduler::Config config{1, 100, 20, 50};
    paperpro::RefreshScheduler scheduler(display, recorder, config);
    scheduler.beginInteractive();
    scheduler.requestInteractive({10, 10, 20, 20}, 1, 1);
    (void)scheduler.tick(1, error);
    scheduler.endInteractive(2);
    // Cleanup becomes due while the first explicit update is still outstanding.
    (void)scheduler.tick(60, error);
    EXPECT(test, !scheduler.pendingRegion().has_value());
    scheduler.beginInteractive();
    scheduler.requestInteractive({100, 100, 10, 10}, 61, 61);
    display.completeLast(70);
    (void)scheduler.tick(70, error);
    EXPECT(test, display.submissions().size() == 2);
    EXPECT(test, display.submissions().back().request.mode
        == paperpro::UpdateMode::InteractiveMono);
}

void testSyntheticOverrun() {
    constexpr auto test = "synthetic_overrun";
    paperpro::SyntheticInputBackend input;
    std::string error;
    input.start(error);
    for (std::uint32_t index = 0; index < 1100; ++index) {
        input.push({paperpro::InputEventType::MarkerMove, {1, 1}, index, index, 0});
    }
    EXPECT(test, input.markerSamplesDropped() > 0);
    EXPECT(test, input.markerRingHighWater() == 1024);
    input.stop();
}

void testLatencyReportPrivacy() {
    constexpr auto test = "latency_report_privacy";
    paperpro::LatencyRecorder recorder;
    recorder.markerSampleReceived();
    recorder.markerSampleConsumed();
    recorder.observeRenderPreparation(1'000'000);
    const auto path = std::filesystem::temp_directory_path() / "ppr-native-metrics.jsonl";
    std::string error;
    EXPECT(test, recorder.writeReport(path.string(), "FAKE", "test", false, error));
    std::ifstream input(path);
    std::stringstream buffer;
    buffer << input.rdbuf();
    const auto report = buffer.str();
    EXPECT(test, report.find("marker_samples_received") != std::string::npos);
    EXPECT(test, report.find("coordinates") == std::string::npos);
    EXPECT(test, report.find("question") == std::string::npos);
    EXPECT(test, paperpro::LatencyRecorder::appendRestoration(path.string(), true, error));
    std::filesystem::remove(path);
}

} // namespace

int main() {
    testCoordinateTransform();
    testRingBuffer();
    testPalmAndControls();
    testMarkerControlIsolation();
    testPalmControlsSuppressedDuringMarker();
    testMarkerLiftOutsideCanvasIsClipped();
    testInkAndContinuousEraser();
    testClearUndoGrouping();
    testDirtyBounds();
    testRefreshCoalescingAndOutstanding();
    testCoalescingPreservesEveryInkSample();
    testMaximumPendingRegionAge();
    testIdleCleanupAndCancellation();
    testNewStrokeCancelsWaitingCleanup();
    testSyntheticOverrun();
    testLatencyReportPrivacy();
    if (failures != 0) {
        std::cerr << failures << " native-reader assertions failed\n";
        return 1;
    }
    std::cout << "native-reader tests: PASS\n";
    return 0;
}
