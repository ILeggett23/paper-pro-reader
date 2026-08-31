# Phase 6 hardware feedback loop

Phase 6 remains open through RC5 physical qualification. Every returned finding is classified:

- `INSTALL`
- `CRASH`
- `INPUT`
- `MARKER`
- `REFRESH`
- `LAYOUT`
- `NETWORK`
- `AI`
- `PERSISTENCE`
- `PERFORMANCE`
- `UNKNOWN`

For each failure:

1. Preserve the candidate version, commit, firmware, checksum, reproduction
   steps, photo/video, and diagnostic log.
2. Reproduce with source tests, fixtures, packaged runtime, or the smallest
   safe emulator approximation.
3. Identify the narrowest responsible layer. Start in product code; do not
   change A-class code without physical evidence of an engine blocker.
4. Implement the smallest fix and a focused regression test.
5. Run critical Phase 1–5 regressions and package validation.
6. Produce a uniquely identified RC2/RC3/RC4/RC5 artifact without overwriting prior
   checksums or evidence.
7. Give the user only the finding-specific retest plus launch/exit, EPUB/PDF,
   and persistence smoke checks.
8. Update `PAPER_PRO_QUALIFICATION.md` only with evidence the user explicitly
   reports.

Vague symptoms do not justify broad rewrites. Ask for the diagnostic excerpt,
exact last action, repeatability, orientation, document type, Wi-Fi state, and
whether the stock UI recovered.

## RC1 finding 001

- Classification: `INPUT`
- Device: reMarkable Paper Pro, OS 3.27.3.0
- Result: launch/render PASS; all finger taps, swipes, and links FAIL
- Recovery: `/home/root/xovi/stock` restored working stock touch
- Narrowest layer: product-owned top-level ink/AI marker windows prevented
  UIManager from dispatching gestures to ReaderUI
- RC2 action: paint-only ink input pass-through, unmatched marker gesture
  forwarding, safe `touch_route` diagnostics, and focused UIManager regression
- Status: RC2 PHYSICAL PASS

## RC2 finding 002

- Classification: `REFRESH`
- Device: reMarkable Paper Pro, OS 3.27.3.0
- Result: Marker capture, completed-stroke rendering, undo, eraser, and
  persistence PASS; active stroke invisible until pen lift
- Narrowest layer: `InkCanvas:requestActiveSegment()` requested bounded `fast`
  refreshes while the working final path requested bounded `ui` refreshes
- Additional source risk: one pending segment slot could overwrite earlier
  segments when multiple Marker frames arrived in one input batch
- RC3 action: use bounded `ui` refresh for live segments and retain all pending
  segments until the next canvas paint
- Status: RC3 PHYSICAL FAIL

## RC3 finding 003

- Classification: `REFRESH`, `LAYOUT`, and `PERFORMANCE`
- Device: reMarkable Paper Pro, OS 3.27.3.0
- Result: slow live line PASS; normal-speed writing FAIL with HIGH latency and
  SEVERE ghosting; ink/residual strokes over menus/modals; eraser and finger
  page-turn presentation regressed; persistence and Undo remained correct
- Narrowest layer: per-segment GL16 `ui` updates saturated presentation, while
  the permanently topmost toast canvas repainted page ink above non-reader UI
- RC4 action: preserve all samples, coalesce presentation at KOReader's existing
  30 Hz interactive ceiling, use supported A2 while contact is active, retain
  final `ui` cleanup, and suppress canvas painting unless ReaderUI is the active
  surface
- Status: RC4 PHYSICAL FAIL

## RC4 finding 004

- Classification: `INPUT`, `MARKER`, `REFRESH`, and `PERFORMANCE`
- Device: reMarkable Paper Pro, OS 3.27.3.0
- Result: constant refreshes made writing slow/clunky; palm/finger input turned
  pages and selected text during writing; highlighting competed with Ink Mode;
  eraser was not continuous
- Architectural conclusion: handwriting cannot remain in normal ReaderUI
  interaction mode
- RC5 action: exclusive strict Write Mode, pen/finger guard policy, direct
  Marker-friendly toolbar, deliberate Navigate/Done controls, adaptive
  one-outstanding A2 presentation, idle quality cleanup, debounced atomic
  persistence, incremental visible cache/index work, and grouped continuous
  eraser
- Status: RC5 PHYSICAL RETEST REQUIRED
