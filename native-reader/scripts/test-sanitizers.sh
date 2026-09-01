#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
(
    cd "$root"
    cmake --preset host-sanitized
    cmake --build --preset host-sanitized
)
if [[ $(uname -s) == Darwin ]]; then
    ASAN_OPTIONS=detect_leaks=0:strict_string_checks=1 \
        UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1 \
        ctest --test-dir "$root/build/host-sanitized" --output-on-failure
else
    ASAN_OPTIONS=detect_leaks=1:strict_string_checks=1 \
        UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1 \
        ctest --test-dir "$root/build/host-sanitized" --output-on-failure
fi
