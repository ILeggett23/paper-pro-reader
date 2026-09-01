#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(git -C "$root" rev-parse --show-toplevel)
build_dir=${PPR_BUILD_DIR:-$root/build/ferrari-release}
artifact_dir=${PPR_ARTIFACT_DIR:-$root/artifacts}
binary=$build_dir/paper-pro-reader-benchmark
version=$(tr -d '[:space:]' < "$root/BUILD-VERSION.txt")
commit=$(git -C "$repo_root" rev-parse HEAD)
short_commit=${commit:0:12}
source_date_epoch=${SOURCE_DATE_EPOCH:-$(git -C "$repo_root" show -s --format=%ct HEAD)}

[[ $(uname -s) == Linux ]] || { printf '%s\n' "Deterministic device packaging requires Linux/GNU tar." >&2; exit 2; }
for command_name in file readelf sha256sum tar; do
    command -v "$command_name" >/dev/null || { printf 'Missing package tool: %s\n' "$command_name" >&2; exit 2; }
done
[[ -x $binary ]] || { printf '%s\n' "Cross-built benchmark executable is missing" >&2; exit 2; }
file "$binary" | grep -E 'ELF 64-bit.*(ARM aarch64|ARM64|aarch64)'
readelf -h "$binary" | grep -E 'Machine:.*AArch64'

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
package_root=$stage/paper-pro-reader-native
install -d -m 0755 "$package_root/bin" "$package_root/scripts" \
    "$package_root/systemd" "$package_root/licenses"
install -m 0755 "$binary" "$package_root/bin/paper-pro-reader-benchmark"
for script in launch-takeover.sh run-takeover-session.sh restore-xochitl.sh \
    launch-qtfb.sh uninstall.sh; do
    install -m 0755 "$root/scripts/$script" "$package_root/scripts/$script"
done
install -m 0644 "$root/platform/paperpro/lifecycle/systemd/paper-pro-reader-benchmark.service" \
    "$package_root/systemd/paper-pro-reader-benchmark.service"
install -m 0644 "$root/platform/paperpro/lifecycle/systemd/paper-pro-reader-recovery.service" \
    "$package_root/systemd/paper-pro-reader-recovery.service"
install -m 0644 "$root/platform/paperpro/lifecycle/external.manifest.json" \
    "$package_root/external.manifest.json"
install -m 0644 "$root/BUILD-VERSION.txt" "$package_root/BUILD-VERSION.txt"
install -m 0644 "$root/DEPENDENCIES.json" "$package_root/DEPENDENCIES.json"
install -m 0644 "$repo_root/COPYING" "$package_root/licenses/AGPL-3.0.txt"
install -m 0644 "$root/third_party/quill/LICENSE" "$package_root/licenses/QUILL-MIT.txt"
printf '{"schema_version":1,"repository":"https://github.com/ILeggett23/paper-pro-reader","branch":"native-reader-v2-spike","commit":"%s","license":"AGPL-3.0-only"}\n' \
    "$commit" > "$package_root/SOURCE.json"

if find "$package_root" -type f \( -name '*.so' -o -name '*.epub' -o -name '*.pdf' \
    -o -name '*.rmdoc' -o -name '*.rm' \) -print -quit | grep -q .; then
    printf '%s\n' "Forbidden library or document found in device package" >&2
    exit 3
fi
if grep -R -I -E 'sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9_-]{24,}' \
    "$package_root/bin" "$package_root/scripts"; then
    printf '%s\n' "Credential-like material found in executable/runtime scripts" >&2
    exit 3
fi

(cd "$package_root" && find . -type f ! -name PACKAGE-CONTENTS.sha256 -print0 | LC_ALL=C sort -z \
    | xargs -0 sha256sum) > "$package_root/PACKAGE-CONTENTS.sha256"

mkdir -p "$artifact_dir"
artifact=$artifact_dir/paper-pro-reader-native-${version}-ferrari-aarch64-${short_commit}.tar
tar --sort=name --mtime="@$source_date_epoch" --owner=0 --group=0 --numeric-owner \
    --format=posix --pax-option=delete=atime,delete=ctime \
    -C "$stage" -cf "$artifact" paper-pro-reader-native
(
    cd "$artifact_dir"
    sha256sum "$(basename "$artifact")" > "$(basename "$artifact").sha256"
)
tar -tf "$artifact" > "$artifact.contents.txt"
printf 'artifact=%s\nsha256=%s\n' "$artifact" "$(awk '{print $1}' "$artifact.sha256")"
