# Phase 6 — Paper Pro release candidate qualification

## Stage A

RC identity: `0.6.0-rc1` / Phase 6 RC1.

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

Stage B begins when the user installs RC1 and returns
`PAPER_PRO_TEST_REPORT_TEMPLATE.md`. No physical qualification row becomes
PASS before that explicit evidence. Failures enter the controlled process in
`PHASE6_FEEDBACK_LOOP.md`, produce an identified RC2/RC3, and retain previous
artifacts and checksums.

Current state: **PHYSICAL PAPER PRO VALIDATION PENDING USER TEST**.
