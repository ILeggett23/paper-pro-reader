# Implementation roadmap

Each phase must preserve the engine boundaries and keep EPUB/PDF, offline
reading, annotations, navigation, and refresh scheduling operational.

## Phase 1 — Selection and overlay vertical slice

Create the Paper Pro composition seam, normalized SelectionService, reusable
ReaderOverlay host, and a contextual action surface. Implement one complete
offline definition path using ReaderDictionary/StarDict while retaining
Highlight and Note actions. Ask AI is represented only as a disabled future
capability. No handwriting or network AI is included.

Implementation status: complete and merged into `main` by pull request #1.

## Phase 2 — Vocabulary and contextual notes

Adapt Vocabulary Builder and ReaderAnnotation to retain definitions, source
anchors, context, and review state; add inline note markers and Notes Hub
navigation without introducing duplicate storage authorities.

Implementation status: complete and merged into `main` by pull request #2.

## Phase 3 — Marker ink foundation

Verify Paper Pro evdev capabilities, capture and persist raw strokes, add
bounded low-latency ink rendering, and derive raster artifacts. Pressure remains
optional until hardware evidence proves it.

Implementation status: complete and merged into `main` by pull request #3.

## Phase 4 — Provider-neutral AI and offline queue

Implement ContextResolver, secure-backend AIProvider, queued offline requests,
saved-response reading, and the Quick Ask overlay. No permanent provider secret
is stored on the device.

Implementation status: complete and merged into `main` by pull request #4.

## Phase 5 — Book Writes Back and study surfaces

Add handwritten-question recognition, text or handwriting-styled responses,
expanded conversation/full-study states, and a complete library/study visual
system using complete-line or completed-response e-ink updates.

Implementation status: complete and merged into `main` by pull request #5.

## Phase 6 — Release candidate and physical qualification

Produce an identified Paper Pro aarch64 RC, persistent paid-request
idempotency, safe diagnostics, installation/rollback guidance, and a structured
user-driven hardware qualification loop.

Stage A status: complete on `phase-6-paperpro-qualification`. RC1 installed and
rendered on OS 3.27.3.0 but was blocked by a product-overlay touch-routing
failure. RC2 physically fixed touch and validated core reading, notes, and ink
persistence; live ink remained invisible until pen lift. RC3 proved live
presentation but failed at normal speed and contaminated higher UI layers. RC4
adds bounded A2 coalescing and reader-surface-only painting and remains pending
physical retest. Phase 6 stays open until that evidence is reviewed.

The next phase should focus only on physical Paper Pro qualification and
product polish: real Marker/refresh/latency evidence, shared backend
idempotency if deployed at scale, and usability refinement. It should not add
web search, tools, or a general chatbot.
