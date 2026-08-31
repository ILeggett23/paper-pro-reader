# Native Paper Pro runtime feasibility

## Scope and conclusion

This assessment covers only the native display/input/ink benchmark. It does not
approve an EPUB migration, replace KOReader, or qualify a release. The target is
the reMarkable Paper Pro (`reMarkable Ferrari`, 1620 x 2160 portrait) on the
3.27 firmware family, with 3.27.3.0 as the known physical-test version.

The proposed native runtime is feasible enough to build and take to a bounded
device experiment. Direct display takeover is the primary performance path;
QTFB/AppLoad remains the required fallback and comparison path. Neither path is
qualified for this new executable until the same package is tested on a real
Paper Pro. In particular, host tests cannot establish visible Marker latency,
Gallery 3 waveform behavior, palm behavior, power use, or recovery after a real
process failure.

## Evaluated paths

| Path | Existing evidence | Benefits | Principal risks | Role |
| --- | --- | --- | --- | --- |
| Current KOReader product path | KOReader `main` has the Phase 1-5 reading, annotation, ink, dictionary, AI, and offline contracts. The separate RC5 branch has Write Mode and refresh work but remains physically unqualified. Earlier hardware tests on 3.27.3.0 proved the installed KOReader/QTFB stack can launch, render, route touch and Marker input, persist notes and ink, undo, and erase. | Largest working feature set; mature document engines; safest behavioral reference; existing AppLoad return path. | The live Marker path crosses Lua input, product ink services, widget painting, UIManager refresh policy, and QTFB. RC4 hardware results showed that architecture was not yet a satisfactory writing experience. RC5 cannot be treated as passed without its pending device result. | Preserved reference and rollback application. Not modified or deleted by the spike. |
| Native application over QTFB/AppLoad | QTFB is already the Paper Pro bridge used by the KOReader package. The fallback manifest can request the established native-input and RGB565 environment. | Does not stop Xochitl; easiest visual-debug and recovery route; reuses the installed Xovi/AppLoad environment; useful A/B baseline against KOReader. | Additional process, shared-memory, shim, and Xochitl layers; refresh behavior is mediated by QTFB; shim and AppLoad compatibility can change by firmware; QTFB latency is not evidence for takeover latency. | Mandatory fallback, recovery, and comparison backend. |
| Native direct takeover through Quill | Quill v0.1.0 exposes a small clean-room MIT C ABI around the device's display engine. Its upstream project records Paper Pro testing on 3.27.3.0, fast monochrome dirty updates, quality cleanup updates, wake-lock needs, and Xochitl restoration. That evidence belongs to Quill, not to this application. | Removes ReaderUI, Lua widgets, UIManager, QTFB, layout, persistence, and application queues from the Marker-to-display path; gives the native scheduler direct bounded dirty rectangles; allows the benchmark to measure the intended architecture. | Temporarily stopping Xochitl is high impact; Quill relies on the proprietary device-local `libqsgepaper.so`; ABI and framebuffer discovery may change; a crash can leave stock UI stopped unless independent recovery works; suspend can start a competing Xochitl instance if wake locking fails; vendor support is not implied. | Primary benchmark and intended production display path, subject to physical qualification and recovery gates. |

## Why direct takeover is primary

The mission's ordering makes reliability first and Marker latency second. A
direct backend is selected only because it permits both concerns to be made
explicit:

1. a small C++ hot path receives raw evdev frames, normalizes them, and writes
   new segments to a reusable surface;
2. `RefreshScheduler` owns all display submission, dirty-region union, and the
   one-outstanding-update rule;
3. no document layout, Lua/UIManager dispatch, persistence, serialization,
   network activity, or general UI queue is allowed between receipt and live
   submission; and
4. a launcher plus an independent systemd recovery unit owns restoration of
   Xochitl rather than trusting only the application process.

This does not mean takeover is intrinsically safe. It means the lowest-latency
candidate can be isolated and rejected at a hardware gate without rebuilding
the future reader around a mediated display path.

## Why QTFB remains mandatory

QTFB/AppLoad remains available because takeover can fail for reasons outside
the application: an unsupported firmware build, changed vendor symbols,
ambiguous framebuffer discovery, missing wake-lock access, or restoration
policy that does not pass a real failure test. The fallback:

- preserves a route that leaves Xochitl running;
- provides visual debugging before display ownership is taken;
- allows the same synthetic and raw-input logic to be compared across display
  backends;
- gives the operator a usable benchmark mode when takeover preflight refuses;
  and
- provides an independent latency comparison without claiming equivalence.

Fallback is a separate backend, not a silent downgrade after Xochitl has been
stopped. A takeover initialization failure restores Xochitl and exits. The
operator must explicitly launch QTFB mode afterward. Backend selection is
spelled `--backend takeover|qtfb` (or equivalently
`PPR_DISPLAY_BACKEND=takeover|qtfb`) so a report can never conceal which path
was measured.

## Proprietary boundary

The project does not contain, fetch, build in CI, or redistribute
`libqsgepaper.so` or any other proprietary reMarkable object, font, icon, or
asset. Direct mode dynamically loads a user-built Quill library pinned to
v0.1.0 commit `39262ee0bef69915e3ead3ac218d5973916f422a` (MIT). Quill reaches the
vendor library supplied by the owner's device. The package accepts paths to
those device-local libraries and validates the required Quill symbols plus
reported width, height, stride, buffer, and pixel format before Xochitl remains
stopped.

A hash or ELF build ID for the device vendor library is diagnostic evidence,
not a compatibility allowlist and not permission to redistribute it. The
operator must obtain it from their own device and comply with the applicable
reMarkable terms. The dependency and license record is in
`DEPENDENCIES-AND-LICENSES.md`.

## Firmware compatibility

Firmware compatibility is an observed tuple, not a model-name assumption. A
qualification record must include at least:

- model string and portrait dimensions;
- OS version and kernel build;
- Quill commit and user-built library hash;
- device-local vendor-library hash and build ID when available;
- Xovi, AppLoad, and QTFB versions for fallback mode;
- discovered touch and Marker device capabilities and ABS ranges, without
  logging event coordinates; and
- whether normal and forced Xochitl restoration succeeded.

Known 3.27.3.0 results from KOReader/QTFB reduce uncertainty only for the
existing stack. They do not qualify this native application. A firmware update
may change systemd unit behavior, input capabilities, coordinate rotation,
vendor symbols, framebuffer selection, wake locks, QTFB protocol behavior, or
Xovi/AppLoad injection. Direct mode therefore refuses unknown model/firmware
tuples by default. Expanding the supported set requires a new physical record,
not a documentation-only edit.

## Recovery feasibility and risks

Takeover is feasible only with two independent restoration paths:

- the foreground launcher handles normal exit and catchable `INT`, `TERM`, and
  shell-exit paths; and
- a systemd service uses stop/failure handling (`ExecStopPost` or an equivalent
  independent recovery unit) to call an idempotent restoration script even
  when the benchmark cannot.

The restoration script must be harmless when repeated, must never kill SSH,
and must start only the stock Xochitl service after confirming it is not
already active. Preflight, startup, crash, suspend, low-battery, and manual SSH
recovery behavior are specified in `RECOVERY-MODEL.md`.

Risks that remain device-gated include a kernel panic, power loss before the
recovery unit runs, systemd or filesystem corruption unrelated to the app,
suspend during display ownership, and a vendor library that initializes but
misidentifies the writable auxiliary buffer. USB SSH must be verified before
every takeover test. The benchmark never remounts or modifies the immutable
root partition merely to install.

## Testability limits

Host fakes and synthetic input can prove deterministic software invariants:
coordinate clipping, rotation, ring-buffer capacity and overrun reporting,
strict palm rejection, eraser/Undo grouping, bounded dirty rectangles,
coalescing, one update in flight, cleanup cancellation, and shutdown behavior.
Script tests can prove idempotent command selection against fake `systemctl`.
Secret and package scans can prove that the produced archive contains no known
proprietary object or test content.

They cannot prove:

- pen-to-glass latency or whether ink follows the Marker;
- the correct waveform for every transition;
- ghosting, color quality, per-letter flashing, or panel damage risk;
- pressure semantics or touch/Marker concurrency;
- palm rejection ergonomics on the physical digitizers;
- suspend/resume and low-battery behavior;
- CPU, memory, and battery impact on the target; or
- restoration after killing the real process while it owns the display.

The benchmark report is written outside the Marker hot path to
`/home/root/.local/state/paper-pro-reader-native/benchmark.jsonl`. Those items
remain `NOT RUN` until the procedure in
`DEVICE-QUALIFICATION.md` is returned with evidence. No EPUB migration begins
before that gate.

## Feasibility decision

Proceed with a minimal, reversible native benchmark in both display modes.
Keep KOReader and RC5 unchanged as the behavioral reference and rollback.
Treat direct takeover as experimental until the primary and fallback backends,
raw input, palm behavior, latency report, forced termination, and stock-UI
restoration have all been exercised on the specified Paper Pro.

Current status: **DEVICE TEST REQUIRED**.
