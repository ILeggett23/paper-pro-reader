#!/bin/sh
set -eu

run_dir=${PPR_RUN_DIR:-/run/paper-pro-reader-native}
if [ -r "$run_dir/session.env" ]; then
    # File is created mode 0600 by launch-takeover.sh from validated paths.
    # shellcheck disable=SC1090
    . "$run_dir/session.env"
fi

install_root=${PPR_INSTALL_ROOT:-/home/root/xovi/exthome/appload/paper-pro-reader-native}
systemctl_bin=${PPR_SYSTEMCTL:-systemctl}
report_path=${PPR_BENCHMARK_REPORT:-/home/root/.local/state/paper-pro-reader-native/benchmark.jsonl}
quill_library=${PPR_QUILL_LIBRARY:-/home/root/.local/lib/paper-pro-reader/libquill.so}
quill_commit_file=${PPR_QUILL_COMMIT_FILE:-/home/root/.local/lib/paper-pro-reader/quill.commit}
vendor_library=${PPR_VENDOR_LIBRARY_PATH:-/usr/lib/plugins/scenegraph/libqsgepaper.so}
state_file="$run_dir/session.state"
wake_lock=${PPR_WAKE_LOCK:-/sys/power/wake_lock}

trap 'exit 130' INT
trap 'exit 143' TERM

umask 077
mkdir -p "$run_dir" "$(dirname "$report_path")"
if "$systemctl_bin" is-active --quiet xochitl.service; then
    printf 'xochitl_was_active=1\n' > "$state_file"
    "$systemctl_bin" stop xochitl.service
else
    printf 'xochitl_was_active=0\n' > "$state_file"
fi
if "$systemctl_bin" is-active --quiet xochitl.service; then
    printf '%s\n' "xochitl did not stop; refusing display acquisition" >&2
    exit 20
fi

# Quill's reviewed recovery procedure removes only this volatile singleton lock,
# and only after xochitl is confirmed inactive.
rm -f "${PPR_EPFRAMEBUFFER_LOCK:-/tmp/epframebuffer.lock}"
if [ -w "$wake_lock" ]; then
    printf '%s\n' paper-pro-reader-native > "$wake_lock"
fi

vendor_library_dir=$(dirname "$vendor_library")
export LD_LIBRARY_PATH="$vendor_library_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$install_root/bin/paper-pro-reader-benchmark" \
    --backend takeover \
    --quill-library "$quill_library" \
    --quill-commit-file "$quill_commit_file" \
    --report "$report_path"
