# Feature migration map

## Purpose and inventory baseline

This map defines how the existing Paper Pro Reader behavior can move into the
native application without creating two competing owners for user data. It is
an inventory and migration contract, not authorization to migrate data now.

The baseline inspected for this decision is `origin/main`, including Phases
1–5, plus the open and unmerged Phase 6 PR #6 at RC5 commit
`8ae4353409e8c5569c9d1fba3176fb0318517c6e`. RC5 is a behavioral reference for
Write Mode, palm suppression, coalesced refresh, idle persistence, and
continuous erasing. Nothing in this spike copies RC5 commits, changes its
branch, or treats its unreturned device qualification as a PASS.

During the native display/input benchmark, KOReader remains the only working
reader and the only authority for all existing reading data. The native
benchmark owns only its in-memory benchmark strokes and privacy-safe aggregate
measurements.

## Phase 1 no-write boundary

The native benchmark MUST NOT read, import, rewrite, delete, migrate, or append
to any of these existing stores:

- KOReader global settings or per-document DocSettings sidecars;
- ReaderAnnotation annotations, bookmarks, notes, or reading position;
- `vocabulary_builder.sqlite3`;
- any per-document `paperpro-ink.json`;
- `paperpro-ai-queue.json` or its `.old` recovery copy;
- `paperpro-ai-responses.json` or its `.old` recovery copy;
- AI credentials, device tokens, backend settings, or diagnostics;
- installed StarDict indexes, dictionaries, or lookup history;
- PDF-embedded annotations or user EPUB/PDF files.

Benchmark Pen, Eraser, Undo, and Clear state is deliberately ephemeral. A
benchmark report may contain counts, timings, memory/CPU measurements, backend
identity, and shutdown/recovery state, but never coordinates, stroke geometry,
book content, selected text, questions, answers, images, credentials, or
personal paths. This boundary prevents a platform experiment from silently
becoming a data migration.

## Feature-by-feature map

“Legacy role” describes the intended state only after a native feature reaches
behavioral, migration, and physical-device parity. Until then, KOReader remains
the available implementation.

| Feature | Current implementation | Authoritative owner today | Reusable concept or native component | Native migration strategy | Data conversion | Legacy role after parity |
| --- | --- | --- | --- | --- | --- | --- |
| Reader composition | `PaperProReader` attached to `ReaderUI` | KOReader `ReaderUI` lifecycle | Explicit application composition root with dependency-injected interfaces | Rebuild feature composition around native services; do not embed `ReaderUI` in the Marker path | None | Recovery/reference reader until native reading parity |
| Document opening/provider choice | `ReaderUI`, `DocumentRegistry`, CREngine and MuPDF/K2pdfopt providers | KOReader provider registry and DocSettings | `DocumentEngine`, later backed by CREngine for EPUB | Add EPUB only after the hardware gate; preserve a separately installable KOReader path for unsupported documents | Later import of recent-book metadata only, if explicitly approved | Fallback for non-migrated formats |
| Reading position | ReaderRolling/ReaderPaging state in DocSettings | Per-document KOReader DocSettings | Versioned native document revision plus structural location | Import by copy after anchor resolver exists; retain source value and import ledger | Yes, format-specific and later | Read-only recovery source after verified import |
| Bookmarks | ReaderBookmark list, mutations, and navigation | Per-document DocSettings/ReaderAnnotation data | Native annotation row with `bookmark` kind and a resolved text anchor | Import stable source identity, timestamps, label, and anchor after position resolution is qualified | Yes | Read-only recovery source after count/navigation audit |
| Selection snapshot | `SelectionService` copies ReaderHighlight/provider data | Transient selection; document provider owns geometry/text | Immutable native `SelectionSnapshot` with a versioned `TextAnchor` | Reimplement selection over native layout hit-testing; retain explicit capability flags | No persistent conversion | Behavioral reference |
| EPUB anchors | CREngine XPointer start/end in `DocumentAnchor` | CREngine/DocSettings records that contain the anchor | Structural CFI/XPointer plus quote/prefix/suffix recovery | Resolve against an exact document fingerprint and revision; never attach on ambiguous recovery | Yes for records imported from existing stores | Compatibility input after migration |
| PDF anchors | Page, native `pos0`/`pos1`, and page boxes | KOReader fixed-layout providers and each referencing store | A separate fixed-layout anchor type, not an EPUB approximation | Deferred until EPUB MVP is stable; preserve raw legacy payload on any future import | Yes, later and format-specific | KOReader remains PDF fallback |
| Passage navigation | `AnchorNavigator`, ReaderLink back stack, ReaderRolling/ReaderPaging | Active KOReader reader | Native `NavigationController` with immutable history entries | Resolve anchor first, then commit navigation and history atomically | No standalone store; imported records retain anchors | Reference/fallback |
| Highlight display and creation | ReaderHighlight, ReaderAnnotation, ReaderBookmark | ReaderAnnotation collection in DocSettings; optional PDF write-through | Native selection overlay plus `AnnotationStore` transaction | Write only to native SQLite once its schema, migrations, backups, and importer are qualified | Yes, copy annotations with stable legacy identity and resolution status | Read-only recovery source; PDF path remains fallback initially |
| Contextual typed notes | `AnnotationService`, `NoteOverlay`, Notes Hub | ReaderAnnotation/ReaderBookmark in DocSettings | Native annotation service and contextual overlay | Import as annotation rows referencing resolved text anchors; never create a duplicate note for the same legacy key | Yes | Reference/fallback after reconciliation |
| Note markers | ReaderView sidemark plus product marker policy | Derived presentation from annotations | Scene node derived from visible anchored note rows | Recompute from layout; do not store screen coordinates | None | Reference only |
| Sticky handwritten notes | Not yet a durable standalone feature; Phase 3 ink and Phase 5 question ink supply building blocks | No existing sticky-note authority | Native `StickyNote` with note-local vector canvas and text anchor | Implement only after native anchors and SQLite authority; show a small marker and bounded note panel | Potential opt-in conversion from selected legacy ink, never automatic | New native feature |
| Local definitions | `DefinitionService` -> ReaderDictionary -> `sdcv`/StarDict | Installed StarDict files; lookup result is transient | `DictionaryService`, direct StarDict index reader or measured helper | Reuse user-installed openly licensed StarDict data; normalize Unicode and retain source provenance | Dictionary files need no conversion; cache rows are new | KOReader lookup remains fallback until result parity |
| Definition overlay | `ReaderOverlay` and `DefinitionOverlay` | Derived UI state | Native compact overlay anchored to selection boxes | Recreate with retained scene primitives; no network fallback implied | None | Reference only |
| Vocabulary | `VocabularyService` and Vocabulary Builder plugin | `vocabulary_builder.sqlite3`, one authoritative row per word/title | Native vocabulary tables in the single SQLite authority | Transactional, idempotent copy preserving review schedule, definitions, provenance, context, and source anchor | Yes | Read-only recovery/export source after verified row reconciliation |
| Vocabulary review state | Vocabulary Builder review/due/streak columns | `vocabulary_builder.sqlite3` | Versioned native review model | Preserve counts and timestamps exactly; do not reinterpret during import | Yes | Reference until round-trip audit succeeds |
| Document ink | `InkService`, `InkStroke`, `InkAnchor`, `InkStore`, `InkCanvas` | Per-document `paperpro-ink.json` schema 1; raw vectors are authoritative | Native vector stroke rows/blobs with explicit coordinate space and anchor | Later importer validates every point and anchor, copies into one SQLite transaction, and records legacy hash | Yes | Read-only recovery source after visual/anchor comparison |
| EPUB ink anchoring | Normalized viewport points plus strict layout signature and top XPointer | `paperpro-ink.json` | Prefer semantic text/sticky-note anchors; retain a compatibility layout-anchor type | Import as unresolved or compatibility ink when layout differs; never silently relocate | Yes; some records may remain unresolved | Compatibility renderer or KOReader fallback |
| PDF ink anchoring | Page-native coordinates projected with ReaderView transforms | `paperpro-ink.json` | Fixed-page native coordinate anchor | Deferred with PDF; preserve payload unchanged until support exists | Yes, later | KOReader PDF ink fallback |
| Pen/eraser/undo | Phase 3 InkService; RC5 adds page-locked Write Mode and grouped continuous erase | In-memory operation history; persisted result in InkStore | `InputBackend`, `InteractionController`, vector model, bounded command history | Reimplement native from raw evdev. One physical erase contact is one undo command. Preserve every accepted sample | Existing data conversion is later; benchmark data is not persisted | RC5 remains behavioral reference until device parity |
| Palm rejection | RC5 strict/automatic Write Mode policy in open PR #6 | Transient interaction state | `InteractionController` with separate Marker/touch streams | Native Write mode consumes all page-area touch while controls remain intentional; qualify on hardware | None | Reference policy only |
| Live-ink refresh | RC5 adaptive one-outstanding A2 updates and idle cleanup in open PR #6 | Transient rendering state | `RefreshScheduler`, dirty-region union, reusable surface | Implement below any document/UI event queue; test deterministic scheduling and validate on both display backends | None | Reference metrics and failure history |
| Handwritten question capture | `InkQuestionSession`, `Rasterizer`, `InkQuestionCodec` | Raw local vectors in queued/conversation records; PNG is temporary derived data | Bounded note-local capture plus just-in-time rasterizer | Reuse contract only after native ink and secure persistence; keep vectors local and delete transport raster immediately | Yes for queued/saved records if imported | KOReader remains functional fallback |
| Typed AI request | `ContextResolver`, `AIRequest`, Quick Ask | Durable request in OfflineQueue; selected context derives from document | Provider-neutral `AIClient` and bounded `ReadingContext` | Reimplement schema behind private backend; preserve stable request IDs and local anchors while stripping anchors from transport | Yes, only through an explicit queue migration | Fallback until offline/retry/security parity |
| Secure AI transport | `AIProvider` and subprocess `HTTPTransport` | Device has revocable token; backend owns provider key | HTTPS client behind `AIClient`; secrets supplied at runtime | Keep provider-neutral device protocol. Never place provider key on device. Validate TLS and response bounds | Settings migration optional and must not expose token | Existing backend may be reused if protocol remains compatible |
| Authenticated backend | `backend/` Node service and OpenAI adapter | Server environment and provider adapter | Existing versioned HTTP contract or compatible private service | Treat backend as an external service, not a Marker-path dependency; pin protocol and retain `store:false` | Server data migration depends on deployment; none in Phase 1 | Can remain the backend implementation |
| Offline requests | `OfflineQueue`, `paperpro-ai-queue.json` schema 1 | OfflineQueue atomic JSON primary/`.old` | Native SQLite request state machine with single-flight worker | Import only while native/KOReader workers are both stopped; preserve request ID, state, attempts, retry time, and payload version | Yes, high-risk and later | Source queue disabled only after reconciliation; never dual-send |
| Saved answers/conversations | `ResponseStore` schema 2, `ConversationService`, AI History/Full Study | `paperpro-ai-responses.json` primary/`.old` | Native SQLite conversations, turns, anchors, local vectors, and status | Copy idempotently; keep legacy IDs and source hashes; validate turn counts and bounds | Yes | Read-only recovery/export source after parity |
| AI passage markers | `ConversationMarker` over visible source anchor | Derived from ResponseStore | Scene marker derived from resolved conversation anchor | Recompute on layout; no stored screen geometry | None beyond conversation import | Reference only |
| Quick Ask and study surfaces | Product overlays and hubs | Derived from source stores | Original retained-mode reading UI, compact overlays, explicit full-study destination | Redesign without copying stock or KOReader assets; maintain reading visibility and e-ink rules | None | Reference/functional fallback |
| Product settings | KOReader settings (`paperpro_*`) | KOReader global settings | Native settings table with typed defaults and schema version | Import a reviewed allowlist only; never import secrets into logs or package | Yes, optional | Independent settings remain for KOReader fallback |
| Diagnostics | RC5 privacy-safe JSON-lines log and report | KOReader product diagnostics file | Native `LatencyRecorder` aggregate report | Start a separate native schema; do not merge logs or retain coordinate/content fields | No | Separate diagnostic systems |
| Packaging/launch | KOReader `remarkable-aarch64` AppLoad/QTFB package | Existing installed KOReader application | Native takeover and QTFB launchers with explicit backend identity | Install side-by-side; use distinct paths/manifests; never overwrite RC5 package or prerequisites | None | KOReader package remains rollback/fallback |
| Exit to stock UI | AppLoad/Xovi/QTFB launch lifecycle; RC evidence confirms stock return | Xochitl/systemd owns stock UI | Idempotent restore script plus independent recovery unit | Native takeover must stop temporarily and restore on normal exit, signals, failures, and watchdog action | None | Existing AppLoad path remains recovery option |
| Frontlight, power, suspend, hall sensor | KOReader reMarkable device adapter, with stock Xochitl responsible for platform behavior in the coexistence path | Device OS and stock services | Narrow future platform services with fail-safe lifecycle hooks | Defer beyond the benchmark except required wake/restore guards; never replace firmware or stock power policy | Existing user settings are not imported in Phase 1 | Stock UI remains authority until separately qualified |

## Native data authority target

After the hardware gate and before feature migration, the native application
will introduce one SQLite database as its sole durable product-data authority.
It will contain documents/revisions, anchors and resolution attempts,
annotations, sticky notes, vector strokes, vocabulary, AI queue items,
conversations/turns, and a legacy-import ledger. Large derived page tiles and
ephemeral AI transport images do not become database authorities.

The database contract requires:

- explicit schema versions and forward-only, transactional migrations;
- foreign keys enabled and checked;
- WAL or another measured crash-safe journal configuration;
- stable application-generated identifiers;
- bounded text, vector, and queue payloads;
- document fingerprints and explicit revisions;
- no write, checkpoint, migration, or serialization on the Marker hot path;
- deferred writes followed by forced flush on document close and suspend;
- backup/restore and integrity checks before importing user data.

## Legacy import contract

Any later importer must be an explicit user action with a dry-run report. It
must open legacy data read-only, validate schemas and bounds, copy into a single
native transaction, and record `(source_kind, source_path_hash, legacy_key,
payload_hash, imported_id, imported_at)`. Re-running the same import is a
no-op. Changed legacy records are reported as conflicts rather than overwriting
native edits.

Legacy JSON uses a strict, non-executing parser and known schema/size limits.
Vocabulary Builder is opened through SQLite read-only mode with a verified
schema. DocSettings must be exported by a version-pinned, offline KOReader
export tool into a neutral bounded interchange bundle; the native process must
not evaluate a Lua metadata file. The interchange bundle and its checksum are
retained until the import audit succeeds.

Every imported EPUB record keeps the original XPointer/position payload, exact
quote where available, document fingerprint, and an explicit resolution state.
Ambiguous anchors remain unresolved. Every imported vector keeps its original
coordinate-space/version metadata. Unknown future schemas fail closed.

The importer must not:

- modify or delete a legacy file;
- start while either application can mutate the source queue/store;
- send an imported AI request automatically;
- infer that two notes are identical only because their visible text matches;
- convert screen coordinates into a false semantic location;
- place unresolved content at a “near enough” passage.

“Reversible” initially means the original KOReader stores are preserved and
the native import can be deleted without touching them. Export back into
KOReader is a separate, schema-specific feature and must not be promised until
round-trip tests exist.

## Migration gates

Feature migration begins only after the native benchmark passes physical
Paper Pro display, Marker, touch/palm, eraser, suspend/resume, and Xochitl
recovery qualification. Each subsequent feature requires:

1. a named single data authority;
2. an idempotent dry-run importer when conversion is needed;
3. fixtures for valid, malformed, interrupted, repeated, and future schemas;
4. anchor-resolution tests against changed EPUB layout and document revision;
5. a side-by-side behavior and data-count audit;
6. backup and rollback instructions;
7. physical-device validation independent from host/CI results.

No host test or successful package build authorizes conversion of existing
user data.
