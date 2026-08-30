# Phase 2 — Automatic vocabulary and contextual notes

## Implemented architecture

Phase 2 adds two offline, reading-first vertical slices without changing a
document engine, rendering path, framebuffer, UIManager, pagination, reflow,
or device-input implementation.

Product-owned modules:

- `services/vocabularyservice.lua` converts successful single-word definition
  results into a detached persistence payload and delegates storage to the
  Vocabulary Builder plugin.
- `services/anchorcodec.lua` safely maps EPUB XPointers and PDF position tables
  to explicit/JSON database columns and rejects malformed stored values.
- `hubs/vocabularyhub.lua` provides newest-first list, search, detail, learning
  state, and current-book passage navigation.
- `services/annotationservice.lua` creates stable annotation references,
  resolves the live authoritative annotation, and delegates create, update,
  delete, and navigation operations to existing reader modules.
- `overlays/noteoverlay.lua` is the bounded text editor used for both new and
  existing notes.
- `hubs/noteshub.lua` presents current-book note list/detail/edit/delete and
  passage navigation.
- `paperproreader.lua` composes the services, overlays, hubs, Study menu, note-
  marker policy, and automatic vocabulary policy.

## Vocabulary flow

```text
SelectionSnapshot
  -> DefinitionService
  -> normalized successful local StarDict result
  -> VocabularyService eligibility check
  -> DefinitionResolved event
  -> existing Vocabulary Builder plugin/database
  -> added/already/error status
  -> DefinitionOverlay
```

Only a genuine single-word selection with at least one usable local definition
is eligible. Phrase, empty, no-result, and error states are not automatically
stored. The product setting `paperpro_auto_add_vocabulary` defaults to true and
does not change KOReader's legacy Vocabulary Builder auto-add preference.

`WordLookedUp` remains unchanged and occurs before dictionary resolution. The
rich path is idempotent: if legacy auto-add already inserted the word,
`enrichDefinition()` updates metadata only. It never changes `review_count`,
`streak_count`, `due_time`, or `review_time`. If no row exists, it creates the
single authoritative row in the same neutral initial review state used by the
existing plugin.

Every normalized definition retains its own dictionary source in
`definitions_json`; `definition` and `dictionary_source` retain the selected
primary result for compact consumers. DefinitionOverlay labels each displayed
definition separately and only shows “Added to Vocabulary” after the database
callback succeeds.

## Database migration

Vocabulary Builder remains the sole vocabulary authority:

```text
vocabulary_builder.sqlite3
schema 20240905 -> 20260830
```

Nullable columns added to the one-row-per-word `vocabulary` table:

```text
definition, dictionary_source, definitions_json
author, chapter, document_id, source_text
anchor_kind, anchor_start, anchor_finish, anchor_page
anchor_pos0_json, anchor_pos1_json, anchor_page_boxes_json
updated_time
```

Review fields and the existing title relationship are unchanged. Explicit
columns store XPointer data. KOReader's RapidJSON module stores PDF positions
and page boxes with non-throwing malformed-input handling; no executable Lua
serialization or `loadstring` is used.

The rich-column migration runs inside `BEGIN IMMEDIATE`, checks existing
columns before each `ALTER TABLE`, commits only after all additions succeed,
and rolls back and logs on failure. This makes interrupted/repeated migration
safe without purging the database. Fresh databases use the same final schema.

Sync upgrades an older incoming database with missing nullable columns before
the existing merge. Non-empty incoming metadata can enrich local metadata;
empty values cannot erase a local definition or anchor. Existing review merge
semantics remain intact.

## Vocabulary Hub

The Study > Vocabulary surface reads through the plugin event adapter rather
than caching a second database. It provides:

- newest-first word list;
- basic word search and explicit loading, empty, and unavailable states;
- primary/all definitions with per-definition source attribution;
- source text and surrounding context;
- book, author, chapter, and discovery date;
- review count and streak;
- Go to passage for a valid anchor in the currently open book.

Navigation first adds the current location to ReaderLink's stack, then uses
ReaderRolling XPointer or ReaderPaging page/position operations. Cross-book
opening is deliberately disabled; the source book remains visible in detail.

## Note flow

```text
SelectionSnapshot
  -> NoteOverlay through ReaderOverlay
  -> AnnotationService
  -> ReaderHighlight:commitNoteForCurrentSelection()
  -> ReaderBookmark:updateAnnotationNote()
  -> ReaderAnnotation collection / DocSettings
  -> existing ReaderView note marker
```

Cancel dismisses the editor and clears the temporary selection without adding
an annotation. Save validates non-empty text, creates one highlight-backed
annotation, writes PDF annotation content when that existing option is active,
emits normal `AnnotationsModified` events, and clears selection state. Editing
resolves the current annotation from stable identity fields before updating it,
so array sorting or insertion cannot redirect the edit.

An `AnnotationReference` contains `document_id`, original `datetime`, page or
XPointer, and copied `pos0`/`pos1`. No permanent identifier or annotation schema
migration was required.

ReaderHighlight emits `ShowAnnotationNote` with a detached annotation,
reference, and visible boxes when a single note-bearing annotation is tapped.
PaperProReader opens the same product NoteOverlay; an unhandled event falls
through to KOReader's legacy note/highlight UI. Plain highlights retain their
legacy behavior.

## Notes Hub flow

```text
ui.annotation.annotations
  -> AnnotationService:listNotes()
  -> Notes Hub
  -> stable reference resolution
  -> ReaderLink back stack + ReaderBookmark navigation
  -> source passage
```

Study > Notes lists only non-empty notes from the current book, newest updated
first. Detail shows the quoted passage, personal note, chapter/page, date, and
navigation status. Edit reopens NoteOverlay over the book. Delete uses the same
ReaderBookmark note mutation and leaves the underlying highlight. Stale or
malformed anchors remain readable but cannot navigate. `AnnotationsModified`
refreshes an open hub without polling.

## Note markers

No ReaderView code changed. PaperProReader defaults the existing note marker to
`sidemark` when the reader had no configured marker, calls the existing marker
position setup, and exposes `paperpro_note_markers` in Study. Rendering,
coordinates, and repaint behavior remain owned by ReaderView.

## Existing KOReader seams touched

- `frontend/apps/reader/modules/readerhighlight.lua`: adds generic
  `commitNoteForCurrentSelection()` and `ShowAnnotationNote`; both expose
  existing operations/data and preserve legacy fallback.
- `frontend/apps/reader/modules/readerbookmark.lua`: adds generic
  `updateAnnotationNote()` so non-legacy presentation can reuse mutation,
  PDF write-through, and annotation events.
- `plugins/vocabbuilder.koplugin/main.lua`: handles presentation-neutral rich
  persistence and query events.
- `plugins/vocabbuilder.koplugin/db.lua`: performs the compatible schema,
  idempotent enrichment, rich queries, and sync-column merge.

PaperProReader's Phase 1 ReaderUI registration and dictionary-result seam are
reused unchanged.

## Refresh behavior

Contextual definition and note editors are normal KOReader widgets hosted by
ReaderOverlay. Its coverage/MovableContainer bounds remain the refresh region;
there are no animations or direct framebuffer/waveform calls. Notes and
Vocabulary are intentional full-screen Menu/TextViewer destinations and use
normal KOReader full-screen refresh policy.

## Engine boundary audit

No A-class file changed. There are no changes under `base/`,
`frontend/document/`, UIManager, ReaderView, paging/reflow/zoom internals,
framebuffer/QTFB, or device input. The four B-class files above contain only
generic persistence/query/event seams; product layout, wording, settings, and
workflow remain under `frontend/apps/paperpro/`.

## Verification and known limitations

Focused specs cover eligibility, provenance, persistence status, idempotent
enrichment, review-state preservation, new/populated/repeated migrations,
older-database sync, EPUB/PDF anchor round trips, malformed anchors,
contextual-note create/cancel/edit/delete, hub content/empty states, and Phase 1
regressions. Exact local and GitHub Actions results are reported in the pull
request and completion handoff.

- No physical Paper Pro was available. Marker touch targets, keyboard
  ergonomics, Gallery 3 ghosting/color refresh, and latency are not verified.
- Vocabulary navigation is current-book only.
- Scanned PDFs still depend on KOReader's existing text/OCR result and PDF
  sentence/paragraph semantics remain weaker than EPUB.
- Anchors may become stale when source files change; the hubs fail closed.
- The quick note editor is text/keyboard only. Marker ink and handwriting begin
  in Phase 3.
