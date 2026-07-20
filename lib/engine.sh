# shellcheck disable=SC2034  # shared counters/paths are consumed by sibling libs
# lib/engine.sh — one direction only: repo → system. Decide state
# (new / update / ready), and bring it up to date (install package + write
# config, backing up anything it replaces). Resolvers keep machine-local keys,
# so "up to date" means "applying would change nothing".

BACKUP_ROOT="${DOTLAD_BACKUP_ROOT:-$HOME/.dotlad_backup}"
BACKUP_DIR="" # set lazily, once per run
N_UPDATED=0
N_INSTALLED=0
N_BACKED=0
N_FAILED=0
DOTLAD_MODE="${DOTLAD_MODE:-full}"

mode_set() {
    case "$1" in
        full | packages | config)
            DOTLAD_MODE="$1"
            export DOTLAD_MODE
            ;;
        *) return 1 ;;
    esac
}

mode_label() {
    case "$DOTLAD_MODE" in
        packages) printf 'packages only' ;;
        config) printf 'config only' ;;
        *) printf 'packages + config' ;;
    esac
}

mode_packages_enabled() { [[ "$DOTLAD_MODE" != "config" ]]; }
mode_config_enabled() { [[ "$DOTLAD_MODE" != "packages" ]]; }
tool_has_packages() { [[ -n "${T_BREW[$1]}" || -n "${T_INSTALL_URL[$1]}" ]]; }
tool_has_config() { [[ "${T_CONFIG_COUNT[$1]}" -gt 0 ]]; }
config_is_dir() { [[ -d "$ROOT/${C_SRC[$1]}" ]]; }
config_action() { resolver_action "${C_RESOLVER[$1]}"; }

tool_relevant() {
    case "$DOTLAD_MODE" in
        packages) tool_has_packages "$1" ;;
        config) tool_has_config "$1" ;;
        *) return 0 ;;
    esac
}

# shellcheck disable=SC2153  # C_SRC/C_DEST are the manifest arrays
config_paths() {
    TP_SRC="$ROOT/${C_SRC[$1]}"
    TP_DEST="${C_DEST[$1]}"
}

# ---------------------------------------------------------------------------
# Install state
# ---------------------------------------------------------------------------

# The Homebrew prefix, cached for the session (its location never moves; only
# whether a formula's opt link exists changes, and that is stat'd live). Saves
# a `command -v brew` fork on every tool, every scan.
brew_prefix() {
    if [[ -z "${BREW_PREFIX_SET:-}" ]]; then
        local p=""
        p="$(command -v brew 2>/dev/null)" || p=""
        BREW_PREFIX="${p%/bin/brew}"
        BREW_PREFIX_SET=1
    fi
    printf '%s' "$BREW_PREFIX"
}

# Installed = the CHECK command/path exists AND every declared brew formula is
# present (one stat per formula via its opt link — no slow `brew list`).
tool_installed() {
    local i="$1" prefix pkg
    local check="${T_CHECK[$i]}"
    if [[ "$check" == /* ]]; then
        [[ -e "$check" ]] || return 1
    else
        command -v "$check" >/dev/null 2>&1 || return 1
    fi
    if [[ "${T_CASK[$i]}" == "1" && -n "${T_BREW[$i]}" ]]; then
        prefix="$(brew_prefix)"
        for pkg in ${T_BREW[$i]}; do
            [[ -n "$prefix" && -d "$prefix/Caskroom/${pkg##*/}" ]] || return 1
        done
    elif [[ -n "${T_BREW[$i]}" ]]; then
        prefix="$(brew_prefix)"
        for pkg in ${T_BREW[$i]}; do
            [[ -n "$prefix" && -e "$prefix/opt/${pkg##*/}" ]] || return 1
        done
    fi
    return 0
}

install_hint() {
    local i="$1"
    if [[ -n "${T_BREW[$i]}" ]]; then
        if [[ "${T_CASK[$i]}" == "1" ]]; then
            printf 'brew install --cask %s' "${T_BREW[$i]}"
        else printf 'brew install %s' "${T_BREW[$i]}"; fi
    elif [[ -n "${T_INSTALL_URL[$i]}" ]]; then
        printf '%s' "${T_INSTALL_URL[$i]}"
    else printf '—'; fi
}

# tool_uptodate <idx> — rc 0 when applying the config would change nothing.
# Memoized per view pass (UTD_CACHE, cleared at the start of a scan / sync): the
# state list computes this twice per tool (headline + activity), and for
# directories/resolvers it is the expensive part (find+cmp, jq, yq).
UTD_CACHE=()
tool_uptodate() {
    local i="$1" j start count rc=0
    [[ -n "${UTD_CACHE[$i]:-}" ]] && return "$((${UTD_CACHE[$i]} - 1))"
    start="${T_CONFIG_START[$i]}"
    count="${T_CONFIG_COUNT[$i]}"
    for ((j = start; j < start + count; j++)); do
        config_paths "$j"
        resolver_equal "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST" || rc=1
    done
    UTD_CACHE[i]=$((rc == 0 ? 1 : 2))
    return "$rc"
}

# ---------------------------------------------------------------------------
# State for the list: ST_CFG (ready|update|new|pkg) + ST_INSTALLED (0|1)
# ---------------------------------------------------------------------------

tool_state() {
    local i="$1" j start count missing=0
    if mode_packages_enabled; then
        if tool_installed "$i"; then ST_INSTALLED=1; else ST_INSTALLED=0; fi
    else
        ST_INSTALLED=-1
    fi
    if ! mode_config_enabled; then
        ST_CFG="skip"
        return 0
    fi
    if ! tool_has_config "$i"; then
        ST_CFG="pkg"
        return 0
    fi
    start="${T_CONFIG_START[$i]}"
    count="${T_CONFIG_COUNT[$i]}"
    for ((j = start; j < start + count; j++)); do
        if [[ ! -e "${C_DEST[$j]}" && ! -L "${C_DEST[$j]}" ]]; then
            missing=1
            break
        fi
    done
    if [[ "$missing" == 1 ]]; then
        ST_CFG="new"
    elif tool_uptodate "$i"; then
        ST_CFG="ready"
    else ST_CFG="update"; fi
    return 0
}

# ---------------------------------------------------------------------------
# Backup + write
# ---------------------------------------------------------------------------

# Atomically replace a config leaf. `copy` preserves the repository file mode;
# `merge` preserves an existing destination mode and defaults new merged files
# to user-only permissions because they may contain machine-local credentials.
write_config() { # <src> <dest> <copy|merge>
    local src="$1" dest="$2" mode="$3" parent tmp rc=0
    dest_safe "$dest" || {
        err "unsafe destination: $dest"
        return 1
    }
    [[ ! -d "$dest" || -L "$dest" ]] || {
        err "destination is a directory: $dest"
        return 1
    }
    parent="$(dirname "$dest")"
    mkdir -p "$parent" || {
        err "cannot create $parent"
        return 1
    }
    backup_path "$dest" || return 1
    tmp="$(mktemp "$parent/.dotlad.XXXXXX")" || {
        err "cannot create temporary file in $parent"
        return 1
    }
    if [[ "$mode" == copy ]]; then
        cp -p "$src" "$tmp" || rc=1
    elif [[ -f "$dest" && ! -L "$dest" ]]; then
        cp -p "$dest" "$tmp" && cat "$src" >"$tmp" || rc=1
    else
        cat "$src" >"$tmp" && chmod 0600 "$tmp" || rc=1
    fi
    [[ $rc == 0 ]] && mv -f "$tmp" "$dest" || rc=1
    rm -f "$tmp"
    [[ $rc == 0 ]] || {
        err "failed to write $dest"
        return 1
    }
}

write_file() { write_config "$1" "$2" copy; }
write_merged() { write_config "$1" "$2" merge; }

apply_resolved_config() { # <resolver> <src> <dest>
    local resolver="$1" src="$2" dest="$3" t
    t="$(mktemp)" || return 1
    if ! resolver_render "$resolver" "$src" "$dest" >"$t" 2>/dev/null; then
        rm -f "$t"
        err "cannot resolve config with '$resolver'"
        return 1
    fi
    if ! write_merged "$t" "$dest"; then
        rm -f "$t"
        return 1
    fi
    rm -f "$t"
    AP_DEPLOYED=1
}

# Build one canonical, read-only validation result for execution and planning.
# PREFLIGHT_MISSING is space separated; PREFLIGHT_BLOCKERS uses `|` because
# blocker messages contain spaces. Requirements that full mode can install via
# Homebrew are reported as missing but do not block the batch.
preflight_add_blocker() {
    PREFLIGHT_BLOCKERS="${PREFLIGHT_BLOCKERS}${PREFLIGHT_BLOCKERS:+|}$1"
}

preflight_inspect() { # <idx> — populate PREFLIGHT_MISSING/PREFLIGHT_BLOCKERS
    local i="$1" req blocker can_resolve j start count label
    PREFLIGHT_MISSING=""
    PREFLIGHT_BLOCKERS=""
    PREFLIGHT_INSTALLED=-1
    if mode_packages_enabled && tool_has_packages "$i"; then
        if tool_installed "$i"; then PREFLIGHT_INSTALLED=1; else PREFLIGHT_INSTALLED=0; fi
        if [[ "$PREFLIGHT_INSTALLED" == 0 && -n "${T_BREW[$i]}" ]] &&
            ! command -v brew >/dev/null 2>&1; then
            preflight_add_blocker "Homebrew is required"
        fi
        if [[ "$PREFLIGHT_INSTALLED" == 0 && -n "${T_INSTALL_URL[$i]}" ]] &&
            ! command -v curl >/dev/null 2>&1; then
            preflight_add_blocker "curl is required"
        fi
        if [[ "$PREFLIGHT_INSTALLED" == 0 && -n "${T_INSTALL_SHA256[$i]}" ]] &&
            ! command -v shasum >/dev/null 2>&1; then
            preflight_add_blocker "shasum is required"
        fi
    fi
    if ! mode_config_enabled || ! tool_has_config "$i"; then
        [[ -z "$PREFLIGHT_BLOCKERS" ]]
        return
    fi
    backup_root_safe || preflight_add_blocker "unsafe backup root: $BACKUP_ROOT"
    while IFS= read -r req; do
        PREFLIGHT_MISSING="${PREFLIGHT_MISSING}${PREFLIGHT_MISSING:+ }$req"
        can_resolve=0
        if ! mode_packages_enabled || ! command -v brew >/dev/null 2>&1; then
            preflight_add_blocker "missing requirement: $req"
        fi
    done < <(tool_missing_requirements "$i")
    start="${T_CONFIG_START[$i]}"
    count="${T_CONFIG_COUNT[$i]}"
    for ((j = start; j < start + count; j++)); do
        can_resolve=1
        label="config.${C_NAME[$j]}"
        config_paths "$j"
        if ! dest_safe "$TP_DEST"; then
            preflight_add_blocker "$label: unsafe destination: $TP_DEST"
            can_resolve=0
        fi
        [[ -z "$PREFLIGHT_MISSING" ]] || can_resolve=0
        if [[ "$can_resolve" != 1 ]]; then
            continue
        fi
        while IFS= read -r blocker; do
            [[ -n "$blocker" ]] && preflight_add_blocker "$label: $blocker"
        done < <(resolver_check "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST")
    done
    [[ -z "$PREFLIGHT_BLOCKERS" ]]
}

preflight_tool() {
    local i="$1" blocker old_ifs
    preflight_inspect "$i" && return 0
    old_ifs="$IFS"
    IFS='|'
    for blocker in $PREFLIGHT_BLOCKERS; do err "${T_NAME[$i]}: $blocker"; done
    IFS="$old_ifs"
    return 1
}

preflight_selected() {
    local name i failed=0
    UTD_CACHE=()
    for name in "$@"; do
        i="$(tool_find "$name")" || {
            err "unknown tool: $name"
            failed=1
            continue
        }
        tool_relevant "$i" || continue
        preflight_tool "$i" || failed=1
    done
    [[ "$failed" == 0 ]]
}

# Swap a fully staged path into place. Signals during the two-rename window
# restore the previous destination before exiting.
replace_path_transaction() ( # <stage-root> <staged-path> <destination>
    local stage="$1" staged="$2" dest="$3" old="$1/previous" committed=0 had_old=0
    [[ -e "$dest" || -L "$dest" ]] && had_old=1
    rollback_path() {
        [[ "$committed" == 0 ]] || return 0
        if [[ -e "$old" || -L "$old" ]]; then
            if [[ -e "$dest" || -L "$dest" ]]; then rm -rf "$dest"; fi
            mv "$old" "$dest" || true
        elif [[ "$had_old" == 0 && ! -e "$staged" && (-e "$dest" || -L "$dest") ]]; then
            rm -rf "$dest"
        fi
        [[ ! -e "$stage" ]] || rm -rf "$stage"
    }
    trap 'rollback_path; exit 130' HUP INT TERM
    if [[ "$had_old" == 1 ]]; then mv "$dest" "$old" || {
        rollback_path
        return 1
    }; fi
    mv "$staged" "$dest" || {
        rollback_path
        return 1
    }
    committed=1
    [[ "$had_old" == 0 || (! -e "$old" && ! -L "$old") ]] || rm -rf "$old"
    rm -rf "$stage"
    trap - HUP INT TERM
)

# ---------------------------------------------------------------------------
# Apply one named config (repo → system)
# ---------------------------------------------------------------------------

# apply_config reports changed file/link and directory counts; sync_tool prints
# the one-line summary without per-entry output.
AP_DEPLOYED=0
AP_REMOVED=0
AP_CREATED_DIRS=0
AP_REMOVED_DIRS=0
apply_config() {
    local config_i="$1"
    config_paths "$config_i"
    AP_DEPLOYED=0
    AP_REMOVED=0
    AP_CREATED_DIRS=0
    AP_REMOVED_DIRS=0
    resolver_apply "${C_RESOLVER[$config_i]}" "$TP_SRC" "$TP_DEST"
}

# What updating this tool's config would change (preview + pre-write review).
tool_diff() {
    local i="$1" j start count
    if ! mode_config_enabled; then
        if tool_installed "$i"; then hint "installed · config skipped"; else hint "not installed · $(install_hint "$i")"; fi
        return 0
    fi
    if ! tool_has_config "$i"; then
        if tool_installed "$i"; then hint "installed · no config"; else hint "not installed · $(install_hint "$i")"; fi
        return 0
    fi
    start="${T_CONFIG_START[$i]}"
    count="${T_CONFIG_COUNT[$i]}"
    for ((j = start; j < start + count; j++)); do
        config_paths "$j"
        [[ "$count" -eq 1 ]] || hint "config.${C_NAME[$j]} → $(pretty_path "$TP_DEST")"
        resolver_preview "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST"
    done
    return 0
}

# ---------------------------------------------------------------------------
# Bring one tool fully up to date: install if missing, then write its config.
# ---------------------------------------------------------------------------

# Bring one tool up to date, printing the run as clear stages (install → apply
# → done) with a one-line summary per stage. Output is captured per-tool into
# the run log and shown in the picker's pane.
# Also records per-stage markers so the picker's tree can show which step is
# live (<tool>.stage = install|<config>:copy|<config>:link|done) and deployment
# result counts (<tool>.<config>.result =
# "deployed removed backed created-dirs removed-dirs").
sync_tool() {
    local i="$1"
    local did=0 config_did=0 nm="${T_NAME[$i]}" b0 nb sum action active result run="${DOTLAD_RUNDIR:-}"
    local j start count
    UTD_CACHE=() # this call mutates config — never trust a stale up-to-date memo
    if mode_packages_enabled && ! tool_installed "$i" && tool_has_packages "$i"; then
        if [[ -n "$run" ]]; then
            printf "install" >"$run/${nm}.stage" 2>/dev/null || true
        fi
        printf '%s▸%s installing: %s\n' "$C_CYAN" "$C_RESET" "${T_BREW[$i]:-$nm}"
        if install_tool "$i"; then
            printf '%s  ✓ installed%s\n' "$C_GREEN" "$C_RESET"
            did=1
        else
            printf '%s  ✗ install failed%s\n' "$C_RED" "$C_RESET"
            N_FAILED=$((N_FAILED + 1))
            return 1
        fi
    fi
    if mode_config_enabled && tool_has_config "$i" && ! tool_uptodate "$i"; then
        if ! ensure_requirements "$i"; then
            N_FAILED=$((N_FAILED + 1))
            return 1
        fi
        start="${T_CONFIG_START[$i]}"
        count="${T_CONFIG_COUNT[$i]}"
        for ((j = start; j < start + count; j++)); do
            config_paths "$j"
            resolver_equal "${C_RESOLVER[$j]}" "$TP_SRC" "$TP_DEST" && continue
            action="$(config_action "$j")"
            if [[ "$action" == link ]]; then
                active="linking"
                result="linked"
            else
                active="copying"
                result="copied"
            fi
            if [[ -n "$run" ]]; then
                printf '%s:%s' "${C_NAME[$j]}" "$action" >"$run/${nm}.stage" 2>/dev/null || true
            fi
            printf '%s▸%s %s config.%s → %s\n' "$C_CYAN" "$C_RESET" "$active" \
                "${C_NAME[$j]}" "$(pretty_path "$TP_DEST")"
            b0="$N_BACKED"
            if apply_config "$j"; then
                nb=$((N_BACKED - b0))
                if [[ -n "$run" ]]; then
                    printf '%s %s %s %s %s\n' "$AP_DEPLOYED" "$AP_REMOVED" "$nb" \
                        "$AP_CREATED_DIRS" "$AP_REMOVED_DIRS" \
                        >"$run/${nm}.${C_NAME[$j]}.result" 2>/dev/null || true
                fi
                sum=""
                [[ "$AP_DEPLOYED" -gt 0 ]] && sum="${AP_DEPLOYED} ${result}"
                [[ "$AP_CREATED_DIRS" -gt 0 ]] &&
                    sum="${sum:+${sum} · }${AP_CREATED_DIRS} $(directory_noun "$AP_CREATED_DIRS") created"
                [[ "${AP_REMOVED:-0}" -gt 0 ]] &&
                    sum="${sum:+${sum} · }${AP_REMOVED} $(file_noun "$AP_REMOVED") removed"
                [[ "$AP_REMOVED_DIRS" -gt 0 ]] &&
                    sum="${sum:+${sum} · }${AP_REMOVED_DIRS} $(directory_noun "$AP_REMOVED_DIRS") removed"
                [[ "$nb" -gt 0 ]] && sum="${sum:+${sum} · }${nb} backed up"
                [[ -n "$sum" ]] || sum="config updated"
                printf '%s  ✓ %s%s\n' "$C_GREEN" "$sum" "$C_RESET"
                config_did=1
                did=1
            else
                printf '%s  ✗ %s failed%s\n' "$C_RED" "$action" "$C_RESET"
                N_FAILED=$((N_FAILED + 1))
                return 1
            fi
        done
        [[ "$config_did" == 0 ]] || N_UPDATED=$((N_UPDATED + 1))
    fi
    if [[ -n "$run" ]]; then
        printf "done" >"$run/${nm}.stage" 2>/dev/null || true
    fi
    if [[ "$did" == 1 ]]; then
        printf '%s✓ %s done%s\n' "$C_GREEN" "$nm" "$C_RESET"
    elif [[ "$DOTLAD_MODE" == "packages" ]]; then
        hint "${nm} packages already installed"
    elif [[ "$DOTLAD_MODE" == "config" ]]; then
        hint "${nm} config already up to date"
    else
        hint "${nm} already up to date"
    fi
    return 0
}
