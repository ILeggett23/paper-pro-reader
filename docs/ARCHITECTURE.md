# Architecture

## Baseline and intent

This document describes KOReader `v2026.07.1` at commit
`9192014d8bd82a91dc1012473be0f238dedfdb54`. Paper Pro Reader treats KOReader
as the engine and places product behavior above the existing document,
rendering, input, persistence, and e-ink infrastructure.

The governing product rule is: reading remains visible whenever reasonably
possible. Definitions, notes, vocabulary actions, and quick AI interactions
belong in contextual overlays instead of unrelated full-screen flows.

## Boot and document flow

The verified high-level path is:

```text
reader.lua
  -> FileManager or ReaderUI:showReader()
  -> DocumentRegistry:openDocument()
  -> CREngine, MuPDF/K2pdfopt, or another registered provider
  -> ReaderUI modules
  -> ReaderView:paintTo()
  -> UIManager dirty/refresh queues
  -> Screen / BlitBuffer / framebuffer implementation
  -> QTFB bridge on the Paper Pro launch path
  -> Gallery 3 display
```

`reader.lua` initializes the device and UIManager, then opens either a supplied
document through `ReaderUI` or the `FileManager`. `ReaderUI:showReader()` is the
safe document-opening entry point. It resolves a provider through
`DocumentRegistry`, opens the document, creates the reader, and shows it through
UIManager.

`DocumentRegistry` registers `CreDocument`, `PdfDocument`, DjVu, image, and text
providers. It consults DocSettings for per-document provider choices and keeps
reference-counted document instances. FileManager delegates actual reading to
ReaderUI rather than owning rendering.

`ReaderUI:init()` composes the reader from modules. Relevant modules include
ReaderView, ReaderHighlight, ReaderAnnotation, ReaderBookmark,
ReaderDictionary, navigation/paging or rolling modules, search, TOC, settings,
and plugins. ReaderView owns the visible document surface and paints the
document, temporary/saved highlights, note markers, footer, and registered view
modules.

UIManager does not render documents itself. It tracks dirty widgets and refresh
requests, combines intersecting refresh regions, promotes partial refreshes
according to policy, calls widget `paintTo()` methods, and finally invokes the
selected Screen refresh method. Product overlays must use these queues and
bounded refresh regions rather than writing directly to the framebuffer.

## Document providers

### Reflowable documents

`frontend/document/credocument.lua` adapts CREngine. For text selection it can
return selected text, start/end XPointers, and screen-space boxes. It can map
XPointers to pages and screen positions, retrieve text between XPointers, and
extend an XPointer range to a sentence segment. These anchors remain stable
across ordinary navigation but must still be treated as document-version
specific.

### Fixed-layout documents

`frontend/document/pdfdocument.lua` delegates text, word, page-box,
coordinate-transform, OCR, zoom, and reflow work to the K2pdfopt/MuPDF adapter
in `koptinterface`. Selection data is page based and includes position records
and screen/page boxes. Native sentence or paragraph boundaries are not as rich
or reliable as CREngine's DOM-aware operations; ContextResolver must degrade to
nearby words or page text instead of inventing semantic boundaries.

## Selection, dictionary, and annotations

ReaderHighlight receives hold/hold-pan/hold-release gestures. It converts the
gesture's screen coordinate through ReaderView, calls the current document
provider, and stores a selection table containing `text`, `pos0`, `pos1`, and
provider-dependent `sboxes`/`pboxes`. Saved annotations add chapter, timestamp,
drawer/color, note, and page information.

For CREngine, `pos0` and `pos1` are XPointers. For PDF/fixed-layout documents,
they include the page and page coordinates. ReaderView exposes
`screenToPageTransform()` and `pageToScreenTransform()` and tracks visible
highlight rectangles, which are the correct basis for contextual overlay
placement.

ReaderDictionary uses local StarDict data through `sdcv`. A lookup emits
`WordLookedUp(word, book_title)` before result retrieval. Vocabulary Builder
listens for this event and records the word, title, discovery/review times,
surrounding context, highlighted selection, review count, and streak in
`vocabulary_builder.sqlite3`. Phase 2 adds a separate post-result
`DefinitionResolved` event: it enriches that same authoritative row with the
normalized local definition results, source attribution, book metadata, and a
safe document anchor without altering its review schedule.

Baseline gaps and their current status:

- `WordLookedUp` still intentionally does not include the chosen definition or
  final result set; `DefinitionResolved` is the compatible post-result seam.
- Phase 2 extends Vocabulary Builder to retain definitions, chapter, document
  metadata, and EPUB/PDF anchors. Older rows remain valid with nullable fields.
- PDF sentence/paragraph inference is less capable than EPUB inference.
- The remaining provider gap does not justify replacing dictionary,
  annotation, or vocabulary storage.

ReaderAnnotation loads and saves the `annotations` collection in the
document's DocSettings sidecar. Reflowable annotations use XPointer positions;
fixed-layout annotations use pages and coordinate ranges. ReaderBookmark owns
note mutation, PDF write-through, annotation event counts, and passage
navigation. Phase 2's AnnotationService resolves stable references against this
collection and the Notes Hub reads it live; there is no second annotation
authority.

## Plugins and statistics

PluginLoader discovers `.koplugin` packages and ReaderUI registers their
instances as reader modules. Plugins receive ReaderUI events such as
`ReaderReady`, `PageUpdate`, `PosUpdate`, `WordLookedUp`, and document closing.
Vocabulary Builder and Statistics demonstrate reusable event-driven storage.
They are adapters/integration points, not product composition roots.

## Touch and Marker input

On Paper Pro, `frontend/device/remarkable/device.lua` opens the buttons, hall
sensor, Marker, and touch evdev nodes and scales their coordinates into the
1620 x 2160 display coordinate space. Input normalizes kernel events into
per-contact slots. At each synchronization frame it routes stylus slots through
`Input:registerStylusCallback()` before passing remaining contacts to gesture
detection. Generated Gesture events reach UIManager and then InputContainer
touch zones and ReaderUI modules.

The stable callback payload carries slot/contact identity, x/y coordinates,
tool, event time, and optional pressure. Phase 3 retains `ABS_PRESSURE` in the
generic slot because QTFB already emits it, but physical Paper Pro pressure
behavior remains unverified. Tilt, distance, explicit proximity, and button
state are not exposed in the callback. Ink Mode registers its callback only
while active and returns `true` for stylus slots, removing them before ordinary
gesture recognition while leaving touch unchanged.

## Product-owned layer

Phases 1 through 5 establish the product-owned modules under
`frontend/apps/paperpro/`:

```text
frontend/apps/paperpro/
  paperproreader.lua         ReaderUI-attached product composition root
  services/
    selectionservice.lua     immutable EPUB/PDF selection snapshots
    definitionservice.lua    normalized local dictionary result models
    vocabularyservice.lua    rich Vocabulary Builder event adapter/navigation
    anchorcodec.lua          safe EPUB/PDF anchor column serialization
    annotationservice.lua    stable annotation references and authoritative operations
    contextresolver.lua      bounded provider-neutral EPUB/PDF reading context
    airequest.lua            typed stable-ID request contract
    aisettings.lua           backend settings and remote-HTTPS policy
    aiprovider.lua           provider-neutral authenticated backend client
    httptransport.lua        subprocess LuaSocket/LuaSec completion transport
    atomicjsonstore.lua      versioned atomic JSON recovery primitive
    offlinequeue.lua         durable retry/idempotency state machine
    responsestore.lua        local completed exchange authority
    anchornavigator.lua      validated ReaderLink/rolling/paging adapter
    conversationservice.lua  bounded local canonical conversation history
  overlays/
    placement.lua            resolution-aware pure placement policy
    readeroverlay.lua        reusable bounded widget host/lifecycle
    contextualactions.lua    Highlight/Define/Note/Ask AI surface
    definitionoverlay.lua    definition, provenance, and persistence status panel
    noteoverlay.lua          contextual text note editor
    quickaskoverlay.lua      typed compose/queued/sending/result states
    handwrittenresponserenderer.lua existing-font handwriting presentation
    conversationmarker.lua  subtle visible-anchor AI discussion indicator
  hubs/
    vocabularyhub.lua        searchable review/detail/passage surface
    noteshub.lua             current-book note review/edit/delete/navigation
    aihistory.lua            current-book queued/completed AI review/navigation
    conversationhub.lua      expanded conversation and Full Study surfaces
  ink/
    inkstroke.lua            bounded authoritative raw stroke model
    inkanchor.lua            strict EPUB layout and PDF page coordinates
    inkrenderer.lua          vector drawing, bounds, and hit testing
    inkcanvas.lua            transparent active/persisted ink window
    inkstore.lua             atomic per-document RapidJSON sidecar
    inkservice.lua           Ink Mode, input lifecycle, undo/erase/reload
    rasterizer.lua           bounded derived handwriting bitmap
    inkquestioncodec.lua     just-in-time bounded PNG transport artifact
    inkquestionsession.lua   temporary Marker question InkService composition
backend/                     authenticated provider-isolation service
```

ReaderUI remains the functional reader. It registers PaperProReader as one
module after ReaderDictionary; PaperProReader composes product behavior without
taking ownership of the document, selection rendering, annotations, or
dictionary engine. PaperProReader also registers the Study reader-menu entry
and applies product-owned note-marker, vocabulary, AI, and ink settings.
Phases 4 and 5 consume existing network events and navigation APIs without taking
ownership of network management, document navigation, or rendering.

## Product contracts

SelectionSnapshot, DocumentAnchor, ReaderOverlay, ReadingContext, InkStroke,
AIProvider, OfflineQueue, InkQuestionSession, and Conversation are implemented contracts. The device request and
client remain provider-neutral; the isolated backend currently supplies one
OpenAI Responses adapter.

### DocumentAnchor

```text
kind = "xpointer" | "fixed_page"
document_id
start / finish XPointers                    # xpointer
page, pos0, pos1, page_boxes                # fixed_page
```

### SelectionSnapshot

```text
text, selected_word, before_context, after_context
screen_boxes, page_boxes, anchor
book_title, author, chapter
```

SelectionService normalizes ReaderHighlight/provider data without taking
ownership of highlighting or selection rendering.

### ReadingContext

```text
schema_version
book = { document_id, title?, author? }
location = { chapter?, anchor }
selection = { text, selected_word? }
context = { before?, after?, sentence?, paragraph? }
context_mode, truncation
capabilities = { sentence, paragraph, semantic_context, precise_anchor, fixed_layout }
```

Missing provider capabilities are explicit; callers must not confuse inferred
PDF context with CREngine DOM context.

### ReaderOverlay

```text
open(model, anchor_boxes)
update(model)
dismiss()
getCoverageBounds()
getRefreshRegion()
```

All overlays preserve the reading position, choose above/below/side placement
from available space, are touch/Marker friendly, and request only the necessary
UIManager repaint region. Quick Ask is the implemented compact AI state;
expanded conversation and full study remain explicit later transitions.

### InkStroke

```text
id, tool, started_at, ended_at, coordinate_space, anchor?
points = [{ x, y, timestamp, pressure? }]
```

This contract is implemented by Phase 3. Raw strokes are authoritative and
persisted per document. A bounded raster image is a derived local artifact for
future recognition or AI input; Phase 3 sends it nowhere.

### AIProvider and OfflineQueue

```text
AIProvider:isAvailable()
AIProvider:submit(request, callbacks) -> request_id
AIProvider:cancel(request_id)
AIProvider:testConnection(callback)

OfflineQueue:enqueue(request)
OfflineQueue:processNext(provider, response_store)
OfflineQueue:processBatch(provider, response_store)
OfflineQueue:retry(id)
OfflineQueue:cancel(id)
OfflineQueue:listForDocument(document_id)
```

Requests contain a provider-neutral ReadingContext plus typed question input.
The device talks to a secure backend; permanent provider secrets never reside
in the application. Saved responses remain readable offline.

Phase 4 implements this contract with stable UUIDs, a subprocess-backed
LuaSocket/LuaSec transport, atomic global queue/response JSON stores, bounded
retry, and network-event replay. Before transmission AIProvider removes local
document identity and the navigation anchor. Backend authentication uses a
revocable device token; `OPENAI_API_KEY` exists only in the backend environment.

Phase 5 keeps request schema v1 text compatibility and adds schema v2 text or
ink questions. Raw question vectors stay local; AIProvider regenerates a
bounded PNG immediately before authenticated transport. ResponseStore schema 2
migrates Phase 4 exchanges into single-turn conversations and owns bounded
follow-ups, recognition text, anchors, and optional retained question ink.
The backend performs one multimodal response with qualitative recognition and
continues using `store: false` with no tools or web search.
