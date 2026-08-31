# Future native reader architecture

## Status and scope

This document fixes the contracts that the Phase 1 display/input benchmark
must not foreclose. It does not implement an EPUB reader, annotation database,
dictionary, AI client, or product UI. Those features remain gated on physical
Paper Pro performance and recovery evidence.

The application is a reading application that temporarily coexists with
Xochitl. It is not an operating system, notebook-suite, cloud-service,
firmware, account, or proprietary synchronization replacement.

## Architectural priorities

Every trade-off is evaluated in this order:

1. reliability and recoverability;
2. low Marker latency;
3. correct input routing and palm rejection;
4. correct document and annotation persistence;
5. reading functionality;
6. offline capability;
7. security and privacy;
8. visual design.

Visual fidelity cannot justify a blocking Marker path, an ambiguous anchor, a
second data authority, or a recovery path that depends only on the application
process remaining healthy.

## Layered design

```text
app/
  composition, lifecycle state, shutdown and recovery reporting

ui/scene + ui/controls + ui/overlays
  retained scene, original reading UI, selection/note/dictionary/AI surfaces

core/
  document -> layout/page cache -> navigation/selection
  annotations + dictionary + AI + persistence

platform/paperpro/
  display backend + refresh scheduler
  raw input backend + coordinate transform
  lifecycle/takeover guards and Xochitl restoration
```

Dependencies point inward through interfaces. Document, annotation,
dictionary, AI, and UI code cannot select waveforms, open evdev nodes, call a
proprietary display library, or stop Xochitl. Platform code cannot understand
book text, annotations, questions, or credentials.

The public seams are:

- `DisplayBackend`: owns surface presentation, update completion, backend
  capability reporting, and safe shutdown;
- `InputBackend`: produces separate normalized Marker, eraser, and touch
  events with monotonic receipt times;
- `RefreshScheduler`: owns dirty-region union, one outstanding update,
  adaptive interactive cadence, maximum pending age, idle cleanup, and
  shutdown cancellation;
- `CoordinateTransform`: maps queried device ABS ranges and rotation into
  bounded display coordinates and later maps layout-local spaces;
- `InteractionController`: owns Read/Write mode, palm policy, control routing,
  stroke/erase gesture boundaries, and undo grouping;
- `DocumentEngine`: opens immutable document revisions and supplies layout,
  text, hit-testing, navigation, and anchor-resolution operations;
- `AnnotationStore`: is the only write interface for highlights, notes, sticky
  notes, and attached strokes;
- `DictionaryService`: performs bounded local lookup with provenance;
- `AIClient`: submits/cancels provider-neutral requests to a private backend
  and never exposes a provider credential to the device.

## Thread and queue ownership

The native Marker hot path is intentionally separate from all reader feature
work:

```text
blocking epoll input thread
  -> normalize and timestamp
  -> bounded preallocated SPSC sample ring
  -> render/interaction thread
     -> incremental retained surface paint
     -> bounded dirty rectangle
     -> RefreshScheduler
        -> DisplayBackend (at most one update outstanding)
```

After stroke start, this path performs no EPUB layout, SQLite operation, JSON
serialization, network request, normal diagnostic write, unbounded allocation,
or traversal of a general UI event queue. It preserves every accepted sample;
ring overflow is a benchmark failure rather than an invisible simplification.

Static controls live in a separate retained layer and are not repainted for
every segment. Marker segments update only their padded, clipped bounds. A new
stroke cancels or postpones idle cleanup. Pen lift closes an in-memory command;
a separate worker later persists it. Shutdown and suspend force a bounded
flush outside the sample-processing callback.

Touch and Marker have distinct device identities and streams. In Write mode,
all page-area touch contacts are consumed, including contacts beginning before
Marker-down, while explicit toolbar and emergency-exit controls remain
operable. One physical eraser contact can delete many intersected strokes but
creates one undo command.

## Display architecture

`DisplayBackend` has two interchangeable implementations:

1. Direct takeover is the primary performance path. It uses a reviewed,
   version-pinned open adapter and dynamically loads any required proprietary
   library from a user-supplied device-local path. Missing/unknown symbols or
   versions fail before Xochitl is left unavailable. No proprietary object is
   distributed or placed in CI.
2. QTFB/AppLoad is the development, comparison, recovery, and unsupported-
   firmware path. Its latency is measured independently and is never presented
   as equivalent to takeover.

Both consume the same reusable application surface and refresh contract. The
renderer expresses interactive monochrome versus bounded quality cleanup;
backend capability mapping stays inside the backend. The scheduler never has
more than one update outstanding and unions new dirt while waiting for
completion. A maximum pending age prevents quiet starvation.

## EPUB document engine

The first reading engine will support EPUB through a native C++ integration of
CREngine after its ABI, license, toolchain, and threading behavior are pinned
and audited. CREngine remains behind `DocumentEngine`; its internal pointers
and mutable layout objects do not escape into UI or persistence.

Opening a document produces an immutable `DocumentRevision`:

```text
document_id
content_fingerprint
container_fingerprint
engine_version
spine_manifest
opened_at
```

The engine exposes chapter/spine identity, layout pages, text runs, glyph/word
hit boxes, structural positions, selection expansion, and anchor resolution.
It reports missing sentence/paragraph capabilities instead of inventing them.
PDF and other fixed-layout formats remain in KOReader until a separate engine
and anchor contract is designed.

### Page cache

The layout subsystem generates immutable page snapshots keyed by document
revision, spine item, layout signature, and logical page. A bounded memory LRU
keeps the current page and a small forward/back window. An optional disk cache
contains only derived tiles and can be deleted without losing annotations or
position.

Page generation runs away from the input/render thread. Navigation swaps only
a fully prepared page snapshot. A cache miss shows a stable reading surface
rather than blocking Marker processing. Cache keys include engine and schema
versions, viewport, rotation, typography, margins, spacing, and theme.

### Navigation

`NavigationController` owns the current resolved location, forward/back
history, deliberate page turns, chapter jumps, and return-to-passage actions.
It accepts structural locations, never screen coordinates. A navigation commit
updates the visible page first and schedules reading-position persistence
afterward. Write mode page-lock blocks incidental page gestures; a deliberate
Navigate action temporarily enables them.

## Text anchor contract

Every native EPUB annotation uses a versioned anchor:

```text
schema_version
document_fingerprint
spine_href_or_chapter_id
start_cfi_or_xpointer
end_cfi_or_xpointer
exact_quote
prefix
suffix
approximate_chapter_position
layout_signature
resolution_status
```

`layout_signature` helps diagnose the originating presentation but is not the
semantic authority. Resolution is deterministic and ordered:

1. exact structural anchor in the same document revision;
2. exact quote near the expected structural location;
3. bounded prefix/suffix matching;
4. bounded chapter-relative recovery;
5. `unresolved` if a unique attachment cannot be proven.

Candidates are scored only inside documented bounds. A tie or weak match is
unresolved. Resolution records method, revision, and time without overwriting
the source anchor, so a later engine can retry. The application never moves a
note to plausible but incorrect text.

## Selection and highlights

Selection hit-tests immutable page text runs and produces a detached snapshot:

```text
selected_text
selected_word
sentence_or_paragraph_when_available
prefix_and_suffix_context
screen_boxes
TextAnchor
book_and_chapter_metadata
capability_flags
```

Word, sentence, paragraph, and page expansion are engine operations with
explicit capability/failure results. Selection presentation is transient.
Saving a highlight creates one annotation transaction that owns the color,
timestamps, quote, and anchor; selection geometry is never persisted as the
location authority. Markers and highlight paint are derived from resolved
annotations and the current page snapshot.

## Annotation and sticky-note model

One SQLite database is the native application's durable authority. A conceptual
model includes:

```text
documents -> document_revisions
documents -> anchors -> resolution_attempts
anchors -> annotations
annotations -> sticky_notes -> note_strokes
documents -> vocabulary_entries
documents -> ai_conversations -> ai_turns
ai_requests -> ai_turns
legacy_imports -> imported records
```

Foreign keys, transactions, versioned forward migrations, bounded values,
integrity checks, and measured crash recovery are mandatory. Database work is
serialized on a persistence worker, never on the active Marker sample path.
Close and suspend perform a forced, time-bounded flush. Failed flush is visible
and prevents an unsafe normal-exit claim.

A sticky note contains:

```text
stable_note_id
document_id and document_revision_id
TextAnchor
note_canvas_width and note_canvas_height
ordered vector strokes in note-local coordinates
optional typed text
created_at and updated_at
schema_version
```

Note-local coordinates, not page/screen coordinates, are authoritative. The
page shows a small marker derived from the resolved anchor. Opening it presents
a bounded writing panel while preserving the reading page beneath. Pen,
highlighter, eraser, and undo reuse the qualified native ink primitives. A
note stays unresolved rather than drifting when its passage cannot be found.

Existing KOReader/Phase 1–5 stores are never opened for write by the native
application. A later explicit importer copies data transactionally and records
source identity/hashes; preserving the source is the initial rollback model.

## Dictionary and vocabulary

`DictionaryService` targets offline StarDict. The preferred implementation is
a measured direct `.idx`/`.dict` reader with Unicode normalization, bounded
result decoding, dictionary-order configuration, provenance, and an LRU result
cache. A subprocess/helper is acceptable only if measurement and cancellation
show it cannot impair input or shutdown.

A lookup needs no internet connection and returns zero or more results with
the source dictionary identified. The contextual definition overlay remains
compact and leaves the passage visible. An explicit successful single-word
lookup may create or enrich one vocabulary row in the SQLite authority while
preserving review state. Dictionary files remain external content, not copied
into the application package.

## AI, offline queue, and conversations

`AIClient` remains provider-neutral:

```text
submit(request) -> stable request ID
cancel(request ID)
observe(request ID)
testConnection()
```

The device connects over verified HTTPS with a revocable application token to
a private backend. Provider keys stay server-side. The provider adapter uses
`store:false`; tools and web access remain disabled unless a later separately
reviewed design explicitly adds them.

The application sends only an explicit, bounded `ReadingContext`: selected
passage, reliable sentence/paragraph or nearby text, optional title/author/
chapter, question, and response preferences. Local document IDs, paths,
navigation anchors, annotations, unrelated books, vocabulary, and complete
chapters are stripped from transport.

Typed questions contain bounded text. Handwritten questions retain raw vectors
locally and rasterize a tightly cropped bounded image immediately before
submission; the derived image is removed after encoding and is not the local
authority. Recognition uncertainty produces a clarification state rather than
invented words.

The SQLite offline queue persists before sending and owns `queued`, `sending`,
`completed`, `failed`, and `cancelled` transitions, stable IDs, attempts,
backoff, and restart recovery. Exactly one worker sends; a `sending` item found
after a crash returns to a safe retry state with the same ID. Cancellation and
idempotency prevent duplicate paid requests. Network recovery processes a
bounded batch and can never block document or input threads.

Saved conversations contain local anchors, selected source, bounded turns,
status, recognized question text when available, and optional local question
vectors. Prior images are not resent. History, follow-up, passage navigation,
and a deliberate full-study surface read from this local authority and remain
usable offline.

## Original reading UI

The native interface is original and stock-inspired in interaction clarity,
not a copy of proprietary source, icons, fonts, layouts, or assets. It uses a
small retained scene and QPainter or equivalent raster primitives, with no
QML, JavaScript, browser, web view, or cross-platform web framework on the
Marker path.

Design rules:

- the book remains visible behind compact contextual surfaces;
- targets are large enough for touch and Marker;
- Read and Write modes are explicit and visually unmistakable;
- the Write toolbar has deliberate Pen, Eraser, Undo, navigation, and Done;
- selection actions provide Highlight, Note, Define, and explicit Ask;
- sticky-note and conversation markers use selective color and remain subtle;
- there are no decorative animations, token streaming, spinners, or fades;
- full-screen transitions are reserved for deliberate library/study tasks;
- display updates are complete-line or bounded complete-state paints;
- Exit/Back to reMarkable is always obvious, with a documented emergency
  gesture independent of normal controls.

The UI sends render invalidations to `RefreshScheduler`; it never issues
display-specific refresh calls. Modal state is explicit so ink cannot paint
over menus or closed surfaces.

## Reliability, privacy, and observability

Lifecycle recovery remains outside feature services. The takeover launcher
records pre-launch state, refuses unsupported/unknown configurations, stops
Xochitl only after guards pass, and pairs the application with an independent
systemd/ExecStopPost-style restoration path. Normal exit, signals, display
failure, process crash, and repeated restoration all converge on an idempotent
Xochitl restore. USB SSH access is preserved.

`LatencyRecorder` records aggregate sample counts, ring high-water/drops,
input-to-render/submission/completion timing, update counts/coalescing/age,
idle cleanups, full-screen updates, CPU, peak memory, shutdown reason, backend
identity, and restoration success. It does not record coordinates, shapes,
text, books, handwriting images, credentials, or personal paths.

Failures are typed and surfaced. Unsupported firmware, missing display
symbols, evdev discovery ambiguity, ring overflow, persistence failure, and
restoration failure cannot be swallowed or converted into success.

## Sequenced delivery gates

1. **Native benchmark:** qualify takeover and QTFB display, raw input,
   transforms, strict palm behavior, live ink, continuous erase, refresh
   scheduling, instrumentation, package, and restoration. No user-data writes.
2. **Physical Paper Pro gate:** measure visible latency, panel behavior,
   touch/Marker concurrency, eraser ergonomics, pressure, suspend/resume,
   battery impact, firmware compatibility, and real crash restoration. Host
   tests cannot satisfy this gate.
3. **EPUB read-only slice:** integrate CREngine, fingerprints, page cache,
   navigation, and position restore without annotations.
4. **Anchors and native SQLite:** qualify schema, backups, exact resolution,
   highlights, sticky notes, close/suspend flushing, and only then a read-only
   migration dry run.
5. **Offline dictionary and vocabulary:** add local lookup and reviewed import.
6. **AI and conversations:** add secure backend client and durable queue after
   privacy, idempotency, cancellation, offline, and restart tests.
7. **Product UI and broader migration:** replace product-facing KOReader paths
   only feature by feature, while retaining KOReader as rollback and for
   unsupported formats until parity is proven.

The next phase cannot start merely because CI or a simulator passes. The
current implementation stops at `DEVICE TEST REQUIRED`.
