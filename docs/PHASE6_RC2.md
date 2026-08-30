# Phase 6 RC2 — Paper Pro finger-touch routing

## Physical finding

RC1 `0f3c3c9f16c11e7545692c8f502a2061b393d50e` installed and launched through
AppLoad on a reMarkable Paper Pro running OS 3.27.3.0. Quickstart rendered and
refreshed, but finger taps, swipes, and links produced no reader action. Stock
touch worked immediately after `/home/root/xovi/stock`.

Status: **RC1 BLOCKED — TOUCH INPUT FAILURE**.

## Root cause

The upstream Paper Pro definition and current upstream master both select
`/dev/input/event2` for Marker and `/dev/input/event3` for touch and use the
same native-input QTFB/AppLoad manifest as this fork. Phase 3's stylus callback
is registered only while Ink Mode or a temporary written question is active;
it is not registered on ordinary Quickstart launch.

The fork did add two always-attached product paint windows above ReaderUI:

1. `InkCanvas`, attached even when Ink Mode was inactive so saved strokes could
   remain visible.
2. `ConversationMarker`, attached for the small visible-anchor AI affordance.

UIManager sends normal input to the topmost non-toast window and does not then
send unhandled input to ordinary lower windows. RC1 therefore stopped gestures
at the product canvas before ReaderUI could activate links, page taps, or
swipes. Emulator tests called ReaderUI actions directly and did not exercise
this real window-stack dispatch.

## Minimal RC2 change

- Mark `InkCanvas` as a paint-only pass-through window.
- Let `ConversationMarker` consume only a tap inside its visible marker bounds.
- Forward every unmatched marker gesture to the owning ReaderUI.
- Record opt-in `touch_route` state plus gesture mode only.
- Add real UIManager stack regression coverage and marker consume/forward tests.

No A-class or B-class file changes. Device discovery, event-node selection,
coordinate transforms, Input, gesture detection, QTFB/AppLoad manifests,
framebuffer handling, persistence, AI, and backend behavior are unchanged.

## External ReferenceError

The installation-time Xovi ReferenceError is tracked separately because RC1
still launched and rendered. A comparable OS 3.27 AppLoad report was resolved
by updating an old `qt-resource-rebuilder`. Keep the current launcher unchanged
for the first RC2 touch retest if RC2 launches. If the error recurs or prevents
launch, capture the exact message and component versions before updating the
extension and rebuilding the Xovi hashtable.

## First physical retest

1. Upgrade RC1 in place to RC2 without rebuilding Xovi.
2. Launch KOReader from AppLoad.
3. Tap the Quickstart next-page link once.
4. Swipe once and tap another visible control.
5. Stop and report immediately if any of those three gestures fails.

## Physical result

RC2 PASS: launch, Quickstart controls, finger swipe, exit, EPUB page turns,
position persistence, word selection, note creation, and note persistence.
RC1's touch blocker is closed. Dictionary lookup was inconclusive because no
local KOReader dictionary had yet been verified. Ink capture, completed-stroke
rendering, undo, deletion, eraser, and persistence passed; live active-stroke
rendering became the separate RC3 blocker.
