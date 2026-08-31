# Phase 6 RC3 — live active-stroke presentation

## Physical finding

RC2 fixed finger touch and physically passed launch, Quickstart controls, EPUB
page turns, position persistence, selection, note creation/persistence, Marker
capture, completed ink, undo, deletion, eraser, and ink persistence on Paper
Pro OS 3.27.3.0.

The remaining failure was presentation-only: no line appeared while the Marker
tip remained down, then the complete line appeared immediately on pen lift.

Status: **RC2 BLOCKED — LIVE ACTIVE-STROKE RENDERING FAILURE**.

Dictionary is inconclusive, not failed, because no local StarDict dictionary
has yet been verified.

## Source comparison

The active path stored only the latest pending segment and requested:

```text
UIManager:setDirty(InkCanvas, "fast", bounded_segment_region)
```

The physically working final path requested:

```text
UIManager:setDirty(InkCanvas, "ui", bounded_stroke_region)
```

On the shimmed Paper Pro path, KOReader's reMarkable framebuffer maps `fast` to
DU and `ui` to GL16. RC2 hardware proved that the final UI path is presented by
the installed QTFB/AppLoad stack while the live fast path is not. Input polling
can also return multiple synchronization frames in one batch before UIManager's
next paint; a single `paint_segment` slot could therefore discard earlier
unpainted live segments.

## Minimal RC3 change

- Keep every pending active segment until the next canvas paint.
- Draw all pending segments once, then clear the queue.
- Request bounded non-flashing `ui` refreshes for active segment regions.
- Keep the final-stroke `ui` path unchanged.
- Expose the safe diagnostic identity `ui-batched-segments-v3`.

No A-class or B-class changes. InkService capture, pressure retention,
coordinates, anchoring, persistence, undo/redo, eraser, touch pass-through,
QTFB manifests, UIManager, and framebuffer implementations are unchanged.

## First physical retest

1. Enable Ink Mode.
2. Draw one slow horizontal line and confirm it follows the tip before lift.
3. Draw several letters at normal speed and confirm continuous live ink.
4. Undo once.
5. Erase once.
6. Exit/relaunch and confirm persistence and deletion state.

## Physical result

RC3 FAIL. A slow line followed the tip, but normal-speed writing had HIGH
latency and SEVERE ghosting. Finger page turns regressed, eraser presentation
failed, and ink/residual strokes appeared over the Definition modal and Tools
menu. Undo and persistence remained correct. This evidence rejects repeated
GL16 `ui` presentation during contact and establishes the RC4 refresh and
layer-isolation requirements.
