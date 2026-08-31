# Native benchmark device qualification

This procedure is for the reMarkable Paper Pro (`reMarkable Ferrari`) running
the tested 3.27 firmware family. It does not alter Xovi/AppLoad versions, the
KOReader RC5 installation, books, settings, or the immutable OS partition.

No physical row is PASS until a person runs this procedure on the device and
returns evidence. Current overall status: **DEVICE TEST REQUIRED**.

## Safety rules

- Keep two working SSH terminals open during takeover tests.
- Keep the existing KOReader/RC5 directory and archive unchanged.
- Do not run takeover if USB SSH is unavailable.
- Stop immediately if the model/firmware guard, checksum, ELF check, Quill
  check, Xochitl stop, display initialization, or restoration reports an error.
- Never copy `libqsgepaper.so` off the device into this repository, CI, the
  release archive, or a shared location.
- Use the exact candidate archive and checksum supplied with the branch build.

Set these values on the host. Replace only the three angle-bracket values:

```sh
export PPR_DEVICE=<PAPER_PRO_IP>
export PPR_ARCHIVE=<PAPER_PRO_NATIVE_TAR_XZ>
export PPR_SHA_FILE=<PAPER_PRO_NATIVE_TAR_XZ_SHA256>
```

## 1. Verify the archive checksum

```sh
sha256sum -c "$PPR_SHA_FILE"
```

On macOS without `sha256sum`, compare the two exact values:

```sh
shasum -a 256 "$PPR_ARCHIVE"
awk '{print $1}' "$PPR_SHA_FILE"
```

They must match byte-for-byte.

## 2. Verify ELF architecture and package exclusions

```sh
PPR_VERIFY_DIR=$(mktemp -d)
tar -xJf "$PPR_ARCHIVE" -C "$PPR_VERIFY_DIR"
file "$PPR_VERIFY_DIR/paper-pro-reader-native/bin/paper-pro-reader-benchmark"
find "$PPR_VERIFY_DIR/paper-pro-reader-native" -type f -name '*.so' -print
find "$PPR_VERIFY_DIR/paper-pro-reader-native" -type f \( -name '*.epub' -o -name '*.pdf' -o -name '*.rmdoc' \) -print
```

`file` must report ELF64 AArch64. Both `find` commands must print nothing. Keep
the temporary directory until installation finishes, then remove only that
exact directory if desired.

## 3. Install without changing Xovi or AppLoad

First confirm the candidate name, then upload it:

```sh
basename "$PPR_ARCHIVE"
scp "$PPR_ARCHIVE" root@"$PPR_DEVICE":/home/root/
```

Create a recoverable backup and install into a new staging directory. Replace
`<ARCHIVE_BASENAME>` with the exact result from `basename`:

```sh
ssh root@"$PPR_DEVICE"
set -eu
archive=/home/root/<ARCHIVE_BASENAME>
install_root=/home/root/xovi/exthome/appload/paper-pro-reader-native
stamp=$(date +%Y%m%d-%H%M%S)
stage=/home/root/paper-pro-reader-native-stage-$stamp
mkdir -p "$stage"
tar -xJf "$archive" -C "$stage"
test -x "$stage/paper-pro-reader-native/bin/paper-pro-reader-benchmark"
test -r "$stage/paper-pro-reader-native/external.manifest.json"
if [ -e "$install_root" ]; then
    mv "$install_root" "/home/root/paper-pro-reader-native-before-$stamp"
fi
mv "$stage/paper-pro-reader-native" "$install_root"
"$install_root/bin/paper-pro-reader-benchmark" --version
exit
```

Do not rebuild Xovi, replace AppLoad, or replace QTFB for this test.

## 4. Confirm SSH recovery access

Open a second host terminal and keep it open:

```sh
ssh root@"$PPR_DEVICE" 'printf "SSH_RECOVERY_OK\\n"; systemctl is-active xochitl.service'
```

The first line must be `SSH_RECOVERY_OK`. Record Xochitl's initial state.

## 5. Record a stock-UI latency baseline

In the stock notebook UI, write exactly:

```text
testing native ink
```

Then draw five fast loops, five diagonals, erase across three strokes, and Undo
once. Record 240-fps-or-faster video when available. Record perceived latency,
missing points, ghosting, per-letter flashing, palm behavior, CPU/temperature
impression, and firmware shown in Settings. Optical latency comes from the
video; do not substitute submission timestamps.

## 6. Launch QTFB fallback mode

Open AppLoad and select **Paper Pro Reader Native Benchmark (QTFB)**. AppLoad
must launch it because it supplies `QTFB_KEY` and the QTFB socket; invoking the
fallback script directly outside AppLoad is intentionally unsupported.

On the visible benchmark, confirm the backend indicator reads `QTFB FALLBACK`.
Write `testing native ink`, use the controls, then Exit. If launch fails, return
to stock UI and collect the AppLoad/Xovi log without changing their versions.

## 7. Prepare and launch takeover mode

Build Quill v0.1.0 from commit
`39262ee0bef69915e3ead3ac218d5973916f422a` against the matching device/SDK as
its upstream instructions require. Supply only the resulting open-source
adapter and commit marker to this device:

```sh
ssh root@"$PPR_DEVICE" 'mkdir -p /home/root/.local/lib/paper-pro-reader'
scp <USER_BUILT_LIBQUILL_SO> root@"$PPR_DEVICE":/home/root/.local/lib/paper-pro-reader/libquill.so
ssh root@"$PPR_DEVICE" 'printf "%s\\n" 39262ee0bef69915e3ead3ac218d5973916f422a > /home/root/.local/lib/paper-pro-reader/quill.commit'
```

Do not upload `libqsgepaper.so`; the default path uses the copy already on the
device. With the second SSH terminal still connected, launch:

```sh
ssh root@"$PPR_DEVICE" '/home/root/xovi/exthome/appload/paper-pro-reader-native/scripts/launch-takeover.sh'
```

The screen must show `QUILL DIRECT`. If initialization fails, do not retry
until `systemctl is-active xochitl.service` reports `active`.

## 8. Write the same phrase

In takeover mode, use Pen and write exactly:

```text
testing native ink
```

Record the same camera angle/frame rate as the stock baseline. Do not compare
different writing speeds or phrases.

## 9. Test palm behavior

Rest the palm before the Marker touches, then write while keeping the palm on
the page. PASS requires no page action, no touch-generated line, no control
activation, no interruption, and no missing Marker samples. Page-area finger
touches must remain consumed.

## 10. Draw fast loops and diagonals

Draw five connected loops, five fast diagonals, and one slow edge-to-edge line.
Record visible following latency, gaps, clipping, ring-overrun failure, panel
artifacts, and whether presentation waits for pen lift.

## 11. Erase continuously

Create at least five strokes. Start one physical eraser contact and sweep
continuously across at least three strokes. PASS requires each intersected
stroke to disappear during the same contact without tapping repeatedly.

## 12. Use Undo

Tap Undo once. The one eraser gesture must restore all strokes erased by that
gesture as one group. Then draw one new stroke and Undo once; only that stroke
must disappear.

## 13. Check refresh quality

During normal-speed letters, record whether there is per-letter quality
flashing, incomplete live ink, persistent ghosting, or a full-screen update.
One bounded quality cleanup after writing becomes idle is expected. A
full-screen quality update while the Marker is down is FAIL.

## 14. Check CPU and memory

From the recovery SSH terminal while the benchmark is active:

```sh
ssh root@"$PPR_DEVICE" 'pid=$(pidof paper-pro-reader-benchmark); test -n "$pid"; ps -o pid,stat,%cpu,rss,vsz,etime,comm -p "$pid"; cat /proc/"$pid"/status | grep -E "^(VmPeak|VmHWM|Threads):"'
```

Record the output. It contains process metrics, not stroke content.

## 15. Intentionally terminate the process

Do this only with the recovery SSH terminal still working:

```sh
ssh root@"$PPR_DEVICE" 'systemctl kill --signal=TERM paper-pro-reader-benchmark.service'
```

Do not manually start Xochitl yet; the recovery paths must do it.

## 16. Confirm automatic Xochitl restoration

```sh
ssh root@"$PPR_DEVICE" 'for i in 1 2 3 4 5 6 7 8 9 10; do systemctl is-active --quiet xochitl.service && { echo XOCHITL_RESTORED; exit 0; }; sleep 1; done; echo XOCHITL_NOT_RESTORED; exit 1'
```

PASS requires `XOCHITL_RESTORED` without running the restoration script by
hand. If it fails, use the forced recovery command immediately:

```sh
ssh root@"$PPR_DEVICE" '/run/paper-pro-reader-native/restore-xochitl.sh || /home/root/xovi/exthome/appload/paper-pro-reader-native/scripts/restore-xochitl.sh'
```

## 17. Exit normally

Relaunch takeover, then tap the on-screen Exit control. Also test the documented
five-finger 1.5-second emergency hold once. After each exit, repeat the Xochitl
restoration command from step 16.

## 18. Confirm stock UI operation

In stock UI, open a notebook, make one finger gesture, write one Marker line,
erase it, and lock/unlock the device. Record any input, display, frontlight,
suspend, or color issue. This is separate from merely seeing Xochitl active.

## 19. Gather the privacy-safe report

```sh
scp root@"$PPR_DEVICE":/home/root/.local/state/paper-pro-reader-native/benchmark.jsonl .
grep -E 'marker_samples_received|dropped_sample_count|display_submissions|xochitl_restoration_succeeded' benchmark.jsonl
```

The report must not contain coordinates, stroke shapes, handwriting images,
book content, questions, answers, credentials, or personal paths. A nonzero
`dropped_sample_count` invalidates the latency run.

## 20. Uninstall and restore the previous environment

The uninstall is recoverable: it moves rather than deletes the candidate.

```sh
ssh root@"$PPR_DEVICE" '/home/root/xovi/exthome/appload/paper-pro-reader-native/scripts/uninstall.sh'
ssh root@"$PPR_DEVICE" 'systemctl is-active xochitl.service; ls -d /home/root/paper-pro-reader-native-uninstalled-* 2>/dev/null | tail -1'
```

If an earlier native benchmark directory was backed up in step 3, restore it
only after confirming the moved candidate path and stock UI operation:

```sh
ssh root@"$PPR_DEVICE"
ls -d /home/root/paper-pro-reader-native-before-*
mv <EXACT_BACKUP_PATH> /home/root/xovi/exthome/appload/paper-pro-reader-native
exit
```

Do not remove Xovi, AppLoad, QTFB, KOReader, RC5, dictionaries, books, or user
data as part of this benchmark uninstall.

## Structured result template

Use only `PASS`, `FAIL`, or `INCONCLUSIVE` and attach the evidence identifier.

| Gate | Result | Evidence / notes |
| --- | --- | --- |
| Archive checksum and AArch64 ELF |  |  |
| No proprietary blob/book/credential in archive |  |  |
| SSH recovery available |  |  |
| Stock phrase/loops baseline |  |  |
| QTFB fallback launch/exit |  |  |
| Takeover launch/backend indicator |  |  |
| Visible Marker latency |  |  |
| No pen-lift-only rendering |  |  |
| Dirty-region/ghosting quality |  |  |
| Palm rejection before/during writing |  |  |
| Touch/Marker concurrency |  |  |
| Pressure behavior |  |  |
| Continuous eraser |  |  |
| One-gesture Undo grouping |  |  |
| Ring dropped-sample count = 0 |  |  |
| CPU/peak RSS |  |  |
| SIGTERM automatic restoration |  |  |
| Normal-exit automatic restoration |  |  |
| Five-finger emergency restoration |  |  |
| Stock UI input/display after restore |  |  |
| Suspend/resume |  |  |
| Battery/heat observation |  |  |
| Firmware 3.27.3.0 compatibility |  |  |

Do not begin EPUB migration until the physical results are reviewed and the
display/input/recovery gate is explicitly accepted.
