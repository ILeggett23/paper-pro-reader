#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/run" "$fixture/bin" "$fixture/sys" "$fixture/state"

apply_state=$fixture/state/xochitl
benchmark_state=$fixture/state/benchmark
printf '%s\n' inactive > "$apply_state"
printf '%s\n' inactive > "$benchmark_state"
printf '%s\n' 'xochitl_was_active=1' > "$fixture/run/session.state"
: > "$fixture/sys/wake_unlock"

printf '%s\n' '#!/bin/sh' \
    'state=${PPR_TEST_XOCHITL_STATE:?}' \
    'benchmark_state=${PPR_TEST_BENCHMARK_STATE:?}' \
    'case "$1 $2 $3" in' \
    '  "is-active --quiet xochitl.service") [ "$(cat "$state")" = active ] ;;' \
    '  "is-active --quiet paper-pro-reader-benchmark.service") [ "$(cat "$benchmark_state")" = active ] ;;' \
    '  "stop paper-pro-reader-benchmark.service ") if [ "$(cat "$benchmark_state")" = active ]; then printf "%s\\n" inactive > "$benchmark_state"; printf "%s\\n" active > "$state"; fi ;;' \
    '  "start xochitl.service ") printf "%s\\n" active > "$state" ;;' \
    '  "daemon-reload  ") exit 0 ;;' \
    '  *) exit 0 ;;' \
    'esac' > "$fixture/bin/systemctl"
chmod 755 "$fixture/bin/systemctl"

PPR_RUN_DIR="$fixture/run" \
PPR_SYSTEMCTL="$fixture/bin/systemctl" \
PPR_TEST_XOCHITL_STATE="$apply_state" \
PPR_TEST_BENCHMARK_STATE="$benchmark_state" \
PPR_WAKE_UNLOCK="$fixture/sys/wake_unlock" \
PPR_EPFRAMEBUFFER_LOCK="$fixture/run/epframebuffer.lock" \
PPR_INSTALL_ROOT="$fixture/missing-app" \
PPR_BENCHMARK_REPORT="$fixture/state/report.jsonl" \
    "$root/scripts/restore-xochitl.sh"
[[ $(<"$apply_state") == active ]]

# Restoration is deliberately idempotent.
: > "$fixture/run/epframebuffer.lock"
PPR_RUN_DIR="$fixture/run" \
PPR_SYSTEMCTL="$fixture/bin/systemctl" \
PPR_TEST_XOCHITL_STATE="$apply_state" \
PPR_TEST_BENCHMARK_STATE="$benchmark_state" \
PPR_WAKE_UNLOCK="$fixture/sys/wake_unlock" \
PPR_EPFRAMEBUFFER_LOCK="$fixture/run/epframebuffer.lock" \
PPR_INSTALL_ROOT="$fixture/missing-app" \
PPR_BENCHMARK_REPORT="$fixture/state/report.jsonl" \
    "$root/scripts/restore-xochitl.sh"
[[ $(<"$apply_state") == active ]]
[[ -e "$fixture/run/epframebuffer.lock" ]]

# Manual recovery first stops an active supervised benchmark; the fake stop
# models ExecStopPost restoring xochitl before the manual caller returns.
printf '%s\n' inactive > "$apply_state"
printf '%s\n' active > "$benchmark_state"
PPR_RUN_DIR="$fixture/run" \
PPR_SYSTEMCTL="$fixture/bin/systemctl" \
PPR_TEST_XOCHITL_STATE="$apply_state" \
PPR_TEST_BENCHMARK_STATE="$benchmark_state" \
PPR_WAKE_UNLOCK="$fixture/sys/wake_unlock" \
PPR_EPFRAMEBUFFER_LOCK="$fixture/run/epframebuffer.lock" \
PPR_INSTALL_ROOT="$fixture/missing-app" \
PPR_BENCHMARK_REPORT="$fixture/state/report.jsonl" \
    "$root/scripts/restore-xochitl.sh"
[[ $(<"$apply_state") == active ]]
[[ $(<"$benchmark_state") == inactive ]]

# A dead owner cannot permanently wedge recovery.
printf '%s\n' inactive > "$apply_state"
mkdir "$fixture/run/restore.lock"
printf '%s\n' 999999 > "$fixture/run/restore.lock/owner.pid"
PPR_RUN_DIR="$fixture/run" \
PPR_SYSTEMCTL="$fixture/bin/systemctl" \
PPR_TEST_XOCHITL_STATE="$apply_state" \
PPR_TEST_BENCHMARK_STATE="$benchmark_state" \
PPR_WAKE_UNLOCK="$fixture/sys/wake_unlock" \
PPR_EPFRAMEBUFFER_LOCK="$fixture/run/epframebuffer.lock" \
PPR_INSTALL_ROOT="$fixture/missing-app" \
PPR_BENCHMARK_REPORT="$fixture/state/report.jsonl" \
    "$root/scripts/restore-xochitl.sh"
[[ $(<"$apply_state") == active ]]
[[ ! -d "$fixture/run/restore.lock" ]]
grep -q '^Type=notify$' "$root/platform/paperpro/lifecycle/systemd/paper-pro-reader-benchmark.service"
grep -q '^WatchdogSec=10$' "$root/platform/paperpro/lifecycle/systemd/paper-pro-reader-benchmark.service"
grep -q 'ExecStopPost=.*--stop-hook$' "$root/platform/paperpro/lifecycle/systemd/paper-pro-reader-benchmark.service"
printf '%s\n' "lifecycle restoration tests: PASS"
