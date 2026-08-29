# Engine boundaries

These classifications prevent product work from accumulating in KOReader's
rendering and device core. Classification concerns ownership, not code quality.

## A — Engine / avoid modifying

- `base/`, including MuPDF, CREngine, K2pdfopt, BlitBuffer, framebuffer and
  QTFB bindings, and third-party build definitions
- `frontend/document/` providers and document-location mapping
- `frontend/ui/uimanager.lua` and core refresh scheduling
- pagination, reflow, zoom, and render-buffer internals
- pinned dependency and toolchain definitions

An A-class change requires a demonstrated inability to solve the requirement
above the engine, a written rationale in the change, focused tests, full base
and frontend regressions, and Paper Pro testing when device behavior is
affected. Prefer an upstream contribution over a product-only fork.

## B — Adapter / modify only when necessary

- `reader.lua`, `frontend/apps/reader/readerui.lua`, and ReaderView registration
- ReaderHighlight, ReaderDictionary, ReaderAnnotation, and ReaderBookmark seams
- `frontend/device/input.lua`, `frontend/device/remarkable/`, and
  `platform/remarkable/`
- DocumentRegistry, DocSettings, FileManager, PluginLoader, Vocabulary Builder,
  and Statistics integration

B-class edits must be narrow, generic, and event/interface oriented. Examples
include exposing an already-produced dictionary result or retaining a verified
stylus field. Product labels, layouts, provider choices, and workflow policy do
not belong here.

## C — Product UX / expected customization

- the future Paper Pro Reader composition root
- product-owned overlay views, navigation, action presentation, and Notes Hub
- product settings and assets that do not replace engine assets
- adapters that translate KOReader data into documented product contracts

C-class code may hide legacy KOReader UI from the product experience, but it
must not delete the underlying functionality.

## D — Custom new modules

New selection/context services, overlay host and panels, vocabulary and
annotation adapters, InkService, provider-neutral AI client, OfflineQueue,
Notes Hub, and Book Assistant belong under `frontend/apps/paperpro/`.

## Change review checklist

1. Can the requirement be implemented in D or C?
2. Can an existing event or module interface satisfy it without mutation?
3. If B must change, is the seam generic and independently tested?
4. If A must change, is the technical necessity documented and upstreamable?
5. Are EPUB and PDF anchors, reading-position restoration, offline behavior,
   refresh regions, and legacy KOReader functionality preserved?
6. Are emulator, CI, package, and physical-device results stated separately?
