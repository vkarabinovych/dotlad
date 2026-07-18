# shellcheck disable=SC2034  # shared command state is consumed by sibling libs
# lib/commands.sh — command implementations; bin/dotlad owns parsing.

selection_all() {
    local i
    SELECTED_NAMES=()
    for (( i = 0; i < T_COUNT; i++ )); do
        tool_relevant "$i" && SELECTED_NAMES+=("${T_NAME[$i]}")
    done
}

selection_profile() {  # <profile>
    local name i
    SELECTED_NAMES=()
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        i="$(tool_find "$name")"
        tool_relevant "$i" && SELECTED_NAMES+=("$name")
    done < <(profile_tools "$1")
}

selection_explicit() {  # <tool names...>
    local name i
    SELECTED_NAMES=()
    for name in "$@"; do
        i="$(tool_find "$name")" || { err "unknown tool: $name"; return 1; }
        tool_relevant "$i" \
            || { err "$name has nothing to do in $(mode_label) mode"; return 1; }
        SELECTED_NAMES+=("$name")
    done
}

cmd_backups() {
    local tab name count found=0
    tab="$(printf '\t')"
    title "Restore points"
    while IFS="$tab" read -r name count; do
        [[ -n "$name" ]] || continue
        printf '%s\t%s %s\n' "$name" "$count" "$(file_noun "$count")"; found=1
    done < <(list_backups)
    [[ "$found" == 1 ]] || hint "no restore points"
}

cmd_restore_cli() {
    local name="$1" count
    backup_name_valid "$name" || { err "bad backup name: $name"; return 1; }
    count="$(backup_count "$name")"
    [[ "$count" -gt 0 ]] || { err "no such or empty backup: $name"; return 1; }
    confirm "Restore ${count} file(s) from $(fmt_backup_ts "$name")? (current versions backed up)" \
        || { hint "cancelled"; return 0; }
    restore_backup "$name"
}

cmd_backup_delete_cli() {
    local name="$1" count
    backup_name_valid "$name" || { err "bad backup name: $name"; return 1; }
    count="$(backup_count "$name")"
    [[ "$count" -gt 0 ]] || { err "no such or empty backup: $name"; return 1; }
    confirm "Delete backup $(fmt_backup_ts "$name") — ${count} file(s)? Cannot be undone." \
        || { hint "cancelled"; return 0; }
    delete_backup "$name"
    ok "deleted backup $(fmt_backup_ts "$name")"
}

cmd_plan() {
    if [[ $# -eq 0 || "${1:-}" == all ]]; then
        [[ $# -le 1 ]] \
            || { err "usage: $DOTLAD_COMMAND_NAME plan [all|profile NAME|TOOL…]"; return 1; }
        selection_all
    elif [[ "$1" == profile ]]; then
        [[ $# -eq 2 ]] || { err "usage: $DOTLAD_COMMAND_NAME plan profile NAME"; return 1; }
        selection_profile "$2"
    else
        selection_explicit "$@" || return 1
    fi
    [[ ${#SELECTED_NAMES[@]} -gt 0 ]] \
        || { err "plan has no tools for $(mode_label) mode"; return 1; }
    plan_selected "${SELECTED_NAMES[@]}"
}

mode_action() {
    case "$DOTLAD_MODE" in
        packages) printf 'Install packages for' ;;
        config)   printf 'Deploy config for' ;;
        *)        printf 'Install packages and deploy config for' ;;
    esac
}

mode_backup_note() {
    mode_config_enabled && printf ' (replaced files are backed up)'
    return 0
}

ensure_brew() {
    local candidate
    command -v brew >/dev/null 2>&1 && return 0
    confirm "Homebrew is missing. Install it now?" || return 0
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -x "$candidate" ]] || continue
        eval "$("$candidate" shellenv)"
        break
    done
    BREW_PREFIX=""; BREW_PREFIX_SET=""
}

cmd_profile() {
    local profile="$1"
    selection_profile "$profile"
    [[ ${#SELECTED_NAMES[@]} -gt 0 ]] \
        || fatal "profile '$profile' has no tools for $(mode_label) mode"
    title "Profile: $profile"
    confirm "$(mode_action) ${#SELECTED_NAMES[@]} tool(s) from '$profile'?" \
        || { hint "cancelled"; exit 0; }
    mode_packages_enabled && ensure_brew
    DOTLAD_YES=1
    run_selected "${SELECTED_NAMES[@]}"
}

cmd_all() {
    title "Set up this machine — $(mode_label)"
    print_list
    echo ""
    confirm "$(mode_action) every relevant tool now?$(mode_backup_note)" \
        || { hint "cancelled"; exit 0; }
    mode_packages_enabled && ensure_brew
    DOTLAD_YES=1
    selection_all
    run_selected "${SELECTED_NAMES[@]}"
}
