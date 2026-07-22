#!/usr/bin/env bash
# Install the latest tagged Dotlad release from its verified archive.
set -euo pipefail

REPOSITORY="vkarabinovych/dotlad"
GITHUB_URL="https://github.com/$REPOSITORY"
API_URL="https://api.github.com/repos/$REPOSITORY"
MIN_SUPPORTED_VERSION="v0.9.0"
INSTALL_DIR="${DOTLAD_INSTALL_DIR:-$HOME/.local/share/dotlad}"
BIN_DIR="${DOTLAD_BIN_DIR:-$HOME/.local/bin}"
MANAGED_MARKER="dotlad managed installation"
COMMAND_MARKER="# dotlad managed launcher"
WORK_DIR=""
STAGE_DIR=""
RUNTIME_BACKUP=""
COMMAND_TEMP=""
COMMAND_BACKUP=""
INSTALL_PARENT=""
COMMAND_PATH=""
TEMP_ROOT=""
INSTALL_ACTION="install"
CURRENT_VERSION=""
RUNTIME_INSTALLED=0
COMMAND_INSTALLED=0
COMMITTED=0
BLUE=""
YELLOW=""
GREEN=""
RED=""
MUTED=""
WHITE=""
RESET=""

configure_colors() {
    if [[ -t 1 && "${TERM:-}" != dumb && -z "${NO_COLOR:-}" ]]; then
        BLUE=$'\033[38;2;0;87;184m'
        YELLOW=$'\033[38;2;255;215;0m'
        GREEN=$'\033[38;2;46;160;67m'
        RED=$'\033[38;2;248;81;73m'
        MUTED=$'\033[38;2;139;148;158m'
        WHITE=$'\033[1;38;2;240;246;252m'
        RESET=$'\033[0m'
    fi
}

info() {
    printf '%sdotlad install:%s %s\n' "$BLUE" "$RESET" "$*"
}

progress() {
    printf '  %s→%s %s\n' "$BLUE" "$RESET" "$*"
}

success() {
    printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"
}

fail() {
    printf '%s✗%s dotlad install: %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

print_banner() {
    printf '\n  %sWelcome to%s\n\n' "$WHITE" "$RESET"
    printf '  %s╭────────────────────────╮%s\n' "$BLUE" "$RESET"
    printf '  %s│%s  %s•%s  %sdotlad%s             %s│%s\n' \
        "$BLUE" "$RESET" "$YELLOW" "$RESET" "$BLUE" "$RESET" "$BLUE" "$RESET"
    printf '  %s│%s     %s━━━%s                %s│%s\n' \
        "$BLUE" "$RESET" "$YELLOW" "$RESET" "$BLUE" "$RESET"
    printf '  %s│%s  %sDots, in order.%s       %s│%s\n' \
        "$BLUE" "$RESET" "$MUTED" "$RESET" "$BLUE" "$RESET"
    printf '  %s╰────────────────────────╯%s\n\n' "$BLUE" "$RESET"
}

print_completion() { # <version-tag>
    local messages=(
        "All set — enjoy a little more order and harmony!"
        "Everything is ready. Happy configuring!"
        "Your setup is ready — have fun making it yours!"
        "Nice and tidy. You're ready to go!"
        "Looking good — enjoy your freshly arranged setup!"
    )
    local message="${messages[$((RANDOM % ${#messages[@]}))]}"

    printf '\n  %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$YELLOW" "$RESET"
    printf '  %s✓%s %sDotlad %s is ready.%s\n' \
        "$GREEN" "$RESET" "$BLUE" "$1" "$RESET"
    printf '    %s%s%s\n' "$MUTED" "$message" "$RESET"
    printf '  %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$YELLOW" "$RESET"
}

is_absolute_safe_path() {
    [[ "$1" == /* && "$1" != "/" && "$1" != *$'\n'* && "$1" != *$'\r'* ]]
}

is_managed_runtime() { # <path>
    [[ -d "$1" && ! -L "$1" && -f "$1/.dotlad-managed" ]] &&
        grep -Fqx "$MANAGED_MARKER" "$1/.dotlad-managed"
}

is_managed_command() { # <path>
    [[ -f "$1" && ! -L "$1" ]] && grep -Fqx "$COMMAND_MARKER" "$1"
}

remove_managed_runtime() { # <path>
    is_managed_runtime "$1" || return 1
    rm -rf "$1"
}

remove_temp_path() { # <path> <parent> <prefix>
    [[ -n "$1" ]] || return 0
    case "$1" in
        "$2/$3"*) rm -rf "$1" ;;
        *) return 1 ;;
    esac
}

cleanup() {
    local status=$?
    trap - EXIT HUP INT TERM

    if [[ "$COMMITTED" != 1 ]]; then
        if [[ "$COMMAND_INSTALLED" == 1 ]] && is_managed_command "$COMMAND_PATH"; then
            rm -f "$COMMAND_PATH"
        fi
        if [[ -n "$COMMAND_BACKUP" &&
            (-e "$COMMAND_BACKUP" || -L "$COMMAND_BACKUP") ]]; then
            [[ ! -e "$COMMAND_PATH" && ! -L "$COMMAND_PATH" ]] &&
                mv "$COMMAND_BACKUP" "$COMMAND_PATH"
        fi
        if [[ "$RUNTIME_INSTALLED" == 1 ]] && is_managed_runtime "$INSTALL_DIR"; then
            remove_managed_runtime "$INSTALL_DIR" || true
        fi
        if [[ -n "$RUNTIME_BACKUP" && -e "$RUNTIME_BACKUP" ]]; then
            [[ ! -e "$INSTALL_DIR" && ! -L "$INSTALL_DIR" ]] &&
                mv "$RUNTIME_BACKUP" "$INSTALL_DIR"
        fi
    else
        [[ -z "$COMMAND_BACKUP" ||
            (! -e "$COMMAND_BACKUP" && ! -L "$COMMAND_BACKUP") ]] ||
            rm -f "$COMMAND_BACKUP"
        [[ -z "$RUNTIME_BACKUP" || ! -e "$RUNTIME_BACKUP" ]] ||
            remove_managed_runtime "$RUNTIME_BACKUP" || true
    fi

    [[ -z "$COMMAND_TEMP" ||
        (! -e "$COMMAND_TEMP" && ! -L "$COMMAND_TEMP") ]] ||
        rm -f "$COMMAND_TEMP"
    [[ -z "$STAGE_DIR" || ! -e "$STAGE_DIR" ]] ||
        remove_temp_path "$STAGE_DIR" "$INSTALL_PARENT" ".dotlad-install." || true
    [[ -z "$WORK_DIR" || ! -e "$WORK_DIR" ]] ||
        remove_temp_path "$WORK_DIR" "$TEMP_ROOT" "dotlad-installer." || true

    exit "$status"
}

trap cleanup EXIT
trap 'exit 130' HUP INT TERM

detect_platform() {
    local release
    case "$(uname -s 2>/dev/null)" in
        Darwin)
            printf 'macos'
            ;;
        Linux)
            release="$(uname -r 2>/dev/null || true)"
            if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ||
                "$release" == *[Mm]icrosoft* ]]; then
                printf 'wsl'
            else
                printf 'linux'
            fi
            ;;
        *) return 1 ;;
    esac
}

download() { # <https-url> <destination> [show-progress]
    local url="$1" destination="$2" show_progress="${3:-0}"
    [[ "$url" == https://* ]] || fail "refusing non-HTTPS download: $url"
    if command -v curl >/dev/null 2>&1; then
        if [[ "$show_progress" == 1 && -t 2 ]]; then
            curl -fL --progress-bar --retry 3 --connect-timeout 15 \
                --output "$destination" "$url"
        else
            curl -fsSL --retry 3 --connect-timeout 15 --output "$destination" "$url"
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [[ "$show_progress" == 1 && -t 2 ]]; then
            wget -O "$destination" "$url"
        else
            wget -q -O "$destination" "$url"
        fi
    else
        fail "curl or wget is required"
    fi
    [[ -s "$destination" ]] || fail "download was empty: $url"
}

validate_version() { # <tag>
    [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$ ]] ||
        fail "invalid release version: $1"
}

compare_versions() { # <left-tag> <right-tag> — print -1, 0, or 1
    local left="${1#v}" right="${2#v}" left_core right_core
    local left_pre="" right_pre="" left_id right_id
    local left_more right_more index

    left="${left%%+*}"
    right="${right%%+*}"
    left_core="$left"
    right_core="$right"
    if [[ "$left" == *-* ]]; then
        left_core="${left%%-*}"
        left_pre="${left#*-}"
    fi
    if [[ "$right" == *-* ]]; then
        right_core="${right%%-*}"
        right_pre="${right#*-}"
    fi

    for ((index = 0; index < 3; index++)); do
        left_id="${left_core%%.*}"
        right_id="${right_core%%.*}"
        [[ "$left_core" == *.* ]] && left_core="${left_core#*.}" || left_core=""
        [[ "$right_core" == *.* ]] && right_core="${right_core#*.}" || right_core=""
        if ((left_id < right_id)); then
            printf '%s' -1
            return
        elif ((left_id > right_id)); then
            printf '%s' 1
            return
        fi
    done

    [[ "$left_pre" == "$right_pre" ]] && {
        printf '%s' 0
        return
    }
    [[ -n "$left_pre" ]] || {
        printf '%s' 1
        return
    }
    [[ -n "$right_pre" ]] || {
        printf '%s' -1
        return
    }

    while :; do
        left_id="${left_pre%%.*}"
        right_id="${right_pre%%.*}"
        left_more=0
        right_more=0
        [[ "$left_pre" == *.* ]] && {
            left_pre="${left_pre#*.}"
            left_more=1
        }
        [[ "$right_pre" == *.* ]] && {
            right_pre="${right_pre#*.}"
            right_more=1
        }
        if [[ "$left_id" != "$right_id" ]]; then
            if [[ "$left_id" =~ ^[0-9]+$ && "$right_id" =~ ^[0-9]+$ ]]; then
                if ((10#$left_id < 10#$right_id)); then
                    printf '%s' -1
                else
                    printf '%s' 1
                fi
            elif [[ "$left_id" =~ ^[0-9]+$ ]]; then
                printf '%s' -1
            elif [[ "$right_id" =~ ^[0-9]+$ ]]; then
                printf '%s' 1
            elif [[ "$left_id" > "$right_id" ]]; then
                printf '%s' 1
            else
                printf '%s' -1
            fi
            return
        fi
        if [[ "$left_more" == 0 || "$right_more" == 0 ]]; then
            if [[ "$left_more" == "$right_more" ]]; then
                printf '%s' 0
            elif [[ "$left_more" == 1 ]]; then
                printf '%s' 1
            else
                printf '%s' -1
            fi
            return
        fi
    done
}

sha256_file() { # <file>
    local output
    if command -v sha256sum >/dev/null 2>&1; then
        output="$(sha256sum "$1")"
    elif command -v shasum >/dev/null 2>&1; then
        output="$(shasum -a 256 "$1")"
    else
        fail "sha256sum or shasum is required to verify the release"
    fi
    printf '%s' "${output%%[[:space:]]*}" | tr '[:upper:]' '[:lower:]'
}

validate_archive_paths() { # <archive> <expected-root>
    local archive="$1" expected_root="$2" entry details count=0
    tar -tzf "$archive" >"$WORK_DIR/archive-files"
    while IFS= read -r entry; do
        count=$((count + 1))
        [[ -n "$entry" && "$entry" != /* && "$entry" != *$'\r'* ]] ||
            fail "release archive contains an unsafe path"
        case "$entry" in
            "$expected_root" | "$expected_root/" | "$expected_root/"*) ;;
            *) fail "release archive has an unexpected top-level path: $entry" ;;
        esac
        case "/${entry%/}/" in
            */../* | */./*) fail "release archive contains path traversal: $entry" ;;
        esac
    done <"$WORK_DIR/archive-files"
    [[ "$count" -gt 0 ]] || fail "release archive is empty"

    tar -tvzf "$archive" >"$WORK_DIR/archive-details"
    while IFS= read -r details; do
        case "${details:0:1}" in
            - | d) ;;
            *) fail "release archive contains a link or special file" ;;
        esac
    done <"$WORK_DIR/archive-details"
}

validate_bundle() { # <bundle> <release-version>
    local bundle="$1" release_version="$2" unexpected
    [[ -d "$bundle" && ! -L "$bundle" ]] || fail "invalid extracted release layout"
    for required in VERSION dotlad bin/dotlad lib/runtime.sh; do
        [[ -f "$bundle/$required" && ! -L "$bundle/$required" ]] ||
            fail "release archive is missing $required"
    done
    [[ "$(cat "$bundle/VERSION")" == "$release_version" ]] ||
        fail "release archive version does not match v$release_version"
    unexpected="$(find "$bundle/VERSION" "$bundle/dotlad" "$bundle/bin" "$bundle/lib" \
        -type l -print -o ! -type d ! -type f -print | sed -n '1p')"
    [[ -z "$unexpected" ]] || fail "release runtime contains an unsafe entry: $unexpected"
}

normalize_install_paths() {
    local install_name
    is_absolute_safe_path "$INSTALL_DIR" ||
        fail "DOTLAD_INSTALL_DIR must be a safe absolute path: $INSTALL_DIR"
    is_absolute_safe_path "$BIN_DIR" ||
        fail "DOTLAD_BIN_DIR must be a safe absolute path: $BIN_DIR"
    [[ "$BIN_DIR" != *:* ]] ||
        fail "DOTLAD_BIN_DIR cannot contain ':' because it is a PATH separator"

    install_name="$(basename "$INSTALL_DIR")"
    [[ "$install_name" != "." && "$install_name" != ".." ]] ||
        fail "DOTLAD_INSTALL_DIR must name an application directory"
    INSTALL_PARENT="$(dirname "$INSTALL_DIR")"
    mkdir -p "$INSTALL_PARENT" "$BIN_DIR"
    INSTALL_PARENT="$(cd "$INSTALL_PARENT" && pwd -P)"
    BIN_DIR="$(cd "$BIN_DIR" && pwd -P)"
    INSTALL_DIR="$INSTALL_PARENT/$install_name"
    COMMAND_PATH="$BIN_DIR/dotlad"

    case "$BIN_DIR/" in
        "$INSTALL_DIR/"*) fail "DOTLAD_BIN_DIR cannot be inside DOTLAD_INSTALL_DIR" ;;
    esac
    case "$INSTALL_DIR/" in
        "$COMMAND_PATH/"*) fail "DOTLAD_INSTALL_DIR conflicts with $COMMAND_PATH" ;;
    esac
}

validate_existing_installation() {
    if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
        is_managed_runtime "$INSTALL_DIR" ||
            fail "refusing to replace unmanaged path: $INSTALL_DIR"
    fi
    if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
        is_managed_command "$COMMAND_PATH" ||
            fail "refusing to replace unmanaged path: $COMMAND_PATH"
    fi
}

install_bundle() { # <bundle> <release-version>
    local bundle="$1" release_version="$2" installed_version quoted_runtime

    validate_existing_installation
    STAGE_DIR="$(mktemp -d "$INSTALL_PARENT/.dotlad-install.XXXXXX")"
    mkdir -p "$STAGE_DIR/bin"
    cp "$bundle/VERSION" "$bundle/dotlad" "$STAGE_DIR/"
    cp "$bundle/bin/dotlad" "$STAGE_DIR/bin/"
    cp -R "$bundle/lib" "$STAGE_DIR/"
    printf '%s\n' "$MANAGED_MARKER" >"$STAGE_DIR/.dotlad-managed"
    chmod +x "$STAGE_DIR/dotlad" "$STAGE_DIR/bin/dotlad"

    installed_version="$(cd / && "$STAGE_DIR/dotlad" --version)"
    [[ "$installed_version" == "dotlad $release_version" ]] ||
        fail "staged command failed validation"

    COMMAND_TEMP="$(mktemp "$BIN_DIR/.dotlad-command.XXXXXX")"
    quoted_runtime="${INSTALL_DIR//\'/\'\\\'\'}"
    {
        printf '#!/usr/bin/env bash\n'
        printf '%s\n' "$COMMAND_MARKER"
        printf 'set -euo pipefail\n'
        printf "exec '%s/dotlad' \"\$@\"\n" "$quoted_runtime"
    } >"$COMMAND_TEMP"
    chmod +x "$COMMAND_TEMP"

    if [[ -e "$INSTALL_DIR" ]]; then
        RUNTIME_BACKUP="$(mktemp -d "$INSTALL_PARENT/.dotlad-old.XXXXXX")"
        rmdir "$RUNTIME_BACKUP"
        mv "$INSTALL_DIR" "$RUNTIME_BACKUP"
    fi
    mv "$STAGE_DIR" "$INSTALL_DIR"
    STAGE_DIR=""
    RUNTIME_INSTALLED=1

    # Deterministic fault injection for the rollback integration contract.
    [[ -z "${DOTLAD_INSTALL_TEST_FAIL_AFTER_RUNTIME:-}" ]] || exit 97

    if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
        COMMAND_BACKUP="$(mktemp "$BIN_DIR/.dotlad-command-old.XXXXXX")"
        rm -f "$COMMAND_BACKUP"
        mv "$COMMAND_PATH" "$COMMAND_BACKUP"
    fi
    mv "$COMMAND_TEMP" "$COMMAND_PATH"
    COMMAND_TEMP=""
    COMMAND_INSTALLED=1

    installed_version="$(cd / && "$COMMAND_PATH" --version)"
    [[ "$installed_version" == "dotlad $release_version" ]] ||
        fail "installed command failed validation"
    COMMITTED=1
}

print_path_instruction() {
    local startup_file quoted_bin
    case ":$PATH:" in
        *":$BIN_DIR:"*) return 0 ;;
    esac
    case "${SHELL##*/}" in
        zsh) startup_file="$HOME/.zshrc" ;;
        bash)
            if [[ "$PLATFORM" == macos ]]; then
                startup_file="$HOME/.bash_profile"
            else
                startup_file="$HOME/.bashrc"
            fi
            ;;
        *) startup_file="your shell startup file" ;;
    esac
    quoted_bin="${BIN_DIR//\'/\'\\\'\'}"
    printf '\n%s is not on PATH. Add this line to %s:\n\n' "$BIN_DIR" "$startup_file"
    printf "  export PATH='%s':\"\$PATH\"\n" "$quoted_bin"
}

configure_colors
PLATFORM="$(detect_platform)" ||
    fail "unsupported platform: $(uname -s 2>/dev/null || printf unknown)"
normalize_install_paths
validate_existing_installation
if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ||
    -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
    [[ -e "$INSTALL_DIR" && -e "$COMMAND_PATH" ]] ||
        fail "managed installation is incomplete; expected both $INSTALL_DIR and $COMMAND_PATH"
    INSTALL_ACTION="update"
    [[ -f "$INSTALL_DIR/VERSION" ]] ||
        fail "managed installation is missing VERSION: $INSTALL_DIR"
    CURRENT_VERSION="v$(cat "$INSTALL_DIR/VERSION")"
    validate_version "$CURRENT_VERSION"
fi
print_banner

TEMP_ROOT="${TMPDIR:-/tmp}"
is_absolute_safe_path "$TEMP_ROOT" || fail "TMPDIR must be a safe absolute path"
TEMP_ROOT="$(cd "$TEMP_ROOT" && pwd -P)"
WORK_DIR="$(mktemp -d "$TEMP_ROOT/dotlad-installer.XXXXXX")"

VERSION="${DOTLAD_VERSION:-}"
if [[ -z "$VERSION" ]]; then
    progress "Resolving the latest GitHub release"
    download "$API_URL/releases/latest" "$WORK_DIR/latest.json"
    VERSION="$(sed -n \
        's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$WORK_DIR/latest.json" | sed -n '1p')"
    [[ -n "$VERSION" ]] || fail "could not determine the latest release"
fi
validate_version "$VERSION"
if [[ "$(compare_versions "$VERSION" "$MIN_SUPPORTED_VERSION")" == -1 ]]; then
    fail "release $VERSION is not supported; use $MIN_SUPPORTED_VERSION or newer"
fi

RELEASE_VERSION="${VERSION#v}"
ARCHIVE_NAME="dotlad-$RELEASE_VERSION.tar.gz"
CHECKSUM_NAME="dotlad-$RELEASE_VERSION.sha256"
RELEASE_URL="$GITHUB_URL/releases/download/$VERSION"
ARCHIVE_PATH="$WORK_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$WORK_DIR/$CHECKSUM_NAME"

if [[ "$INSTALL_ACTION" == update ]]; then
    case "$(compare_versions "$CURRENT_VERSION" "$VERSION")" in
        -1)
            INSTALL_ACTION="update"
            info "updating from $CURRENT_VERSION to $VERSION for $PLATFORM"
            ;;
        1)
            INSTALL_ACTION="downgrade"
            info "downgrading from $CURRENT_VERSION to $VERSION for $PLATFORM"
            ;;
        *)
            INSTALL_ACTION="reinstall"
            info "reinstalling $VERSION for $PLATFORM"
            ;;
    esac
else
    info "installing $VERSION for $PLATFORM"
fi
progress "Downloading the release archive and checksum"
download "$RELEASE_URL/$ARCHIVE_NAME" "$ARCHIVE_PATH" 1
download "$RELEASE_URL/$CHECKSUM_NAME" "$CHECKSUM_PATH"

progress "Verifying the SHA-256 checksum"
read -r EXPECTED_SHA256 _ <"$CHECKSUM_PATH" ||
    fail "could not read the release checksum"
EXPECTED_SHA256="$(printf '%s' "$EXPECTED_SHA256" | tr '[:upper:]' '[:lower:]')"
[[ "$EXPECTED_SHA256" =~ ^[[:xdigit:]]{64}$ ]] ||
    fail "release checksum file is malformed"
ACTUAL_SHA256="$(sha256_file "$ARCHIVE_PATH")"
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] ||
    fail "release archive checksum mismatch"
success "SHA-256 checksum verified"

ARCHIVE_ROOT="dotlad-$RELEASE_VERSION"
progress "Inspecting the release archive"
validate_archive_paths "$ARCHIVE_PATH" "$ARCHIVE_ROOT"
mkdir "$WORK_DIR/extracted"
progress "Extracting the release archive"
tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR/extracted"
BUNDLE_DIR="$WORK_DIR/extracted/$ARCHIVE_ROOT"
validate_bundle "$BUNDLE_DIR" "$RELEASE_VERSION"
progress "Staging the runtime and command"
install_bundle "$BUNDLE_DIR" "$RELEASE_VERSION"

case "$INSTALL_ACTION" in
    update) info "updated from $CURRENT_VERSION to $VERSION" ;;
    downgrade) info "downgraded from $CURRENT_VERSION to $VERSION" ;;
    reinstall) info "reinstalled $VERSION" ;;
    *) info "installed $VERSION" ;;
esac
printf '  Runtime: %s\n' "$INSTALL_DIR"
printf '  Command: %s\n' "$COMMAND_PATH"
print_path_instruction
print_completion "$VERSION"
