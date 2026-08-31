# Dependencies, licenses, and redistribution boundaries

## Policy

`native-reader/` is part of the AGPL-3.0-licensed Paper Pro Reader repository.
The repository's `COPYING`, KOReader attribution, and existing notices remain in
force. This file is an engineering inventory, not legal advice.

No dependency is fetched from an unpinned branch by the native build. Runtime
components supplied by the device owner are not copied into the release
archive or CI. The deterministic package contains the application, its own
AGPL source/runtime files, manifests, lifecycle scripts, service definition,
version/dependency metadata, and checksums only.

## Phase 0/1 inventory

| Dependency | Exact version or commit | License / terms | Source | Redistributed in native package? | Device-local dynamic load? | CI treatment | Open question or control |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Paper Pro Reader / KOReader behavioral reference | `origin/main` commit `8bd1405297f6a1868ee333b86ad074d203625247`; KOReader foundation v2026.07.1 commit `9192014d8bd82a91dc1012473be0f238dedfdb54` | AGPL-3.0 with retained upstream notices | `https://github.com/ILeggett23/paper-pro-reader` and `https://github.com/koreader/koreader` | Existing repository remains present; the native device archive does not bundle the KOReader application | No | Existing project tests remain separate; native CI builds only `native-reader/` | Existing stores are behavioral/migration references, never modified by this benchmark |
| Native benchmark source | Current `native-reader-v2-spike` commit recorded in `BUILD-VERSION.txt`/package metadata | AGPL-3.0 | This repository, `native-reader/` | Yes, under repository license and source-availability obligations | No | Built, tested, sanitized, scanned, and packaged | Release metadata must identify the exact repository commit |
| Quill display adapter | v0.1.0, commit `39262ee0bef69915e3ead3ac218d5973916f422a` | MIT; clean-room implementation per upstream `LICENSE` and `CLEANROOM.md` | `https://github.com/MaximeRivest/quill` | No Quill source or binary is in the device archive in this phase | Yes. Operator supplies a user-built `libquill.so` from the pinned source at `PPR_QUILL_LIBRARY` and an exact `PPR_QUILL_COMMIT_FILE`; optional `PPR_QUILL_SHA256` verifies that binary | CI compiles/tests the Paper Pro Reader loader against its own declared symbol contract; CI does not fetch a vendor library or produce a Quill device binary | Before a future redistribution decision, retain Quill's MIT notice and re-review its clean-room record. Runtime requires the pinned C ABI symbols and validated geometry/format |
| `libqsgepaper.so` and associated vendor display implementation | Exact file is the copy already installed on the target device; hash and ELF build ID are recorded at test time | Proprietary reMarkable software; terms are outside this repository | User's own Paper Pro firmware/device | **Never** | Indirectly, by user-built Quill in direct mode | Prohibited from CI, artifacts, caches, fixtures, and logs | A hash/build ID is evidence, not permission to redistribute and not a compatibility allowlist. Device owner must establish their right to use it |
| AppLoad / QTFB fallback host | AppLoad v0.5.3, commit `5bb34a362f09f753f18bd6261558f8e2737aacdb` | GPL-3.0 | `https://github.com/asivery/rm-appload` | No; external prerequisite already installed by the operator | AppLoad/QTFB is a host/IPC service, not loaded into the native process as a packaged library | Not installed or built in CI; manifest shape and package exclusions are tested | Compatibility must be retested with the exact installed binary/hash. This pin does not authorize replacing the user's current AppLoad build |
| Xovi | v0.3.3, commit `0c8d5269b55c851901d4e4a754dc2d7deab40b17` | LGPL-3.0 per the audited upstream revision | `https://github.com/asivery/xovi` | No; external fallback prerequisite | No direct load by the benchmark | Not present in CI or package | Firmware injection compatibility is external and can change after OS updates |
| `qt-resource-rebuilder` from `rm-xovi-extensions` | release `v19-23052026`, commit `7874154dba6793cc68a15fae0fb9dd272c4ed20a` | GPL-3.0 | `https://github.com/asivery/rm-xovi-extensions` | No; external fallback prerequisite | No | Not present in CI or package | Needed only to maintain the existing Xovi/AppLoad environment; the benchmark installer does not upgrade it |
| Qt Core/Gui device runtime | Qt 6.8.2 from the selected reMarkable SDK/runtime | LGPL-3.0 or GPL, depending on selected Qt licensing; upstream exceptions/modules must be audited individually | reMarkable SDK sysroot and `https://www.qt.io/licensing/open-source-lgpl-obligations` | Not bundled by the Phase 1 archive; runtime-resolved from the compatible device/SDK only if the build enables Qt helpers | Dynamic system linkage only if enabled | Host CI may use the runner's open-source Qt package when a Qt-enabled preset is selected; the marker core and tests must remain host-buildable without proprietary components | If a future package bundles Qt libraries, add exact module hashes, corresponding-source and relinking compliance, notices, and size/security review before release |
| Official Ferrari/Paper Pro SDK | `5.7.119-ferrari` public x86_64 toolchain | reMarkable SDK/toolchain terms supplied with the download | Official reMarkable developer/toolchain distribution | No | No | Build-only; CI uses a configured toolchain location or records `NOT RUN` when the official SDK is unavailable | Do not substitute an arbitrary generic AArch64 compiler for a claimed device build; retain the SDK version in package metadata |
| Linux evdev/epoll/systemd interfaces | Headers and ABI from the `5.7.119-ferrari` SDK sysroot; runtime kernel/firmware recorded per device (known test family 3.27, known device 3.27.3.0) | Linux UAPI headers are GPL-2.0 WITH Linux-syscall-note; systemd and libc components retain their upstream licenses | SDK sysroot and target OS | No separate kernel/systemd binary is bundled | System interfaces only | Host fakes test behavior; Linux builds compile the platform backend. Device behavior is physically gated | Node numbering and service behavior are deliberately not treated as stable ABI; capabilities/ranges and service names are checked at runtime |
| C++ standard library and libc | Version resolved from the exact host compiler for tests and from the `5.7.119-ferrari` SDK for device builds | GCC Runtime Library Exception / LGPL terms as applicable to the selected runtime | Host compiler or SDK sysroot | No standalone runtime library is intentionally bundled; packaging scan records actual ELF dependencies | Normal dynamic linking on device | Compiler and linker versions are captured in CI logs | If static linking or library bundling is later enabled, repeat license and source-offer review |
| CMake and host test tools | Minimum/version constraints are authoritative in `native-reader/CMakeLists.txt` and CI; the concrete versions are captured in each run | BSD-3-Clause for CMake; compiler/sanitizer licenses depend on selected toolchain | Host environment | No | No | Build-only; ASan/UBSan where supported | Build tools are not runtime dependencies. A tool-version change does not qualify device behavior |

The pinned x86-64-host Ferrari installer is
`remarkable-production-image-5.7.119-ferrari-public-x86_64-toolchain.sh` from
the official 3.27.0.97 directory. Its independently downloaded SHA-256 is
`324d77d84dda5ba8fac484107b3c9981daaa28fe5ebed6589172f0cb1bcdd020`.

## QTFB protocol provenance

The native fallback client is an independently written adapter to the existing
QTFB service contract. Its behavioral reference is the QTFB use already
present in the AGPL-3.0 KOReader foundation and the pinned AppLoad revision
above. No QTFB/AppLoad source file is copied into `native-reader/`. The release
archive includes only an AppLoad manifest and the native client code under this
repository's AGPL-3.0 license.

The user's installed AppLoad/QTFB binary must be recorded by version and SHA-256
during qualification. If it does not match the reviewed revision, fallback
results are labeled against the observed binary rather than silently described
as v0.5.3. The installer never changes Xovi, AppLoad, QTFB, or the QTFB shim.

Direct and fallback selection uses `--backend takeover|qtfb` or
`PPR_DISPLAY_BACKEND=takeover|qtfb`. This setting and the exact external hashes
belong in the privacy-safe report; it never records library paths containing
operator-specific data.

## Deferred components are not current dependencies

CREngine, SQLite, StarDict/sdcv, TLS/HTTP, and an AI transport are future
architecture choices. The existing KOReader implementations inform their
contracts, but the native benchmark does not link or fetch them. Each must
receive an exact version, license audit, vulnerability review, deterministic
build rule, and data-migration review before being added. No provider SDK or
permanent AI secret is permitted on device.

## Package and CI exclusion rules

Both CI and local package validation must fail if an archive contains:

- `libqsgepaper.so`, any other unapproved `.so` copied from a device, or a
  device SDK sysroot;
- a Quill binary not explicitly approved for redistribution;
- Xovi, AppLoad, QTFB, or resource-rebuilder binaries;
- credentials, API keys, device tokens, SSH keys, cookies, or environment
  dumps;
- EPUB/PDF documents, personal books, selected passages, handwriting images,
  raw stroke data, or coordinate traces; or
- paths revealing a developer's home directory.

The dependency manifest in the package records names, exact revisions,
licenses, source URLs, inclusion state, and external-runtime status. A checksum
proves archive integrity only; it does not establish publisher identity,
firmware compatibility, or legal permission for external components.

## Unresolved distribution questions

1. Confirm with counsel or the applicable terms whether each device owner may
   use their firmware's `libqsgepaper.so` through a clean-room adapter. This
   project makes no distribution or support-right claim.
2. Before ever bundling Quill, re-review the exact pinned tree, include the MIT
   notice, verify that no `vendor/` object enters the artifact, and determine
   whether dynamic interaction with the vendor library changes obligations in
   the target jurisdictions.
3. If Qt is bundled later, document every module, license choice, modification,
   corresponding-source route, installation information where applicable, and
   relinking method. The current non-bundling decision avoids resolving those
   questions prematurely.
4. AppLoad/Xovi/QTFB compatibility and licensing are external prerequisites,
   not an invitation to redistribute their release artifacts. Device install
   instructions must keep the operator's current versions unchanged.
5. reMarkable firmware, services, icons, fonts, and UI assets remain
   proprietary. The future UI must be original and may not copy them.
