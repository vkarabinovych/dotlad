# shellcheck disable=SC2034  # UTD_CACHE is consumed by engine.sh
# lib/plan.sh — read-only execution plans for humans and automation.

json_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "$value"
}

plan_tool() { # <idx> — populate PLAN_* globals without changing state
    local i="$1" counts=""
    PLAN_PACKAGES="none"
    PLAN_CONFIG="none"
    PLAN_DEST=""
    PLAN_CHANGES=""
    PLAN_RESOLVER=""
    PLAN_MISSING=""
    PLAN_BLOCKERS=""
    preflight_inspect "$i" || true
    PLAN_MISSING="$PREFLIGHT_MISSING"
    PLAN_BLOCKERS="$PREFLIGHT_BLOCKERS"
    if mode_packages_enabled && tool_has_packages "$i"; then
        if [[ "$PREFLIGHT_INSTALLED" == 1 ]]; then PLAN_PACKAGES="ready"; else PLAN_PACKAGES="install"; fi
    elif ! mode_packages_enabled && tool_has_packages "$i"; then
        PLAN_PACKAGES="skipped"
    fi
    if mode_config_enabled && tool_has_config "$i"; then
        tool_paths "$i"
        PLAN_DEST="$TP_DEST"
        PLAN_RESOLVER="${T_RESOLVER[$i]}"
        if [[ ! -e "$TP_DEST" && ! -L "$TP_DEST" ]]; then
            PLAN_CONFIG="create"
        elif tool_uptodate "$i"; then
            PLAN_CONFIG="ready"
        else
            PLAN_CONFIG="update"
        fi
        if [[ "$PLAN_CONFIG" == "create" || "$PLAN_CONFIG" == "update" ]]; then
            counts="$(resolver_changes "${T_RESOLVER[$i]}" "$TP_SRC" "$TP_DEST")"
            PLAN_CHANGES="$counts"
        fi
    elif ! mode_config_enabled && tool_has_config "$i"; then
        PLAN_CONFIG="skipped"
        PLAN_DEST="${T_DEST[$i]}"
    fi
}

plan_tool_json() { # <idx> <leading-comma 0|1>
    local i="$1" comma="$2" req blocker first=1 old_ifs
    plan_tool "$i"
    [[ "$comma" == 1 ]] && printf ','
    printf '\n    {"name":'
    json_string "${T_NAME[$i]}"
    printf ',"packages":'
    json_string "$PLAN_PACKAGES"
    printf ',"package_names":'
    json_string "${T_BREW[$i]}"
    printf ',"install_url":'
    json_string "${T_INSTALL_URL[$i]}"
    printf ',"config":'
    json_string "$PLAN_CONFIG"
    printf ',"resolver":'
    json_string "$PLAN_RESOLVER"
    printf ',"destination":'
    json_string "$PLAN_DEST"
    printf ',"changes":'
    json_string "$PLAN_CHANGES"
    printf ',"missing_requirements":['
    for req in $PLAN_MISSING; do
        [[ "$first" == 1 ]] && first=0 || printf ','
        json_string "$req"
    done
    printf '],"blockers":['
    first=1
    old_ifs="$IFS"
    IFS='|'
    for blocker in $PLAN_BLOCKERS; do
        [[ -n "$blocker" ]] || continue
        [[ "$first" == 1 ]] && first=0 || printf ','
        json_string "$blocker"
    done
    IFS="$old_ifs"
    printf ']}'
}

plan_selected() { # <tool names...>
    local name i first=1
    UTD_CACHE=()
    if [[ "${DOTLAD_PLAN_JSON:-}" == 1 ]]; then
        printf '{"mode":'
        json_string "$DOTLAD_MODE"
        printf ',"tools":['
        for name in "$@"; do
            i="$(tool_find "$name")" || continue
            if [[ "$first" == 1 ]]; then
                plan_tool_json "$i" 0
                first=0
            else plan_tool_json "$i" 1; fi
        done
        printf '\n]}\n'
        return 0
    fi
    title "Plan — $(mode_label)"
    for name in "$@"; do
        i="$(tool_find "$name")" || continue
        plan_tool "$i"
        printf '\n%s— %s —%s\n' "$C_BOLD" "$name" "$C_RESET"
        case "$PLAN_PACKAGES" in
            install) printf '  packages: install %s\n' "${T_BREW[$i]:-${T_INSTALL_URL[$i]}}" ;;
            ready) printf '  packages: already installed\n' ;;
            skipped) printf '  packages: skipped by mode\n' ;;
        esac
        case "$PLAN_CONFIG" in
            create | update) printf '  config:   %s → %s%s\n' "$PLAN_CONFIG" \
                "$(pretty_path "$PLAN_DEST")" "${PLAN_CHANGES:+ · $PLAN_CHANGES}" ;;
            ready) printf '  config:   already up to date → %s\n' "$(pretty_path "$PLAN_DEST")" ;;
            skipped) printf '  config:   skipped by mode\n' ;;
        esac
        [[ -z "$PLAN_MISSING" ]] || printf '  requires: missing %s\n' "$PLAN_MISSING"
        if [[ -n "$PLAN_BLOCKERS" ]]; then
            printf '  blockers: %s\n' "${PLAN_BLOCKERS//|/, }"
        fi
    done
    printf '\n%sRead-only plan; no changes made.%s\n' "$C_DIM" "$C_RESET"
}
