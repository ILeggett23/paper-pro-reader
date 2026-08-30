#!/usr/bin/env bash

set -euo pipefail

patterns='sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9_-]{32,}|(api[_-]?key|device[_-]?token)[[:space:]]*[:=][[:space:]]*[A-Za-z0-9_-]{24,}'

if git grep -nEI "${patterns}" -- . \
    ':!*.md' ':!backend/.env.example' ':!backend/test/**' ':!spec/**' \
    ':!tools/paperpro-secret-scan.sh'; then
    echo "Potential committed credential found" >&2
    exit 1
fi

echo "Paper Pro secret scan: PASS"
