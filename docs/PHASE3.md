# Phase 3 — Marker ink foundation

## Marker input path

The verified source path is:

```text
Linux evdev or QTFB user-input message
  -> reMarkable event adjustment/scaling
  -> Input Wacom/slot normalization
  -> Input:routeStylusEvents()
  -> registered stylus callback
  -> InkService
```

Paper Pro opens separate Marker and touch nodes. The device adapter scales
Marker `ABS_X`/`ABS_Y` into the 1620 x 2160 screen coordinate space. With QTFB,
`input_qtfb.lua` translates pen press/update/release messages into pen-tool,
touch, x/y, pressure, and synchronization events. Input assigns the dedicated
pen slot and calls the stylus callback before GestureDetector.

Callback fields verified in source:

- `slot`: normalized slot number;
- `id`: active contact when non-negative, up/hover when `-1`;
- `x`, `y`: adjusted screen coordinates;
- `tool`: finger, pen, eraser, or highlighter numeric identity;
- `timev`: normalized fixed-point event time;
- `pressure`: optional raw value when `ABS_PRESSURE`/`ABS_MT_PRESSURE` exists.

Not exposed as callback fields: tilt, distance, explicit proximity, or button
state. A tool/button path may change the normalized tool, but the raw button
state is not forwarded.

## Pressure

Pressure is **available in source but hardware-unverified**. QTFB explicitly
emits `ABS_PRESSURE`, and the generic Input path previously dropped it. Phase 3
adds a narrow B-class change that retains the value on the slot and forwards it
unchanged to the existing callback.

Pressure is optional in every stroke and persistence validator. The renderer
uses a fixed width. No range, sensitivity, latency, or physical support claim is
made without Paper Pro event captures.

## Ink architecture

All product behavior lives under `frontend/apps/paperpro/ink/`:

- `inkstroke.lua`: ordered, bounded, safely validated raw samples.
- `inkanchor.lua`: coordinate conversion, visibility, and strict anchoring.
- `inkrenderer.lua`: fixed-width round lines, dirty bounds, and hit testing.
- `inkcanvas.lua`: transparent reader overlay window for active and stored ink.
- `inkstore.lua`: versioned, atomic per-document RapidJSON persistence.
- `inkservice.lua`: Ink Mode, callback lifecycle, page index, history, and
  persistence coordination.
- `rasterizer.lua`: cropped derived grayscale image generation.

PaperProReader creates these objects per open document and exposes their
controls through Study. It does not take ownership of the document renderer,
framebuffer, QTFB, or normal gesture system.

## Ink Mode

Study contains:

- Ink Mode on/off;
- Ink eraser;
- Undo and Redo;
- Delete last ink stroke;
- Clear ink at the current reading location with confirmation.

Ink Mode is always off on a newly opened reader. Activating it registers one
stylus callback and shows a small `INK`/`ERASE` state badge. Stylus events are
consumed before gesture detection. The transparent InkCanvas defines the
drawing surface and excludes the badge. Finger input is not registered or
intercepted and continues to operate reader controls.

Opening a Phase 1/2 selection or either Study Hub exits Ink Mode. Document
close finalizes an active stroke, persists dirty state, unregisters only the
callback owned by InkService, and detaches the canvas.

## InkStroke

The authoritative schema is:

```text
id
tool
started_at
ended_at
coordinate_space
anchor
points = [{ x, y, timestamp, pressure? }]
```

Capture preserves point order and stroke boundaries. It rejects NaN/infinite
values, clamps screen samples to the canvas, removes consecutive duplicate
coordinates, and limits a stroke to 10,000 points. A document is limited to
5,000 strokes and the undo history to 50 operations. Raw point sequences are
not simplified or rasterized during persistence.

## Coordinate spaces

The system distinguishes:

1. Device coordinates — native Marker values before the reMarkable adapter.
2. Screen coordinates — callback x/y after device adjustment.
3. Canvas coordinates — the full reader window excluding only the status badge.
4. Stored document coordinates:
   - `pdf-page-v1`: native page x/y;
   - `epub-layout-v1`: normalized viewport x/y plus strict layout anchor.

Active strokes use screen coordinates for immediate display. Pen-up converts
every raw sample through the applicable public ReaderView transform before
storage. Conversion never mixes points from two PDF pages.

## Rendering

InkCanvas is a transparent window above ReaderUI. It is not a framebuffer or
ReaderView replacement.

For each active segment:

```text
new point
  -> segment-only canvas paint
  -> UIManager `fast`
  -> small padded segment rectangle
```

On pen-up, the stored stroke is projected back to screen space and its bounded
region receives a normal `ui` repaint. Undo/erase restore only the affected
reader region with `partial`, after which the remaining canvas content is
composited normally. The renderer uses fixed-width black circles sampled along
each segment for acceptable round joins.

No full-screen refresh is intentionally requested for a small stroke. Product
code does not select waveforms, call QTFB, or write directly to the screen
buffer.

## EPUB anchoring

EPUB free ink uses a deliberately strict same-layout contract:

- current top XPointer;
- current logical page for diagnostics;
- normalized viewport point coordinates;
- screen size, rotation, view mode, font face/size, line spacing, and margins.

Ink renders only when the current top XPointer and full layout signature match.
Closing and reopening at the saved position restores it. A typography,
orientation, margin, view-mode, or reflow change hides the stroke. It is not
silently moved to a different paragraph. Advanced XPointer-to-margin remapping
is deferred.

## PDF anchoring

PDF samples are converted with `ReaderView:screenToPageTransform()` and stored
as page-native coordinates with a page anchor. Rendering uses
`pageToScreenTransform()`, so existing zoom, rotation, page offset, and scroll
state determine the current screen position. Only strokes for visible pages
enter the drawing loop.

## Persistence

Each document uses `paperpro-ink.json` in KOReader's selected document sidecar
directory. It is separate from ReaderAnnotation and Vocabulary Builder.

Schema version 1 contains:

```text
schema_version
document_id
coordinate_space_version
created_at
updated_at
strokes[]
```

RapidJSON parses content without executing it. Save writes and fsyncs a `.tmp`
file, rotates the prior primary to `.old`, atomically renames the temporary
file, and fsyncs the directory. Load validates the schema, document identity,
stroke limits, every point, coordinate space, and anchor. A malformed primary
falls back to `.old`; an unsupported future schema fails closed instead of
downgrading silently.

InkStore loads only the open document. InkService indexes strokes by PDF page
or EPUB XPointer so the canvas projects only the current location.

## Erase and history

The source-visible eraser tool and manual Ink eraser both perform whole-stroke
hit-tested deletion. Delete-last and clear-current-location use the same
operation system. Add, delete, and clear operations support bounded Undo and
Redo. This history is product-owned and unrelated to KOReader navigation
history.

## Rasterization

Rasterizer takes screen-projected raw strokes, computes their union bounds,
adds fixed padding, creates a grayscale white BlitBuffer, and draws black ink at
the cropped offset. Empty input returns no image. Dimensions and aspect ratio
are deterministic. The buffer can be written to PNG with KOReader's existing
PNG support, but Phase 3 neither stores duplicate rasters nor sends them over a
network.

## KOReader seams touched

Only `frontend/device/input.lua` changes outside the product directory. It
retains optional pressure already present in generic absolute input events and
documents the optional callback field. No Paper Pro labels, layout, persistence,
or workflow policy exists there.

ReaderUI registration from Phase 1 is reused unchanged. ReaderView's public
coordinate transforms and UIManager's existing window/dirty-region APIs are
consumed without modification.

## Verification status

- Automated/unit: InkStroke, coordinates, renderer bounds, store recovery,
  service lifecycle, page scoping, undo/redo/erase/clear, and rasterization.
- Emulator/runtime: mocked stylus callbacks through real EPUB/PDF ReaderUI,
  close/reopen persistence, current-page filtering, and existing reading flows.
- CI: exact results are recorded in the Phase 3 pull request and handoff.
- Physical Paper Pro: **UNVERIFIED — no device available**.

## Known limitations

- No physical latency, pressure range, eraser, edge, ghosting, Gallery 3,
  touch/Marker concurrency, prolonged battery, or QTFB behavior is verified.
- EPUB ink is hidden after any layout-signature change; it is not semantically
  remapped after reflow.
- The pen is fixed-width black only. There are no brushes, colors, partial
  vector erasing, or pressure-sensitive widths.
- Ink is local per-document data with no cloud sync.
- There is no AI, handwriting recognition, OCR, handwriting search, response
  generation, or Book Writes Back behavior.
