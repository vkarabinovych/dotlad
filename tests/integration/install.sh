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

case "$(uname -s)" in
    Darwin) INACTIVE_PLATFORM=linux ;;
    *) INACTIVE_PLATFORM=macos ;;
esac
mkdir -p "$HOME_DIR/backups/20260722_010000" \
    "$HOME_DIR/backups/not-a-restore-point" "$BREW_CWD" \
    "$PROJECT/tools/demo/files" "$PROJECT/tools/inactive" "$PROJECT/profiles"
printf 'installed = true\n' >"$PROJECT/tools/demo/files/config.toml"
printf 'extends=""\ntools="demo"\n' >"$PROJECT/profiles/base.conf"
printf 'extends="base"\ntools=""\n' >"$PROJECT/profiles/developer.conf"
cat >"$PROJECT/tools/demo/tool.conf" <<'EOF'
NAME="demo"
DESC="Standalone install fixture"
ICON="•"
BREW="demo"
[config.main]
SOURCE="files/config.toml"
DEST="$HOME/.config/demo/config.toml"
EOF
cat >"$PROJECT/tools/inactive/tool.conf" <<EOF
NAME="inactive"
DESC="Inactive platform fixture"
ICON="×"
PLATFORMS="$INACTIVE_PLATFORM"
BREW="inactive"
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
[[ -f "$PREFIX/libexec/dotlad/lib/cli/bootstrap.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/cli/dispatch.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/cli/main.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/cli/presentation.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/cli/spec.sh" ]]
[[ -f "$PREFIX/libexec/dotlad/lib/cli/completion.zsh" ]]
[[ ! -e "$PREFIX/libexec/dotlad/completions" ]]
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

COMPLETION_SCRIPT="$SB/dotlad-completion.zsh"
COMPLETION_PROJECT_ROOT="$(cd "$PROJECT" && pwd)"
HOME="$HOME_DIR" "$PREFIX/bin/dotlad" -C "$PROJECT" \
    --backup-root "$HOME_DIR/backups" completion zsh >"$COMPLETION_SCRIPT"
grep -Fx '#compdef dotlad' "$COMPLETION_SCRIPT" >/dev/null
grep -Fqx "_dotlad_register dotlad $COMPLETION_PROJECT_ROOT $HOME_DIR/backups" \
    "$COMPLETION_SCRIPT"
if command -v zsh >/dev/null 2>&1; then
    zsh -n "$COMPLETION_SCRIPT"
    completion_tools="$(PATH="$PREFIX/bin:$PATH" zsh -f -c '
        compdef() { :; }
        source "$1"
        compadd() {
            printf "%s\n" "$@" "${descriptions[@]}" "${tool_display[@]}" "${profile_display[@]}"
        }
        service=dotlad; words=(dotlad ""); CURRENT=2; _dotlad
    ' completion-probe "$COMPLETION_SCRIPT")"
    grep -Fx demo <<<"$completion_tools" >/dev/null
    if grep -Fx inactive <<<"$completion_tools" >/dev/null; then
        printf 'completion exposed a tool from an inactive platform\n' >&2
        exit 1
    fi
    grep -Fx profile <<<"$completion_tools" >/dev/null
    grep -Fx 'profile    -- Apply a named profile and its inherited tools' \
        <<<"$completion_tools" >/dev/null
    grep -Fx 'demo       -- • Standalone install fixture' \
        <<<"$completion_tools" >/dev/null
    completion_options="$(PATH="$PREFIX/bin:$PATH" zsh -f -c '
        compdef() { :; }
        source "$1"
        compadd() { printf "%s\n" "${descriptions[@]}"; }
        service=dotlad; words=(dotlad --); CURRENT=2; _dotlad
    ' completion-probe "$COMPLETION_SCRIPT")"
    config_description='select the manifest project (defaults to current directory)'
    grep -Fx -- "-C              -- $config_description" \
        <<<"$completion_options" >/dev/null
    grep -Fx -- "--config        -- $config_description" \
        <<<"$completion_options" >/dev/null
    grep -Fx -- "--config=       -- $config_description" \
        <<<"$completion_options" >/dev/null
    HOME="$HOME_DIR" "$PREFIX/bin/dotlad" help |
        grep -F -- "-C, --config PATH   $config_description" >/dev/null
    completion_profile="$(PATH="$PREFIX/bin:$PATH" zsh -f -c '
        compdef() { :; }
        source "$1"
        compadd() { printf "%s\n" "$@" "${profile_display[@]}"; }
        service=dotlad; words=(dotlad profile ""); CURRENT=3; _dotlad
    ' completion-probe "$COMPLETION_SCRIPT")"
    grep -Fx base <<<"$completion_profile" >/dev/null
    grep -Fx 'base      -- demo' <<<"$completion_profile" >/dev/null
    grep -Fx 'developer -- ↳ base' \
        <<<"$completion_profile" >/dev/null
    completion_backup="$(PATH="$PREFIX/bin:$PATH" zsh -f -c '
        compdef() { :; }
        source "$1"
        compadd() { printf "%s\n" "$@"; }
        service=dotlad; words=(dotlad backup delete ""); CURRENT=4; _dotlad
    ' completion-probe "$COMPLETION_SCRIPT")"
    grep -Fx 20260722_010000 <<<"$completion_backup" >/dev/null
    if grep -Fx not-a-restore-point <<<"$completion_backup" >/dev/null; then
        printf 'completion exposed an invalid restore-point name\n' >&2
        exit 1
    fi
    WRAPPER_COMPLETION_SCRIPT="$SB/wrapper-completion.zsh"
    HOME="$HOME_DIR" DOTLAD_COMMAND_NAME='my dots' "$PREFIX/bin/dotlad" \
        -C "$PROJECT" completion zsh >"$WRAPPER_COMPLETION_SCRIPT"
    wrapper_project_root="$(zsh -f -c '
        compdef() { :; }
        source "$1"
        key="my dots"
        printf "%s" "${_dotlad_project_roots[$key]:-}"
    ' completion-probe "$WRAPPER_COMPLETION_SCRIPT")"
    [[ "$wrapper_project_root" == "$COMPLETION_PROJECT_ROOT" ]]
    completion_path="$(PATH="$PREFIX/bin:$PATH" zsh -f -c '
        compdef() { :; }
        source "$1"
        compset() { printf "compset:%s:%s\n" "$1" "$2"; }
        _directories() {
            [[ -o extendedglob && -o globdots ]] && printf "directories\n"
        }
        service=dotlad; words=(dotlad --config=); CURRENT=2; _dotlad
    ' completion-probe "$COMPLETION_SCRIPT")"
    grep -Fx 'compset:-P:*\=' <<<"$completion_path" >/dev/null
    grep -Fx directories <<<"$completion_path" >/dev/null
    completion_hidden_file="$(PATH="$PREFIX/bin:$PATH" zsh -f -c '
        compdef() { :; }
        source "$1"
        compset() { :; }
        _files() { [[ -o globdots ]] && printf "hidden files enabled\n"; }
        service=dotlad; words=(dotlad --output=); CURRENT=2; _dotlad
    ' completion-probe "$COMPLETION_SCRIPT")"
    grep -Fx 'hidden files enabled' <<<"$completion_hidden_file" >/dev/null
fi
if HOME="$HOME_DIR" "$PREFIX/bin/dotlad" completion bash >/dev/null 2>&1; then
    printf 'dotlad accepted an unsupported completion shell\n' >&2
    exit 1
fi

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
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$DIST" && sha256sum -c "dotlad-$VERSION.sha256") >/dev/null
else
    (cd "$DIST" && shasum -a 256 -c "dotlad-$VERSION.sha256") >/dev/null
fi
tar -C "$EXTRACTED" -xzf "$ARCHIVE"
[[ -f "$EXTRACTED/dotlad-$VERSION/.github/assets/demo/cli-dark.gif" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/.github/assets/demo/cli-light.gif" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/.github/assets/dotlad-name-dark.svg" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/.github/assets/dotlad-name-light.svg" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/.editorconfig" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/CHANGELOG.md" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/CONTRIBUTING.md" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/SECURITY.md" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/runtime.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/console.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/tui/input.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/tui/model.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/tui/screen.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/cli/bootstrap.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/cli/dispatch.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/cli/main.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/cli/presentation.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/cli/spec.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/lib/cli/completion.zsh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/SUPPORT.md" ]]
[[ ! -e "$EXTRACTED/dotlad-$VERSION/completions" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/examples/.gitignore" ]]
[[ -x "$EXTRACTED/dotlad-$VERSION/examples/mydot" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/examples/tools/multi-config/tool.conf" ]]
[[ ! -e "$EXTRACTED/dotlad-$VERSION/lib/dotlad" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/scripts/check.sh" ]]
[[ -f "$EXTRACTED/dotlad-$VERSION/tests/run.sh" ]]
/bin/bash "$EXTRACTED/dotlad-$VERSION/scripts/check.sh" --syntax-only
"$EXTRACTED/dotlad-$VERSION/install.sh" --prefix "$SB/archive-prefix" >/dev/null
[[ "$("$SB/archive-prefix/bin/dotlad" --version)" == "dotlad $VERSION" ]]
EXAMPLE_ROOT="$(cd "$EXTRACTED/dotlad-$VERSION/examples" && pwd)"
[[ "$(HOME="$EXAMPLE_ROOT/.tmp" "$EXAMPLE_ROOT/mydot" --version)" == "My Dotfiles $VERSION" ]]
mkdir -p "$EXAMPLE_ROOT/.tmp/output/copy-file"
printf 'local example value\n' >"$EXAMPLE_ROOT/.tmp/output/copy-file/example.conf"
HOME="$EXAMPLE_ROOT/.tmp" "$EXAMPLE_ROOT/mydot" \
    --config-only --yes copy-file >/dev/null
cmp "$EXAMPLE_ROOT/tools/copy-file/files/example.conf" \
    "$EXAMPLE_ROOT/.tmp/output/copy-file/example.conf"
EXAMPLE_BACKUP="$(find "$EXAMPLE_ROOT/.tmp/backups" -type f | head -1)"
grep -qFx 'local example value' "$EXAMPLE_BACKUP"
HOME="$EXAMPLE_ROOT/.tmp" "$EXAMPLE_ROOT/mydot" \
    --config-only --yes inject-block >/dev/null
grep -qE '^# dotlad:begin tool=inject-block source=aliases\.sh$' \
    "$EXAMPLE_ROOT/.tmp/output/inject-block/shellrc"
rm -f "$BREW_CWD/Brewfile"
(cd "$BREW_CWD" && HOME="$HOME_DIR" "$SB/archive-prefix/bin/dotlad" \
    --config="$PROJECT" brewfile >/dev/null)
grep -Fx 'brew "demo"' "$BREW_CWD/Brewfile" >/dev/null

printf 'DOTLAD_INSTALL_TEST_OK\n'
