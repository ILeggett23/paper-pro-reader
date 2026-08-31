#pragma once

#include "core/types.h"

#include <array>
#include <cstddef>
#include <cstdint>

namespace paperpro {

enum class InteractionAction : std::uint8_t {
    None,
    BeginStroke,
    ContinueStroke,
    EndStroke,
    BeginErase,
    ContinueErase,
    EndErase,
    SelectPen,
    SelectEraser,
    Undo,
    Clear,
    Exit,
    EmergencyExit,
};

struct InteractionDecision {
    InteractionAction action = InteractionAction::None;
    bool consumed = true;
    Point point;
    MonotonicNs received_at_ns = 0;
    std::uint16_t pressure = 0;
};

class InteractionController {
public:
    static constexpr std::size_t kMaxTouchContacts = 16;
    static constexpr MonotonicNs kEmergencyHoldNs = 1'500'000'000ULL;

    InteractionController(Rect canvas, Rect toolbar) noexcept;

    [[nodiscard]] InteractionDecision handle(const InputEvent& event) noexcept;
    [[nodiscard]] InteractionDecision tick(MonotonicNs now_ns) noexcept;
    [[nodiscard]] Tool selectedTool() const noexcept { return selected_tool_; }
    [[nodiscard]] bool markerContactActive() const noexcept { return marker_contact_active_; }
    [[nodiscard]] std::size_t activeTouchContacts() const noexcept;
    void selectTool(Tool tool) noexcept { selected_tool_ = tool; }

private:
    struct TouchContact {
        bool active = false;
        ControlButton pressed_button = ControlButton::None;
    };

    [[nodiscard]] ControlButton buttonAt(Point point) const noexcept;
    [[nodiscard]] InteractionDecision controlDecision(ControlButton button,
        const InputEvent& event) noexcept;
    [[nodiscard]] InteractionDecision markerDecision(const InputEvent& event) noexcept;
    [[nodiscard]] InteractionDecision touchDecision(const InputEvent& event) noexcept;
    void updateEmergencyState(MonotonicNs now_ns) noexcept;

    Rect canvas_;
    Rect toolbar_;
    Tool selected_tool_ = Tool::Pen;
    Tool active_marker_tool_ = Tool::Pen;
    bool marker_contact_active_ = false;
    bool marker_control_contact_ = false;
    bool marker_has_canvas_point_ = false;
    Point last_marker_canvas_point_;
    bool emergency_requires_all_touches_up_ = false;
    bool emergency_fired_ = false;
    MonotonicNs emergency_started_ns_ = 0;
    std::array<TouchContact, kMaxTouchContacts> touches_{};
};

} // namespace paperpro
