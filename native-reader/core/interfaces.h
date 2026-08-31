#pragma once

#include "core/types.h"

#include <chrono>
#include <optional>
#include <span>
#include <string>
#include <string_view>

namespace paperpro {

class DisplayBackend {
public:
    virtual ~DisplayBackend() = default;
    virtual bool initialize(std::string& error) = 0;
    [[nodiscard]] virtual SurfaceView surface() noexcept = 0;
    [[nodiscard]] virtual std::string_view name() const noexcept = 0;
    [[nodiscard]] virtual CompletionModel completionModel() const noexcept = 0;
    [[nodiscard]] virtual std::chrono::nanoseconds estimatedDuration(UpdateMode mode) const noexcept = 0;
    virtual DisplaySubmission submit(const UpdateRequest& request, std::string& error) = 0;
    virtual std::optional<DisplayCompletion> pollCompletion() = 0;
    virtual void shutdown() noexcept = 0;
};

class InputBackend {
public:
    virtual ~InputBackend() = default;
    virtual bool start(std::string& error) = 0;
    virtual bool waitForEvents(std::chrono::milliseconds timeout) = 0;
    virtual std::size_t drain(std::span<InputEvent> destination) = 0;
    [[nodiscard]] virtual std::uint64_t markerSamplesDropped() const noexcept = 0;
    [[nodiscard]] virtual std::size_t markerRingHighWater() const noexcept = 0;
    [[nodiscard]] virtual bool healthy() const noexcept = 0;
    virtual void stop() noexcept = 0;
};

// Phase 1 exposes the future service boundaries without implementing document,
// persistence, dictionary, or network behavior in the benchmark process.
class DocumentEngine {
public:
    virtual ~DocumentEngine() = default;
    [[nodiscard]] virtual std::string_view engineName() const noexcept = 0;
    virtual bool open(const std::string& path, std::string& error) = 0;
    virtual void close() noexcept = 0;
};

class AnnotationStore {
public:
    virtual ~AnnotationStore() = default;
    virtual bool openForDocument(std::string_view document_id, std::string& error) = 0;
    virtual bool flush(std::string& error) = 0;
    virtual void close() noexcept = 0;
};

class DictionaryService {
public:
    virtual ~DictionaryService() = default;
    [[nodiscard]] virtual bool availableOffline() const noexcept = 0;
    virtual void cancel() noexcept = 0;
};

class AIClient {
public:
    virtual ~AIClient() = default;
    [[nodiscard]] virtual bool configured() const noexcept = 0;
    virtual void cancel(std::string_view request_id) noexcept = 0;
};

} // namespace paperpro
