#include "core/refresh_scheduler.h"

#include <algorithm>
#include <chrono>

namespace paperpro {

RefreshScheduler::RefreshScheduler(DisplayBackend& display, LatencyRecorder& recorder) noexcept
    : RefreshScheduler(display, recorder, Config{}) {
}

RefreshScheduler::RefreshScheduler(DisplayBackend& display, LatencyRecorder& recorder,
    Config config) noexcept
    : display_(display)
    , recorder_(recorder)
    , config_(config)
    , adaptive_cadence_ns_(config.minimum_cadence_ns) {
}

UpdateMode RefreshScheduler::stronger(UpdateMode left, UpdateMode right) noexcept {
    const auto strength = [](UpdateMode mode) {
        switch (mode) {
        case UpdateMode::InteractiveMono: return 0;
        case UpdateMode::Ui: return 1;
        case UpdateMode::QualityMono: return 2;
        case UpdateMode::Full: return 3;
        }
        return 0;
    };
    return strength(right) > strength(left) ? right : left;
}

void RefreshScheduler::beginInteractive() noexcept {
    interactive_ = true;
    cleanup_due_ns_ = 0;
}

void RefreshScheduler::mergePending(Rect region, UpdateMode mode,
    MonotonicNs input_received_ns, MonotonicNs now_ns) noexcept {
    region = region.clippedTo(display_.surface().bounds());
    if (region.empty() || cancelled_) return;
    if (pending_region_) {
        pending_region_ = pending_region_->united(region);
        pending_mode_ = stronger(pending_mode_, mode);
        ++pending_damage_count_;
    } else {
        pending_region_ = region;
        pending_mode_ = mode;
        pending_started_ns_ = now_ns;
        pending_oldest_input_ns_ = input_received_ns;
        pending_damage_count_ = 1;
    }
    if (input_received_ns != 0 && (pending_oldest_input_ns_ == 0
        || input_received_ns < pending_oldest_input_ns_)) {
        pending_oldest_input_ns_ = input_received_ns;
    }
}

void RefreshScheduler::requestInteractive(Rect region, MonotonicNs input_received_ns,
    MonotonicNs now_ns) noexcept {
    mergePending(region, UpdateMode::InteractiveMono, input_received_ns, now_ns);
    cleanup_region_ = cleanup_region_ ? cleanup_region_->united(region) : region;
    cleanup_due_ns_ = 0;
}

void RefreshScheduler::endInteractive(MonotonicNs now_ns) noexcept {
    interactive_ = false;
    if (cleanup_region_) cleanup_due_ns_ = now_ns + config_.idle_cleanup_delay_ns;
}

void RefreshScheduler::requestUi(Rect region, UpdateMode mode, MonotonicNs now_ns) noexcept {
    mergePending(region, mode, 0, now_ns);
}

void RefreshScheduler::completeOutstanding(MonotonicNs completed_at_ns,
    bool completion_observed) noexcept {
    if (!outstanding_) return;
    const auto duration = completed_at_ns >= outstanding_->submitted_at_ns
        ? completed_at_ns - outstanding_->submitted_at_ns : 0;
    if (completion_observed) recorder_.observeDisplayCompletion(duration);
    if (completion_observed && duration > 0) {
        adaptive_cadence_ns_ = std::clamp(duration,
            config_.minimum_cadence_ns, config_.maximum_cadence_ns);
    }
    outstanding_.reset();
}

bool RefreshScheduler::tick(MonotonicNs now_ns, std::string& error) {
    if (cancelled_) return true;

    if (outstanding_) {
        const auto completion = display_.pollCompletion();
        if (completion && completion->token == outstanding_->token) {
            completeOutstanding(completion->completed_at_ns != 0
                ? completion->completed_at_ns : now_ns, true);
        } else if (display_.completionModel() == CompletionModel::Estimated
            && now_ns >= outstanding_->estimated_completion_ns) {
            completeOutstanding(now_ns, false);
        }
    }

    if (!interactive_ && !outstanding_ && !pending_region_
        && cleanup_due_ns_ != 0 && now_ns >= cleanup_due_ns_ && cleanup_region_) {
        mergePending(*cleanup_region_, UpdateMode::QualityMono, 0, now_ns);
        cleanup_region_.reset();
        cleanup_due_ns_ = 0;
        recorder_.idleCleanup();
    }

    if (outstanding_ || !pending_region_) return true;
    const auto pending_age = now_ns >= pending_started_ns_ ? now_ns - pending_started_ns_ : 0;
    if (now_ns < next_submission_ns_
        && pending_age < config_.maximum_pending_age_ns) {
        return true;
    }

    const auto request = UpdateRequest{*pending_region_, pending_mode_, now_ns};
    const auto submission = display_.submit(request, error);
    if (!submission.accepted || submission.token == 0) {
        if (error.empty()) error = "display backend rejected update";
        return false;
    }

    recorder_.observeDirtyRegionAge(pending_age);
    if (pending_oldest_input_ns_ != 0 && now_ns >= pending_oldest_input_ns_) {
        recorder_.observeInputToSubmission(now_ns - pending_oldest_input_ns_);
    }
    recorder_.displaySubmitted(pending_damage_count_ > 1, pending_mode_);
    const auto estimated = static_cast<MonotonicNs>(
        display_.estimatedDuration(pending_mode_).count());
    if (display_.completionModel() == CompletionModel::Estimated) {
        adaptive_cadence_ns_ = std::clamp(estimated,
            config_.minimum_cadence_ns, config_.maximum_cadence_ns);
    }
    outstanding_ = Outstanding{
        submission.token,
        now_ns,
        now_ns + std::max(estimated, config_.minimum_cadence_ns),
        pending_mode_,
    };
    next_submission_ns_ = now_ns + adaptive_cadence_ns_;
    pending_region_.reset();
    pending_started_ns_ = 0;
    pending_oldest_input_ns_ = 0;
    pending_damage_count_ = 0;
    pending_mode_ = UpdateMode::InteractiveMono;
    return true;
}

void RefreshScheduler::cancel() noexcept {
    cancelled_ = true;
    pending_region_.reset();
    cleanup_region_.reset();
    cleanup_due_ns_ = 0;
}

std::optional<MonotonicNs> RefreshScheduler::nextDeadline() const noexcept {
    std::optional<MonotonicNs> deadline;
    const auto consider = [&deadline](MonotonicNs value) {
        if (value == 0) return;
        if (!deadline || value < *deadline) deadline = value;
    };
    if (outstanding_ && display_.completionModel() == CompletionModel::Estimated) {
        consider(outstanding_->estimated_completion_ns);
    }
    if (pending_region_) consider(std::min(next_submission_ns_,
        pending_started_ns_ + config_.maximum_pending_age_ns));
    if (!interactive_) consider(cleanup_due_ns_);
    return deadline;
}

} // namespace paperpro
