#!/bin/sh
set -eu

required_commit=39262ee0bef69915e3ead3ac218d5973916f422a
install_root=${PPR_INSTALL_ROOT:-/home/root/xovi/exthome/appload/paper-pro-reader-native}
run_dir=${PPR_RUN_DIR:-/run/paper-pro-reader-native}
systemd_runtime_dir=${PPR_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}
machine_file=${PPR_MACHINE_FILE:-/sys/devices/soc0/machine}
os_release_file=${PPR_OS_RELEASE_FILE:-/etc/os-release}
systemctl_bin=${PPR_SYSTEMCTL:-systemctl}
quill_library=${PPR_QUILL_LIBRARY:-/home/root/.local/lib/paper-pro-reader/libquill.so}
quill_commit_file=${PPR_QUILL_COMMIT_FILE:-/home/root/.local/lib/paper-pro-reader/quill.commit}
vendor_library=${PPR_VENDOR_LIBRARY_PATH:-/usr/lib/plugins/scenegraph/libqsgepaper.so}
report_path=${PPR_BENCHMARK_REPORT:-/home/root/.local/state/paper-pro-reader-native/benchmark-takeover.jsonl}
wake_lock=${PPR_WAKE_LOCK:-/sys/power/wake_lock}
wake_unlock=${PPR_WAKE_UNLOCK:-/sys/power/wake_unlock}
epframebuffer_lock=${PPR_EPFRAMEBUFFER_LOCK:-/tmp/epframebuffer.lock}
battery_capacity_file=${PPR_BATTERY_CAPACITY_FILE:-/sys/class/power_supply/max1726x_battery/capacity}
battery_status_file=${PPR_BATTERY_STATUS_FILE:-/sys/class/power_supply/max1726x_battery/status}

fail() {
    printf '%s\n' "takeover refused: $*" >&2
    exit 1
}

for configured_path in "$install_root" "$run_dir" "$systemd_runtime_dir" \
    "$quill_library" "$quill_commit_file" "$vendor_library" "$report_path" "$systemctl_bin" \
    "$wake_lock" "$wake_unlock" "$epframebuffer_lock" "$battery_capacity_file" "$battery_status_file"; do
    case "$configured_path" in
        *[!A-Za-z0-9_./:-]*) fail "runtime paths may contain only safe path characters" ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    fail "run as root so systemd can restore xochitl"
fi
[ -n "${SSH_CONNECTION:-}" ] || [ "${PPR_SSH_RECOVERY_CONFIRMED:-0}" = 1 ] \
    || fail "confirm a working recovery SSH session with PPR_SSH_RECOVERY_CONFIRMED=1"
[ -r "$machine_file" ] || fail "device model file is unavailable"
[ "$(sed -n '1p' "$machine_file")" = "reMarkable Ferrari" ] \
    || fail "supported model is exactly reMarkable Ferrari"
[ -r "$os_release_file" ] || fail "firmware metadata is unavailable"
firmware=$(awk -F= '$1 == "VERSION_ID" { gsub(/"/, "", $2); print $2; exit }' "$os_release_file")
case "$firmware" in
    3.27.3.0) ;;
    *) fail "direct takeover is admitted only on physically referenced firmware 3.27.3.0" ;;
esac

[ -x "$install_root/bin/paper-pro-reader-benchmark" ] || fail "benchmark executable is missing"
[ -f "$quill_library" ] && [ -r "$quill_library" ] || fail "user-supplied libquill.so is missing"
[ -r "$quill_commit_file" ] || fail "Quill commit marker is missing"
[ -f "$vendor_library" ] && [ -r "$vendor_library" ] || fail "device-local vendor display library is missing"
[ "$(basename "$vendor_library")" = libqsgepaper.so ] \
    || fail "PPR_VENDOR_LIBRARY_PATH must identify libqsgepaper.so exactly"
[ "$(tr -d '[:space:]' < "$quill_commit_file")" = "$required_commit" ] \
    || fail "Quill commit marker is not the reviewed v0.1.0 pin"

if [ -n "${PPR_QUILL_SHA256:-}" ]; then
    command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required for PPR_QUILL_SHA256"
    actual_quill_sha=$(sha256sum "$quill_library" | awk '{print $1}')
    [ "$actual_quill_sha" = "$PPR_QUILL_SHA256" ] || fail "Quill library SHA-256 mismatch"
fi
if [ -n "${PPR_VENDOR_LIBRARY_SHA256:-}" ]; then
    command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required for vendor-library verification"
    actual_vendor_sha=$(sha256sum "$vendor_library" | awk '{print $1}')
    [ "$actual_vendor_sha" = "$PPR_VENDOR_LIBRARY_SHA256" ] \
        || fail "device-local vendor library SHA-256 mismatch"
fi

command -v "$systemctl_bin" >/dev/null 2>&1 || fail "systemctl is unavailable"
"$systemctl_bin" cat xochitl.service >/dev/null 2>&1 || fail "xochitl.service is unavailable"
"$systemctl_bin" is-active --quiet xochitl.service \
    || fail "xochitl must be active before a temporary takeover session"
[ -x "$install_root/scripts/run-takeover-session.sh" ] || fail "takeover session script is missing"
[ -x "$install_root/scripts/restore-xochitl.sh" ] || fail "recovery script is missing"
[ -r "$install_root/systemd/paper-pro-reader-benchmark.service" ] || fail "systemd benchmark unit is missing"
[ -r "$install_root/systemd/paper-pro-reader-recovery.service" ] || fail "systemd recovery unit is missing"
[ -w "$wake_lock" ] || fail "kernel wake lock is not writable"
[ -w "$wake_unlock" ] || fail "kernel wake unlock is not writable"
[ -r "$battery_capacity_file" ] || fail "battery capacity is unavailable"
battery_capacity=$(tr -dc '0-9' < "$battery_capacity_file")
battery_status=$(sed -n '1p' "$battery_status_file" 2>/dev/null || true)
case "$battery_capacity" in ''|*[!0-9]*) fail "battery capacity is invalid" ;; esac
if [ "$battery_capacity" -lt 20 ]; then
    case "$battery_status" in Charging|Full) ;; *) fail "battery must be at least 20 percent or charging" ;; esac
fi
if "$systemctl_bin" is-active --quiet paper-pro-reader-benchmark.service; then
    printf '%s\n' "Paper Pro Reader native benchmark is already running."
    exit 0
fi

for process_exe in /proc/[0-9]*/exe; do
    [ -e "$process_exe" ] || continue
    process_target=$(readlink "$process_exe" 2>/dev/null || true)
    case "$process_target" in
        */paper-pro-reader-benchmark|*/paper-pro-reader-benchmark\ \(deleted\))
            fail "a benchmark process already exists outside the supervised unit"
            ;;
    esac
done

"$install_root/bin/paper-pro-reader-benchmark" --probe-input >/dev/null \
    || fail "Marker/touch capability discovery or ABS-range validation failed"

umask 077
mkdir -p "$run_dir" "$systemd_runtime_dir" "$(dirname "$report_path")"
rm -f "$run_dir/restoration.reported" "$run_dir/session.state"
cp "$install_root/scripts/run-takeover-session.sh" "$run_dir/run-takeover-session.sh"
cp "$install_root/scripts/restore-xochitl.sh" "$run_dir/restore-xochitl.sh"
chmod 700 "$run_dir/run-takeover-session.sh" "$run_dir/restore-xochitl.sh"
cp "$install_root/systemd/paper-pro-reader-benchmark.service" \
    "$systemd_runtime_dir/paper-pro-reader-benchmark.service"
cp "$install_root/systemd/paper-pro-reader-recovery.service" \
    "$systemd_runtime_dir/paper-pro-reader-recovery.service"
chmod 600 "$systemd_runtime_dir/paper-pro-reader-benchmark.service" \
    "$systemd_runtime_dir/paper-pro-reader-recovery.service"

{
    printf 'PPR_INSTALL_ROOT=%s\n' "$install_root"
    printf 'PPR_QUILL_LIBRARY=%s\n' "$quill_library"
    printf 'PPR_QUILL_COMMIT_FILE=%s\n' "$quill_commit_file"
    printf 'PPR_VENDOR_LIBRARY_PATH=%s\n' "$vendor_library"
    printf 'PPR_BENCHMARK_REPORT=%s\n' "$report_path"
    printf 'PPR_RUN_DIR=%s\n' "$run_dir"
    printf 'PPR_SYSTEMCTL=%s\n' "$systemctl_bin"
    printf 'PPR_WAKE_LOCK=%s\n' "$wake_lock"
    printf 'PPR_WAKE_UNLOCK=%s\n' "$wake_unlock"
    printf 'PPR_EPFRAMEBUFFER_LOCK=%s\n' "$epframebuffer_lock"
} > "$run_dir/session.env"
chmod 600 "$run_dir/session.env"

"$systemctl_bin" daemon-reload
"$systemctl_bin" start paper-pro-reader-benchmark.service
printf '%s\n' "Native takeover benchmark started."
printf '%s\n' "Emergency exit: hold five fingers for 1.5 seconds, press Power, or run:"
printf '  %s stop paper-pro-reader-benchmark.service\n' "$systemctl_bin"
