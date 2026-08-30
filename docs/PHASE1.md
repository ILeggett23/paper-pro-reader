# Phase 1 — Selection service, contextual overlay, and offline definitions

## Implemented architecture

Phase 1 adds the first product-owned vertical slice while retaining ReaderUI as
the functional reader composition system.

```text
ReaderUI
  -> PaperProReader composition module
     -> SelectionService
     -> ReaderOverlay
        -> ContextualActions
        -> DefinitionOverlay
     -> DefinitionService
        -> ReaderDictionary:lookupWordResults()
           -> existing sdcv / StarDict data
```

Every new module has an active Phase 1 responsibility:

- `paperproreader.lua` owns the action/overlay lifecycle and delegates existing
  Highlight and Note behavior.
- `selectionservice.lua` creates detached product-facing selection snapshots.
- `definitionservice.lua` normalizes existing dictionary results and states.
- `placement.lua` performs pure resolution-aware placement calculations.
- `readeroverlay.lua` hosts normal KOReader widgets, replacement, dismissal,
  coverage, and refresh-region reporting.
- `contextualactions.lua` presents Highlight, Define, Note, and a visibly
  disabled Ask AI action.
- `definitionoverlay.lua` presents static loading, success, no-result, and
  error states with deliberate internal scrolling for long definitions.

No AI, handwriting, vocabulary schema, Notes Hub, or custom refresh engine was
added.

## Selection flow

```text
ReaderHighlight selection
  -> generic ShowSelectionActions event with a copied selection table
  -> PaperProReader
  -> SelectionService
  -> SelectionSnapshot
```

For CREngine-backed documents, SelectionService retains selected text, XPointer
start/end values, screen boxes, nearby word context when available, chapter,
title, and author metadata. Its DocumentAnchor is:

```text
kind = "xpointer"
document_id
start
finish
```

For fixed-layout/PDF selections it retains page, copied positions, native/page
boxes, and ReaderView-transformed screen boxes. Its anchor is:

```text
kind = "fixed_page"
document_id
page
pos0
pos1
page_boxes
```

PDF capabilities explicitly report that sentence and paragraph semantics are
unavailable. SelectionSnapshot copies nested tables and boxes, so later overlay
work does not depend on mutable ReaderHighlight selection data or retain a
document object.

If selected text is unavailable (for example, an OCR path that has not produced
text), PaperProReader returns `false` and ReaderHighlight executes its unchanged
legacy fallback.

## Overlay flow

```text
SelectionSnapshot
  -> ContextualActions widget factory
  -> ReaderOverlay
  -> normal ButtonDialog / UIManager stack over the active document
```

ReaderOverlay computes the combined selection bounds and evaluates below,
above, right, and left placement in that order when each candidate fits. If no
candidate fits, it selects the candidate with the greatest proportional space;
all coordinates are clamped to the viewport. With no boxes it centers the
overlay. The same calculation is tested at small, desktop, and 1620 x 2160
viewports.

ReaderOverlay supports `open`, `update`, `dismiss`, `isOpen`,
`getCoverageBounds`, and `getRefreshRegion`. Replacing the action panel with a
loading or result panel does not reopen the book or alter reader location.
Explicit Close and ButtonDialog's safe outside-tap dismissal both clear the
selection and return to the document.

## Definition flow

```text
Define
  -> static loading DefinitionOverlay
  -> DefinitionService
  -> ReaderDictionary:lookupWordResults()
  -> cleanSelection + existing dictionary filtering + startSdcv
  -> existing local StarDict files
  -> normalized definition model
  -> updated DefinitionOverlay
```

DefinitionService passes a selected word or the complete selected phrase to the
existing dictionary behavior. It never chooses an arbitrary word from a
multi-word selection. The normalized model contains query/display word,
definition entries, dictionary name, status, and the copied selection anchor.
No pronunciation field is invented when the dictionary result does not expose
one.

The adapter emits the existing `WordLookedUp` event and updates lookup history
before reading local results, preserving Vocabulary Builder compatibility. It
does not open DictQuickLookup, call an online dictionary, or create another
dictionary configuration.

## Highlight and Note preservation

- Highlight delegates to `ReaderHighlight:showHighlightPrompt()`, the same
  operation used by KOReader's existing Highlight selection button.
- Note delegates to `ReaderHighlight:addNote()`, which continues through
  ReaderAnnotation/ReaderBookmark and DocSettings.
- No product annotation database or duplicate note/highlight record exists.

## Engine seams touched

Only three B-class KOReader files are modified:

1. `frontend/apps/reader/readerui.lua` registers PaperProReader after the
   existing dictionary module.
2. `frontend/apps/reader/modules/readerhighlight.lua` emits a generic copied
   selection event before unchanged legacy behavior.
3. `frontend/apps/reader/modules/readerdictionary.lua` exposes a presentation-
   neutral local result callback and factors shared lookup event/history and
   per-document dictionary filtering.

No ReaderView, ReaderAnnotation, ReaderBookmark, document provider, base
submodule, UIManager, input, framebuffer, or QTFB file is changed.

## Refresh behavior

ReaderOverlay hosts ButtonDialog, whose existing `onShow` dirties only the
MovableContainer bounds with a `ui` refresh and whose close path restores the
same bounded region with `flashui`. Long definitions use ScrollTextWidget,
which dirties its own region while scrolling. Product code never calls a
framebuffer method, chooses a waveform, or requests a full-screen animation.

There are no fades, slides, opacity transitions, or animated loading elements.

## Verification

Focused automated coverage includes:

- immutable EPUB selection normalization and XPointer anchors;
- fixed-layout page/coordinate anchors and screen transforms;
- explicit missing capabilities;
- top, bottom, left, right, clamped, small, Paper Pro, and no-anchor placement;
- definition success, no result, multiple results, failure, and phrase input;
- contextual action presence and disabled Ask AI;
- Highlight and Note delegation;
- definition overlay replacement and reading-location preservation;
- generic dictionary result callbacks and `WordLookedUp` compatibility;
- existing ReaderHighlight EPUB/PDF regression helpers.

The completion report records exact local, CI, and manual results after the
branch verification run.

## Known limitations

- No physical Paper Pro was available; touch/Marker behavior, Gallery 3
  refresh, ghosting, and latency remain unverified.
- The macOS Retina window cannot visibly fit a 1620 x 2160 logical viewport;
  exact-size initialization can be checked headlessly while visual checks use a
  smaller portrait viewport.
- Scanned PDFs without extracted/OCR text use the existing legacy fallback.
- Phrase lookup is passed through as-is and depends on available StarDict data.
- Definition HTML is normalized by ReaderDictionary's existing tidy-markup
  path; Phase 1 does not add rich HTML rendering to the compact overlay.
- Ask AI is intentionally disabled and contains no network or provider code.
