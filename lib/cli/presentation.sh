# CLI help and generated completion output.

cli_print_help_row() { # <label-width> <label> <description>
    local width="$1" label="$2" padding
    padding=$((width - ${#label}))
    [[ "$padding" -lt 0 ]] && padding=0
    printf '  %s%*s  %s\n' "$label" "$padding" "" "$3"
}

cli_print_zsh_completion() {
    local completion_project_root="" completion_backup_root="" i
    if [[ "$DOTLAD_PROJECT_ROOT_EXPLICIT" == 1 ]]; then
        completion_project_root="$ROOT"
    fi
    if [[ "$DOTLAD_BACKUP_ROOT_EXPLICIT" == 1 ]]; then
        completion_backup_root="$DOTLAD_BACKUP_ROOT"
    fi
    case "$completion_backup_root" in
        "~") completion_backup_root="$HOME" ;;
        \~/*) completion_backup_root="$HOME/${completion_backup_root#\~/}" ;;
    esac
    [[ -z "$completion_backup_root" || "$completion_backup_root" == /* ]] ||
        completion_backup_root="$PWD/$completion_backup_root"
    cat "$DOTLAD_RUNTIME_ROOT/lib/cli/completion.zsh"
    printf '\n_dotlad_root_commands=('
    for ((i = 0; i < ${#CLI_COMMAND_NAMES[@]}; i++)); do
        [[ -n "${CLI_COMMAND_NAMES[$i]}" ]] || continue
        cli_command_is_visible "${CLI_COMMAND_NAMES[$i]}" || continue
        printf ' %q' "${CLI_COMMAND_NAMES[$i]}"
    done
    printf ' )\n_dotlad_root_descriptions=('
    for ((i = 0; i < ${#CLI_COMMAND_NAMES[@]}; i++)); do
        [[ -n "${CLI_COMMAND_NAMES[$i]}" ]] || continue
        cli_command_is_visible "${CLI_COMMAND_NAMES[$i]}" || continue
        printf ' %q' "${CLI_COMMAND_DESCRIPTIONS[$i]}"
    done
    printf ' )\n_dotlad_option_alias_groups=('
    for ((i = 0; i < ${#CLI_OPTION_ALIASES[@]}; i++)); do
        printf ' %q' "${CLI_OPTION_ALIASES[$i]}"
    done
    printf ' )\n_dotlad_option_group_descriptions=('
    for ((i = 0; i < ${#CLI_OPTION_ALIASES[@]}; i++)); do
        printf ' %q' "${CLI_OPTION_DESCRIPTIONS[$i]}"
    done
    printf ' )\n_dotlad_register %q %q %q\n' \
        "$DOTLAD_COMMAND_NAME" "$completion_project_root" "$completion_backup_root"
}

cli_print_completion_metadata() {
    local i file name extends tools item direct_tools
    for ((i = 0; i < T_COUNT; i++)); do
        platform_list_matches "${T_PLATFORMS[$i]}" "$DOTLAD_PLATFORM" || continue
        printf 'tool\037%s\037%s\037%s\n' \
            "${T_NAME[$i]}" "${T_ICON[$i]}" "${T_DESC[$i]}"
    done
    [[ -d "$ROOT/profiles" && ! -L "$ROOT/profiles" ]] || return 0
    for file in "$ROOT"/profiles/*.conf; do
        [[ -e "$file" ]] || continue
        name="${file##*/}"
        name="${name%.conf}"
        profile_tools "$name" >/dev/null || return 1
        extends=""
        tools=""
        direct_tools=""
        assignment_read_file "$file" profile || return 1
        for item in $tools; do
            direct_tools="${direct_tools:+$direct_tools }$item"
        done
        printf 'profile\037%s\037%s\037%s\n' \
            "$name" "$extends" "$direct_tools"
    done
}

cli_usage() {
    local command_width=0 option_width=0 i label
    printf "%s — install a project's packages and configs onto your system.\n\n" \
        "$DOTLAD_DISPLAY_NAME"

    printf 'Usage:\n'
    for ((i = 0; i < ${#CLI_COMMAND_USAGE[@]}; i++)); do
        cli_command_is_visible "${CLI_COMMAND_NAMES[$i]}" || continue
        label="$DOTLAD_COMMAND_NAME${CLI_COMMAND_USAGE[$i]:+ ${CLI_COMMAND_USAGE[$i]}}"
        [[ ${#label} -le $command_width ]] || command_width=${#label}
    done
    for ((i = 0; i < ${#CLI_COMMAND_USAGE[@]}; i++)); do
        cli_command_is_visible "${CLI_COMMAND_NAMES[$i]}" || continue
        label="$DOTLAD_COMMAND_NAME${CLI_COMMAND_USAGE[$i]:+ ${CLI_COMMAND_USAGE[$i]}}"
        cli_print_help_row "$command_width" "$label" "${CLI_COMMAND_DESCRIPTIONS[$i]}"
    done

    printf "\nThe list shows each tool's state:\n"
    cli_print_help_row 18 "✓ up to date" "the config matches the repo, or the package is installed"
    cli_print_help_row 18 "↑ update available" "the config differs — updating would change it"
    cli_print_help_row 18 "+ not set up" "no config deployed yet"
    cli_print_help_row 18 "+ not installed" "one or more declared packages are missing"

    cat <<EOF

Move with ↑/↓, pick with space and run with enter (a = all, d = diff,
m = mode, q = quit). Replaced files are backed up to $(pretty_path "$DOTLAD_BACKUP_ROOT") and
appear at the bottom of the list to restore. Named resolvers can preserve
machine-local JSON, TOML, and Git values or deploy a repository symlink.
Letter shortcuts use the same physical keys on Ukrainian keyboard layouts.

JSON, TOML, and Git config merging requires jq, yq, and git respectively.
HTTPS installers require curl; checksum-pinned installers also require
sha256sum or shasum.

Modes:
EOF
    for ((i = 0; i < ${#CLI_OPTION_NAMES[@]}; i++)); do
        case "${CLI_OPTION_NAMES[$i]}" in
            packages-only | config-only | symlink)
                cli_print_help_row 15 "${CLI_OPTION_USAGE[$i]}" \
                    "${CLI_OPTION_DESCRIPTIONS[$i]}"
                ;;
        esac
    done
    cli_print_help_row 15 "default" "installs packages and deploys config"

    printf '\nOptions:\n'
    for ((i = 0; i < ${#CLI_OPTION_USAGE[@]}; i++)); do
        [[ ${#CLI_OPTION_USAGE[$i]} -le $option_width ]] ||
            option_width=${#CLI_OPTION_USAGE[$i]}
    done
    for ((i = 0; i < ${#CLI_OPTION_USAGE[@]}; i++)); do
        cli_print_help_row "$option_width" "${CLI_OPTION_USAGE[$i]}" \
            "${CLI_OPTION_DESCRIPTIONS[$i]}"
    done

    printf '\n--plain changes presentation only; use plan or --dry-run to guarantee no changes.\n'
}
