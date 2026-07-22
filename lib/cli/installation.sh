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
    [[ "$1" != uninstall || -n "$(cli_installation_kind)" ]]
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
