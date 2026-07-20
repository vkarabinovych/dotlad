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
    local i="$1" j start count state changes
    PLAN_PACKAGES="none"
    PLAN_CONFIG_NAMES=()
    PLAN_CONFIG_STATES=()
    PLAN_CONFIG_DESTS=()
    PLAN_CONFIG_CHANGES=()
    PLAN_CONFIG_RESOLVERS=()
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
    start="${T_CONFIG_START[$i]}"
    count="${T_CONFIG_COUNT[$i]}"
    for ((j = start; j < start + count; j++)); do
        changes=""
        config_paths "$j"
        if ! mode_config_enabled; then
            state="skipped"
        elif ! resolver_present "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST"; then
            state="create"
        elif resolver_equal "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST"; then
            state="ready"
        else
            state="update"
        fi
        if [[ "$state" == "create" || "$state" == "update" ]]; then
            changes="$(resolver_changes "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST")"
        fi
        PLAN_CONFIG_NAMES+=("${C_NAME[$j]}")
        PLAN_CONFIG_STATES+=("$state")
        PLAN_CONFIG_DESTS+=("$TP_DEST")
        PLAN_CONFIG_CHANGES+=("$changes")
        PLAN_CONFIG_RESOLVERS+=("${C_RESOLVER[$j]}")
    done
}

plan_tool_json() { # <idx> <leading-comma 0|1>
    local i="$1" comma="$2" req blocker first=1 old_ifs j
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
    printf ',"configs":['
    for ((j = 0; j < ${#PLAN_CONFIG_NAMES[@]}; j++)); do
        [[ "$j" == 0 ]] || printf ','
        printf '{"name":'
        json_string "${PLAN_CONFIG_NAMES[$j]}"
        printf ',"state":'
        json_string "${PLAN_CONFIG_STATES[$j]}"
        printf ',"resolver":'
        json_string "${PLAN_CONFIG_RESOLVERS[$j]}"
        printf ',"destination":'
        json_string "${PLAN_CONFIG_DESTS[$j]}"
        printf ',"changes":'
        json_string "${PLAN_CONFIG_CHANGES[$j]}"
        printf '}'
    done
    printf ']'
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
    local name i first=1 j
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
        for ((j = 0; j < ${#PLAN_CONFIG_NAMES[@]}; j++)); do
            case "${PLAN_CONFIG_STATES[$j]}" in
                create | update) printf '  config.%-12s %s → %s%s\n' "${PLAN_CONFIG_NAMES[$j]}" \
                    "${PLAN_CONFIG_STATES[$j]}" "$(pretty_path "${PLAN_CONFIG_DESTS[$j]}")" \
                    "${PLAN_CONFIG_CHANGES[$j]:+ · ${PLAN_CONFIG_CHANGES[$j]}}" ;;
                ready) printf '  config.%-12s already up to date → %s\n' "${PLAN_CONFIG_NAMES[$j]}" \
                    "$(pretty_path "${PLAN_CONFIG_DESTS[$j]}")" ;;
                skipped) printf '  config.%-12s skipped by mode\n' "${PLAN_CONFIG_NAMES[$j]}" ;;
            esac
        done
        [[ -z "$PLAN_MISSING" ]] || printf '  requires: missing %s\n' "$PLAN_MISSING"
        if [[ -n "$PLAN_BLOCKERS" ]]; then
            printf '  blockers: %s\n' "${PLAN_BLOCKERS//|/, }"
        fi
    done
    printf '\n%sRead-only plan; no changes made.%s\n' "$C_DIM" "$C_RESET"
}
