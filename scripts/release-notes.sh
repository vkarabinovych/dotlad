#!/usr/bin/env bash
# Print one version's release notes from CHANGELOG.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:-}"
CHANGELOG="${2:-$ROOT/CHANGELOG.md}"

[[ "$TAG" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] ||
    {
        printf 'Usage: %s vVERSION [CHANGELOG]\n' "$0" >&2
        exit 1
    }
[[ -r "$CHANGELOG" ]] ||
    {
        printf 'Changelog not found: %s\n' "$CHANGELOG" >&2
        exit 1
    }

VERSION="${TAG#v}"
awk -v heading="## [$VERSION]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found && /^\[[^]]+\]:[[:space:]]/ { exit }
    found {
        if (!started && $0 == "") next
        started = 1
        lines[++count] = $0
    }
    END {
        while (count > 0 && lines[count] == "") count--
        if (!found || count == 0) exit 1
        for (i = 1; i <= count; i++) print lines[i]
    }
' "$CHANGELOG" || {
    printf 'No release notes for %s in %s\n' "$TAG" "$CHANGELOG" >&2
    exit 1
}
