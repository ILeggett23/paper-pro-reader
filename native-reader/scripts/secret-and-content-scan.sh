#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
repo_root=$(git -C "$root" rev-parse --show-toplevel)
patterns='sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9_-]{24,}|(api[_-]?key|device[_-]?token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{24,}'

if git -C "$repo_root" grep -nEI "$patterns" -- native-reader \
    ':!native-reader/docs/**' ':!native-reader/tests/**' \
    ':!native-reader/scripts/secret-and-content-scan.sh'; then
    printf '%s\n' "Credential-like material found in native-reader runtime source" >&2
    exit 1
fi
if find "$root" -type f \( -iname '*.epub' -o -iname '*.pdf' -o -iname '*.mobi' \
    -o -iname '*.azw*' -o -iname '*.rmdoc' -o -iname '*.rm' \
    -o -name 'libqsgepaper.so' \) -print -quit | grep -q .; then
    printf '%s\n' "Book, user-document, or proprietary display blob found under native-reader" >&2
    exit 1
fi
printf '%s\n' "native-reader secret/content scan: PASS"
