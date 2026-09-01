#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
(
    cd "$root"
    cmake --preset host-debug
    cmake --build --preset host-debug
    ctest --preset host-debug --output-on-failure
)
"$root/scripts/test-lifecycle.sh"
"$root/scripts/secret-and-content-scan.sh"
