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
| Public GitHub fork | PENDING | Fork form prepared; final public creation requires action-time confirmation |

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

## Emulator functional baseline

| Area | Scenario | Emulator | Physical Paper Pro |
| --- | --- | --- | --- |
| Application | Launch at 1620 x 2160 / 229 DPI | BLOCKED | NOT RUN |
| Application | Simulated e-ink flash | BLOCKED | NOT RUN |
| File manager | Browse/open fixture | BLOCKED | NOT RUN |
| EPUB | Open and render `juliet.epub` | BLOCKED | NOT RUN |
| EPUB | Turn page and change typography | BLOCKED | NOT RUN |
| EPUB | Select, highlight, note, bookmark | BLOCKED | NOT RUN |
| EPUB | Local dictionary lookup, then offline repeat | BLOCKED | NOT RUN |
| PDF | Open and render `sample.pdf` | BLOCKED | NOT RUN |
| PDF | Page navigation, zoom, and reflow | BLOCKED | NOT RUN |
| PDF | Selection and highlight | BLOCKED | NOT RUN |
| Persistence | Close/reopen and restore position/settings | BLOCKED | NOT RUN |

No StarDict dictionary was installed because the emulator could not be built.
The later manual baseline must record the dictionary name, source, and license
before verifying offline lookup.

## Remote CI and package baseline

| Check | Status | Evidence |
| --- | --- | --- |
| Existing macOS ARM64 workflow | PENDING | Verify after the public fork and `main` push |
| Existing macOS x86-64 workflow | PENDING | Verify after the public fork and `main` push |
| CircleCI | NOT RUN | No fork-specific CircleCI project/configuration established |
| `remarkable-aarch64` package | NOT RUN | Embedded target requires supported Linux cross-toolchain; command documented only |

## Physical Paper Pro baseline

No device was available. The following are `NOT RUN`: device/model detection,
QTFB connection, launch/install, touch, Marker coordinates, pressure, partial
refresh, full refresh, Gallery 3 color, ghosting, refresh latency, frontlight,
exit/return to xochitl, reboot persistence, and firmware compatibility.

## Completion interpretation

Repository structure, source analysis, documentation, and exact dependency
checkout are established. Local build/run acceptance remains blocked by the
administrator-gated prerequisite installation and must not be reported as a
successful emulator baseline. Remote CI remains pending publication.
