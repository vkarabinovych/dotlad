#!/usr/bin/env bash
# Build the release archive and checksum from the current commit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
OUT_DIR="${1:-$ROOT/dist}"
ARCHIVE="dotlad-$VERSION.tar.gz"
CHECKSUMS="dotlad-$VERSION.sha256"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] \
    || { printf 'VERSION is not semantic: %s\n' "$VERSION" >&2; exit 1; }
if [[ -n "${GITHUB_REF_NAME:-}" && "$GITHUB_REF_NAME" == v* \
    && "$GITHUB_REF_NAME" != "v$VERSION" ]]; then
    printf 'Tag %s does not match VERSION %s\n' "$GITHUB_REF_NAME" "$VERSION" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$ARCHIVE" "$OUT_DIR/$CHECKSUMS"
stage="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT HUP INT TERM
bundle="$stage/dotlad-$VERSION"
mkdir -p "$bundle/bin" "$bundle/scripts" "$bundle/.github/assets/demo"
cp "$ROOT/VERSION" "$ROOT/LICENSE" "$ROOT/README.md" \
    "$ROOT/CHANGELOG.md" "$ROOT/CONTRIBUTING.md" "$ROOT/SECURITY.md" \
    "$ROOT/dotlad" "$ROOT/install.sh" "$bundle/"
cp "$ROOT/bin/dotlad" "$bundle/bin/"
cp "$ROOT/scripts/"*.sh "$bundle/scripts/"
cp "$ROOT/.github/assets/demo/cli.gif" "$bundle/.github/assets/demo/"
cp -R "$ROOT/lib" "$ROOT/docs" "$ROOT/tests" "$bundle/"
tar -C "$stage" -czf "$OUT_DIR/$ARCHIVE" "dotlad-$VERSION"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$OUT_DIR" && sha256sum "$ARCHIVE") > "$OUT_DIR/$CHECKSUMS"
elif command -v shasum >/dev/null 2>&1; then
    (cd "$OUT_DIR" && shasum -a 256 "$ARCHIVE") > "$OUT_DIR/$CHECKSUMS"
else
    printf 'Neither sha256sum nor shasum is available\n' >&2
    exit 1
fi

printf '%s\n%s\n' "$OUT_DIR/$ARCHIVE" "$OUT_DIR/$CHECKSUMS"
