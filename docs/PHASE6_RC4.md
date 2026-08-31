# Phase 6 RC4 — coalesced A2 live ink and reader-layer isolation

## Physical finding

RC3 on Paper Pro OS 3.27.3.0 made a slow line visible before pen lift, but
normal-speed letters failed with HIGH latency and SEVERE ghosting. Eraser
presentation and finger page turns regressed. Photos showed ink or residual
ink above the Definition modal and Tools menu. Undo and persistence still
passed, so capture/storage semantics remain authoritative and unchanged.

Status: **RC3 BLOCKED — REFRESH, LAYER, AND RESPONSIVENESS FAILURES**.

Dictionary remains inconclusive because no local StarDict dictionary has been
verified.

## Evidence and strategy

RC3 requested one GL16 `ui` refresh for every active segment. UIManager already
supports `a2`; the reMarkable framebuffer maps it to waveform A2, and the
current AppLoad shim translates A2 (`0x04`) to QTFB
`REFRESH_MODE_ANIMATE`. KOReader's ReaderUI defines 30 Hz as its interactive
maximum. RC4 reuses that established ceiling for the explicitly low-latency A2
path instead of inheriting the generic e-ink 2 Hz quality-pan fallback.

## Minimal RC4 change

- Capture and retain every Marker sample immediately.
- Union pending segment regions without requesting a refresh per sample.
- Schedule at most one bounded A2 presentation every 1/30 second.
- Draw all coalesced segments during that paint.
- Cancel pending live presentation at pen lift and keep one final bounded `ui`
  quality cleanup.
- Skip all InkCanvas painting while any menu, dialog, keyboard, definition, AI
  overlay, or other non-reader window is above ReaderUI.
- Resume deferred page ink only after ReaderUI is visible again.
- Extend content-safe diagnostics through `touch_detected`, `reader_forwarded`,
  `reader_handled`/`reader_unhandled`, and `page_action` lifecycle states.

No A-class or B-class changes. InkService capture, coordinates, pressure,
anchoring, persistence, undo/redo, eraser semantics, RC2 touch pass-through,
QTFB manifests, UIManager, framebuffer code, notes, and AI remain unchanged.

## First physical retest

1. Enable Ink Mode and draw one slow line.
2. Write `testing ink` at normal speed.
3. Rate latency and check missing segments/ghosting.
4. Open Tools and another modal; confirm no page ink is painted above either.
5. Undo one stroke and erase one stroke; confirm immediate presentation.
6. Turn a page with a finger and return.
7. Exit/relaunch and confirm persistence/deletion state.

RC4 remains **NOT TESTED** until the user returns physical evidence.
