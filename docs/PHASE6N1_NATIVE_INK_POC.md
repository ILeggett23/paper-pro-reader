# Phase 6N-1 native ink POC

## Scope

This branch keeps KOReader as the EPUB/document and persistence engine while
moving only raw live Marker presentation to an opt-in native AppLoad overlay.
It does not add tools, colors, layers, favorites, AI/notes changes, or a new
anchor schema.

The AppLoad manifest opts in with `nativeInk: true`, forces fullscreen to keep
native screen coordinates aligned with KOReader's 1620 × 2160 framebuffer, and
sets `KO_NATIVE_INK=1`.

## KOReader responsibilities

`nativebridge.lua` connects to the AppLoad side socket derived from `QTFB_KEY`,
polls it without driving live presentation, validates sequence and bounds, and
passes completed strokes/erase transactions into `InkService`.

`InkService:importNativeStroke()` reuses the existing screen-v1 → EPUB/PDF
anchor conversion and v1 `paperpro-ink.json` store. It writes only on
`STROKE_END`. Native erasure reuses whole-stroke hit testing and one grouped
undo operation. Both paths skip per-point and end-of-gesture UIManager cleanup
requests while the native preview owns the live surface.

## Automatic interaction

- No native-ink Write Mode activation is possible.
- Study menu entries `Write Mode`, `Palm rejection`, and `Ink eraser` are
  removed when `KO_NATIVE_INK=1`.
- Native bridge polling starts automatically on `ReaderReady` and closes with
  the document.
- AppLoad suppresses generic Marker events for the entire opted-in session.
- AppLoad suppresses touch only during raw Marker/rear proximity; finger
  gestures resume outside proximity.

Legacy Write Mode remains compiled and testable for non-native builds and
non-Paper-Pro devices; it is never attached or exposed by the POC manifest.

## Engine-boundary rationale

The new bridge and policy live under `frontend/apps/paperpro/`. No document
provider, pagination, UIManager, framebuffer, QTFB FFI, or generic device-input
file is modified. The existing InkService gets only generic completed-stroke
and grouped-erase entry points. This keeps the POC above protected engine code.

## Known POC limitations

- The native overlay can erase current-session native strokes immediately.
  Erasing strokes loaded from a prior session becomes visibly authoritative
  only after KOReader redraw; that handoff is a later POC refinement if the
  latency experiment passes.
- The overlay uses the in-process Qt Quick e-paper scene graph but does not
  guess an undocumented `ScreenModeItem` QML spelling. Target build and physical
  measurement must determine whether the default native damage path is fast
  enough before a screen-mode wrapper is added.
- No frame-present acknowledgement exists in this minimal one-way IPC.
- Optical pen-to-visible latency cannot be inferred from update submission and
  must be measured at 240 fps or faster.

## Verification

Focused specs:

```sh
./kodev test front paperpro_nativebridge_spec.lua
./kodev test front paperpro_inkservice_spec.lua
./kodev test front paperproreader_spec.lua
```

Then run `./kodev test front`. Package and physical gates remain separate.
