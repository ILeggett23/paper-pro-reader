# Takeover recovery model

## Safety objective

Xochitl is the device's authoritative stock interface. Direct takeover is a
temporary, reversible session; the benchmark never permanently replaces or
patches Xochitl. A successful session ends with Xochitl active, the benchmark
stopped, temporary wake-lock/state files cleared, and USB SSH still available.

Reliability takes priority over starting the benchmark. Any uncertainty before
display ownership causes refusal. Any uncertainty after Xochitl has been
stopped causes restoration and a non-zero exit.

## Recovery actors

Three independent actors cooperate:

1. `scripts/launch-takeover.sh` performs guarded preflight, records state, arms
   recovery, stops Xochitl, launches the benchmark, and handles normal shell and
   catchable signal paths.
2. The native process handles its on-screen Exit control and emergency gesture,
   cancels refresh work, releases the display backend, records a privacy-safe
   shutdown reason, and exits. It does not claim authority to restore Xochitl
   by itself.
3. A systemd service/recovery unit runs the idempotent
   `scripts/restore-xochitl.sh` from `ExecStopPost` or an equivalent independent
   failure path. Its operation does not depend on the benchmark event loop or
   shell trap surviving.

The restoration script is the single restoration implementation used by all
three paths. Repeated calls are harmless.

The package lives under
`/home/root/xovi/exthome/appload/paper-pro-reader-native`. Takeover state and ownership
locks live under `/run/paper-pro-reader-native`; transient service files live
under `/run/systemd/system`. Installation does not write a persistent unit to
`/etc`, remount the immutable root, or enable takeover at boot. The privacy-safe
benchmark report is
`/home/root/.local/state/paper-pro-reader-native/benchmark.jsonl`.

## State machine

```text
STOCK
  -> PREFLIGHTED       model, firmware policy, SSH, services, files, input,
                       space, battery and library prerequisites validated
  -> RECOVERY_ARMED    restrictive volatile state recorded; independent unit ready
  -> XOCHITL_STOPPED   stop confirmed; SSH untouched
  -> DISPLAY_READY     Quill symbols/geometry/buffer/format validated
  -> RUNNING           benchmark owns the temporary display session
  -> QUIESCING         input stopped; refresh scheduler cancelled; report closed
  -> RESTORING         display released; restoration script running
  -> STOCK             Xochitl active and recovery state cleared
```

Transitions only move forward except restoration, which may be entered from
any state after `RECOVERY_ARMED`. Session state is recorded under the volatile
`/run/paper-pro-reader-native` directory with restrictive permissions before
Xochitl is stopped; it cannot make takeover persistent across reboot.
It contains service/backend/version/status facts only, never coordinates,
strokes, book content, credentials, or personal paths.

## Preflight and refusal rules

Before stopping Xochitl, the launcher must verify all of the following:

- effective user is root and the model string is the supported Paper Pro
  (`reMarkable Ferrari`);
- firmware is explicitly allowed for this experimental build; known
  3.27.3.0 is still device-test required, not an automatic pass;
- the stock Xochitl unit exists and its pre-launch active state is recorded;
- USB SSH access has been confirmed by the operator for this test session;
- the recovery service/unit and restoration script exist, are executable, and
  pass a dry preflight;
- no other takeover session or stale ownership lock is active;
- the user-supplied Quill and device-local vendor-library paths are regular,
  readable files containing only safe path characters; their exact commit
  marker and optional operator-provided SHA-256 values match;
- Marker and touch candidates can be discovered by capability and their ABS
  ranges are sane;
- writable storage exists for the bounded report/state file;
- battery/charging status satisfies the configured safety threshold; and
- the requested backend and rotation are explicit.

Preflight must not restart, upgrade, or reinstall Xovi, AppLoad, QTFB, or
Xochitl. It does not remount the immutable root filesystem. If a condition is
not met, the launcher leaves Xochitl untouched and returns an actionable error.

## Normal exit

On the Exit control or documented emergency gesture:

1. stop accepting new input frames;
2. cancel idle cleanup and pending scheduler work;
3. cancel pending scheduler work; the backend-specific outstanding logical
   update is abandoned as part of process teardown rather than blocking exit;
4. close the display backend and release its buffer/resources;
5. release the named wake lock if this session acquired it;
6. serialize only privacy-safe final metrics and shutdown reason;
7. exit the benchmark;
8. run idempotent restoration through the launcher and systemd stop path;
9. start Xochitl only if it is not already active, then wait with a bounded
   timeout for `active`; and
10. clear the takeover state/lock only after restoration is confirmed.

The on-screen Exit and emergency gesture are application mechanisms. SSH
restoration remains available if neither receives input.

## Process crash or forced termination

The benchmark may be unable to clean up after `SIGSEGV`, `SIGABRT`, out-of-
memory termination, or `SIGKILL`. Recovery must therefore not rely on native
signal handlers. systemd observes the service exit, runs the stop/failure path,
and invokes `restore-xochitl.sh`. The launcher waiting on the process also calls
the same script as a second idempotent attempt.

`SIGINT` and `SIGTERM` request orderly native shutdown but are subject to a
bounded timeout. If the process does not exit, systemd termination proceeds and
the independent restoration path still runs. The forced-termination device
test is mandatory; host mocks are insufficient.

## Shell termination or lost SSH session

Closing the initiating shell, losing Wi-Fi, or dropping an SSH connection must
not determine recovery. The takeover process is run as a supervised systemd
service (or equivalent detached supervisor), not as an unsupervised child tied
to the terminal. The launcher's shell traps are defense in depth only.

USB SSH must remain enabled and unmodified. The launcher never stops networking,
SSH, or the USB gadget service. A lost client connection does not cancel the
independent watchdog.

## Display initialization failure

Quill initialization occurs only after recovery has been armed. Failure to
load any required symbol, resolve the device-local vendor implementation,
obtain the expected 1620 x 2160 buffer, validate stride/format, or select an
unambiguous writable surface results in:

1. no rendering attempt;
2. immediate backend close for any partially initialized resources;
3. Xochitl restoration;
4. a non-zero exit with a privacy-safe error category; and
5. retention of the state record if restoration cannot be confirmed.

The launcher does not silently fall through to QTFB after stopping Xochitl.
Fallback is launched separately from the restored stock environment.

## Unsupported firmware or model

An unsupported model or firmware is a preflight refusal, not a warning. Direct
mode does not stop Xochitl. The operator may use the explicit QTFB/AppLoad
fallback if that installed environment supports the firmware, but fallback
success does not authorize direct mode. Supporting a new firmware tuple
requires dependency/symbol inventory plus the full physical qualification.

## Suspend and resume

Direct mode must hold the supported kernel wake lock for the whole display
ownership interval because a suspend/resume can start or expose a competing
Xochitl process. If the wake lock cannot be acquired, takeover refuses to
start. If a suspend signal is nevertheless observed:

- stop accepting input and cancel new refresh work;
- flush only already-prepared privacy-safe metrics outside the hot path;
- release the display;
- restore Xochitl; and
- exit rather than trying to resume display ownership in place.

Resume-in-takeover is deferred until it has a separate lifecycle design and
physical qualification. The stock UI remains responsible for normal suspend.

## Low battery and power loss

The launcher checks a conservative configurable battery threshold and may
allow a lower value only while external power is confirmed. During a session,
a low-battery event requests the same orderly exit as the on-screen control.
Input-to-display processing remains prioritized until shutdown begins; no
synchronous battery logging enters the Marker path.

No userspace mechanism can guarantee restoration after abrupt power loss.
After reboot, the service must default to stock Xochitl and must not
automatically re-enter takeover. A stale takeover state causes one restoration
attempt and an audit message, not an automatic benchmark restart.

## Watchdog behavior

The supervisor's job is recovery, not aggressive restart. It may monitor that
the process remains alive and that bounded heartbeats continue, but it never
restarts the benchmark automatically. On timeout it stops the benchmark,
invokes restoration, and leaves the device in stock mode.

The watchdog timeout must be long enough that a slow but valid display update
does not cause a restart loop. It must not interpret a missing Marker event as
failure. Heartbeats contain sequence/time/status only, never input content.

## SSH recovery

Before every direct test, the operator verifies a second USB SSH session. If
the screen is unusable, set `PPR_DEVICE` to the address recorded in the device
qualification procedure and run the package's restoration script from that session:

```sh
ssh root@"$PPR_DEVICE" '/home/root/xovi/exthome/appload/paper-pro-reader-native/scripts/restore-xochitl.sh'
```

If installed at a different reviewed location, substitute that exact absolute
installation root; do not execute an unverified copy from `/tmp`. The script
must be safe to run when the benchmark never started, when Xochitl is already
active, and after a prior restoration attempt.

If the wrapper is unavailable but SSH works, the bounded manual recovery is:

```sh
ssh root@"$PPR_DEVICE" 'systemctl start xochitl.service'
ssh root@"$PPR_DEVICE" 'systemctl is-active xochitl.service'
```

Use the actual unit discovered and recorded by preflight if the firmware names
it differently. Do not kill unrelated processes or reboot as the first
recovery step.

## Forced restoration algorithm

`restore-xochitl.sh` follows this idempotent order:

1. obtain a restoration lock with a bounded wait;
2. read the minimal takeover state if present;
3. request benchmark service stop only when it is still active and the caller
   is not already its stop hook;
4. release only the named wake lock recorded for this application;
5. avoid killing arbitrary PIDs from stale files; validate executable and
   service identity first;
6. start Xochitl only when inactive;
7. wait a bounded time for active state;
8. write restoration success/failure without secrets or user content;
9. retain failure state for SSH diagnosis, or atomically clear successful
   takeover ownership; and
10. release the lock and return non-zero if stock operation is not confirmed.

Calling this algorithm twice yields the same stock state. A running Xochitl is
not restarted merely to make logs look clean.

## QTFB fallback recovery

QTFB/AppLoad mode does not stop Xochitl, install ecosystem updates, or acquire
direct panel ownership. Normal Exit asks AppLoad to close the app and returns
to its stock-hosted surface. If the app crashes, AppLoad/Xochitl remains the
recovery authority. The native package's Xochitl restoration script may still
be used as an emergency check, but fallback must not stop a healthy stock UI.

Fallback and takeover reports use distinct backend identifiers so recovery and
latency results cannot be conflated.

## Uninstall and post-update behavior

Uninstall first invokes restoration, confirms Xochitl active, disables/removes
only the benchmark's own service units and application directory, reloads
systemd, and leaves Xovi, AppLoad, QTFB, KOReader, user documents, and firmware
untouched. It does not disable Developer Mode.

After any firmware update, the direct-mode support record is invalid until
requalified. The package must default to refusal and stock UI. It must not
patch the new firmware or automatically rebuild Xovi resources.

## Qualification requirements

Recovery is not `PASS` until physical tests demonstrate:

- normal Exit restores a responsive stock UI;
- emergency gesture restores a responsive stock UI;
- `SIGTERM` restores Xochitl;
- forced process kill restores Xochitl through the independent path;
- a deliberately invalid Quill/vendor path fails after guarded startup and
  restores Xochitl;
- repeated restoration is harmless;
- a stale state after reboot does not relaunch takeover;
- USB SSH stays reachable during failure; and
- no test changes the user's Xovi/AppLoad versions or KOReader installation.

Until those results are supplied, lifecycle status is **DEVICE TEST REQUIRED**.
