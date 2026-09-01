#!/bin/sh
set -eu

install_root=${PPR_INSTALL_ROOT:-/home/root/xovi/exthome/appload/paper-pro-reader-native}
run_dir=${PPR_RUN_DIR:-/run/paper-pro-reader-native}
systemd_runtime_dir=${PPR_SYSTEMD_RUNTIME_DIR:-/run/systemd/system}
systemctl_bin=${PPR_SYSTEMCTL:-systemctl}

if "$systemctl_bin" is-active --quiet paper-pro-reader-benchmark.service; then
    "$systemctl_bin" stop paper-pro-reader-benchmark.service
fi
if [ -x "$run_dir/restore-xochitl.sh" ]; then
    "$run_dir/restore-xochitl.sh"
fi
"$systemctl_bin" is-active --quiet xochitl.service \
    || { printf '%s\n' "xochitl is not active; uninstall stopped for SSH recovery" >&2; exit 1; }
rm -f "$systemd_runtime_dir/paper-pro-reader-benchmark.service" \
    "$systemd_runtime_dir/paper-pro-reader-recovery.service"
"$systemctl_bin" daemon-reload

if [ -d "$install_root" ]; then
    destination="/home/root/paper-pro-reader-native-uninstalled-$(date +%Y%m%d-%H%M%S)"
    mv "$install_root" "$destination"
    printf 'Moved the benchmark to %s (recoverable; not deleted).\n' "$destination"
fi
rm -f "$run_dir/session.env" "$run_dir/session.state" "$run_dir/restoration.reported" \
    "$run_dir/run-takeover-session.sh" "$run_dir/restore-xochitl.sh"
rmdir "$run_dir" 2>/dev/null || true
printf '%s\n' "xochitl is active; Xovi, AppLoad, QTFB, books, and KOReader were not changed."
