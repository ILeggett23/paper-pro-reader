#!/bin/sh
set -u

run_dir=${PPR_RUN_DIR:-/run/paper-pro-reader-native}
if [ -r "$run_dir/session.env" ]; then
    # shellcheck disable=SC1090
    . "$run_dir/session.env"
fi

install_root=${PPR_INSTALL_ROOT:-/home/root/xovi/exthome/appload/paper-pro-reader-native}
systemctl_bin=${PPR_SYSTEMCTL:-systemctl}
report_path=${PPR_BENCHMARK_REPORT:-/home/root/.local/state/paper-pro-reader-native/benchmark-takeover.jsonl}
state_file="$run_dir/session.state"
wake_unlock=${PPR_WAKE_UNLOCK:-/sys/power/wake_unlock}
restored=true
context=${1:-manual}

# A manual/recovery request unconditionally stops the supervised unit. This is
# harmless when inactive and also covers Type=notify's pre-READY "activating"
# window. ExecStopPost invokes this script with --stop-hook after owned
# processes are gone.
if [ "$context" != --stop-hook ]; then
    "$systemctl_bin" stop paper-pro-reader-benchmark.service || true
    if "$systemctl_bin" is-active --quiet paper-pro-reader-benchmark.service; then
        printf '%s\n' "benchmark service did not stop; refusing parallel xochitl" >&2
        exit 1
    fi
fi

# Refuse to remove the vendor lock or start xochitl beside an unowned stray
# benchmark process. Validate /proc executable identity rather than the Linux
# 15-character comm name.
for process_exe in /proc/[0-9]*/exe; do
    [ -e "$process_exe" ] || continue
    process_target=$(readlink "$process_exe" 2>/dev/null || true)
    case "$process_target" in
        */paper-pro-reader-benchmark|*/paper-pro-reader-benchmark\ \(deleted\))
            printf '%s\n' "benchmark process is still running; refusing parallel xochitl" >&2
            exit 1
            ;;
    esac
done

mkdir -p "$run_dir"
lock_dir="$run_dir/restore.lock"
lock_acquired=false
attempts=0
while [ "$attempts" -lt 40 ]; do
    if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "$lock_dir/owner.pid"
        lock_acquired=true
        break
    fi
    attempts=$((attempts + 1))
    owner_pid=$(sed -n '1p' "$lock_dir/owner.pid" 2>/dev/null || true)
    case "$owner_pid" in
        ''|*[!0-9]*)
            # Recover an empty lock left by a process killed between mkdir and
            # owner recording. rmdir cannot remove a live non-empty lock.
            [ "$attempts" -gt 1 ] && rmdir "$lock_dir" 2>/dev/null || true
            ;;
        *)
            if ! kill -0 "$owner_pid" 2>/dev/null; then
                rm -f "$lock_dir/owner.pid"
                rmdir "$lock_dir" 2>/dev/null || true
            fi
            ;;
    esac
    [ "$lock_acquired" = true ] || sleep 0.25
done
if [ "$lock_acquired" != true ]; then
    if "$systemctl_bin" is-active --quiet xochitl.service; then exit 0; fi
    printf '%s\n' "xochitl restoration lock could not be acquired" >&2
    exit 1
fi
trap 'rm -f "$lock_dir/owner.pid"; rmdir "$lock_dir" 2>/dev/null || true' EXIT

xochitl_already_active=false
if "$systemctl_bin" is-active --quiet xochitl.service; then
    xochitl_already_active=true
fi

if [ -w "$wake_unlock" ]; then
    printf '%s\n' paper-pro-reader-native > "$wake_unlock" 2>/dev/null || true
fi

if [ "$xochitl_already_active" != true ]; then
    rm -f "${PPR_EPFRAMEBUFFER_LOCK:-/tmp/epframebuffer.lock}"
fi

xochitl_was_active=1
if [ -r "$state_file" ]; then
    # Contains one launcher-owned numeric assignment only.
    # shellcheck disable=SC1090
    . "$state_file"
fi
if [ "$xochitl_was_active" = 1 ] && ! "$systemctl_bin" is-active --quiet xochitl.service; then
    "$systemctl_bin" start xochitl.service || restored=false
fi

if [ "$xochitl_was_active" = 1 ]; then
    attempts=0
    while ! "$systemctl_bin" is-active --quiet xochitl.service; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 20 ]; then
            restored=false
            break
        fi
        sleep 0.25
    done
fi

if [ ! -e "$run_dir/restoration.reported" ]; then
    if [ -x "$install_root/bin/paper-pro-reader-benchmark" ] && [ -e "$report_path" ]; then
        "$install_root/bin/paper-pro-reader-benchmark" \
            --append-restoration "$report_path" "$restored" >/dev/null 2>&1 || true
    fi
    : > "$run_dir/restoration.reported"
fi

if [ "$restored" = true ]; then
    rm -f "$state_file"
    printf '%s\n' "xochitl restoration: PASS"
    exit 0
fi
printf '%s\n' "xochitl restoration: FAIL; use SSH and run systemctl start xochitl.service" >&2
exit 1
