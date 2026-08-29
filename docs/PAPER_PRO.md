# reMarkable Paper Pro baseline

## Existing support to reuse

KOReader `v2026.07.1` recognizes the Paper Pro sysfs model string
`reMarkable Ferrari` and selects `RemarkablePaperPro`. The device declaration
provides:

- `remarkable-aarch64` package/OTA target;
- 1620 x 2160 display dimensions;
- 229 DPI;
- color-screen capability;
- touch, Marker, buttons, hall sensor, battery, and frontlight paths;
- Paper Pro coordinate scaling;
- QTFB, Blight, or mxcfb framebuffer selection based on the launch environment.

These definitions live in `frontend/device/remarkable/device.lua` and are
B-class adapters. They are not product UI and should remain upstream-compatible.

## Package and launcher

Build the installable target on a supported Linux cross-compilation host:

```sh
./kodev release remarkable-aarch64
```

`make/remarkable.mk` packages `koreader.sh`, the icon, QTFB keep-alive helper,
and AppLoad manifests. The aarch64 README delegates Paper Pro installation to
KOReader's reMarkable wiki.

The shim manifest launches `koreader.sh` with:

```text
LD_PRELOAD=/home/root/shims/qtfb-shim.so
QTFB_SHIM_MODEL=false
QTFB_SHIM_INPUT_MODE=NATIVE
QTFB_SHIM_MODE=N_RGB565
QTFB_SHIM_RESPECT_FULL_REFRESH_REQUESTS=1
KO_DONT_GRAB_INPUT=1
KO_DONT_SET_DEPTH=1
```

The manual Paper Pro path depends on external reMarkable community tooling,
including Xovi, AppLoad, QTFB, and a compatible aarch64 QTFB shim. Those
projects are installation prerequisites, not dependencies to vendor into this
repository. Their versions must be checked against the installed reMarkable OS
at device-test time.

## Display and refresh

ReaderView paints into the Screen buffer. UIManager aggregates `fast`, `ui`,
`partial`, `flashui`, and `full` regional requests; the selected framebuffer
implementation translates those requests to the active display bridge. Product
overlays must request bounded regions and must not call QTFB or framebuffer
functions directly.

The N_RGB565 shim mode is the current aarch64 launch assumption. It is not proof
that all color transitions are cheap or accurate. Gallery 3 color behavior,
waveform selection, full-refresh honoring, ghosting, and refresh latency require
physical verification.

## Touch and Marker

Paper Pro declares separate touch and Marker evdev nodes. Device hooks scale
coordinates into screen space. Input reserves a pen slot and invokes a
registered stylus callback before ordinary gesture recognition, providing the
lowest-risk future InkService seam.

The callback currently retains x/y, contact id, tool, and event time but not
pressure. Do not add guessed pressure handling. On hardware, capture the actual
event capabilities and representative down/move/up frames, then make the
smallest generic Input adapter change if pressure is emitted and stable.

## Firmware and installation risks

- reMarkable OS updates can change input-node numbering, QTFB compatibility,
  preload requirements, AppLoad/Xovi behavior, or remove custom launch setup.
- Stock xochitl must remain responsible for suspend/standby in the current
  Paper Pro coexistence path.
- A failed launch must return cleanly to the stock UI without leaving stale
  QTFB connections or input grabs.
- Package and physical-device verification must be repeated after firmware,
  QTFB shim, toolchain, or reMarkable adapter changes.

No physical Paper Pro was available in Phase 0. All hardware results are
therefore explicitly `NOT RUN` in `BASELINE_TESTS.md`.

## Physical test procedure

1. Record device model, firmware, kernel, launcher, QTFB, and shim versions.
2. Back up existing app/launcher configuration.
3. Install the `remarkable-aarch64` archive through the documented AppLoad path.
4. Capture startup logs and confirm model, 1620 x 2160 framebuffer, and QTFB.
5. Test EPUB/PDF rendering, touch, Marker event detection, partial/full refresh,
   grayscale and color content, frontlight, exit, and return to xochitl.
6. Reboot and repeat launch/exit. Record every deviation without changing
   framebuffer or input internals during diagnosis.
