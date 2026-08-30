# Phase 6 — Paper Pro release candidate qualification

## Stage A

Current RC identity: `0.6.0-rc2` / Phase 6 RC2.

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

Stage B continues when the user upgrades to RC2 and returns
`PAPER_PRO_TEST_REPORT_TEMPLATE.md`. No physical qualification row becomes
PASS before that explicit evidence. Failures enter the controlled process in
`PHASE6_FEEDBACK_LOOP.md`, produce an identified RC2/RC3, and retain previous
artifacts and checksums.

Current state: **BLOCKED — RC1 TOUCH INPUT FAILURE; RC2 PHYSICAL RETEST REQUIRED**.
