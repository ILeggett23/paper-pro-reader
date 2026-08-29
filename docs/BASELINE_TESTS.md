# Phase 0 baseline tests

Status vocabulary:

- `PASS`: executed with the stated evidence.
- `FAIL`: executed and produced an incorrect result.
- `BLOCKED`: not executable because a prerequisite is unavailable.
- `NOT RUN`: intentionally outside the available environment or Phase 0 scope.

Emulator, CI, package, and physical device are independent gates.

## Repository baseline

| Check | Status | Evidence |
| --- | --- | --- |
| Baseline tag/commit | PASS | `v2026.07.1` resolves to `9192014d8bd82a91dc1012473be0f238dedfdb54` |
| Product branch | PASS | Local `main` created directly from the baseline tag |
| Remotes | PASS | `origin` is `ILeggett23/paper-pro-reader`; `upstream` is `koreader/koreader` |
| Pinned submodules | PASS | All top-level submodules and nested CREngine checked out at superproject SHAs |
| License/history | PASS | Full upstream Git history and `COPYING` retained; derivative notice added |
| Public GitHub fork | PASS | `ILeggett23/paper-pro-reader` is public and identifies `koreader/koreader` as its fork source |
| Default branch | PASS | GitHub reports `main`; `master` remains the unmodified upstream-development mirror |
| Remote file integrity | PASS | All ten Phase 0 files on `main` matched their locally generated Git blob SHAs |

## Automated local baseline

| Check | Status | Evidence |
| --- | --- | --- |
| Prerequisite audit | PASS | Host has Xcode/Apple clang; system Bash 3.2, Make 3.81, and Python 3.9 are below KOReader minimums; CMake/Meson/Ninja/NASM/pkg-config absent |
| Homebrew installation | BLOCKED | Official noninteractive installer stopped at the administrator-password boundary; no credentials requested or supplied |
| `./kodev fetch-thirdparty` | BLOCKED | Requires Bash 4+; exact git submodules were initialized directly |
| `./kodev build` | BLOCKED | Required native build toolchain is unavailable |
| `./kodev test base` | BLOCKED | Emulator/base build unavailable |
| `./kodev test front` | BLOCKED | Emulator/frontend build unavailable |
| `./kodev check` | BLOCKED | Required lint/build tools unavailable |
| Clean rebuild | BLOCKED | Initial build unavailable |
| ARM64 CI artifact integrity | PASS | Downloaded artifact SHA-256 matched GitHub's `134e2edcdb1ca2ba5c39f10003ba2fafbbd8b99069e4c6c1a164ef60b939b910`; signature valid and executable is native arm64 |
| ARM64 CI artifact launch | PASS | App reported `v2026.07.1-3-g795ca53_2026-08-29` and exited cleanly with code 0 after each smoke run |

## Emulator functional baseline

| Area | Scenario | Emulator | Physical Paper Pro |
| --- | --- | --- | --- |
| Application | Headless initialization at 1620 x 2160 / 229 DPI | PASS | NOT RUN |
| Application | Exact-profile visual launch | BLOCKED | NOT RUN |
| Application | Display-fitted portrait launch at 600 x 800 logical / 1200 x 1600 Retina pixels | PASS | NOT RUN |
| Application | Simulated e-ink flash behavior | NOT RUN | NOT RUN |
| File manager | Browse/open fixture | NOT RUN | NOT RUN |
| EPUB | Open and render `juliet.epub` | PASS | NOT RUN |
| EPUB | Turn page | PASS | NOT RUN |
| EPUB | Change typography | NOT RUN | NOT RUN |
| EPUB | Select, highlight, note, bookmark | NOT RUN | NOT RUN |
| Dictionary | Local English definition through bundled `sdcv` | PASS | NOT RUN |
| Dictionary | Download through KOReader UI and repeat with network disabled | NOT RUN | NOT RUN |
| PDF | Open and render `sample.pdf` | PASS | NOT RUN |
| PDF | Page navigation | PASS | NOT RUN |
| PDF | Zoom and reflow | NOT RUN | NOT RUN |
| PDF | Selection and highlight | NOT RUN | NOT RUN |
| Persistence | Clean close/reopen and restore reading position | PASS | NOT RUN |

The visible Mac window could not fit a 1620 x 2160 logical surface and SDL
constrained it to the physical display. The exact profile was therefore tested
headlessly, while visual behavior was tested in a smaller portrait viewport.
Neither substitutes for Gallery 3 hardware.

KOReader's listed GPLv3+ GCIDE host returned HTTP 522. The catalog-listed GNU
Public License English explanatory dictionary was used instead. Its archive
SHA-256 was `b4245175e50d773f221364a9c81303f2703a018cb8195a3255c6c5934d3970f1`;
the bundled StarDict engine returned a local definition for `love`. The
download/extraction lived under `/private/tmp` and no UI-download or physical
network-off toggle is claimed.

## Remote CI and package baseline

| Check | Status | Evidence |
| --- | --- | --- |
| Existing macOS ARM64 workflow | PASS | Run #3 (`33275727345`) passed build, binary checks, frontend tests, package generation, and artifact upload |
| Existing macOS x86-64 workflow | PASS | Run #3 (`33275727345`) passed build, binary checks, frontend tests, package generation, and artifact upload |
| CircleCI | NOT RUN | No fork-specific CircleCI project/configuration established |
| `remarkable-aarch64` package | NOT RUN | Embedded target requires supported Linux cross-toolchain; command documented only |

## Physical Paper Pro baseline

No device was available. The following are `NOT RUN`: device/model detection,
QTFB connection, launch/install, touch, Marker coordinates, pressure, partial
refresh, full refresh, Gallery 3 color, ghosting, refresh latency, frontlight,
exit/return to xochitl, reboot persistence, and firmware compatibility.

## Completion interpretation

Repository structure, source analysis, documentation, exact dependency
checkout, public publication, ARM64 CI, and artifact-backed local runtime smoke
tests are established. A source build from this local checkout remains blocked
by the administrator-gated Homebrew installation. The CI-built app run is
reported separately and must not be described as a successful local source
build or as physical Paper Pro verification.
