#!/usr/bin/env bash
# Install or remove a self-contained Dotlad runtime.
set -euo pipefail

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${DOTLAD_PREFIX:-$HOME/.local}"
ACTION="install"

usage() {
    cat <<'EOF'
Install the dotlad command and its runtime.

Usage:
  ./install.sh [--prefix PATH]
  ./install.sh [--prefix PATH] --uninstall

Options:
  --prefix PATH  Installation prefix (default: ~/.local)
  --uninstall    Remove the managed command and runtime
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)
            [[ $# -gt 1 ]] || {
                printf 'dotlad install: --prefix needs a path\n' >&2
                exit 1
            }
            PREFIX="$2"
            shift 2
            ;;
        --prefix=*)
            PREFIX="${1#*=}"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'dotlad install: unknown option: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

[[ "$PREFIX" == /* ]] ||
    {
        printf 'dotlad install: prefix must be an absolute path: %s\n' "$PREFIX" >&2
        exit 1
    }

RUNTIME_DIR="$PREFIX/libexec/dotlad"
BIN_DIR="$PREFIX/bin"
COMMAND_PATH="$BIN_DIR/dotlad"
COMMAND_MARKER="# dotlad managed launcher"

is_managed_command() {
    [[ -f "$COMMAND_PATH" ]] && grep -Fqx "$COMMAND_MARKER" "$COMMAND_PATH"
}

is_managed_runtime() {
    [[ -f "$RUNTIME_DIR/.dotlad-managed" ]]
}

if [[ "$ACTION" == "uninstall" ]]; then
    # Validate ownership of every target before removing either one, so a mixed
    # managed/unmanaged installation is left untouched on refusal.
    if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
        is_managed_command ||
            {
                printf 'dotlad install: refusing to remove unmanaged path: %s\n' "$COMMAND_PATH" >&2
                exit 1
            }
    fi
    if [[ -e "$RUNTIME_DIR" || -L "$RUNTIME_DIR" ]]; then
        is_managed_runtime ||
            {
                printf 'dotlad install: refusing to remove unmanaged runtime: %s\n' "$RUNTIME_DIR" >&2
                exit 1
            }
    fi
    [[ ! -e "$COMMAND_PATH" && ! -L "$COMMAND_PATH" ]] || rm -f "$COMMAND_PATH"
    [[ ! -e "$RUNTIME_DIR" && ! -L "$RUNTIME_DIR" ]] || rm -rf "$RUNTIME_DIR"
    printf 'Removed dotlad from %s\n' "$PREFIX"
    exit 0
fi

for required in VERSION dotlad bin/dotlad completions/_dotlad lib/runtime.sh; do
    [[ -e "$SOURCE_ROOT/$required" ]] ||
        {
            printf 'dotlad install: incomplete source tree: missing %s\n' "$required" >&2
            exit 1
        }
done

if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
    is_managed_command ||
        {
            printf 'dotlad install: refusing to replace unmanaged path: %s\n' "$COMMAND_PATH" >&2
            exit 1
        }
fi
if [[ -e "$RUNTIME_DIR" || -L "$RUNTIME_DIR" ]]; then
    is_managed_runtime ||
        {
            printf 'dotlad install: refusing to replace unmanaged runtime: %s\n' "$RUNTIME_DIR" >&2
            exit 1
        }
fi

mkdir -p "$PREFIX/libexec" "$BIN_DIR"
stage="$(mktemp -d "$PREFIX/libexec/.dotlad-install.XXXXXX")"
old_runtime=""
temp_command="$BIN_DIR/.dotlad.$$"
had_command=0
had_runtime=0
committed=0
[[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]] && had_command=1

cleanup() {
    if [[ "$committed" != 1 ]]; then
        if [[ -n "$old_runtime" && -e "$old_runtime" ]]; then
            [[ ! -e "$RUNTIME_DIR" ]] || rm -rf "$RUNTIME_DIR"
            mv "$old_runtime" "$RUNTIME_DIR" || true
        elif [[ "$had_runtime" == 0 && ! -e "$stage" && -e "$RUNTIME_DIR" ]]; then
            rm -rf "$RUNTIME_DIR"
        fi
        if [[ "$had_command" == 0 && ! -e "$temp_command" ]] && is_managed_command; then
            rm -f "$COMMAND_PATH"
        fi
    elif [[ -n "$old_runtime" && -e "$old_runtime" ]]; then
        rm -rf "$old_runtime"
    fi
    [[ -z "$stage" || ! -e "$stage" ]] || rm -rf "$stage"
    [[ ! -e "$temp_command" && ! -L "$temp_command" ]] || rm -f "$temp_command"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

mkdir -p "$stage/bin" "$stage/completions" "$stage/lib/resolvers" "$stage/lib/tui"
cp "$SOURCE_ROOT/VERSION" "$SOURCE_ROOT/dotlad" "$stage/"
cp "$SOURCE_ROOT/bin/dotlad" "$stage/bin/"
cp "$SOURCE_ROOT/completions/_dotlad" "$stage/completions/"
cp "$SOURCE_ROOT/lib/"*.sh "$stage/lib/"
cp "$SOURCE_ROOT/lib/resolvers/"*.sh "$stage/lib/resolvers/"
cp "$SOURCE_ROOT/lib/tui/"*.sh "$stage/lib/tui/"
: >"$stage/.dotlad-managed"
chmod +x "$stage/dotlad" "$stage/bin/dotlad"
if ! "$stage/bin/dotlad" --version >/dev/null 2>&1; then
    printf 'dotlad install: staged runtime failed its self-check\n' >&2
    exit 1
fi

if [[ -e "$RUNTIME_DIR" || -L "$RUNTIME_DIR" ]]; then
    had_runtime=1
    old_runtime="$PREFIX/libexec/.dotlad-old.$$"
    [[ ! -e "$old_runtime" ]] ||
        {
            printf 'dotlad install: temporary path already exists: %s\n' "$old_runtime" >&2
            exit 1
        }
    mv "$RUNTIME_DIR" "$old_runtime"
fi

mv "$stage" "$RUNTIME_DIR"
stage=""

# Deterministic fault injection for the rollback integration contract.
[[ -z "${DOTLAD_INSTALL_TEST_FAIL_AFTER_RUNTIME:-}" ]] || exit 97

cat >"$temp_command" <<'EOF'
#!/usr/bin/env bash
# dotlad managed launcher
set -euo pipefail
runtime="$(cd "$(dirname "${BASH_SOURCE[0]}")/../libexec/dotlad" && pwd)"
exec "$runtime/dotlad" "$@"
EOF
chmod +x "$temp_command"
if ! mv -f "$temp_command" "$COMMAND_PATH"; then
    printf 'dotlad install: could not create command: %s\n' "$COMMAND_PATH" >&2
    exit 1
fi
committed=1

[[ -z "$old_runtime" ]] || rm -rf "$old_runtime"
version="$(cat "$RUNTIME_DIR/VERSION")"
printf 'Installed dotlad %s at %s\n' "$version" "$COMMAND_PATH"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) printf 'Add %s to PATH to run dotlad.\n' "$BIN_DIR" ;;
esac
