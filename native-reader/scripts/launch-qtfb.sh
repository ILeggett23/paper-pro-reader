#!/bin/sh
set -eu

install_root=${PPR_INSTALL_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
report_path=${PPR_BENCHMARK_REPORT:-/home/root/.local/state/paper-pro-reader-native/benchmark.jsonl}
machine_file=${PPR_MACHINE_FILE:-/sys/devices/soc0/machine}

[ -r "$machine_file" ] || { printf '%s\n' "Paper Pro model file missing" >&2; exit 1; }
[ "$(sed -n '1p' "$machine_file")" = "reMarkable Ferrari" ] \
    || { printf '%s\n' "QTFB benchmark supports reMarkable Ferrari only" >&2; exit 1; }
mkdir -p "$(dirname "$report_path")"
exec "$install_root/bin/paper-pro-reader-benchmark" \
    --backend qtfb --report "$report_path" "$@"
