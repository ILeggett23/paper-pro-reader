# Paper Pro Reader native runtime spike

This directory contains the Phase 0 architecture and Phase 1 hardware benchmark
for an original, native, reading-first Paper Pro application. It is deliberately
not an EPUB reader yet. It exists to answer one question first: can a small C++
runtime provide reliable recovery, low-latency Marker presentation, strict palm
rejection, and predictable refresh behavior on physical Ferrari hardware?

Status: **DEVICE TEST REQUIRED**.

## Safety boundary

- The benchmark does not read or write KOReader annotations, ink, vocabulary,
  settings, AI queue, responses, dictionaries, or documents.
- Benchmark strokes are transient memory only.
- The primary backend dynamically loads a user-built Quill v0.1.0 adapter and
  the device owner's `libqsgepaper.so`; neither shared object is distributed.
- The fallback backend speaks the existing AppLoad QTFB protocol.
- Takeover is temporary. Xochitl is restored by an in-process shell trap,
  `ExecStopPost`, and an independent recovery unit.
- Installation lives under `/home/root`; no immutable OS partition is changed.

## Runtime architecture

```text
evdev capability discovery
  -> dedicated epoll input thread
  -> preallocated Marker SPSC ring
  -> CoordinateTransform
  -> InteractionController (strict page touch suppression)
  -> InkModel + retained RasterSurface
  -> bounded dirty rectangle
  -> RefreshScheduler (one logical update outstanding)
  -> Quill direct backend OR QTFB fallback backend
```

There is no QML, JavaScript, browser, Lua widget, persistence, document layout,
network request, or synchronous log write on the Marker sample path. The
benchmark uses a small software rasterizer so it can paint directly into either
Quill's BGRA32 buffer or QTFB's RGB565 shared memory. Qt remains behind the
audited Quill boundary and is not required by the application core.

Public future boundaries are declared in `core/interfaces.h`: `DisplayBackend`,
`InputBackend`, `DocumentEngine`, `AnnotationStore`, `DictionaryService`, and
`AIClient`. `RefreshScheduler`, `CoordinateTransform`, and
`InteractionController` are concrete, testable public types.

## Host build and tests

Requirements: CMake 3.22+, Ninja, a C++20 compiler, and pthreads.

```sh
cd native-reader
./scripts/test-host.sh
./scripts/test-sanitizers.sh
```

The host executable can print its identity, but real display/input startup is
Linux-device-only:

```sh
./build/host-debug/paper-pro-reader-benchmark --version
```

## Official Ferrari cross-build

Install the official public 3.27 Ferrari SDK on a supported Linux host. Do not
use a generic AArch64 compiler. Then point the build at the SDK-owned setup and
CMake toolchain files:

```sh
export PPR_FERRARI_SDK_ENV=/opt/remarkable/ferrari/environment-setup-cortexa53-crypto-remarkable-linux
export PPR_FERRARI_CMAKE_TOOLCHAIN_FILE=/opt/remarkable/ferrari/sysroots/x86_64-codexsdk-linux/usr/share/cmake/OEToolchainConfig.cmake
./scripts/cross-build.sh
./scripts/package-device.sh
```

The exact environment filename is SDK-generated; discover it under the chosen
SDK install directory instead of copying the example blindly. The scripts
verify the compiler reports AArch64 and the result is an ELF64 AArch64 binary.

## Device modes

QTFB fallback is launched from AppLoad using `external.manifest.json`. It keeps
Xochitl/AppLoad in the path and is for recovery, visual debugging, and A/B
comparison. It is not latency-equivalent to takeover.

Direct takeover is launched over SSH:

```sh
/home/root/xovi/exthome/appload/paper-pro-reader-native/scripts/launch-takeover.sh
```

It admits only `reMarkable Ferrari` on firmware family 3.27, verifies the
pinned Quill commit marker and required Quill C symbols, confirms the device-
local vendor library is readable, records prior state, stops Xochitl, holds a
wake lock, and starts a transient systemd unit. Any initialization failure runs
the same idempotent restoration path used for normal exit and signals.

Controls are `Pen`, `Eraser`, `Undo`, `Clear`, and `Exit`. All page-area finger
contacts are consumed. Controls accept deliberate finger or Marker taps. Hold
five fingers for 1.5 seconds, press Power, or stop the transient service over
SSH for emergency exit.

See `docs/DEVICE-QUALIFICATION.md` before installing or launching anything.
