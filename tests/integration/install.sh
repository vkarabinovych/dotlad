#!/usr/bin/env bash
# Standalone installation contract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-install-test.XXXXXX")"
trap 'rm -rf "$SB"' EXIT HUP INT TERM
PREFIX="$SB/prefix"
HOME_DIR="$SB/home"
PROJECT="$SB/project"
BREW_CWD="$SB/brew-cwd"
VERSION="$(cat "$ROOT/VERSION")"

# Release notes come from exactly one versioned changelog section.
NOTES_CHANGELOG="$SB/release-notes.md"
cat >"$NOTES_CHANGELOG" <<'EOF'
## [Unreleased]

- Later work.

## [1.2.3] - 2026-07-18

### Added

- Released feature.

## [1.2.2] - 2026-07-17

- Earlier work.

[1.2.2]: https://example.test/releases/1.2.2
EOF
release_notes="$("$ROOT/scripts/release-notes.sh" v1.2.3 "$NOTES_CHANGELOG")"
[[ "$release_notes" == $'### Added\n\n- Released feature.' ]]
release_notes="$("$ROOT/scripts/release-notes.sh" v1.2.2 "$NOTES_CHANGELOG")"
[[ "$release_notes" == '- Earlier work.' ]]
if "$ROOT/scripts/release-notes.sh" v9.9.9 "$NOTES_CHANGELOG" >/dev/null 2>&1; then
    printf 'release notes accepted a missing changelog section\n' >&2
    exit 1
fi

mkdir -p "$HOME_DIR" "$BREW_CWD" "$PROJECT/tools/demo/files" "$PROJECT/profiles"
printf 'installed = true\n' >"$PROJECT/tools/demo/files/config.toml"
cat >"$PROJECT/tools/demo/tool.conf" <<'EOF'
NAME="demo"
DESC="Standalone install fixture"
ICON="•"
BREW="demo"
SOURCE="files/config.toml"
DEST="$HOME/.config/demo/config.toml"
EOF

# A failed fresh install leaves neither half of the managed installation.
FRESH_FAIL_PREFIX="$SB/fresh-fail-prefix"
fresh_fail_rc=0
DOTLAD_INSTALL_TEST_FAIL_AFTER_RUNTIME=1 "$ROOT/install.sh" \
    --prefix "$FRESH_FAIL_PREFIX" >/dev/null 2>&1 || fresh_fail_rc=$?
[[ "$fresh_fail_rc" == 97 ]]
[[ ! -e "$FRESH_FAIL_PREFIX/libexec/dotlad" ]]
[[ ! -e "$FRESH_FAIL_PREFIX/bin/dotlad" ]]

"$ROOT/install.sh" --prefix "$PREFIX" >/dev/null
[[ -x "$PREFIX/bin/dotlad" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/runtime.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/console.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/tui/input.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/tui/model.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/tui/screen.sh" ]]
[[ ! -e "$PREFIX/libexec/dotlad/lib/dotlad" ]]
[[ "$(cd "$SB" && "$PREFIX/bin/dotlad" --version)" == "dotlad $VERSION" ]]
[[ "$(cd "$SB" && "$PREFIX/bin/dotlad" help | head -1)" == "dotlad — install a project's packages and configs onto your system." ]]
(cd "$PROJECT" && HOME="$HOME_DIR" DOTLAD_PLAIN=1 \
    "$PREFIX/bin/dotlad" >/dev/null)
if HOME="$HOME_DIR" "$PREFIX/bin/dotlad" -C >"$SB/missing-root.out" 2>&1; then
    printf 'dotlad accepted -C without a path\n' >&2
    exit 1
fi
grep -Fx 'dotlad: -C needs a path' "$SB/missing-root.out" >/dev/null

HOME="$HOME_DIR" "$PREFIX/bin/dotlad" -C "$PROJECT" \
    --config-only --yes demo >/dev/null
cmp "$PROJECT/tools/demo/files/config.toml" "$HOME_DIR/.config/demo/config.toml"
(cd "$BREW_CWD" && HOME="$HOME_DIR" "$PREFIX/bin/dotlad" \
    -C "$PROJECT" brewfile >/dev/null)
grep -Fx 'brew "demo"' "$BREW_CWD/Brewfile" >/dev/null
[[ ! -e "$PROJECT/Brewfile" ]]

# Reinstallation upgrades the managed runtime without replacing unrelated bins.
printf 'old runtime survives rollback\n' >"$PREFIX/libexec/dotlad/rollback-sentinel"
rollback_rc=0
DOTLAD_INSTALL_TEST_FAIL_AFTER_RUNTIME=1 "$ROOT/install.sh" --prefix "$PREFIX" \
    >/dev/null 2>&1 || rollback_rc=$?
[[ "$rollback_rc" == 97 ]]
grep -Fx 'old runtime survives rollback' "$PREFIX/libexec/dotlad/rollback-sentinel" >/dev/null
[[ "$("$PREFIX/bin/dotlad" --version)" == "dotlad $VERSION" ]]
rm -f "$PREFIX/libexec/dotlad/rollback-sentinel"
"$ROOT/install.sh" --prefix "$PREFIX" >/dev/null
printf '#!/bin/sh\n' >"$PREFIX/bin/foreign"
"$ROOT/install.sh" --prefix "$PREFIX" --uninstall >/dev/null
[[ ! -e "$PREFIX/bin/dotlad" ]]
[[ ! -e "$PREFIX/libexec/dotlad" ]]
[[ -f "$PREFIX/bin/foreign" ]]

# Existing unrelated paths are never adopted or removed.
FOREIGN_PREFIX="$SB/foreign-prefix"
mkdir -p "$FOREIGN_PREFIX/libexec/dotlad" "$FOREIGN_PREFIX/bin"
printf 'keep\n' >"$FOREIGN_PREFIX/libexec/dotlad/sentinel"
if "$ROOT/install.sh" --prefix "$FOREIGN_PREFIX" >/dev/null 2>&1; then
    printf 'installer replaced an unmanaged runtime\n' >&2
    exit 1
fi
[[ "$(cat "$FOREIGN_PREFIX/libexec/dotlad/sentinel")" == "keep" ]]

# Uninstall validates both owned paths before removing either one.
MIXED_PREFIX="$SB/mixed-prefix"
"$ROOT/install.sh" --prefix "$MIXED_PREFIX" >/dev/null
rm -rf "$MIXED_PREFIX/libexec/dotlad"
mkdir -p "$MIXED_PREFIX/libexec/dotlad"
printf 'keep\n' >"$MIXED_PREFIX/libexec/dotlad/sentinel"
if "$ROOT/install.sh" --prefix "$MIXED_PREFIX" --uninstall >/dev/null 2>&1; then
    printf 'uninstall removed a mixed managed/unmanaged installation\n' >&2
    exit 1
fi
[[ -x "$MIXED_PREFIX/bin/dotlad" ]]
[[ "$(cat "$MIXED_PREFIX/libexec/dotlad/sentinel")" == "keep" ]]

# The release archive contains the same installable command contract.
DIST="$SB/dist"
EXTRACTED="$SB/extracted"
ARCHIVE="$DIST/dotlad-$VERSION.tar.gz"
"$ROOT/scripts/package.sh" "$DIST" >/dev/null
mkdir -p "$EXTRACTED"
(cd "$DIST" && shasum -a 256 -c "dotlad-$VERSION.sha256") >/dev/null
tar -C "$EXTRACTED" -xzf "$ARCHIVE"
[[ -f "$EXTRACTED/dotlad-$VERSION/.github/assets/demo/cli.gif" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/.editorconfig" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/CHANGELOG.md" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/CONTRIBUTING.md" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/SECURITY.md" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/runtime.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/console.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/tui/input.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/tui/model.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/tui/screen.sh" ]]
[[ ! -e "$EXTRACTED/dotlad-$VERSION/lib/dotlad" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/scripts/check.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/tests/run.sh" ]]
/bin/bash "$EXTRACTED/dotlad-$VERSION/scripts/check.sh" --syntax-only
"$EXTRACTED/dotlad-$VERSION/install.sh" --prefix "$SB/archive-prefix" >/dev/null
[[ "$("$SB/archive-prefix/bin/dotlad" --version)" == "dotlad $VERSION" ]]
rm -f "$BREW_CWD/Brewfile"
(cd "$BREW_CWD" && HOME="$HOME_DIR" "$SB/archive-prefix/bin/dotlad" \
    --config="$PROJECT" brewfile >/dev/null)
grep -Fx 'brew "demo"' "$BREW_CWD/Brewfile" >/dev/null

printf 'DOTLAD_INSTALL_TEST_OK\n'
