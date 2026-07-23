# Global installation commands that do not load project manifests.

cli_installation_kind() {
    if [[ -f "$DOTLAD_RUNTIME_ROOT/.dotlad-managed" ]] &&
        grep -Fqx 'dotlad managed installation' \
            "$DOTLAD_RUNTIME_ROOT/.dotlad-managed"; then
        printf 'curl'
    elif [[ -f "$DOTLAD_RUNTIME_ROOT/.dotlad-homebrew" ]] &&
        grep -Fqx 'dotlad Homebrew installation' \
            "$DOTLAD_RUNTIME_ROOT/.dotlad-homebrew"; then
        printf 'homebrew'
    fi
}

cli_command_is_visible() { # <command-name>
    case "$1" in
        update | uninstall) [[ -n "$(cli_installation_kind)" ]] ;;
        *) return 0 ;;
    esac
}

cli_update() {
    local kind command_path bin_dir update_script status
    kind="$(cli_installation_kind)"
    case "$kind" in
        homebrew)
            printf 'Dotlad was installed with Homebrew.\n'
            printf 'Run: brew upgrade dotlad\n'
            return 0
            ;;
        curl)
            command_path="${DOTLAD_LAUNCHER_PATH:-}"
            [[ -n "$command_path" ]] ||
                command_path="$(command -v dotlad 2>/dev/null || true)"
            if [[ -z "$command_path" || ! -f "$command_path" ||
                -L "$command_path" ]] ||
                ! grep -Fqx '# dotlad managed launcher' "$command_path"; then
                err "could not locate the managed dotlad launcher"
                return 1
            fi
            bin_dir="$(cd "$(dirname "$command_path")" && pwd -P)"
            update_script="$(mktemp "${TMPDIR:-/tmp}/dotlad-update.XXXXXX")" || {
                err "could not create a temporary update script"
                return 1
            }
            if command -v curl >/dev/null 2>&1; then
                if ! curl -fsSL -o "$update_script" \
                    https://raw.githubusercontent.com/vkarabinovych/dotlad/main/install.sh; then
                    rm -f "$update_script"
                    err "update script download failed"
                    return 1
                fi
            elif command -v wget >/dev/null 2>&1; then
                if ! wget -q -O "$update_script" \
                    https://raw.githubusercontent.com/vkarabinovych/dotlad/main/install.sh; then
                    rm -f "$update_script"
                    err "update script download failed"
                    return 1
                fi
            else
                rm -f "$update_script"
                err "curl or wget is required to update Dotlad"
                return 1
            fi
            if [[ ! -s "$update_script" ]]; then
                rm -f "$update_script"
                err "downloaded update script is empty"
                return 1
            fi
            if DOTLAD_VERSION='' \
                DOTLAD_INSTALL_DIR="$DOTLAD_RUNTIME_ROOT" \
                DOTLAD_BIN_DIR="$bin_dir" /bin/bash "$update_script"; then
                status=0
            else
                status=$?
            fi
            rm -f "$update_script"
            return "$status"
            ;;
        *)
            err "update is only available for a global installation"
            return 1
            ;;
    esac
}

cli_uninstall() {
    local kind command_path bin_dir
    kind="$(cli_installation_kind)"
    case "$kind" in
        homebrew)
            printf 'Dotlad was installed with Homebrew.\n'
            printf 'Run: brew uninstall dotlad\n'
            ;;
        curl)
            command_path="${DOTLAD_LAUNCHER_PATH:-}"
            [[ -n "$command_path" ]] ||
                command_path="$(command -v dotlad 2>/dev/null || true)"
            if [[ -z "$command_path" || ! -f "$command_path" ||
                -L "$command_path" ]] ||
                ! grep -Fqx '# dotlad managed launcher' "$command_path"; then
                err "could not locate the managed dotlad launcher"
                return 1
            fi
            bin_dir="$(cd "$(dirname "$command_path")" && pwd -P)"
            DOTLAD_INSTALL_DIR="$DOTLAD_RUNTIME_ROOT" DOTLAD_BIN_DIR="$bin_dir" \
                exec /bin/bash "$DOTLAD_RUNTIME_ROOT/uninstall.sh"
            ;;
        *)
            err "uninstall is only available for a global installation"
            return 1
            ;;
    esac
}
