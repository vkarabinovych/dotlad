# shellcheck disable=SC2153  # ST_CFG/ST_INSTALLED are set by tool_state in engine.sh
# lib/pick.sh — presentation model shared by plain and interactive views:
# state rows, activity trees, ordering, and restore-point rows. Queue
# execution lives in runner.sh; terminal interaction lives in tui.sh.

# shellcheck disable=SC2034  # SPIN is consumed by tui.sh
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# Print an activity row and wrap its payload to ACTIVITY_WIDTH visible columns.
# Used by both package lists and config source → destination rows. Continuations
# use a shallow indent so paths and long formula names fit on narrow screens;
# a single unbroken token is split only when it is wider than a whole row.
wrapped_activity() {  # <color> <glyph> <verb> <space-separated-payload>
    local color="$1" glyph="$2" verb="$3" payload="$4"
    local width="${ACTIVITY_WIDTH:-76}" prefix first_cap cont_cap first=1 line="" word cap part
    [[ "$width" -lt 16 ]] && width=16
    prefix=$((1 + 1 + ${#verb} + 2))
    first_cap=$((width - prefix)); [[ "$first_cap" -lt 4 ]] && first_cap=4
    cont_cap=$((width - 2)); [[ "$cont_cap" -lt 8 ]] && cont_cap=8

    for word in $payload; do
        cap=$first_cap; [[ "$first" == 0 ]] && cap=$cont_cap
        if [[ -n "$line" && $(( ${#line} + 1 + ${#word} )) -gt $cap ]]; then
            if [[ "$first" == 1 ]]; then
                printf '%s%s%s %s%s%s  %s\n' "$color" "$glyph" "$C_RESET" "$C_DIM" "$verb" "$C_RESET" "$line"
                first=0
            else
                printf '\002  %s\n' "$line"
            fi
            line=""; cap=$cont_cap
        fi
        while [[ ${#word} -gt $cap ]]; do
            part="${word:0:$cap}"; word="${word:$cap}"
            if [[ "$first" == 1 ]]; then
                printf '%s%s%s %s%s%s  %s\n' "$color" "$glyph" "$C_RESET" "$C_DIM" "$verb" "$C_RESET" "$part"
                first=0; cap=$cont_cap
            else
                printf '\002  %s\n' "$part"
            fi
        done
        if [[ -z "$line" ]]; then line="$word"; else line="$line $word"; fi
    done
    if [[ "$first" == 1 ]]; then
        printf '%s%s%s %s%s%s  %s\n' "$color" "$glyph" "$C_RESET" "$C_DIM" "$verb" "$C_RESET" "$line"
    elif [[ -n "$line" ]]; then
        printf '\002  %s\n' "$line"
    fi
}

# Convert physical activity lines into a connected tree. Wrapped continuations
# are marked with STX by wrapped_activity: a non-final logical action continues
# with │, while the final action continues with whitespace only.
tree_activity_lines() {
    local lines=() line stx logical=0 logical_i=0 current_last=0 con
    stx="$(printf '\002')"
    while IFS= read -r line; do lines+=("$line"); done
    for line in "${lines[@]}"; do [[ "$line" == "$stx"* ]] || logical=$((logical + 1)); done
    for line in "${lines[@]}"; do
        if [[ "$line" == "$stx"* ]]; then
            line="${line#"$stx"}"
            if [[ "$current_last" == 1 ]]; then con=' '; else con='│'; fi
        else
            logical_i=$((logical_i + 1))
            if [[ "$logical_i" -eq "$logical" ]]; then con='└'; current_last=1
            else con='├'; current_last=0; fi
        fi
        printf '  %s%s%s %s\n' "$C_DIM" "$con" "$C_RESET" "$line"
    done
}

# compute_row <idx> [spinner-frame] — the tool's headline state. Sets:
#   RS_GLYPH RS_COLOR RS_LABEL RS_NOTE RS_NOTECOLOR RS_WEIGHT RS_WANT
# Failed / running / queued float to the top (negative weights) and always show
# their subtree; otherwise the state comes from the config/install check. An
# A missing tool leads in full/package mode even when its config is ready; the
# config state becomes a coloured note so a green check never masks missing
# runtime state.
compute_row() {
    local i="$1"
    local frame="${2:-}" run="${DOTLAD_RUNDIR:-}" nm="${T_NAME[$i]}"
    RS_WANT=0; RS_NOTE=""; RS_NOTECOLOR="$C_DIM"
    if [[ -n "$run" && -f "$run/${nm}.failed" ]]; then
        RS_GLYPH='✗'; RS_COLOR="$C_RED"; RS_LABEL='failed'; RS_NOTE='enter to retry'; RS_WEIGHT=-3; RS_WANT=1
    elif [[ -n "$run" && -f "$run/${nm}.running" ]]; then
        RS_GLYPH="$frame"; RS_COLOR="$C_CYAN"; RS_LABEL='working…'; RS_NOTE=''; RS_WEIGHT=-2; RS_WANT=1
    elif [[ -n "$run" ]] && queue_has_tool "$run" "$nm"; then
        RS_GLYPH='…'; RS_COLOR="$C_CYAN"; RS_LABEL='queued'; RS_NOTE=''; RS_WEIGHT=-1; RS_WANT=1
    else
        tool_state "$i"
        local has_installer=0
        [[ -n "${T_BREW[$i]}" || -n "${T_INSTALL_URL[$i]}" ]] && has_installer=1
        # Headline = the state relevant to the active mode. In full mode a
        # missing runtime takes priority over config state because the tool is
        # not usable yet; config readiness remains visible as the note.
        if [[ "$DOTLAD_MODE" == "packages" ]]; then
            if [[ "$ST_INSTALLED" == 1 ]]; then RS_GLYPH='✓'; RS_COLOR="$C_GREEN"; RS_LABEL='installed'; RS_WEIGHT=5
            else RS_GLYPH='+'; RS_COLOR="$C_MAGENTA"; RS_LABEL='not installed'; RS_WEIGHT=2; fi
        elif [[ "$DOTLAD_MODE" == "config" ]]; then
            case "$ST_CFG" in
                update) RS_GLYPH='↑'; RS_COLOR="$C_YELLOW";  RS_LABEL='update available'; RS_WEIGHT=0 ;;
                new)    RS_GLYPH='+'; RS_COLOR="$C_MAGENTA"; RS_LABEL='not set up';       RS_WEIGHT=1 ;;
                ready)  RS_GLYPH='✓'; RS_COLOR="$C_GREEN";   RS_LABEL='up to date';       RS_WEIGHT=5 ;;
            esac
        elif ! tool_has_config "$i"; then
            if [[ "$ST_INSTALLED" == 1 ]]; then RS_GLYPH='✓'; RS_COLOR="$C_GREEN"; RS_LABEL='installed'; RS_WEIGHT=5
            else RS_GLYPH='+'; RS_COLOR="$C_MAGENTA"; RS_LABEL='not installed'; RS_WEIGHT=2; fi
        elif [[ "$ST_INSTALLED" == "0" ]]; then
            if [[ "$has_installer" == 1 ]]; then
                RS_GLYPH='+'; RS_COLOR="$C_MAGENTA"; RS_LABEL='not installed'
            else
                RS_GLYPH='!'; RS_COLOR="$C_YELLOW"; RS_LABEL='tool not found'
            fi
            case "$ST_CFG" in
                update) RS_NOTE='config update available'; RS_NOTECOLOR="$C_YELLOW";  RS_WEIGHT=0 ;;
                new)    RS_NOTE='config not set up';       RS_NOTECOLOR="$C_MAGENTA"; RS_WEIGHT=1 ;;
                ready)  RS_NOTE='config up to date';       RS_NOTECOLOR="$C_GREEN";   RS_WEIGHT=2 ;;
            esac
        else
            case "$ST_CFG" in
                update) RS_GLYPH='↑'; RS_COLOR="$C_YELLOW";  RS_LABEL='update available'; RS_WEIGHT=0 ;;
                new)    RS_GLYPH='+'; RS_COLOR="$C_MAGENTA"; RS_LABEL='not set up';       RS_WEIGHT=1 ;;
                ready)  RS_GLYPH='✓'; RS_COLOR="$C_GREEN";   RS_LABEL='up to date';       RS_WEIGHT=5 ;;
            esac
        fi
        [[ -n "$run" && -f "$run/${nm}.done" ]] && { RS_NOTE='just updated'; RS_NOTECOLOR="$C_GREEN"; }
        # Show the activity subtree for multi-package tools, an installable tool
        # that's missing, a pending config change, or a recorded run result.
        local kids npk
        read -ra kids <<< "${T_BREW[$i]}"; npk=${#kids[@]}
        if mode_packages_enabled; then
            [[ "$npk" -gt 1 ]] && RS_WANT=1
            [[ "$ST_INSTALLED" == "0" && "$has_installer" == 1 ]] && RS_WANT=1
        fi
        if mode_config_enabled; then
            tool_has_config "$i" && [[ "$ST_CFG" == "update" || "$ST_CFG" == "new" ]] && RS_WANT=1
            [[ -n "$run" && -f "$run/${nm}.result" ]] && RS_WANT=1
        fi
    fi
    return 0   # the trailing `[[ … ]] &&` above must not become our exit status
}

# The subtree body for a tool: one activity line per action, shaped as
#   <status glyph>  <dim verb>  <payload>
# so the eye lands on the coloured glyph (state) then the payload (what). Live:
#   ✓ installed  <pkgs present>
#   ↓ install / <spinner> installing   <pending pkgs, or a remote-installer URL>
#                                       (queued shows on the parent row)
#   + create <src> → <dest>    (config not there yet, magenta)
#   ↑ update <src> → <dest> · N files to sync [· M files to remove]
#                                           (existing config differs, yellow)
#   ✓ copy|link <src> → <dest> · N entries synced  (completed result, green)
#   ✓ <dest> up to date
# Callers add the ├/└ connector and indent.
tool_activity() {  # <idx> <spinner-frame>
    local i="$1"
    local frame="$2" run="${DOTLAD_RUNDIR:-}" nm="${T_NAME[$i]}"
    local stage='' running=0 prefix pkgs pk pkbase inst='' pend='' hurl=''
    if [[ -n "$run" ]]; then
        [[ -f "$run/${nm}.stage" ]] && stage="$(cat "$run/${nm}.stage" 2>/dev/null)"
        [[ -f "$run/${nm}.running" ]] && running=1
    fi
    read -ra pkgs <<< "${T_BREW[$i]}"
    if mode_packages_enabled && [[ ${#pkgs[@]} -gt 0 && "${T_CASK[$i]}" == "1" ]]; then
        # Casks have no opt links to stat per-package — judge the whole set by
        # the tool's own CHECK.
        if tool_installed "$i"; then
            wrapped_activity "$C_GREEN" '✓' installed "${pkgs[*]}"
        elif [[ "$running" == 1 && "$stage" == "install" ]]; then
            wrapped_activity "$C_CYAN" "$frame" installing "${pkgs[*]}"
        else
            wrapped_activity "$C_YELLOW" '↓' install "${pkgs[*]}"
        fi
    elif mode_packages_enabled && [[ ${#pkgs[@]} -gt 0 ]]; then
        prefix="$(brew_prefix)"
        for pk in "${pkgs[@]}"; do
            pkbase="${pk##*/}"
            if [[ -n "$prefix" && -e "$prefix/opt/$pkbase" ]]; then inst="${inst} $pkbase"; else pend="${pend} $pkbase"; fi
        done
        inst="${inst# }"; pend="${pend# }"
        [[ -n "$inst" ]] && wrapped_activity "$C_GREEN" '✓' installed "$inst"
        if [[ -n "$pend" ]]; then
            if [[ "$running" == 1 && "$stage" == "install" ]]; then
                wrapped_activity "$C_CYAN" "$frame" installing "$pend"
            else
                # idle or queued alike just list what will be installed — the
                # "queued" waiting state already shows on the parent row
                wrapped_activity "$C_YELLOW" '↓' install "$pend"
            fi
        fi
    elif mode_packages_enabled && [[ -n "${T_INSTALL_URL[$i]}" ]]; then
        # No brew package — this tool installs via a remote script. Show the
        # installer host so it's clear what running it would fetch.
        hurl="${T_INSTALL_URL[$i]}"; hurl="${hurl#https://}"; hurl="${hurl#http://}"
        if tool_installed "$i"; then
            wrapped_activity "$C_GREEN" '✓' installed "$nm"
        elif [[ "$running" == 1 && "$stage" == "install" ]]; then
            wrapped_activity "$C_CYAN" "$frame" 'running installer' "$hurl"
        else
            wrapped_activity "$C_YELLOW" '↓' install "$hurl"
        fi
    fi
    if mode_config_enabled && tool_has_config "$i"; then
        local src="${T_SRC[$i]}" dest c m b counts cg cc verb action
        dest="$(pretty_path "${T_DEST[$i]}")"
        action="$(tool_config_action "$i")"
        # A pending change either creates a config that isn't there yet
        # (+ create, magenta — like the "not set up" headline) or updates an
        # existing one (↑ update, yellow — like "update available").
        if [[ -e "${T_DEST[$i]}" || -L "${T_DEST[$i]}" ]]; then cg='↑'; cc="$C_YELLOW"; verb='update'
        else cg='+'; cc="$C_MAGENTA"; verb='create'; fi
        if [[ "$running" == 1 && ( "$stage" == "copy" || "$stage" == "link" ) ]]; then
            wrapped_activity "$C_CYAN" "$frame" "$verb" "$src → $dest"
        elif [[ -n "$run" && -f "$run/${nm}.result" ]]; then
            # `|| true`: read returns non-zero on a newline-less file, which
            # under set -e would abort before the result line is printed.
            read -r c m b < "$run/${nm}.result" || true
            counts=''
            if [[ "${c:-0}" -gt 0 && "$action" == link ]]; then
                counts="${c} link synced"
            elif [[ "${c:-0}" -gt 0 ]]; then
                counts="${c} $(file_noun "$c") synced"
            fi
            [[ "${m:-0}" -gt 0 ]] && counts="${counts:+${counts} · }${m} $(file_noun "$m") removed"
            [[ "${b:-0}" -gt 0 ]] && counts="${counts:+${counts} · }${b} $(file_noun "$b") backed up"
            wrapped_activity "$C_GREEN" '✓' "$action" "$src → $dest${counts:+ · $counts}"
        elif tool_uptodate "$i"; then
            wrapped_activity "$C_GREEN" '✓' 'up to date' "$dest"
        elif tool_config_is_dir "$i" || [[ "$action" == link ]]; then
            counts="$(resolver_changes "${T_RESOLVER[$i]}" "$ROOT/$src" "${T_DEST[$i]}")"
            wrapped_activity "$cc" "$cg" "$verb" "$src → $dest${counts:+ · $counts}"
        else
            wrapped_activity "$cc" "$cg" "$verb" "$src → $dest"
        fi
    fi
}

# tool_block <idx> [frame] — the tool's rendered lines: a header line then the
# activity subtree. Every line starts with two literal spaces so the TUI can
# stamp a pointer/marker into that gutter; the plain view just prints them.
# headline_line <idx> [frame] — the single state row (runs compute_row, so the
# caller can read RS_* afterwards). Name column is sized to the longest tool
# name (computed once) so a long name can never break the state column's
# alignment. The note carries secondary config state or a green completion tag.
headline_line() {
    local i="$1"
    local nm="${T_NAME[$i]}" icon="${T_ICON[$i]}"
    compute_row "$i" "${2:-}"
    if [[ -z "${NAME_W:-}" ]]; then
        local _k; NAME_W=8
        for (( _k = 0; _k < T_COUNT; _k++ )); do [[ ${#T_NAME[$_k]} -gt $NAME_W ]] && NAME_W=${#T_NAME[$_k]}; done
    fi
    printf '  %s%s%s %s%s%s %-*s %s%-17s%s %s%s%s\n' \
        "$RS_COLOR" "$RS_GLYPH" "$C_RESET" "$C_CYAN" "$icon" "$C_RESET" "$NAME_W" "$nm" \
        "$C_ITALIC$RS_COLOR" "$RS_LABEL" "$C_RESET" \
        "$C_ITALIC$RS_NOTECOLOR" "$RS_NOTE" "$C_RESET"
}

# tool_block <idx> [frame] — headline plus, when there's pending activity, its
# subtree. Used by the plain view; the interactive screen expands the subtree
# only for the focused (or running) tool — see tui_build.
tool_block() {
    local i="$1" frame="${2:-}"
    headline_line "$i" "$frame"
    [[ "$RS_WANT" == 1 ]] || return 0
    tree_activity_lines < <(tool_activity "$i" "$frame")
}

# sep_line <label> — a dim section divider (used above the restore points).
# Two leading spaces to match every other content line's gutter.
sep_line() {
    printf '  %s── %s ──────────────────────%s\n' "$C_DIM" "$1" "$C_RESET"
}

# backup_line <dirname> <file-count> — one row for a restore point.
backup_line() {
    local dir="$1" count="$2"
    printf '  %s⏮%s %s%s%s %s(%s %s)%s\n' \
        "$C_MAGENTA" "$C_RESET" "$C_BOLD" "$(fmt_backup_ts "$dir")" "$C_RESET" \
        "$C_ITALIC$C_DIM" "$count" "$(file_noun "$count")" "$C_RESET"
}

# backup_file_line <mark> <rel> — one file inside a restore point, tagged by
# what restoring it would do: = unchanged (dim) · ~ differs (yellow) · +
# would be recreated (green).
backup_file_line() {
    case "$1" in
        '~') printf '%s~%s %s' "$C_YELLOW" "$C_RESET" "$2" ;;
        '+') printf '%s+%s %s' "$C_GREEN" "$C_RESET" "$2" ;;
        *)   printf '%s= %s%s' "$C_DIM" "$2" "$C_RESET" ;;
    esac
}

backup_more_line() {  # <remaining-count>
    printf '%s… %s more %s · d details%s' \
        "$C_DIM" "$1" "$(file_noun "$1")" "$C_RESET"
}

backup_activity() {  # <dirname> — all restore-point child lines
    local dir="$1" mark rel tab
    tab="$(printf '\t')"
    while IFS="$tab" read -r mark rel; do
        [[ -n "$rel" ]] && { backup_file_line "$mark" "$rel"; printf '\n'; }
    done < <(backup_entries "$dir")
}

# Fit cached backup activity into a row budget. When clipping is required, the
# final row reports the hidden entries and points to the complete paged diff.
backup_activity_window() {  # <multiline-activity> <row-budget> <total>
    local activity="$1" budget="$2" total="$3" line shown=0 limit remaining
    [[ "$budget" -gt 0 ]] || return 0
    if [[ "$total" -le "$budget" ]]; then limit="$total"
    else limit=$((budget - 1)); fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$shown" -lt "$limit" ]] || break
        printf '%s\n' "$line"; shown=$((shown + 1))
    done <<< "$activity"
    remaining=$((total - shown))
    if [[ "$remaining" -gt 0 ]]; then
        backup_more_line "$remaining"; printf '\n'
    fi
}

# tool_order — tool indices sorted by (weight, name); weight floats
# failed/running/queued to the top and up-to-date/package to the bottom.
tool_order() {
    local i tab
    tab="$(printf '\t')"
    for (( i = 0; i < T_COUNT; i++ )); do
        tool_relevant "$i" || continue
        compute_row "$i"
        printf '%s\t%s\t%s\n' "$RS_WEIGHT" "${T_NAME[$i]}" "$i"
    done | sort -t"$tab" -k1,1n -k2,2 | cut -f3
}

# Plain, non-interactive view (no TTY): the same tree, printed once.
print_list() {
    local i tab bdir bcount
    tab="$(printf '\t')"; UTD_CACHE=()
    ACTIVITY_WIDTH=$(( ${COLUMNS:-80} - 4 )); [[ "$ACTIVITY_WIDTH" -lt 16 ]] && ACTIVITY_WIDTH=16
    hint "mode: $(mode_label)"
    while read -r i; do
        [[ -n "$i" ]] || continue
        tool_block "$i"
    done < <(tool_order)
    if mode_config_enabled; then
        while IFS="$tab" read -r bdir bcount; do
            [[ -n "$bdir" ]] || continue
            backup_line "$bdir" "$bcount"
        done < <(list_backups)
    fi
    echo ""
    hint "run $DOTLAD_COMMAND_NAME to pick and update, or $DOTLAD_COMMAND_NAME <tool>… / all"
}
