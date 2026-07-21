# shellcheck disable=SC2034  # shared command state is consumed by sibling libs
# lib/commands.sh — command implementations; bin/dotlad owns parsing.

selection_all() {
    local i
    SELECTED_NAMES=()
    for ((i = 0; i < T_COUNT; i++)); do
        tool_relevant "$i" && SELECTED_NAMES+=("${T_NAME[$i]}")
    done
    return 0
}

selection_require_any() {
    [[ ${#SELECTED_NAMES[@]} -gt 0 ]] ||
        {
            err "no tools for $(mode_label) mode"
            return 1
        }
}

selection_profile() { # <profile>
    local name i
    SELECTED_NAMES=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        i="$(tool_find "$name")"
        tool_relevant "$i" && SELECTED_NAMES+=("$name")
    done < <(profile_tools "$1")
    return 0
}

selection_explicit() { # <tool names...>
    local name i
    SELECTED_NAMES=()
    for name in "$@"; do
        i="$(tool_find "$name")" || {
            err "unknown tool: $name"
            return 1
        }
        tool_platform_supported "$i" ||
            {
                err "$name is not available on $DOTLAD_PLATFORM"
                return 1
            }
        tool_relevant "$i" ||
            {
                err "$name has nothing to do in $(mode_label) mode"
                return 1
            }
        SELECTED_NAMES+=("$name")
    done
    return 0
}

cmd_backups() {
    local tab name files directories found=0
    tab="$(printf '\t')"
    title "Restore points"
    while IFS="$tab" read -r name files directories; do
        [[ -n "$name" ]] || continue
        printf '%s\t%s\n' "$name" "$(backup_change_summary "$files" "$directories")"
        found=1
    done < <(list_backups)
    [[ "$found" == 1 ]] || hint "no restore points"
}

cmd_restore_cli() {
    local name="$1" files directories
    backup_name_valid "$name" || {
        err "bad backup name: $name"
        return 1
    }
    backup_exists "$name" || {
        err "no such backup: $name"
        return 1
    }
    files="$(backup_count "$name")"
    directories="$(backup_directory_count "$name")"
    [[ "$files" -gt 0 || "$directories" -gt 0 ]] ||
        {
            hint "everything already matches this backup"
            return 0
        }
    confirm "Restore $(backup_change_summary "$files" "$directories") from $(fmt_backup_ts "$name")? (current versions backed up)" ||
        {
            hint "cancelled"
            return 0
        }
    restore_backup "$name"
}

cmd_backup_delete_cli() {
    local name="$1"
    backup_name_valid "$name" || {
        err "bad backup name: $name"
        return 1
    }
    backup_exists "$name" || {
        err "no such backup: $name"
        return 1
    }
    confirm "Delete backup $(fmt_backup_ts "$name")? Cannot be undone." ||
        {
            hint "cancelled"
            return 0
        }
    delete_backup "$name"
    ok "deleted backup $(fmt_backup_ts "$name")"
}

cmd_plan() {
    if [[ $# -eq 0 || "${1:-}" == all ]]; then
        [[ $# -le 1 ]] ||
            {
                err "usage: $DOTLAD_COMMAND_NAME plan [all|profile NAME|TOOL…]"
                return 1
            }
        selection_all
    elif [[ "$1" == profile ]]; then
        [[ $# -eq 2 ]] || {
            err "usage: $DOTLAD_COMMAND_NAME plan profile NAME"
            return 1
        }
        selection_profile "$2"
    else
        selection_explicit "$@" || return 1
    fi
    selection_require_any || return 1
    plan_selected "${SELECTED_NAMES[@]}"
}

selection_has_packages() { # <tool names...>
    local name i
    mode_packages_enabled || return 1
    for name in "$@"; do
        i="$(tool_find "$name")" || continue
        tool_has_packages "$i" && return 0
    done
    return 1
}

selection_has_config() { # <tool names...>
    local name i
    mode_config_enabled || return 1
    for name in "$@"; do
        i="$(tool_find "$name")" || continue
        tool_has_config "$i" && return 0
    done
    return 1
}

selection_action() { # <tool names...>
    local packages=0 config=0
    selection_has_packages "$@" && packages=1
    selection_has_config "$@" && config=1
    if [[ "$packages" == 1 && "$config" == 1 ]]; then
        printf 'Install packages and deploy config for'
    elif [[ "$packages" == 1 ]]; then
        printf 'Install packages for'
    else
        printf 'Deploy config for'
    fi
}

selection_prompt() { # <target-label> <tool names...>
    local target="$1"
    shift
    printf '%s %s?' "$(selection_action "$@")" "$target"
    selection_has_config "$@" && printf ' (replaced files are backed up)'
    return 0
}

ensure_brew() {
    local candidate platform candidates=()
    command -v brew >/dev/null 2>&1 && return 0
    confirm "Homebrew is missing. Install it now?" || return 0
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    platform="${DOTLAD_PLATFORM:-$(platform_detect)}"
    if [[ "$platform" == linux || "$platform" == wsl ]]; then
        candidates=("$HOME/.linuxbrew/bin/brew" /home/linuxbrew/.linuxbrew/bin/brew)
    else
        candidates=(/opt/homebrew/bin/brew /usr/local/bin/brew)
    fi
    for candidate in "${candidates[@]}"; do
        [[ -x "$candidate" ]] || continue
        eval "$("$candidate" shellenv)"
        break
    done
    command -v brew >/dev/null 2>&1 || {
        err "Homebrew was installed but is not available on PATH"
        return 1
    }
    BREW_PREFIX=""
    BREW_PREFIX_SET=""
}

cmd_profile() {
    local profile="$1"
    selection_profile "$profile"
    [[ ${#SELECTED_NAMES[@]} -gt 0 ]] ||
        fatal "profile '$profile' has no tools for $(mode_label) mode"
    title "Profile: $profile"
    confirm "$(selection_prompt "${#SELECTED_NAMES[@]} tool(s) from '$profile'" \
        "${SELECTED_NAMES[@]}")" ||
        {
            hint "cancelled"
            exit 0
        }
    selection_has_packages "${SELECTED_NAMES[@]}" && ensure_brew
    DOTLAD_YES=1
    run_selected "${SELECTED_NAMES[@]}"
}

cmd_all() {
    title "Set up this machine — $(mode_label)"
    print_list
    echo ""
    selection_all
    selection_require_any || return 1
    confirm "$(selection_prompt 'every relevant tool now' "${SELECTED_NAMES[@]}")" ||
        {
            hint "cancelled"
            exit 0
        }
    selection_has_packages "${SELECTED_NAMES[@]}" && ensure_brew
    DOTLAD_YES=1
    run_selected "${SELECTED_NAMES[@]}"
}
