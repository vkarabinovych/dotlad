#!/usr/bin/env bash
# Render the tap formula from one published release checksum file.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/packaging/homebrew/dotlad.rb.in"

usage() {
    printf 'Usage: %s <vVERSION> <checksum-file> <output-formula>\n' "$0" >&2
}

[[ $# -eq 3 ]] || {
    usage
    exit 1
}

tag="$1"
checksum_file="$2"
output="$3"
[[ "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]] || {
    printf 'Invalid release tag: %s\n' "$tag" >&2
    exit 1
}
[[ -f "$checksum_file" ]] || {
    printf 'Checksum file not found: %s\n' "$checksum_file" >&2
    exit 1
}
[[ -f "$TEMPLATE" ]] || {
    printf 'Formula template not found: %s\n' "$TEMPLATE" >&2
    exit 1
}

version="${tag#v}"
archive="dotlad-$version.tar.gz"
sha256="$(awk -v archive="$archive" '$2 == archive { print $1 }' "$checksum_file")"
[[ "$sha256" =~ ^[[:xdigit:]]{64}$ ]] || {
    printf 'No valid SHA-256 entry for %s in %s\n' "$archive" "$checksum_file" >&2
    exit 1
}
sha256="$(printf '%s' "$sha256" | tr '[:upper:]' '[:lower:]')"

mkdir -p "$(dirname "$output")"
temporary="$(mktemp "$(dirname "$output")/.dotlad-formula.XXXXXX")"
trap 'rm -f "$temporary"' EXIT HUP INT TERM
sed -e "s/@VERSION@/$version/g" -e "s/@SHA256@/$sha256/g" \
    "$TEMPLATE" >"$temporary"
chmod 0644 "$temporary"
mv "$temporary" "$output"
trap - EXIT HUP INT TERM
printf '%s\n' "$output"
