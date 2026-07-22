#!/usr/bin/env bash
# Remove a standalone Dotlad installation created by install.sh.
set -euo pipefail

INSTALL_DIR="${DOTLAD_INSTALL_DIR:-$HOME/.local/share/dotlad}"
BIN_DIR="${DOTLAD_BIN_DIR:-$HOME/.local/bin}"
MANAGED_MARKER="dotlad managed installation"
COMMAND_MARKER="# dotlad managed launcher"

fail() {
    printf 'dotlad uninstall: %s\n' "$*" >&2
    exit 1
}

is_absolute_safe_path() {
    [[ "$1" == /* && "$1" != "/" && "$1" != *$'\n'* && "$1" != *$'\r'* ]]
}

is_managed_runtime() { # <path>
    [[ -d "$1" && ! -L "$1" && -f "$1/.dotlad-managed" ]] &&
        grep -Fqx "$MANAGED_MARKER" "$1/.dotlad-managed"
}

is_managed_command() { # <path> <runtime>
    local quoted_runtime="${2//\'/\'\\\'\'}"
    [[ -f "$1" && ! -L "$1" ]] &&
        grep -Fqx "$COMMAND_MARKER" "$1" &&
        grep -Fqx "exec '$quoted_runtime/dotlad' \"\$@\"" "$1"
}

is_homebrew_installation() {
    local prefix
    command -v brew >/dev/null 2>&1 || return 1
    prefix="$(brew --prefix dotlad 2>/dev/null || true)"
    [[ -n "$prefix" && -f "$prefix/libexec/.dotlad-homebrew" ]] &&
        grep -Fqx 'dotlad Homebrew installation' \
            "$prefix/libexec/.dotlad-homebrew"
}

normalize_paths() {
    local install_name
    is_absolute_safe_path "$INSTALL_DIR" ||
        fail "DOTLAD_INSTALL_DIR must be a safe absolute path: $INSTALL_DIR"
    is_absolute_safe_path "$BIN_DIR" ||
        fail "DOTLAD_BIN_DIR must be a safe absolute path: $BIN_DIR"
    [[ "$BIN_DIR" != *:* ]] ||
        fail "DOTLAD_BIN_DIR cannot contain ':' because it is a PATH separator"

    [[ -d "$(dirname "$INSTALL_DIR")" && -d "$BIN_DIR" ]] ||
        fail "no managed installation found"
    install_name="$(basename "$INSTALL_DIR")"
    INSTALL_DIR="$(cd "$(dirname "$INSTALL_DIR")" && pwd -P)/$install_name"
    BIN_DIR="$(cd "$BIN_DIR" && pwd -P)"
    COMMAND_PATH="$BIN_DIR/dotlad"
}

if [[ ! -e "$INSTALL_DIR" && ! -L "$INSTALL_DIR" &&
    ! -e "$BIN_DIR/dotlad" && ! -L "$BIN_DIR/dotlad" ]]; then
    if is_homebrew_installation; then
        printf 'Dotlad was installed with Homebrew.\n'
        printf 'Run: brew uninstall dotlad\n'
        exit 0
    fi
    fail "no managed installation found"
fi
normalize_paths
is_managed_runtime "$INSTALL_DIR" ||
    fail "refusing to remove unmanaged path: $INSTALL_DIR"
is_managed_command "$COMMAND_PATH" "$INSTALL_DIR" ||
    fail "refusing to remove unmanaged path: $COMMAND_PATH"

printf 'dotlad uninstall: removing standalone installation\n'
printf '  Runtime: %s\n' "$INSTALL_DIR"
printf '  Command: %s\n' "$COMMAND_PATH"
rm -f "$COMMAND_PATH"
rm -rf "$INSTALL_DIR"
printf 'Dotlad was uninstalled. Your projects, deployed config, and backups were left untouched.\n'
