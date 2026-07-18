#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2317,SC2329  # sourced cases call the shared helpers
#
# Test suite for dotlad. Runs on the stock macOS Bash 3.2.
# Assertions are semantic (jq / yq / git config), never exact output text.
# Everything happens in a throwaway sandbox — the real $HOME is never touched.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DOTLAD_RUNTIME_ROOT="$ROOT"
CASES=0; FAILS=0
pass() { CASES=$((CASES + 1)); printf 'ok %d - %s\n' "$CASES" "$1"; }
fail() { CASES=$((CASES + 1)); FAILS=$((FAILS + 1)); printf 'not ok %d - %s\n' "$CASES" "$1"; }
check()    { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
checknot() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }
rc_is()    { local d="$1" want="$2"; shift 2; local r=0; "$@" >/dev/null 2>&1 || r=$?; [[ "$r" == "$want" ]] && pass "$d" || fail "$d (rc=$r want=$want)"; }
lines_fit() { local width="$1" line stx; stx="$(printf '\002')"; while IFS= read -r line; do line="${line#"$stx"}"; [[ ${#line} -le $width ]] || return 1; done; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq required"; exit 0; }

SB="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-test.XXXXXX")"
FAKE="$SB/repo"; H="$SB/home"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$FAKE/modules" "$FAKE/profiles" "$H" "$SB/bin"
# brew simulator: `install` creates both the opt link and a bin stub for each
# formula, so "installed" flips deterministically regardless of what the host
# happens to have on PATH.
cat > "$SB/bin/brew" <<'EOF'
#!/bin/sh
if [ "$1" = install ]; then
  shift
  cask=0
  for p in "$@"; do
    case "$p" in --cask) cask=1; continue ;; --*) continue ;; esac
    n="${p##*/}"
    if [ -n "${BREW_FAIL_FILE:-}" ] && [ -f "$BREW_FAIL_FILE" ] \
       && [ "$(cat "$BREW_FAIL_FILE")" = "$n" ]; then
      exit 42
    fi
    printf '%s\n' "$n" >> "$BREW_LOG"
    if [ "$cask" = 1 ]; then
      mkdir -p "$BREW_PREFIX/Caskroom/$n"
      [ "$n" = desktop ] && mkdir -p "$FAKE_APPLICATIONS/Desktop.app"
      continue
    fi
    mkdir -p "$BREW_PREFIX/opt/$n"
    printf '#!/bin/sh\nexit 0\n' > "$BREW_PREFIX/bin/$n" && chmod +x "$BREW_PREFIX/bin/$n"
  done
fi
exit 0
EOF
chmod +x "$SB/bin/brew"
export BREW_PREFIX="$SB/brewprefix"; mkdir -p "$SB/brewprefix/bin"
export BREW_FAIL_FILE="$SB/brew-fail"
export BREW_LOG="$SB/brew.log"; : > "$BREW_LOG"
export FAKE_APPLICATIONS="$H/Applications"
ln -sf "$SB/bin/brew" "$SB/brewprefix/bin/brew"

mkdir -p "$FAKE/modules/filecopy/files" "$FAKE/modules/package" \
    "$FAKE/modules/jsonmerge/files" "$FAKE/modules/tomlmerge/files" \
    "$FAKE/modules/desktop/files" "$FAKE/modules/git/files" \
    "$FAKE/modules/directory/files/lua" "$FAKE/modules/multipkg/files"

printf 'repo = 1\n' > "$FAKE/modules/filecopy/files/config.toml"
cat > "$FAKE/modules/filecopy/module.conf" <<EOF
NAME="filecopy"
DESC="File deployment fixture"
ICON="a"
ORDER="10"
BREW="filecopy"
SOURCE="files/config.toml"
DEST="$H/.config/filecopy/config.toml"
REQUIRES="reqtool"
EOF

cat > "$FAKE/modules/package/module.conf" <<'EOF'
NAME="package"
DESC="Package-only fixture"
ICON="b"
ORDER="20"
BREW="package"
EOF

printf '{"model": "opus"}\n' > "$FAKE/modules/jsonmerge/files/settings.json"
cat > "$FAKE/modules/jsonmerge/module.conf" <<EOF
NAME="jsonmerge"
DESC="JSON resolver fixture"
ICON="c"
ORDER="30"
CHECK="jsonmerge"
SOURCE="files/settings.json"
DEST="$H/.config/jsonmerge/settings.json"
RESOLVER="json-merge"
REQUIRES="jq"
EOF

printf 'model = "repo"\n' > "$FAKE/modules/tomlmerge/files/config.toml"
cat > "$FAKE/modules/tomlmerge/module.conf" <<EOF
NAME="tomlmerge"
DESC="TOML resolver fixture"
ICON="x"
ORDER="40"
CHECK="tomlmerge"
SOURCE="files/config.toml"
DEST="$H/.config/tomlmerge/config.toml"
RESOLVER="toml-merge"
REQUIRES="yq"
EOF

printf 'font-family = fixture\n' > "$FAKE/modules/desktop/files/config"
cat > "$FAKE/modules/desktop/module.conf" <<EOF
NAME="desktop"
DESC="Cask fixture"
ICON="g"
ORDER="50"
BREW="vendor/tap/desktop fixture-font"
CASK="1"
CHECK="$FAKE_APPLICATIONS/Desktop.app"
SOURCE="files/config"
DEST="$H/.config/desktop/config"
EOF

printf '[user]\n\tname = Repo\n[core]\n\tpager = repo-pager\n[color]\n\tui = auto\n' \
    > "$FAKE/modules/git/files/.gitconfig"
cat > "$FAKE/modules/git/module.conf" <<EOF
NAME="git"
DESC="Git config resolver fixture"
ICON="i"
ORDER="60"
CHECK="git"
SOURCE="files/.gitconfig"
DEST="$H/.gitconfig"
RESOLVER="gitconfig-merge"
REQUIRES="git"
EOF

printf -- '-- init\n' > "$FAKE/modules/directory/files/init.lua"
printf -- '-- mod\n' > "$FAKE/modules/directory/files/lua/mod.lua"
cat > "$FAKE/modules/directory/module.conf" <<EOF
NAME="directory"
DESC="Directory mirror fixture"
ICON="n"
ORDER="70"
BREW="directory syntax-parser"
CHECK="directory"
SOURCE="files"
DEST="$H/.config/directory"
EOF

printf '# fixture\n' > "$FAKE/modules/multipkg/files/config"
cat > "$FAKE/modules/multipkg/module.conf" <<EOF
NAME="multipkg"
DESC="Multi-package fixture"
ICON="z"
ORDER="80"
CHECK="multipkg"
BREW="multipkg alpha beta gamma delta vendor/tap/epsilon zeta eta"
SOURCE="files/config"
DEST="$H/.config/multipkg/config"
EOF

cat > "$FAKE/profiles/base.conf" <<'EOF'
extends=""
modules="filecopy package jsonmerge tomlmerge desktop git directory multipkg"
EOF
cat > "$FAKE/profiles/developer.conf" <<'EOF'
extends="base"
modules=""
EOF
cat > "$FAKE/profiles/complete.conf" <<'EOF'
extends="developer"
modules=""
EOF

df() { (cd "$FAKE" && PATH="$SB/brewprefix/bin:$SB/bin:$PATH" HOME="$H" \
    DOTLAD_YES=1 DOTLAD_PLAIN=1 /bin/bash "$ROOT/dotlad" \
    -C "$FAKE" --backup-root "$H/.dotlad_backup" "$@"); }
state_json() { # print ST_CFG/ST_INSTALLED for a tool via a tiny sourced probe
    (cd "$FAKE" && PATH="$SB/brewprefix/bin:$SB/bin:$PATH" HOME="$H" DOTLAD_PLAIN=1 \
        ROOT="$FAKE" /bin/bash -c '
        . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"; manifest_load
        i="$(manifest_find "'"$1"'")"; tool_state "$i"; printf "%s %s\n" "$ST_CFG" "$ST_INSTALLED"')
}

restore() {
    (cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
        . "$DOTLAD_RUNTIME_ROOT/lib/ui.sh"
        . "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
        . "$DOTLAD_RUNTIME_ROOT/lib/backup.sh"
        BACKUP_ROOT="$HOME/.dotlad_backup"; BACKUP_DIR=""; N_BACKED=0
        restore_backup "$1"' _ "$1")
}

CASES_DIR="$ROOT/tests/integration/cases"
for case_file in "$CASES_DIR"/*.sh; do
    # shellcheck disable=SC1090
    . "$case_file"
done
unset case_file CASES_DIR

printf '\n%d cases, %d failed\n' "$CASES" "$FAILS"
exit "$((FAILS > 0 ? 1 : 0))"
