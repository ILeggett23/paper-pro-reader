# Implementation roadmap

Each phase must preserve the engine boundaries and keep EPUB/PDF, offline
reading, annotations, navigation, and refresh scheduling operational.

## Phase 1 — Selection and overlay vertical slice

Create the Paper Pro composition seam, normalized SelectionService, reusable
ReaderOverlay host, and a contextual action surface. Implement one complete
offline definition path using ReaderDictionary/StarDict while retaining
Highlight and Note actions. Ask AI is represented only as a disabled future
capability. No handwriting or network AI is included.

Implementation status: complete on `phase-1-selection-overlay`, pending review
and merge into `main`.

## Phase 2 — Vocabulary and contextual notes

Adapt Vocabulary Builder and ReaderAnnotation to retain definitions, source
anchors, context, and review state; add inline note markers and Notes Hub
navigation without introducing duplicate storage authorities.

## Phase 3 — Marker ink foundation

Verify Paper Pro evdev capabilities, capture and persist raw strokes, add
bounded low-latency ink rendering, and derive raster artifacts. Pressure remains
optional until hardware evidence proves it.

## Phase 4 — Provider-neutral AI and offline queue

Implement ContextResolver, secure-backend AIProvider, queued offline requests,
saved-response reading, and the Quick Ask overlay. No permanent provider secret
is stored on the device.

## Phase 5 — Book Writes Back and study surfaces

Add handwritten-question recognition, text or handwriting-styled responses,
expanded conversation/full-study states, and intentional Notes/Vocabulary
review pages using complete-line or completed-response e-ink updates.

The only recommended next implementation phase after this foundation is
Phase 1.
