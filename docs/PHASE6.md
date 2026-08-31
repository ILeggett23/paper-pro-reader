# Phase 6 — Paper Pro release candidate qualification

## Stage A

Current RC identity: `0.6.0-rc5` / Phase 6 RC5.

Stage A provides:

- Linux native `remarkable-aarch64` CI using KOReader's current
  `koreader/koremarkable:2.1.0-22.04` toolchain image;
- repository-native `tar.xz` release renamed predictably for Paper Pro Reader;
- ELF aarch64, manifest, module, permission, contents, checksum, and secret
  validation;
- safe product diagnostics and exportable log path;
- restart-safe file idempotency retaining only completed responses;
- installation, upgrade, rollback, uninstall, backend, first-boot, A/B,
  qualification, report, and feedback-loop guides.

RC1 launched and rendered the Quickstart Guide on a Paper Pro running OS
3.27.3.0, but every finger tap and swipe was blocked. Source reproduction
identified two product-owned paint windows above ReaderUI. RC2 makes the ink
canvas input-passive and forwards gestures outside the AI conversation marker
to ReaderUI. No device, evdev, QTFB, framebuffer, or engine file changes.

RC2 physically passed touch routing, Quickstart controls, EPUB navigation,
position persistence, selection, notes, completed ink, undo, eraser, and ink
persistence. Its remaining blocker was live ink: the active line appeared only
after pen lift. RC3 keeps RC2 behavior and changes only active-segment painting
to the already-proven bounded `ui` refresh while batching every segment received
before the next paint.

RC3 made slow ink visible but failed at normal writing speed with HIGH latency,
SEVERE ghosting, menu/modal contamination, eraser presentation failure, and
finger page-turn regression. RC4 rejects per-segment GL16. It continuously
captures samples, coalesces presentation at KOReader's established 30 Hz
interactive ceiling, uses QTFB-supported A2 while contact is active, retains
one final `ui` cleanup, and suppresses InkCanvas painting whenever a non-reader
window is above ReaderUI.

RC4 still failed the overall writing experience: repeated refreshes remained
slow, palm contacts turned pages and selected text, selection could disrupt Ink
Mode, and erasing was not continuous. RC5 introduces an explicit page-locked
Write Mode above otherwise unchanged Read Mode. It adds strict/automatic palm
policies, a Marker-friendly Write/Undo/Eraser/Navigate/Done toolbar, adaptive
one-outstanding A2 presentation, one idle quality cleanup/save, incremental
index/cache updates, and one-Undo continuous eraser gestures.

The package contains the native KOReader aarch64 launcher, resources, pinned
libraries, Paper Pro product modules, `koreader.sh`, QTFB/AppLoad manifests,
keep-alive helper, and aarch64 README. Xovi, qt-resource-rebuilder, rm-appload,
and QTFB shims remain external device prerequisites and are not vendored.

## Diagnostics

Study > Diagnostics can enable a bounded JSON-lines log and view a report with:

- RC version and app revision;
- firmware/machine when readable;
- device model, dimensions, and DPI;
- QTFB/shim presence;
- AI enabled/configured state;
- queue-state counts;
- Ink Mode and stylus-callback state.
- RC2 product-overlay touch-routing identity.
- RC3 live-ink refresh strategy identity.
- RC4 A2 cadence and reader-surface layer policy.
- RC5 Write Mode, palm suppression, adaptive presentation, persistence, and
  performance counters.

Logged lifecycle fields are restricted to event, request ID, state, error
category, points, bounds, mode, and duration. Keys, tokens, URLs, book text,
questions, answers, and images are excluded. On Paper Pro the export path is:

```text
/home/root/xovi/exthome/appload/koreader/settings/paperpro-diagnostics.log
```

Retrieve it with:

```sh
scp root@<PAPER_PRO_IP>:/home/root/xovi/exthome/appload/koreader/settings/paperpro-diagnostics.log .
```

## Stage B

Stage B continues when the user upgrades to RC5 and returns
`PAPER_PRO_TEST_REPORT_TEMPLATE.md`. No physical qualification row becomes
PASS before that explicit evidence. Failures enter the controlled process in
`PHASE6_FEEDBACK_LOOP.md`, produce an identified RC2/RC3/RC4/RC5, and retain previous
artifacts and checksums.

Current state: **BLOCKED — RC4 WRITING-MODE, PALM-REJECTION, REFRESH, AND ERASER FAILURES; RC5 PHYSICAL RETEST REQUIRED**.
