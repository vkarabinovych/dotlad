# shellcheck disable=SC2034  # shared counters/paths are consumed by sibling libs
# lib/engine.sh — one direction only: repo → system. Decide state
# (new / update / ready), and bring it up to date (install package + write
# config, backing up anything it replaces). Resolvers keep machine-local keys,
# so "up to date" means "applying would change nothing".

BACKUP_ROOT="${DOTLAD_BACKUP_ROOT:-$HOME/.dotlad_backup}"
BACKUP_DIR=""            # set lazily, once per run
N_UPDATED=0; N_INSTALLED=0; N_BACKED=0; N_FAILED=0
DOTLAD_MODE="${DOTLAD_MODE:-full}"

mode_set() {
    case "$1" in
        full|packages|config) DOTLAD_MODE="$1"; export DOTLAD_MODE ;;
        *) return 1 ;;
    esac
}

mode_label() {
    case "$DOTLAD_MODE" in
        packages) printf 'packages only' ;;
        config)   printf 'config only' ;;
        *)        printf 'packages + config' ;;
    esac
}

mode_packages_enabled() { [[ "$DOTLAD_MODE" != "config" ]]; }
mode_config_enabled()   { [[ "$DOTLAD_MODE" != "packages" ]]; }
tool_has_packages()     { [[ -n "${T_BREW[$1]}" || -n "${T_INSTALL_URL[$1]}" ]]; }
tool_has_config()       { [[ -n "${T_SRC[$1]}" ]]; }
tool_config_is_dir()    { tool_has_config "$1" && [[ -d "$ROOT/${T_SRC[$1]}" ]]; }

tool_relevant() {
    case "$DOTLAD_MODE" in
        packages) tool_has_packages "$1" ;;
        config)   tool_has_config "$1" ;;
        *)        return 0 ;;
    esac
}

# shellcheck disable=SC2153  # T_SRC/T_DEST are the manifest arrays
tool_paths() { TP_SRC="$ROOT/${T_SRC[$1]}"; TP_DEST="${T_DEST[$1]}"; }

# ---------------------------------------------------------------------------
# Install state
# ---------------------------------------------------------------------------

# The Homebrew prefix, cached for the session (its location never moves; only
# whether a formula's opt link exists changes, and that is stat'd live). Saves
# a `command -v brew` fork on every tool, every scan.
brew_prefix() {
    if [[ -z "${BREW_PREFIX_SET:-}" ]]; then
        local p=""; p="$(command -v brew 2>/dev/null)" || p=""
        BREW_PREFIX="${p%/bin/brew}"; BREW_PREFIX_SET=1
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
        if [[ "${T_CASK[$i]}" == "1" ]]; then printf 'brew install --cask %s' "${T_BREW[$i]}"
        else printf 'brew install %s' "${T_BREW[$i]}"; fi
    elif [[ -n "${T_INSTALL_URL[$i]}" ]]; then printf '%s' "${T_INSTALL_URL[$i]}"
    else printf '—'; fi
}

# ---------------------------------------------------------------------------
# Up-to-date checks ("would applying change anything?" — rc 0 = no)
# ---------------------------------------------------------------------------

eq_file() { [[ -f "$2" && ! -L "$2" ]] && cmp -s "$1" "$2"; }

dir_files_to_sync() {  # <source-dir> <destination-dir> — relative paths
    local src="$1" dest="$2" file rel
    while IFS= read -r file; do
        rel="${file#"$src"/}"
        [[ -f "$dest/$rel" && ! -L "$dest/$rel" ]] \
            && cmp -s "$file" "$dest/$rel" && continue
        printf '%s\n' "$rel"
    done < <(find "$src" -type f | sort)
}

dir_leaves_to_backup() {  # <source-dir> <destination-dir> — changed/stale paths
    local src="$1" dest="$2" file rel
    [[ -d "$dest" && ! -L "$dest" ]] || return 0
    while IFS= read -r file; do
        rel="${file#"$dest"/}"
        [[ -f "$src/$rel" && -f "$file" && ! -L "$file" ]] \
            && cmp -s "$src/$rel" "$file" && continue
        printf '%s\n' "$rel"
    done < <(find "$dest" \( -type f -o -type l \) | sort)
}

# A directory is up to date when its file contents and directory structure
# match the source, with no extra destination entries.
eq_dir() {
    local src="$1" dest="$2" f rel
    [[ -d "$dest" && ! -L "$dest" ]] || return 1
    while IFS= read -r f; do
        rel="${f#"$src"/}"
        [[ -d "$dest/$rel" && ! -L "$dest/$rel" ]] || return 1
    done < <(find "$src" -mindepth 1 -type d)
    while IFS= read -r rel; do [[ -z "$rel" ]] || return 1; done \
        < <(dir_files_to_sync "$src" "$dest")
    while IFS= read -r rel; do [[ -z "$rel" ]] || return 1; done \
        < <(dir_leaves_to_backup "$src" "$dest")
    while IFS= read -r f; do
        rel="${f#"$dest"/}"
        [[ -d "$src/$rel" && ! -L "$src/$rel" ]] || return 1
    done < <(find "$dest" -mindepth 1 -type d)
    return 0
}

# tool_uptodate <idx> — rc 0 when applying the config would change nothing.
# Memoized per view pass (UTD_CACHE, cleared at the start of a scan / sync): the
# state list computes this twice per tool (headline + activity), and for
# directories/resolvers it is the expensive part (find+cmp, jq, yq).
UTD_CACHE=()
tool_uptodate() {
    local i="$1"
    [[ -n "${UTD_CACHE[$i]:-}" ]] && return "$(( ${UTD_CACHE[$i]} - 1 ))"
    tool_paths "$i"
    local rc=0
    if ! tool_has_config "$i"; then
        :
    elif [[ -n "${T_RESOLVER[$i]}" ]]; then
        resolver_equal "${T_RESOLVER[$i]}" "$TP_SRC" "$TP_DEST" || rc=1
    elif tool_config_is_dir "$i"; then
        eq_dir "$TP_SRC" "$TP_DEST" || rc=1
    else
        eq_file "$TP_SRC" "$TP_DEST" || rc=1
    fi
    UTD_CACHE[i]=$(( rc == 0 ? 1 : 2 ))
    return "$rc"
}

# ---------------------------------------------------------------------------
# State for the list: ST_CFG (ready|update|new|pkg) + ST_INSTALLED (0|1)
# ---------------------------------------------------------------------------

tool_state() {
    local i="$1"; tool_paths "$i"
    if mode_packages_enabled; then
        if tool_installed "$i"; then ST_INSTALLED=1; else ST_INSTALLED=0; fi
    else
        ST_INSTALLED=-1
    fi
    if ! mode_config_enabled; then ST_CFG="skip"; return 0; fi
    if ! tool_has_config "$i"; then ST_CFG="pkg"; return 0; fi
    if [[ ! -e "$TP_DEST" && ! -L "$TP_DEST" ]]; then ST_CFG="new"
    elif tool_uptodate "$i"; then ST_CFG="ready"
    else ST_CFG="update"; fi
    return 0
}

# ---------------------------------------------------------------------------
# Backup + write
# ---------------------------------------------------------------------------

# Atomically replace a config leaf. `copy` preserves the repository file mode;
# `merge` preserves an existing destination mode and defaults new merged files
# to user-only permissions because they may contain machine-local credentials.
write_config() {  # <src> <dest> <copy|merge>
    local src="$1" dest="$2" mode="$3" parent tmp rc=0
    dest_safe "$dest" || { err "unsafe destination: $dest"; return 1; }
    [[ ! -d "$dest" || -L "$dest" ]] || { err "destination is a directory: $dest"; return 1; }
    parent="$(dirname "$dest")"
    mkdir -p "$parent" || { err "cannot create $parent"; return 1; }
    backup_path "$dest" || return 1
    tmp="$(mktemp "$parent/.dotlad.XXXXXX")" || { err "cannot create temporary file in $parent"; return 1; }
    if [[ "$mode" == copy ]]; then
        cp -p "$src" "$tmp" || rc=1
    elif [[ -f "$dest" && ! -L "$dest" ]]; then
        cp -p "$dest" "$tmp" && cat "$src" > "$tmp" || rc=1
    else
        cat "$src" > "$tmp" && chmod 0600 "$tmp" || rc=1
    fi
    [[ $rc == 0 ]] && mv -f "$tmp" "$dest" || rc=1
    rm -f "$tmp"
    [[ $rc == 0 ]] || { err "failed to write $dest"; return 1; }
}

write_file()   { write_config "$1" "$2" copy; }
write_merged() { write_config "$1" "$2" merge; }

apply_resolved_config() {  # <resolver> <src> <dest>
    local resolver="$1" src="$2" dest="$3" t
    t="$(mktemp)" || return 1
    if ! resolver_render "$resolver" "$src" "$dest" > "$t" 2>/dev/null; then
        rm -f "$t"; err "cannot resolve config with '$resolver'"; return 1
    fi
    if ! write_merged "$t" "$dest"; then rm -f "$t"; return 1; fi
    rm -f "$t"
}

# Build one canonical, read-only validation result for execution and planning.
# PREFLIGHT_MISSING is space separated; PREFLIGHT_BLOCKERS uses `|` because
# blocker messages contain spaces. Requirements that full mode can install via
# Homebrew are reported as missing but do not block the batch.
preflight_add_blocker() {
    PREFLIGHT_BLOCKERS="${PREFLIGHT_BLOCKERS}${PREFLIGHT_BLOCKERS:+|}$1"
}

preflight_inspect() {  # <idx> — populate PREFLIGHT_MISSING/PREFLIGHT_BLOCKERS
    local i="$1" req bad="" can_render=1 rendered=""
    PREFLIGHT_MISSING=""; PREFLIGHT_BLOCKERS=""; PREFLIGHT_INSTALLED=-1
    if mode_packages_enabled && tool_has_packages "$i"; then
        if tool_installed "$i"; then PREFLIGHT_INSTALLED=1; else PREFLIGHT_INSTALLED=0; fi
        if [[ "$PREFLIGHT_INSTALLED" == 0 && -n "${T_BREW[$i]}" ]] \
           && ! command -v brew >/dev/null 2>&1; then
            preflight_add_blocker "Homebrew is required"
        fi
        if [[ "$PREFLIGHT_INSTALLED" == 0 && -n "${T_INSTALL_URL[$i]}" ]] \
           && ! command -v curl >/dev/null 2>&1; then
            preflight_add_blocker "curl is required"
        fi
    fi
    if ! mode_config_enabled || ! tool_has_config "$i"; then
        [[ -z "$PREFLIGHT_BLOCKERS" ]]
        return
    fi
    tool_paths "$i"
    if ! dest_safe "$TP_DEST"; then
        preflight_add_blocker "unsafe destination: $TP_DEST"; can_render=0
    fi
    backup_root_safe || preflight_add_blocker "unsafe backup root: $BACKUP_ROOT"
    if tool_config_is_dir "$i"; then
        if [[ -L "$TP_DEST" ]]; then
            preflight_add_blocker "directory destination is a symlink"; can_render=0
        elif [[ -e "$TP_DEST" && ! -d "$TP_DEST" ]]; then
            preflight_add_blocker "directory destination is not a directory"; can_render=0
        fi
        if [[ -d "$TP_DEST" ]]; then
            bad="$(find "$TP_DEST" ! -type d ! -type f ! -type l -print 2>/dev/null)"
            [[ -z "$bad" ]] || preflight_add_blocker "directory destination contains an unsupported entry"
        fi
    elif [[ -d "$TP_DEST" && ! -L "$TP_DEST" ]]; then
        preflight_add_blocker "file destination is a directory"; can_render=0
    fi
    for req in ${T_REQUIRES[$i]}; do
        command -v "$req" >/dev/null 2>&1 && continue
        PREFLIGHT_MISSING="${PREFLIGHT_MISSING}${PREFLIGHT_MISSING:+ }$req"
        can_render=0
        if ! mode_packages_enabled || ! command -v brew >/dev/null 2>&1; then
            preflight_add_blocker "missing requirement: $req"
        fi
    done
    if [[ -n "${T_RESOLVER[$i]}" && "$can_render" == 1 ]]; then
        if ! rendered="$(mktemp)"; then
            preflight_add_blocker "cannot create resolver preview"
        elif ! resolver_render "${T_RESOLVER[$i]}" "$TP_SRC" "$TP_DEST" > "$rendered" 2>/dev/null; then
            rm -f "$rendered"
            preflight_add_blocker "cannot resolve config with '${T_RESOLVER[$i]}'"
        else
            rm -f "$rendered"
        fi
    fi
    [[ -z "$PREFLIGHT_BLOCKERS" ]]
}

preflight_tool() {
    local i="$1" blocker old_ifs
    preflight_inspect "$i" && return 0
    old_ifs="$IFS"; IFS='|'
    for blocker in $PREFLIGHT_BLOCKERS; do err "${T_NAME[$i]}: $blocker"; done
    IFS="$old_ifs"
    return 1
}

preflight_selected() {
    local name i failed=0
    UTD_CACHE=()
    for name in "$@"; do
        i="$(manifest_find "$name")" || { err "unknown tool: $name"; failed=1; continue; }
        tool_relevant "$i" || continue
        preflight_tool "$i" || failed=1
    done
    [[ "$failed" == 0 ]]
}

# Swap a fully staged directory into place. Signals during the two-rename window
# restore the previous destination before exiting.
replace_directory_transaction() (  # <stage-root> <staged-dir> <destination>
    local stage="$1" staged="$2" dest="$3" old="$1/previous" committed=0 had_old=0
    [[ -e "$dest" ]] && had_old=1
    rollback_directory() {
        [[ "$committed" == 0 ]] || return 0
        if [[ -e "$old" ]]; then
            if [[ -e "$dest" || -L "$dest" ]]; then rm -rf "$dest"; fi
            mv "$old" "$dest" || true
        elif [[ "$had_old" == 0 && ! -e "$staged" && ( -e "$dest" || -L "$dest" ) ]]; then
            rm -rf "$dest"
        fi
        [[ ! -e "$stage" ]] || rm -rf "$stage"
    }
    trap 'rollback_directory; exit 130' HUP INT TERM
    if [[ "$had_old" == 1 ]]; then mv "$dest" "$old" || { rollback_directory; return 1; }; fi
    mv "$staged" "$dest" || { rollback_directory; return 1; }
    committed=1
    [[ "$had_old" == 0 || ! -e "$old" ]] || rm -rf "$old"
    rm -rf "$stage"
    trap - HUP INT TERM
)

apply_directory_config() {  # <src> <dest>
    local src="$1" dest="$2" parent stage staged rel
    parent="$(dirname "$dest")"
    mkdir -p "$parent" || { err "cannot create $parent"; return 1; }
    stage="$(mktemp -d "$parent/.dotlad-dir.XXXXXX")" \
        || { err "cannot stage directory in $parent"; return 1; }
    staged="$stage/payload"
    if ! cp -R -p "$src" "$staged"; then rm -rf "$stage"; err "cannot stage $src"; return 1; fi

    while IFS= read -r rel; do
        [[ -n "$rel" ]] && AP_COPIED=$((AP_COPIED + 1))
    done < <(dir_files_to_sync "$src" "$dest")
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        backup_path "$dest/$rel" || { rm -rf "$stage"; return 1; }
        [[ -f "$src/$rel" ]] || AP_REMOVED=$((AP_REMOVED + 1))
    done < <(dir_leaves_to_backup "$src" "$dest")
    replace_directory_transaction "$stage" "$staged" "$dest" \
        || { err "failed to replace directory: $dest"; return 1; }
}

# ---------------------------------------------------------------------------
# Apply one config (repo → system)
# ---------------------------------------------------------------------------

# apply_config writes the config and reports how much changed via AP_COPIED /
# AP_REMOVED (files copied / pruned) — no per-file output; sync_tool prints the
# one-line summary. AP_COPIED counts directory entries, else one config file.
AP_COPIED=0
AP_REMOVED=0
apply_config() {
    local i="$1"; tool_paths "$i"
    local src="$TP_SRC" dest="$TP_DEST" resolver="${T_RESOLVER[$i]}"
    AP_COPIED=0; AP_REMOVED=0
    if [[ -n "$resolver" ]]; then
        apply_resolved_config "$resolver" "$src" "$dest" || return 1
        AP_COPIED=1
    elif tool_config_is_dir "$i"; then
        [[ -d "$src" ]] || { err "${T_NAME[$i]}: repo dir missing"; return 1; }
        [[ ! -L "$dest" ]] || { err "${T_NAME[$i]}: directory destination is a symlink"; return 1; }
        [[ ! -e "$dest" || -d "$dest" ]] \
            || { err "${T_NAME[$i]}: directory destination is not a directory"; return 1; }
        dest_safe "$dest/.dotlad-directory" \
            || { err "${T_NAME[$i]}: unsafe directory destination"; return 1; }
        apply_directory_config "$src" "$dest" || return 1
    else
        write_file "$src" "$dest" || return 1
        AP_COPIED=1
    fi
    return 0
}

# What updating this tool's config would change (preview + pre-write review).
tool_diff() {
    local i="$1"; tool_paths "$i"
    local src="$TP_SRC" dest="$TP_DEST" t
    if ! mode_config_enabled; then
        if tool_installed "$i"; then hint "installed · config skipped"; else hint "not installed · $(install_hint "$i")"; fi
        return 0
    fi
    if ! tool_has_config "$i"; then
        if tool_installed "$i"; then hint "installed · no config"; else hint "not installed · $(install_hint "$i")"; fi
        return 0
    fi
    if [[ -n "${T_RESOLVER[$i]}" ]]; then
        t="$(mktemp)"
        if resolver_render "${T_RESOLVER[$i]}" "$src" "$dest" > "$t" 2>/dev/null; then
            diff_file "$t" "$dest"
        else
            warn "cannot resolve config with '${T_RESOLVER[$i]}'"
        fi
        rm -f "$t"
    elif tool_config_is_dir "$i"; then
        local rel shown=0
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            printf '%s— %s —%s\n' "$C_DIM" "$rel" "$C_RESET"
            diff_file "$src/$rel" "$dest/$rel"; shown=1
        done < <(dir_files_to_sync "$src" "$dest")
        while IFS= read -r rel; do
            [[ -n "$rel" && ! -f "$src/$rel" ]] || continue
            warn "would remove stale: $rel"; shown=1
        done < <(dir_leaves_to_backup "$src" "$dest")
        [[ "$shown" == 0 ]] && hint "already up to date"
    else
        diff_file "$src" "$dest"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Bring one tool fully up to date: install if missing, then write its config.
# ---------------------------------------------------------------------------

# Bring one tool up to date, printing the run as clear stages (install → apply
# → done) with a one-line summary per stage. Output is captured per-tool into
# the run log and shown in the picker's pane.
# Also records per-stage markers so the picker's tree can show which step is
# live (<tool>.stage = install|copy|done) and the copy result counts
# (<tool>.result = "copied removed backed").
sync_tool() {
    local i="$1"
    local did=0 nm="${T_NAME[$i]}" b0 nb sum run="${DOTLAD_RUNDIR:-}"
    UTD_CACHE=()   # this call mutates config — never trust a stale up-to-date memo
    if mode_packages_enabled && ! tool_installed "$i" && tool_has_packages "$i"; then
        if [[ -n "$run" ]]; then
            printf "install" > "$run/${nm}.stage" 2>/dev/null || true
        fi
        printf '%s▸%s installing: %s\n' "$C_CYAN" "$C_RESET" "${T_BREW[$i]:-$nm}"
        if install_tool "$i"; then
            printf '%s  ✓ installed%s\n' "$C_GREEN" "$C_RESET"; did=1
        else
            printf '%s  ✗ install failed%s\n' "$C_RED" "$C_RESET"
            N_FAILED=$((N_FAILED + 1)); return 1
        fi
    fi
    if mode_config_enabled && tool_has_config "$i" && ! tool_uptodate "$i"; then
        if ! ensure_requirements "$i"; then
            N_FAILED=$((N_FAILED + 1)); return 1
        fi
        tool_paths "$i"
        if [[ -n "$run" ]]; then
            printf "copy" > "$run/${nm}.stage" 2>/dev/null || true
        fi
        printf '%s▸%s copying config → %s\n' "$C_CYAN" "$C_RESET" "$(pretty_path "$TP_DEST")"
        b0="$N_BACKED"
        if apply_config "$i"; then
            nb=$(( N_BACKED - b0 ))
            if [[ -n "$run" ]]; then
                printf '%s %s %s\n' "$AP_COPIED" "$AP_REMOVED" "$nb" > "$run/${nm}.result" 2>/dev/null || true
            fi
            sum="${AP_COPIED} copied"
            [[ "${AP_REMOVED:-0}" -gt 0 ]] && sum="${sum} · ${AP_REMOVED} removed"
            [[ "$nb" -gt 0 ]] && sum="${sum} · ${nb} backed up"
            printf '%s  ✓ %s%s\n' "$C_GREEN" "$sum" "$C_RESET"
            N_UPDATED=$((N_UPDATED + 1)); did=1
        else
            printf '%s  ✗ copy failed%s\n' "$C_RED" "$C_RESET"
            N_FAILED=$((N_FAILED + 1)); return 1
        fi
    fi
    if [[ -n "$run" ]]; then
        printf "done" > "$run/${nm}.stage" 2>/dev/null || true
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

# Human-readable file counts for a pending directory sync (tree preview).
dir_change_counts() {
    local i="$1" src dest c=0 m=0 rel counts=''
    tool_paths "$i"; src="$TP_SRC"; dest="$TP_DEST"
    if tool_config_is_dir "$i"; then
        while IFS= read -r rel; do [[ -n "$rel" ]] && c=$((c + 1)); done \
            < <(dir_files_to_sync "$src" "$dest")
        while IFS= read -r rel; do
            [[ -n "$rel" && ! -f "$src/$rel" ]] && m=$((m + 1))
        done < <(dir_leaves_to_backup "$src" "$dest")
    else
        c=1
    fi
    [[ "$c" -gt 0 ]] && counts="${c} $(file_noun "$c") to sync"
    [[ "$m" -gt 0 ]] && counts="${counts:+${counts} · }${m} $(file_noun "$m") to remove"
    printf '%s' "$counts"
}
