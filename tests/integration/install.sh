#!/usr/bin/env bash
# Release packaging and curl-installer contract.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SB="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-install-test.XXXXXX")"
trap 'rm -rf "$SB"' EXIT HUP INT TERM
SOURCE_VERSION="$(cat "$ROOT/VERSION")"
VERSION="0.9.0"
TAG="v$VERSION"
DIST="$SB/dist"
SOURCE_DIST="$SB/source-dist"
DOWNLOAD_BIN="$SB/download-bin"
DOWNLOAD_LOG="$SB/download.log"
INSTALL_DIR="$SB/paths with spaces/share/dotlad"
BIN_DIR="$SB/paths with spaces/bin"
COMMAND="$BIN_DIR/dotlad"

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

"$ROOT/scripts/package.sh" "$SOURCE_DIST" >/dev/null
SOURCE_ARCHIVE="$SOURCE_DIST/dotlad-$SOURCE_VERSION.tar.gz"
SOURCE_CHECKSUM="$SOURCE_DIST/dotlad-$SOURCE_VERSION.sha256"
[[ -s "$SOURCE_ARCHIVE" && -s "$SOURCE_CHECKSUM" ]]
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$SOURCE_DIST" && sha256sum -c "$(basename "$SOURCE_CHECKSUM")") >/dev/null
else
    (cd "$SOURCE_DIST" && shasum -a 256 -c "$(basename "$SOURCE_CHECKSUM")") >/dev/null
fi

# Model the first supported release without changing the repository version
# before its release-preparation commit exists.
FIXTURE_SOURCE="$SB/release-fixture"
mkdir -p "$FIXTURE_SOURCE" "$DIST"
tar -xzf "$SOURCE_ARCHIVE" -C "$FIXTURE_SOURCE"
mv "$FIXTURE_SOURCE/dotlad-$SOURCE_VERSION" "$FIXTURE_SOURCE/dotlad-$VERSION"
printf '%s\n' "$VERSION" >"$FIXTURE_SOURCE/dotlad-$VERSION/VERSION"
ARCHIVE="$DIST/dotlad-$VERSION.tar.gz"
CHECKSUM="$DIST/dotlad-$VERSION.sha256"
tar -czf "$ARCHIVE" -C "$FIXTURE_SOURCE" "dotlad-$VERSION"
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$DIST" && sha256sum "$(basename "$ARCHIVE")") >"$CHECKSUM"
else
    (cd "$DIST" && shasum -a 256 "$(basename "$ARCHIVE")") >"$CHECKSUM"
fi
[[ -s "$ARCHIVE" && -s "$CHECKSUM" ]]
if command -v sha256sum >/dev/null 2>&1; then
    (cd "$DIST" && sha256sum -c "$(basename "$CHECKSUM")") >/dev/null
else
    (cd "$DIST" && shasum -a 256 -c "$(basename "$CHECKSUM")") >/dev/null
fi

# The tap formula is rendered from the checksum attached to the exact release.
FORMULA="$SB/homebrew-tap/Formula/dotlad.rb"
"$ROOT/scripts/render-homebrew-formula.sh" "$TAG" "$CHECKSUM" "$FORMULA" >/dev/null
grep -Fqx \
    "  url \"https://github.com/vkarabinovych/dotlad/releases/download/$TAG/dotlad-$VERSION.tar.gz\"" \
    "$FORMULA"
formula_sha256="$(awk '$1 == "sha256" { gsub(/"/, "", $2); print $2 }' "$FORMULA")"
archive_sha256="$(awk -v archive="dotlad-$VERSION.tar.gz" '$2 == archive { print $1 }' "$CHECKSUM")"
[[ "$formula_sha256" == "$archive_sha256" ]]
grep -Fqx '    libexec.install "VERSION", "dotlad", "uninstall.sh", "bin", "lib"' "$FORMULA"
grep -Fqx '    bin.write_exec_script libexec/"dotlad"' "$FORMULA"
grep -Fqx '    (libexec/".dotlad-homebrew").write "dotlad Homebrew installation\n"' "$FORMULA"
grep -Fqx '  def caveats' "$FORMULA"
grep -Fqx '      To enable native Zsh completion, add this to ~/.zshrc:' "$FORMULA"
grep -Fq 'source <(dotlad completion zsh)' "$FORMULA"
if grep -E '@(VERSION|SHA256)@' "$FORMULA" >/dev/null; then
    printf 'rendered Homebrew formula retained a template placeholder\n' >&2
    exit 1
fi
if "$ROOT/scripts/render-homebrew-formula.sh" v0.9.1 "$CHECKSUM" \
    "$SB/invalid-formula.rb" >/dev/null 2>&1; then
    printf 'Homebrew formula renderer accepted a mismatched checksum file\n' >&2
    exit 1
fi

mkdir -p "$DOWNLOAD_BIN"
cat >"$DOWNLOAD_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
destination=""
url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o | --output)
            destination="$2"
            shift 2
            ;;
        *)
            [[ "$1" == -* ]] || url="$1"
            shift
            ;;
    esac
done
[[ -n "$destination" && -n "$url" ]]
printf '%s\n' "$url" >>"$DOTLAD_TEST_DOWNLOAD_LOG"
case "$url" in
    https://api.github.com/repos/vkarabinovych/dotlad/releases/latest)
        printf '{"tag_name":"v%s"}\n' "$DOTLAD_TEST_VERSION" >"$destination"
        ;;
    */dotlad-"$DOTLAD_TEST_VERSION".tar.gz)
        if [[ -n "${DOTLAD_TEST_BAD_ARCHIVE:-}" ]]; then
            printf 'corrupt archive\n' >"$destination"
        else
            cp "$DOTLAD_TEST_DIST/dotlad-$DOTLAD_TEST_VERSION.tar.gz" "$destination"
        fi
        ;;
    */dotlad-"$DOTLAD_TEST_VERSION".sha256)
        cp "$DOTLAD_TEST_DIST/dotlad-$DOTLAD_TEST_VERSION.sha256" "$destination"
        ;;
    *)
        printf 'unexpected download: %s\n' "$url" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$DOWNLOAD_BIN/curl"

run_installer() {
    PATH="$DOWNLOAD_BIN:$PATH" \
        DOTLAD_TEST_DIST="$DIST" \
        DOTLAD_TEST_VERSION="$VERSION" \
        DOTLAD_TEST_DOWNLOAD_LOG="$DOWNLOAD_LOG" \
        DOTLAD_INSTALL_DIR="${DOTLAD_INSTALL_DIR:-$INSTALL_DIR}" \
        DOTLAD_BIN_DIR="${DOTLAD_BIN_DIR:-$BIN_DIR}" \
        "$ROOT/install.sh"
}

# Latest release lookup, paths containing spaces, and invocation away from the
# repository all use the same verified archive contract.
latest_output="$(SHELL=/bin/zsh run_installer)"
grep -Fqx '  Welcome to' <<<"$latest_output"
grep -Fqx '  ╭────────────────────────╮' <<<"$latest_output"
grep -Fqx '  │  •  dotlad             │' <<<"$latest_output"
grep -Fqx '  │     ━━━                │' <<<"$latest_output"
grep -Fqx '  │  Dots, in order.       │' <<<"$latest_output"
grep -Fqx '  ╰────────────────────────╯' <<<"$latest_output"
grep -F "dotlad install: installing $TAG for" <<<"$latest_output" >/dev/null
grep -Fqx '  → Resolving the latest GitHub release' <<<"$latest_output"
grep -Fqx '  → Downloading the release archive and checksum' <<<"$latest_output"
grep -Fqx '  → Verifying the SHA-256 checksum' <<<"$latest_output"
grep -Fqx '  → Inspecting the release archive' <<<"$latest_output"
grep -Fqx '  → Extracting the release archive' <<<"$latest_output"
grep -Fqx '  → Staging the runtime and command' <<<"$latest_output"
grep -Fqx '  ✓ SHA-256 checksum verified' <<<"$latest_output"
grep -Fqx "  ✓ Dotlad $TAG is ready." <<<"$latest_output"
completion_message="$(sed -n '/^  ✓ Dotlad .* is ready\.$/{n;p;}' <<<"$latest_output")"
case "$completion_message" in
    '    All set — enjoy a little more order and harmony!' | \
        '    Everything is ready. Happy configuring!' | \
        '    Your setup is ready — have fun making it yours!' | \
        "    Nice and tidy. You're ready to go!" | \
        '    Looking good — enjoy your freshly arranged setup!') ;;
    *)
        printf 'unexpected installer completion message: %s\n' "$completion_message" >&2
        exit 1
        ;;
esac
ZSH_HOME="$SB/zsh-home"
mkdir -p "$ZSH_HOME"
printf '%s\n' 'source <(dotlad completion zsh)' >"$ZSH_HOME/.zshrc"
configured_output="$(HOME="$ZSH_HOME" DOTLAD_VERSION="$TAG" run_installer)"
grep -Fqx "  ✓ Zsh completion is already configured in $ZSH_HOME/.zshrc." \
    <<<"$configured_output"
grep -F "https://api.github.com/repos/vkarabinovych/dotlad/releases/latest" \
    "$DOWNLOAD_LOG" >/dev/null
grep -F "Add this line to $HOME/.zshrc:" <<<"$latest_output" >/dev/null
grep -Fqx '  Zsh completion:' <<<"$latest_output"
grep -Fq "source <(dotlad completion zsh)" <<<"$latest_output"
[[ -x "$COMMAND" && ! -L "$COMMAND" ]]
grep -Fqx '# dotlad managed launcher' "$COMMAND"
[[ -f "$INSTALL_DIR/.dotlad-managed" ]]
[[ -f "$INSTALL_DIR/lib/runtime.sh" ]]
[[ -f "$INSTALL_DIR/lib/tui/input.sh" ]]
[[ -f "$INSTALL_DIR/lib/cli/completion.zsh" ]]
mkdir "$SB/outside"
[[ "$(cd "$SB/outside" && "$COMMAND" --version)" == "dotlad $VERSION" ]]
help_output="$(cd "$SB/outside" && "$COMMAND" help)"
[[ "${help_output%%$'\n'*}" == "dotlad — install a project's packages and configs onto your system." ]]
grep -Fq 'dotlad uninstall' <<<"$help_output"

# An explicit version skips the latest-release API and safely updates the
# already managed installation. Running the same update again is idempotent.
: >"$DOWNLOAD_LOG"
update_output="$(DOTLAD_VERSION="$TAG" run_installer)"
grep -F "dotlad install: reinstalling $TAG for" <<<"$update_output" >/dev/null
grep -Fqx "dotlad install: reinstalled $TAG" <<<"$update_output"
if grep -F '/releases/latest' "$DOWNLOAD_LOG" >/dev/null; then
    printf 'explicit installer version queried the latest release\n' >&2
    exit 1
fi
DOTLAD_VERSION="$TAG" run_installer >/dev/null
[[ "$(cd / && "$COMMAND" --version)" == "dotlad $VERSION" ]]

printf '0.8.0\n' >"$INSTALL_DIR/VERSION"
upgrade_output="$(DOTLAD_VERSION="$TAG" run_installer)"
grep -F "dotlad install: updating from v0.8.0 to $TAG for" \
    <<<"$upgrade_output" >/dev/null
grep -Fqx "dotlad install: updated from v0.8.0 to $TAG" <<<"$upgrade_output"

printf '0.10.0\n' >"$INSTALL_DIR/VERSION"
downgrade_output="$(DOTLAD_VERSION="$TAG" run_installer)"
grep -F "dotlad install: downgrading from v0.10.0 to $TAG for" \
    <<<"$downgrade_output" >/dev/null
grep -Fqx "dotlad install: downgraded from v0.10.0 to $TAG" <<<"$downgrade_output"

unsupported_rc=0
DOTLAD_VERSION=v0.8.0 run_installer >/dev/null 2>"$SB/unsupported.err" || unsupported_rc=$?
[[ "$unsupported_rc" != 0 ]]
grep -Fqx \
    '✗ dotlad install: release v0.8.0 is not supported; use v0.9.0 or newer' \
    "$SB/unsupported.err"

invalid_version_rc=0
DOTLAD_VERSION=main run_installer >/dev/null 2>&1 || invalid_version_rc=$?
[[ "$invalid_version_rc" != 0 ]]

# Piped execution has no source-tree location and must follow the same path as
# the documented curl command.
PIPE_ROOT="$SB/piped"
PATH="$DOWNLOAD_BIN:$PATH" \
    DOTLAD_TEST_DIST="$DIST" \
    DOTLAD_TEST_VERSION="$VERSION" \
    DOTLAD_TEST_DOWNLOAD_LOG="$DOWNLOAD_LOG" \
    DOTLAD_INSTALL_DIR="$PIPE_ROOT/share/dotlad" \
    DOTLAD_BIN_DIR="$PIPE_ROOT/bin" \
    DOTLAD_VERSION="$TAG" \
    /bin/bash <"$ROOT/install.sh" >/dev/null
[[ "$(cd / && "$PIPE_ROOT/bin/dotlad" --version)" == "dotlad $VERSION" ]]

# A failure after the runtime swap restores both the previous runtime and its
# command. A bad download also leaves the existing installation untouched.
printf 'rollback sentinel\n' >"$INSTALL_DIR/rollback-sentinel"
rollback_rc=0
DOTLAD_VERSION="$TAG" DOTLAD_INSTALL_TEST_FAIL_AFTER_RUNTIME=1 \
    run_installer >/dev/null 2>&1 || rollback_rc=$?
[[ "$rollback_rc" == 97 ]]
grep -Fx 'rollback sentinel' "$INSTALL_DIR/rollback-sentinel" >/dev/null
[[ "$("$COMMAND" --version)" == "dotlad $VERSION" ]]

bad_download_rc=0
DOTLAD_VERSION="$TAG" DOTLAD_TEST_BAD_ARCHIVE=1 \
    run_installer >/dev/null 2>&1 || bad_download_rc=$?
[[ "$bad_download_rc" != 0 ]]
grep -Fx 'rollback sentinel' "$INSTALL_DIR/rollback-sentinel" >/dev/null
[[ "$("$COMMAND" --version)" == "dotlad $VERSION" ]]

# Existing unrelated runtime or command paths are never adopted.
FOREIGN_INSTALL="$SB/foreign/share/dotlad"
FOREIGN_BIN="$SB/foreign/bin"
mkdir -p "$FOREIGN_INSTALL" "$FOREIGN_BIN"
printf 'keep\n' >"$FOREIGN_INSTALL/sentinel"
foreign_rc=0
DOTLAD_VERSION="$TAG" DOTLAD_INSTALL_DIR="$FOREIGN_INSTALL" \
    DOTLAD_BIN_DIR="$FOREIGN_BIN" run_installer >/dev/null 2>&1 || foreign_rc=$?
[[ "$foreign_rc" != 0 ]]
grep -Fx keep "$FOREIGN_INSTALL/sentinel" >/dev/null

COMMAND_ONLY_INSTALL="$SB/foreign-command/share/dotlad"
COMMAND_ONLY_BIN="$SB/foreign-command/bin"
mkdir -p "$COMMAND_ONLY_BIN"
printf '#!/bin/sh\n' >"$COMMAND_ONLY_BIN/dotlad"
command_rc=0
DOTLAD_VERSION="$TAG" DOTLAD_INSTALL_DIR="$COMMAND_ONLY_INSTALL" \
    DOTLAD_BIN_DIR="$COMMAND_ONLY_BIN" run_installer >/dev/null 2>&1 || command_rc=$?
[[ "$command_rc" != 0 ]]
grep -Fx '#!/bin/sh' "$COMMAND_ONLY_BIN/dotlad" >/dev/null
[[ ! -e "$COMMAND_ONLY_INSTALL" ]]

# Platform detection is validated through isolated uname projections. Each
# projection performs a real staged install from the local release archive.
PLATFORM_BIN="$SB/platform-bin"
mkdir -p "$PLATFORM_BIN"
cat >"$PLATFORM_BIN/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -s) printf '%s\n' "$DOTLAD_TEST_UNAME_SYSTEM" ;;
    -r) printf '%s\n' "$DOTLAD_TEST_UNAME_RELEASE" ;;
    *) printf '%s\n' "$DOTLAD_TEST_UNAME_SYSTEM" ;;
esac
EOF
chmod +x "$PLATFORM_BIN/uname"

platform_install() { # <expected> <uname-system> <uname-release> [wsl-interop]
    local expected="$1" system="$2" release="$3" interop="${4:-}" startup_file
    local root="$SB/platform-$expected" output
    output="$(PATH="$PLATFORM_BIN:$DOWNLOAD_BIN:$PATH" \
        DOTLAD_TEST_UNAME_SYSTEM="$system" \
        DOTLAD_TEST_UNAME_RELEASE="$release" \
        WSL_DISTRO_NAME='' \
        WSL_INTEROP="$interop" \
        DOTLAD_TEST_DIST="$DIST" \
        DOTLAD_TEST_VERSION="$VERSION" \
        DOTLAD_TEST_DOWNLOAD_LOG="$DOWNLOAD_LOG" \
        DOTLAD_INSTALL_DIR="$root/share/dotlad" \
        DOTLAD_BIN_DIR="$root/bin" \
        DOTLAD_VERSION="$TAG" \
        SHELL=/bin/bash \
        "$ROOT/install.sh")"
    grep -F "installing $TAG for $expected" <<<"$output" >/dev/null
    if [[ "$expected" == macos ]]; then
        startup_file="$HOME/.bash_profile"
    else
        startup_file="$HOME/.bashrc"
    fi
    grep -F "Add this line to $startup_file:" <<<"$output" >/dev/null
    [[ "$("$root/bin/dotlad" --version)" == "dotlad $VERSION" ]]
}

platform_install macos Darwin 23.0.0
platform_install linux Linux 6.8.0
platform_install wsl Linux 5.15.0-microsoft-standard /run/WSL/1_interop

# The release archive retains the complete source-bundle contract.
EXTRACTED="$SB/extracted"
mkdir "$EXTRACTED"
tar -xzf "$ARCHIVE" -C "$EXTRACTED"
BUNDLE="$EXTRACTED/dotlad-$VERSION"
[[ -f "$BUNDLE/install.sh" ]]
[[ -f "$BUNDLE/uninstall.sh" ]]
[[ -f "$BUNDLE/.github/assets/demo/cli-dark.gif" ]]
[[ -f "$BUNDLE/.github/assets/demo/cli-light.gif" ]]
[[ -f "$BUNDLE/.github/assets/dotlad-name-dark.svg" ]]
[[ -f "$BUNDLE/.github/assets/dotlad-name-light.svg" ]]
[[ -f "$BUNDLE/CHANGELOG.md" ]]
[[ -f "$BUNDLE/CONTRIBUTING.md" ]]
[[ -f "$BUNDLE/SECURITY.md" ]]
[[ -f "$BUNDLE/SUPPORT.md" ]]
[[ -f "$BUNDLE/examples/.gitignore" ]]
[[ -x "$BUNDLE/examples/mydot" ]]
[[ -f "$BUNDLE/tests/run.sh" ]]
/bin/bash "$BUNDLE/scripts/check.sh" --syntax-only

# Homebrew owns its Cellar installation and the CLI only prints the matching
# package-manager instruction; it never removes Homebrew-managed files itself.
printf 'dotlad Homebrew installation\n' >"$BUNDLE/.dotlad-homebrew"
homebrew_uninstall_output="$(cd "$SB/outside" && "$BUNDLE/dotlad" uninstall)"
[[ "$homebrew_uninstall_output" == $'Dotlad was installed with Homebrew.\nRun: brew uninstall dotlad' ]]
[[ -f "$BUNDLE/VERSION" ]]
rm -f "$BUNDLE/.dotlad-homebrew"

HOMEBREW_PREFIX="$SB/homebrew-prefix"
HOMEBREW_BIN="$SB/homebrew-bin"
mkdir -p "$HOMEBREW_PREFIX/libexec" "$HOMEBREW_BIN"
printf 'dotlad Homebrew installation\n' >"$HOMEBREW_PREFIX/libexec/.dotlad-homebrew"
cat >"$HOMEBREW_BIN/brew" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == --prefix && "${2:-}" == dotlad ]]
printf '%s\n' "$DOTLAD_TEST_HOMEBREW_PREFIX"
EOF
chmod +x "$HOMEBREW_BIN/brew"
standalone_homebrew_output="$(PATH="$HOMEBREW_BIN:$PATH" \
    DOTLAD_TEST_HOMEBREW_PREFIX="$HOMEBREW_PREFIX" \
    DOTLAD_INSTALL_DIR="$SB/missing/share/dotlad" \
    DOTLAD_BIN_DIR="$SB/missing/bin" /bin/bash <"$ROOT/uninstall.sh")"
[[ "$standalone_homebrew_output" == $'Dotlad was installed with Homebrew.\nRun: brew uninstall dotlad' ]]
[[ -f "$HOMEBREW_PREFIX/libexec/.dotlad-homebrew" ]]

# Both the installed command and the standalone script remove only the
# curl-managed runtime and launcher, including custom paths containing spaces.
UNINSTALL_INSTALL="$SB/uninstall paths/share/dotlad"
UNINSTALL_BIN="$SB/uninstall paths/bin"
DOTLAD_INSTALL_DIR="$UNINSTALL_INSTALL" DOTLAD_BIN_DIR="$UNINSTALL_BIN" \
    DOTLAD_VERSION="$TAG" run_installer >/dev/null
mkdir -p "$SB/user-project" "$SB/user-backups"
printf 'keep\n' >"$SB/user-project/config"
printf 'keep\n' >"$SB/user-backups/backup"
uninstall_output="$(PATH="$UNINSTALL_BIN:$PATH" "$UNINSTALL_BIN/dotlad" uninstall)"
grep -Fqx 'Dotlad was uninstalled. Your projects, deployed config, and backups were left untouched.' \
    <<<"$uninstall_output"
[[ ! -e "$UNINSTALL_INSTALL" && ! -e "$UNINSTALL_BIN/dotlad" ]]
grep -Fqx keep "$SB/user-project/config"
grep -Fqx keep "$SB/user-backups/backup"

DOTLAD_INSTALL_DIR="$UNINSTALL_INSTALL" DOTLAD_BIN_DIR="$UNINSTALL_BIN" \
    DOTLAD_VERSION="$TAG" run_installer >/dev/null
standalone_uninstall_output="$(DOTLAD_INSTALL_DIR="$UNINSTALL_INSTALL" \
    DOTLAD_BIN_DIR="$UNINSTALL_BIN" /bin/bash <"$ROOT/uninstall.sh")"
grep -Fqx 'Dotlad was uninstalled. Your projects, deployed config, and backups were left untouched.' \
    <<<"$standalone_uninstall_output"
[[ ! -e "$UNINSTALL_INSTALL" && ! -e "$UNINSTALL_BIN/dotlad" ]]

UNMANAGED_INSTALL="$SB/unmanaged/share/dotlad"
UNMANAGED_BIN="$SB/unmanaged/bin"
mkdir -p "$UNMANAGED_INSTALL" "$UNMANAGED_BIN"
printf 'keep\n' >"$UNMANAGED_INSTALL/sentinel"
unmanaged_uninstall_rc=0
DOTLAD_INSTALL_DIR="$UNMANAGED_INSTALL" DOTLAD_BIN_DIR="$UNMANAGED_BIN" \
    /bin/bash "$ROOT/uninstall.sh" >/dev/null 2>&1 || unmanaged_uninstall_rc=$?
[[ "$unmanaged_uninstall_rc" != 0 ]]
grep -Fqx keep "$UNMANAGED_INSTALL/sentinel"

printf 'DOTLAD_INSTALL_TEST_OK\n'
