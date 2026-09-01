#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if [[ $(uname -s) != Linux ]]; then
    printf '%s\n' "Ferrari target builds require a supported Linux host." >&2
    exit 2
fi
: "${PPR_FERRARI_SDK_ENV:?Set PPR_FERRARI_SDK_ENV to the official 3.27 Ferrari SDK environment-setup file}"
[[ -r "$PPR_FERRARI_SDK_ENV" ]] || { printf '%s\n' "Ferrari SDK environment file is unreadable" >&2; exit 2; }

unset LD_LIBRARY_PATH
# The selected file is the exact operator/CI-provided official SDK environment.
# shellcheck disable=SC1090
source "$PPR_FERRARI_SDK_ENV"

if [[ -z ${PPR_FERRARI_CMAKE_TOOLCHAIN_FILE:-} ]]; then
    PPR_FERRARI_CMAKE_TOOLCHAIN_FILE=${OE_CMAKE_TOOLCHAIN_FILE:-}
fi
if [[ -z ${PPR_FERRARI_CMAKE_TOOLCHAIN_FILE:-} || ! -r $PPR_FERRARI_CMAKE_TOOLCHAIN_FILE ]]; then
    printf '%s\n' "Set PPR_FERRARI_CMAKE_TOOLCHAIN_FILE to the SDK's CMake toolchain file." >&2
    exit 2
fi
export PPR_FERRARI_CMAKE_TOOLCHAIN_FILE

compiler=${CXX%% *}
command -v "$compiler" >/dev/null \
    || { printf '%s\n' "Official SDK C++ compiler is unavailable" >&2; exit 2; }
machine=$($compiler -dumpmachine)
[[ $machine == aarch64* ]] || { printf 'Unexpected Ferrari compiler target: %s\n' "$machine" >&2; exit 2; }

(
    cd "$root"
    cmake --preset ferrari-release
    cmake --build --preset ferrari-release
)
file "$root/build/ferrari-release/paper-pro-reader-benchmark" | grep -E 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)'
