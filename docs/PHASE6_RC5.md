# Phase 6 RC5 — exclusive Write Mode

## Physical finding

RC4 remained unacceptable on Paper Pro OS 3.27.3.0. Constant refresh activity
made writing slow and clunky; palm/finger contacts turned pages, selected text,
and opened highlight actions; and erasing was not continuous. Persistence paths
remained valid. The hardware evidence rejects simultaneous normal ReaderUI
interaction and handwriting.

Status: **RC4 BLOCKED — WRITING-MODE, PALM, REFRESH, AND ERASER FAILURES**.

Dictionary remains inconclusive because no local StarDict dictionary is
installed and verified.

## Minimal RC5 architecture

- Explicit Read Mode and page-locked Write Mode.
- Strict palm policy by default on Paper Pro: every page-area finger gesture is
  consumed before ReaderUI.
- Automatic option: suppress during Marker contact and for a configurable
  300/500/900 ms guard after lift. No unverified hover claim.
- Persistent direct toolbar: Ink status, Undo, Eraser, Navigate, and Done;
  controls accept finger or Marker and do not leak to ReaderUI.
- Navigate deliberately forwards reading gestures; Done removes the toolbar and
  restores unchanged RC2 Read Mode.
- Every Marker point is retained immediately; one bounded A2 presentation may
  be outstanding, with regions coalesced and cadence adapted to measured UI
  presentation time.
- Pen lift performs no quality refresh or JSON write.
- One 500 ms writing-idle task performs one unioned UI cleanup and one atomic
  schema-1 persistence save; page/location/close/exit/suspend force a flush.
- Visible projected strokes are cached per location and invalidated only for
  location, dimension, or visible ink changes.
- Eraser movement continuously removes newly hit strokes and groups all records
  into one Undo operation and one idle persistence save.
- Diagnostics expose counters/timings only, never coordinates or content.

No A-class or B-class changes. Marker mapping, pressure, anchors, stored schema,
ReaderUI, device input, QTFB manifests, framebuffer, notes, and AI remain
unchanged.

## First physical retest

1. Enable Write Mode and rest a palm before writing.
2. Confirm no page turn, selection, or highlight.
3. Write `testing palm rejection` at normal speed.
4. Confirm low-latency live ink without per-letter quality flashing.
5. Confirm a one-finger swipe is blocked.
6. Use Navigate deliberately, turn a page, return, and resume Write.
7. Undo once and erase continuously across several strokes.
8. Confirm menus/modals remain clean.
9. Exit/relaunch and verify retained/deleted state.
10. Tap Done and verify normal Read Mode page turns and selection.

RC5 remains **NOT TESTED** until the user returns physical evidence.
