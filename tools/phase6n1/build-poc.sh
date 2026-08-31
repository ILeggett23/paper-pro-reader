#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    echo "Phase 6N-1 target build requires Linux" >&2
    exit 2
fi

for command_name in aarch64-remarkable-linux-gnu-gcc aarch64-remarkable-linux-gnu-g++ readelf sha256sum tar; do
    command -v "$command_name" >/dev/null || {
        echo "missing required tool: $command_name" >&2
        exit 3
    }
done

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
artifact_dir="$repo_dir/artifacts/phase6n1"
mkdir -p "$artifact_dir"

cd "$repo_dir"
./kodev test front \
    spec/unit/paperpro_nativebridge_spec.lua \
    spec/unit/paperpro_inkservice_spec.lua \
    spec/unit/paperproreader_spec.lua
./kodev test front
./kodev release --ignore-translation remarkable-aarch64 txz

source_archive=$(find . -maxdepth 1 -type f -name 'koreader-remarkable-aarch64-*.tar.xz' -print -quit)
test -n "$source_archive"
short_sha=$(git rev-parse --short=12 HEAD)
artifact="$artifact_dir/paper-pro-reader-phase6n1-poc-${short_sha}.tar.xz"
cp "$source_archive" "$artifact"
sha256sum "$artifact" >"$artifact.sha256"

package_dir=$(mktemp -d)
trap 'rm -rf "$package_dir"' EXIT
tar -xJf "$artifact" -C "$package_dir"
root="$package_dir/koreader"
test -x "$root/luajit"
test -x "$root/reader.lua"
test -r "$root/external.manifest.json"
python3 -m json.tool "$root/external.manifest.json" >/dev/null
grep -q '"nativeInk"[[:space:]]*:[[:space:]]*true' "$root/external.manifest.json"
grep -q '"KO_NATIVE_INK"[[:space:]]*:[[:space:]]*"1"' "$root/external.manifest.json"
readelf -h "$root/luajit" | grep -E 'Class:.*ELF64'
readelf -h "$root/luajit" | grep -E 'Machine:.*AArch64'
tar -tJf "$artifact" >"$artifact.contents.txt"

printf 'artifact=%s\n' "$artifact"
printf 'checksum=%s\n' "$(cut -d' ' -f1 "$artifact.sha256")"
