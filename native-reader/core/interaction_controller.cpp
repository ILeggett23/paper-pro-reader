#include "core/interaction_controller.h"

#include <algorithm>

namespace paperpro {

InteractionController::InteractionController(Rect canvas, Rect toolbar) noexcept
    : canvas_(canvas), toolbar_(toolbar) {
}

std::size_t InteractionController::activeTouchContacts() const noexcept {
    return static_cast<std::size_t>(std::count_if(touches_.begin(), touches_.end(),
        [](const TouchContact& contact) { return contact.active; }));
}

ControlButton InteractionController::buttonAt(Point point) const noexcept {
    if (!toolbar_.contains(point)) return ControlButton::None;
    constexpr std::array<ControlButton, 5> buttons{
        ControlButton::Pen, ControlButton::Eraser, ControlButton::Undo,
        ControlButton::Clear, ControlButton::Exit,
    };
    const auto relative_x = std::clamp(point.x - toolbar_.x, 0, toolbar_.width - 1);
    const auto index = std::min<std::size_t>(buttons.size() - 1,
        static_cast<std::size_t>(relative_x) * buttons.size()
            / static_cast<std::size_t>(toolbar_.width));
    return buttons[index];
}

InteractionDecision InteractionController::controlDecision(ControlButton button,
    const InputEvent& event) noexcept {
    InteractionDecision decision{
        InteractionAction::None, true, event.point, event.received_at_ns, event.pressure,
    };
    switch (button) {
    case ControlButton::Pen:
        selected_tool_ = Tool::Pen;
        decision.action = InteractionAction::SelectPen;
        break;
    case ControlButton::Eraser:
        selected_tool_ = Tool::Eraser;
        decision.action = InteractionAction::SelectEraser;
        break;
    case ControlButton::Undo: decision.action = InteractionAction::Undo; break;
    case ControlButton::Clear: decision.action = InteractionAction::Clear; break;
    case ControlButton::Exit: decision.action = InteractionAction::Exit; break;
    case ControlButton::None: break;
    }
    return decision;
}

InteractionDecision InteractionController::markerDecision(const InputEvent& event) noexcept {
    InteractionDecision decision{
        InteractionAction::None, true, event.point, event.received_at_ns, event.pressure,
    };
    if (event.type == InputEventType::MarkerDown) {
        marker_contact_active_ = true;
        marker_has_canvas_point_ = false;
        emergency_requires_all_touches_up_ = true;
        emergency_started_ns_ = 0;
        for (auto& touch : touches_) touch.pressed_button = ControlButton::None;
        const auto button = buttonAt(event.point);
        if (button != ControlButton::None) {
            marker_control_contact_ = true;
            return controlDecision(button, event);
        }
        marker_control_contact_ = false;
        marker_has_canvas_point_ = canvas_.contains(event.point);
        if (!marker_has_canvas_point_) return decision;
        last_marker_canvas_point_ = event.point;
        active_marker_tool_ = event.tool == Tool::Eraser ? Tool::Eraser : selected_tool_;
        decision.action = active_marker_tool_ == Tool::Eraser
            ? InteractionAction::BeginErase : InteractionAction::BeginStroke;
        return decision;
    }

    if (event.type == InputEventType::MarkerMove) {
        if (!marker_contact_active_ || marker_control_contact_) return decision;
        if (!canvas_.contains(event.point)) return decision;
        marker_has_canvas_point_ = true;
        last_marker_canvas_point_ = event.point;
        decision.action = active_marker_tool_ == Tool::Eraser
            ? InteractionAction::ContinueErase : InteractionAction::ContinueStroke;
        return decision;
    }

    if (event.type == InputEventType::MarkerUp) {
        const auto was_control = marker_control_contact_;
        const auto active_tool = active_marker_tool_;
        const auto had_canvas_point = marker_has_canvas_point_;
        marker_contact_active_ = false;
        marker_control_contact_ = false;
        marker_has_canvas_point_ = false;
        if (was_control || !had_canvas_point) return decision;
        decision.point = canvas_.contains(event.point)
            ? event.point : last_marker_canvas_point_;
        decision.action = active_tool == Tool::Eraser
            ? InteractionAction::EndErase : InteractionAction::EndStroke;
    }
    return decision;
}

void InteractionController::updateEmergencyState(MonotonicNs now_ns) noexcept {
    if (emergency_requires_all_touches_up_) {
        if (activeTouchContacts() == 0) emergency_requires_all_touches_up_ = false;
        emergency_started_ns_ = 0;
        emergency_fired_ = false;
        return;
    }
    if (!marker_contact_active_ && activeTouchContacts() >= 5) {
        if (emergency_started_ns_ == 0) emergency_started_ns_ = now_ns;
    } else {
        emergency_started_ns_ = 0;
        emergency_fired_ = false;
    }
}

InteractionDecision InteractionController::touchDecision(const InputEvent& event) noexcept {
    InteractionDecision decision{
        InteractionAction::None, true, event.point, event.received_at_ns, event.pressure,
    };
    if (event.contact_id < 0
        || static_cast<std::size_t>(event.contact_id) >= touches_.size()) {
        return decision;
    }
    auto& contact = touches_[static_cast<std::size_t>(event.contact_id)];
    if (event.type == InputEventType::TouchDown) {
        contact.active = true;
        contact.pressed_button = marker_contact_active_
            ? ControlButton::None : buttonAt(event.point);
    } else if (event.type == InputEventType::TouchUp) {
        const auto pressed = contact.pressed_button;
        contact.active = false;
        contact.pressed_button = ControlButton::None;
        updateEmergencyState(event.received_at_ns);
        if (!marker_contact_active_ && pressed != ControlButton::None
            && pressed == buttonAt(event.point)
            && activeTouchContacts() == 0) {
            return controlDecision(pressed, event);
        }
        return decision;
    }
    updateEmergencyState(event.received_at_ns);
    return decision;
}

InteractionDecision InteractionController::handle(const InputEvent& event) noexcept {
    if (isMarkerEvent(event.type)) return markerDecision(event);
    if (event.type == InputEventType::PowerPressed) {
        return {InteractionAction::EmergencyExit, true, event.point,
            event.received_at_ns, event.pressure};
    }
    return touchDecision(event);
}

InteractionDecision InteractionController::tick(MonotonicNs now_ns) noexcept {
    updateEmergencyState(now_ns);
    if (!emergency_fired_ && emergency_started_ns_ != 0
        && now_ns - emergency_started_ns_ >= kEmergencyHoldNs) {
        emergency_fired_ = true;
        return {InteractionAction::EmergencyExit, true, {}, now_ns, 0};
    }
    return {};
}

} // namespace paperpro
