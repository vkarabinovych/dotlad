#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2317,SC2329  # sourced cases call the shared helpers
#
# Test suite for dotlad. Runs on macOS Bash 3.2 and Ubuntu Bash.
# Assertions are semantic (jq / yq / git config), never exact output text.
# Everything happens in a throwaway sandbox — the real $HOME is never touched.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DOTLAD_RUNTIME_ROOT="$ROOT"
CASES=0
FAILS=0
pass() {
    CASES=$((CASES + 1))
    printf 'ok %d - %s\n' "$CASES" "$1"
}
fail() {
    CASES=$((CASES + 1))
    FAILS=$((FAILS + 1))
    printf 'not ok %d - %s\n' "$CASES" "$1"
}
check() {
    local d="$1"
    shift
    if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi
}
checknot() {
    local d="$1"
    shift
    if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi
}
test_sha256() {
    local output
    if command -v sha256sum >/dev/null 2>&1; then
        output="$(sha256sum "$1")" || return 1
    else
        output="$(shasum -a 256 "$1")" || return 1
    fi
    printf '%s' "${output%% *}"
}
rc_is() {
    local d="$1" want="$2"
    shift 2
    local r=0
    "$@" >/dev/null 2>&1 || r=$?
    [[ "$r" == "$want" ]] && pass "$d" || fail "$d (rc=$r want=$want)"
}
lines_fit() {
    local width="$1" line stx
    stx="$(printf '\002')"
    while IFS= read -r line; do
        line="${line#"$stx"}"
        [[ ${#line} -le $width ]] || return 1
    done
}

for required in jq yq git; do
    command -v "$required" >/dev/null 2>&1 ||
        {
            echo "SKIP: $required required"
            exit 0
        }
done

case "$(uname -s)" in
    Darwin) TEST_PLATFORM=macos ;;
    Linux)
        kernel_release="$(uname -r 2>/dev/null || true)"
        if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ||
            "$kernel_release" == *[Mm]icrosoft* ]]; then
            TEST_PLATFORM=wsl
        else
            TEST_PLATFORM=linux
        fi
        ;;
    *)
        printf 'unsupported test platform\n' >&2
        exit 1
        ;;
esac
unset kernel_release
export TEST_PLATFORM

SB="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-test.XXXXXX")"
FAKE="$SB/repo"
H="$SB/home"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$FAKE/tools" "$FAKE/profiles" "$H" "$SB/bin"
# brew simulator: `install` creates both the opt link and a bin stub for each
# formula, so "installed" flips deterministically regardless of what the host
# happens to have on PATH.
cat >"$SB/bin/brew" <<'EOF'
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
    if [ "$n" = requirement-provider ]; then
      printf '#!/bin/sh\nexit 0\n' > "$BREW_PREFIX/bin/requirement-command"
      chmod +x "$BREW_PREFIX/bin/requirement-command"
    fi
  done
fi
exit 0
EOF
chmod +x "$SB/bin/brew"
export BREW_PREFIX="$SB/brewprefix"
mkdir -p "$SB/brewprefix/bin"
export BREW_FAIL_FILE="$SB/brew-fail"
export BREW_LOG="$SB/brew.log"
: >"$BREW_LOG"
export FAKE_APPLICATIONS="$H/Applications"
ln -sf "$SB/bin/brew" "$SB/brewprefix/bin/brew"

mkdir -p "$FAKE/tools/filecopy/files" "$FAKE/tools/package" \
    "$FAKE/tools/jsonmerge/files" "$FAKE/tools/tomlmerge/files" \
    "$FAKE/tools/desktop/files" "$FAKE/tools/git/files" \
    "$FAKE/tools/directory/files/lua" "$FAKE/tools/multipkg/files"

printf 'repo = 1\n' >"$FAKE/tools/filecopy/files/config.toml"
cat >"$FAKE/tools/filecopy/tool.conf" <<EOF
NAME="filecopy"
DESC="File deployment fixture"
ICON="a"
ORDER="10"
BREW="filecopy"
REQUIRES="reqtool"
[config.main]
SOURCE="files/config.toml"
DEST="$H/.config/filecopy/config.toml"
EOF

cat >"$FAKE/tools/package/tool.conf" <<'EOF'
NAME="package"
DESC="Package-only fixture"
ICON="b"
ORDER="20"
BREW="package"
EOF

printf '{"model": "opus"}\n' >"$FAKE/tools/jsonmerge/files/settings.json"
cat >"$FAKE/tools/jsonmerge/tool.conf" <<EOF
NAME="jsonmerge"
DESC="JSON resolver fixture"
ICON="c"
ORDER="30"
CHECK="jsonmerge"
[config.main]
SOURCE="files/settings.json"
DEST="$H/.config/jsonmerge/settings.json"
RESOLVER="json"
EOF

printf 'model = "repo"\n' >"$FAKE/tools/tomlmerge/files/config.toml"
cat >"$FAKE/tools/tomlmerge/tool.conf" <<EOF
NAME="tomlmerge"
DESC="TOML resolver fixture"
ICON="x"
ORDER="40"
CHECK="tomlmerge"
[config.main]
SOURCE="files/config.toml"
DEST="$H/.config/tomlmerge/config.toml"
RESOLVER="toml"
EOF

printf 'font-family = fixture\n' >"$FAKE/tools/desktop/files/config"
cat >"$FAKE/tools/desktop/tool.conf" <<EOF
NAME="desktop"
DESC="Cask fixture"
ICON="g"
ORDER="50"
PLATFORMS="macos"
BREW="vendor/tap/desktop fixture-font"
CASK="1"
CHECK="$FAKE_APPLICATIONS/Desktop.app"
[config.main]
SOURCE="files/config"
DEST="$H/.config/desktop/config"
EOF

printf '[user]\n\tname = Repo\n[core]\n\tpager = repo-pager\n[color]\n\tui = auto\n' \
    >"$FAKE/tools/git/files/.gitconfig"
cat >"$FAKE/tools/git/tool.conf" <<EOF
NAME="git"
DESC="Git config resolver fixture"
ICON="i"
ORDER="60"
CHECK="git"
[config.main]
SOURCE="files/.gitconfig"
DEST="$H/.gitconfig"
RESOLVER="gitconfig"
EOF

printf -- '-- init\n' >"$FAKE/tools/directory/files/init.lua"
printf -- '-- mod\n' >"$FAKE/tools/directory/files/lua/mod.lua"
cat >"$FAKE/tools/directory/tool.conf" <<EOF
NAME="directory"
DESC="Directory mirror fixture"
ICON="n"
ORDER="70"
BREW="directory syntax-parser"
CHECK="directory"
[config.main]
SOURCE="files"
DEST="$H/.config/directory"
EOF

printf '# fixture\n' >"$FAKE/tools/multipkg/files/config"
cat >"$FAKE/tools/multipkg/tool.conf" <<EOF
NAME="multipkg"
DESC="Multi-package fixture"
ICON="z"
ORDER="80"
CHECK="multipkg"
BREW="multipkg alpha beta gamma delta vendor/tap/epsilon zeta eta"
[config.main]
SOURCE="files/config"
DEST="$H/.config/multipkg/config"
EOF

cat >"$FAKE/profiles/base.conf" <<'EOF'
extends=""
tools="filecopy package jsonmerge tomlmerge desktop git directory multipkg"
EOF
cat >"$FAKE/profiles/developer.conf" <<'EOF'
extends="base"
tools=""
EOF
cat >"$FAKE/profiles/complete.conf" <<'EOF'
extends="developer"
tools=""
EOF

df() { (cd "$FAKE" && PATH="$SB/brewprefix/bin:$SB/bin:$PATH" HOME="$H" \
    DOTLAD_YES=1 DOTLAD_PLAIN=1 /bin/bash "$ROOT/dotlad" \
    "$FAKE" --backup "$H/.dotlad_backup" "$@"); }
state_json() { # print ST_CFG/ST_INSTALLED for a tool via a tiny sourced probe
    (cd "$FAKE" && PATH="$SB/brewprefix/bin:$SB/bin:$PATH" HOME="$H" DOTLAD_PLAIN=1 \
        ROOT="$FAKE" /bin/bash -c '
        . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"; manifest_load
        i="$(tool_find "'"$1"'")"; tool_state "$i"; printf "%s %s\n" "$ST_CFG" "$ST_INSTALLED"')
}

restore() {
    (cd "$FAKE" && HOME="$H" ROOT="$FAKE" DOTLAD_PLAIN=1 /bin/bash -c '
        . "$DOTLAD_RUNTIME_ROOT/lib/console.sh"
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
