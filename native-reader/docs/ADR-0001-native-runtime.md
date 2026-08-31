# ADR-0001: Native runtime and isolated Marker path

- Status: Accepted for the Phase 0/1 benchmark; device qualification pending
- Date: 2026-08-31
- Decision owners: Paper Pro Reader maintainers
- Applies to: `native-reader/`
- Supersedes: none

## Context

The existing product is a KOReader derivative with valuable, tested reading
contracts and substantial Phase 1-5 functionality. Its product-facing writing
path still passes through KOReader's Lua input and widget infrastructure and a
QTFB display bridge. Physical testing showed that completed-stroke behavior,
persistence, Undo, erasing, selection, notes, and normal touch can work, while
the writing experience remained the release gate. RC5 is still awaiting its
returned hardware result.

The new application must ultimately provide an original reading-first EPUB
interface. This execution is deliberately narrower: establish a native
display/input/ink benchmark that measures whether a simpler path can satisfy
reliability, latency, input routing, and recovery requirements. The existing
KOReader implementation remains intact as a behavioral reference and fallback.

## Decision

Build the benchmark as a C++20 application with CMake. Use Qt Core/Gui or
QPainter only when it materially helps outside the input-to-live-refresh path;
do not require QML, JavaScript, a browser runtime, or a general UI event queue
for Marker processing. The first renderer is a small retained raster surface
with incremental segment painting and bounded dirty rectangles.

The runtime is organized around public interfaces:

- `DisplayBackend` owns display initialization, the reusable surface,
  interactive and cleanup submissions, optional completion reporting, and
  shutdown;
- `InputBackend` owns capability-based evdev discovery, blocking receipt,
  frame assembly, monotonic receipt times, and separate Marker/touch events;
- `RefreshScheduler` owns dirty-region union, adaptive cadence, maximum region
  age, one update in flight, completion, idle cleanup, and cancellation;
- `CoordinateTransform` owns queried ABS-range normalization, portrait
  rotation, clipping, and conversions between input and display coordinates;
- `InteractionController` owns Pen/Eraser/Undo/Clear/Exit behavior, strict palm
  rejection, continuous erasing, and one-contact Undo grouping;
- `DocumentEngine`, `AnnotationStore`, `DictionaryService`, and `AIClient` are
  interface contracts for later phases and have no live benchmark work to do.

No existing KOReader A- or B-class engine file is changed to make the spike
work.

## Marker hot-path rule

The permitted live path is:

```text
evdev fd ready
  -> InputBackend receives a complete frame
  -> monotonic timestamp + preallocated sample ring
  -> CoordinateTransform
  -> InteractionController tool/contact policy
  -> incremental retained-surface segment
  -> bounded dirty rectangle
  -> RefreshScheduler
  -> DisplayBackend interactive submission
```

The following are forbidden synchronously on that path:

- ReaderUI, UIManager, the KOReader Lua widget tree, or a QML scene;
- document layout, pagination, EPUB parsing, or anchor resolution;
- SQLite or any other persistence write;
- JSON/image serialization or benchmark-report file output;
- network access, AI requests, authentication work, or retry processing;
- normal diagnostic logging, coordinate recording, or stroke-shape capture;
- unbounded allocation after a contact begins; and
- waiting for an unrelated application task.

The ring is fixed capacity. Every valid Marker sample is either consumed or
the overrun counter makes the benchmark fail; samples are never silently
replaced. Static controls are rendered separately and are not repainted for
each segment.

## Display abstraction

Two interchangeable backends are required.

### Direct takeover backend

The primary backend dynamically loads a user-built Quill v0.1.0 library pinned
to commit `39262ee0bef69915e3ead3ac218d5973916f422a`. The project packages no
Quill binary and no vendor library. Before drawing, the adapter requires all
expected C ABI symbols and validates non-null buffer access, exactly 1620 x
2160 dimensions for this target, sane stride, and a supported pixel format.
Ambiguous or incomplete initialization is a hard failure.

The operator selects it with `--backend takeover` or
`PPR_DISPLAY_BACKEND=takeover`. `PPR_QUILL_LIBRARY` defaults to
`/home/root/.local/lib/paper-pro-reader/libquill.so`.
`PPR_QUILL_COMMIT_FILE` defaults to the adjacent `quill.commit` file and must
contain the exact pin above. `PPR_QUILL_SHA256`, when supplied, adds an
operator-controlled binary-integrity check; it does not change the source pin
or establish firmware compatibility.

`PPR_VENDOR_LIBRARY_PATH` selects the proprietary copy already present on the
operator's device (default `/usr/lib/plugins/scenegraph/libqsgepaper.so`). It is
never copied into the application or package. Optional
`PPR_VENDOR_LIBRARY_SHA256` verifies the operator-selected device file; Quill's
dynamic load and required-symbol resolution remain the final compatibility
check after recovery is armed.

The launcher, not the backend, owns Xochitl lifecycle. It completes guarded
model/firmware/library/input/SSH preflight, arms independent recovery, stops
Xochitl, and starts the benchmark. A failed backend initialization triggers
immediate restoration and a non-zero exit. A Quill or vendor-library hash is
recorded in the qualification report but is not treated as a compatibility
allowlist.

### QTFB/AppLoad backend

The fallback backend uses the installed Xovi/AppLoad/QTFB environment and does
not stop Xochitl. It exists for development, recovery, unsupported takeover
firmware, and comparison. It receives the same retained surface and scheduler
requests but translates them through the fallback bridge. QTFB measurements
are labeled separately and are never represented as direct-backend latency.

Backend selection is explicit at launch. Takeover failure does not silently
continue through QTFB after stock UI has been stopped.
The command-line form `--backend takeover|qtfb` takes the same values as
`PPR_DISPLAY_BACKEND=takeover|qtfb`.

## Input abstraction

Linux input discovery is based on evdev capabilities, not unexplained event
node numbers. The backend scans candidates, queries event/key/ABS bitsets and
ABS ranges, and classifies Marker versus touch. It then uses epoll (or an
equivalent blocking kernel wait), assembles events to `SYN_REPORT`, and assigns
monotonic receipt timestamps.

The Paper Pro portrait transform is derived from queried ranges and explicit
rotation configuration. Hard-coded 1620 x 2160 output bounds are acceptable for
this device target; hard-coded input minima/maxima or `/dev/input/eventN`
selection are not.

Write mode consumes every page-area finger contact. Touch never draws, selects,
or navigates. Only intentional control hit targets remain operable. Marker and
eraser contacts remain separate from finger slots. The synthetic backend uses
the same normalized event contract in host tests.

## Refresh policy

Refresh policy belongs only in `RefreshScheduler`. Interactive Marker updates
use the fastest appropriate monochrome partial operation. Dirty rectangles are
clipped and unioned while a submission is outstanding. Completion drains at
most one next union. If a backend does not expose completion, its documented
submission acknowledgment is the serialization boundary and the scheduler
still permits only one logical outstanding update.

An idle timer schedules a bounded quality cleanup after writing stops. A new
contact cancels or postpones cleanup. Full-screen quality refresh is forbidden
while the Marker is down. Shutdown cancels pending work before display release.

## Persistence boundaries

Phase 1 benchmark strokes are session data, not a new annotation authority.
The latency recorder retains counters, durations, resource usage, shutdown
reason, and restoration outcome only. It does not retain coordinates, shapes,
selected text, book content, handwriting images, credentials, or personal
paths. Report serialization occurs outside the live path.

The later native product will use one SQLite authority with versioned
migrations, foreign keys, transactions, crash recovery, bounded fields, and
explicit document revisions. Active Marker samples first enter memory; durable
flush happens asynchronously and is forced only at safe close/suspend
boundaries. Existing KOReader sidecars, ink stores, vocabulary data, queued AI
requests, and response stores are read-only migration inputs until a separately
reviewed conversion phase.

## Future document and service integration

CREngine is the intended future EPUB engine behind `DocumentEngine`, not a
component of this benchmark. Layout and page cache workers will publish
immutable page scenes to the UI. Versioned EPUB text anchors will combine
document fingerprint, spine identity, structural range, quote context,
chapter-relative position, layout signature, and explicit resolution status.
Screen coordinates will never be authoritative annotation locations.

`AnnotationStore` will own highlights, text notes, and sticky-note metadata in
SQLite. Sticky-note strokes use note-local coordinates and a text anchor.
`DictionaryService` will provide local StarDict lookup and provenance without a
network requirement.

`AIClient` will talk only to a private HTTPS backend using a revocable device
token. Permanent provider keys stay server-side. Raw handwriting vectors remain
local; any image is derived immediately before an explicit bounded submission.
Offline queueing, stable request IDs, cancellation, saved conversations, and
passage navigation are later work and must remain off the Marker path.

## Rejected alternatives

### Continue moving refresh policy through ReaderUI/UIManager

Rejected for the performance benchmark because it does not isolate the known
hardware question. KOReader remains valuable and preserved, but its general UI
pipeline is not the measurement architecture.

### QTFB-only native application

Rejected as the sole path because it retains a mediation layer precisely where
latency is under test. QTFB remains required as fallback and comparison.

### Link directly to `libqsgepaper.so`

Rejected. It would broaden proprietary ABI coupling, complicate redistribution,
and lose the reviewed clean-room Quill boundary. The device-local vendor object
is never committed or packaged.

### QML/Qt Quick, Flutter, React Native, Electron, or a web view

Rejected from the live Marker path due to extra scene/event/runtime layers and,
for web-derived stacks, inappropriate dependency and security cost. This does
not prohibit carefully measured Qt Core/Gui utilities outside the hot path.

### Permanently replace Xochitl

Rejected. The application is a reader, not an operating-system replacement.
Xochitl remains the stock UI and is restored after every takeover session.

### Begin EPUB migration before hardware qualification

Rejected because it would optimize product structure before proving the
display/input foundation. Phase 1 stops at the device gate.

## Consequences

Positive consequences:

- the latency-critical path is small, testable, and auditable;
- direct and fallback measurements are comparable behind one interface;
- product persistence and backend behavior remain isolated from input timing;
- lifecycle failure is treated as a first-class platform concern; and
- later document, annotation, dictionary, and AI services have explicit seams.

Costs and unresolved consequences:

- direct mode depends on an unsupported community adapter and a proprietary
  device-local library;
- Xochitl stop/restore and wake-lock policy require root privileges and real
  failure testing;
- two display backends must be maintained and qualified independently;
- the present raster UI intentionally has little visual polish; and
- host success does not authorize EPUB implementation.

The decision is revisited if direct mode cannot restore Xochitl reliably, loses
samples, fails strict palm rejection, or does not show a meaningful latency
advantage over QTFB on the target hardware.
