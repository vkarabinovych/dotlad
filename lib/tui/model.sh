# shellcheck shell=bash disable=SC2034,SC2153
# lib/tui/model.sh — cached rows, cursor, selection, and viewport state.

# Scan cache: expensive tool state and activity, rebuilt only after state
# changes or while work is in flight.
SCAN_NAME=()
SCAN_DESC=()
SCAN_HEAD=()
SCAN_ACT=()
SCAN_ACTIVE=()
SCAN_N=0
SCAN_BDIR=()
SCAN_BCOUNT=()
SCAN_BFILES=()
SCAN_NB=0

# Cheap per-frame item and rendered-line model.
I_TYPE=()
I_NAME=()
I_FIRSTLINE=()
N_ITEMS=0
L_TEXT=()
L_ITEM=()
L_FIRST=()
L_N=0

SEL=" "
CURSOR=0
CUR_NAME=""
TOP=0

tui_selection_contains() { [[ "$SEL" == *" $1 "* ]]; }

tui_selection_count() {
    local count=0 name
    for name in $SEL; do count=$((count + 1)); done
    printf '%s' "$count"
}

tui_scan() {
    local frame="${1:-}" i k=0 nm run="${DOTLAD_RUNDIR:-}" tab bdir bcount
    tab="$(printf '\t')"
    UTD_CACHE=()
    SCAN_NAME=()
    SCAN_DESC=()
    SCAN_HEAD=()
    SCAN_ACT=()
    SCAN_ACTIVE=()
    SCAN_N=0
    while read -r i; do
        [[ -n "$i" ]] || continue
        nm="${T_NAME[$i]}"
        SCAN_NAME[k]="$nm"
        SCAN_DESC[k]="${T_DESC[$i]}"
        SCAN_HEAD[k]="$(headline_line "$i" "$frame")"
        SCAN_ACT[k]="$(tool_activity "$i" "$frame")"
        if [[ -n "$run" ]] &&
            { [[ -f "$run/${nm}.running" ]] || [[ -f "$run/${nm}.failed" ]] ||
                queue_has_tool "$run" "$nm"; }; then
            SCAN_ACTIVE[k]=1
        else
            SCAN_ACTIVE[k]=0
        fi
        k=$((k + 1))
    done < <(tool_order)
    SCAN_N=$k
    SCAN_BDIR=()
    SCAN_BCOUNT=()
    SCAN_BFILES=()
    SCAN_NB=0
    if mode_config_enabled; then
        while IFS="$tab" read -r bdir bcount; do
            [[ -n "$bdir" ]] || continue
            SCAN_BDIR[SCAN_NB]="$bdir"
            SCAN_BCOUNT[SCAN_NB]="$bcount"
            SCAN_BFILES[SCAN_NB]="$(backup_activity "$bdir")"
            SCAN_NB=$((SCAN_NB + 1))
        done < <(list_backups)
    fi
    [[ -z "$CUR_NAME" && $SCAN_N -gt 0 ]] && CUR_NAME="${SCAN_NAME[0]}"
    return 0
}

tui_refresh_running() {
    local frame="${1:-}" rt k i run="${DOTLAD_RUNDIR:-}"
    rt="$(runner_running_tool "$run" || true)"
    [[ -n "$rt" ]] || return 0
    for ((k = 0; k < SCAN_N; k++)); do
        [[ "${SCAN_NAME[k]}" == "$rt" ]] || continue
        i="$(tool_find "$rt")" || return 0
        SCAN_HEAD[k]="$(headline_line "$i" "$frame")"
        SCAN_ACT[k]="$(tool_activity "$i" "$frame")"
        return 0
    done
    return 0
}

tui_append_children() {
    local acts="$1" line
    [[ -n "$acts" ]] || return 0
    while IFS= read -r line; do
        L_TEXT[L_N]="$line"
        L_ITEM[L_N]=$N_ITEMS
        L_FIRST[L_N]=0
        L_N=$((L_N + 1))
    done < <(tree_activity_lines <<<"$acts")
    return 0
}

tui_build() {
    local k nm b had=0 dline
    I_TYPE=()
    I_NAME=()
    I_FIRSTLINE=()
    N_ITEMS=0
    L_TEXT=()
    L_ITEM=()
    L_FIRST=()
    L_N=0
    for ((k = 0; k < SCAN_N; k++)); do
        nm="${SCAN_NAME[k]}"
        I_TYPE[N_ITEMS]='tool'
        I_NAME[N_ITEMS]="$nm"
        I_FIRSTLINE[N_ITEMS]=$L_N
        L_TEXT[L_N]="${SCAN_HEAD[k]}"
        L_ITEM[L_N]=$N_ITEMS
        L_FIRST[L_N]=1
        L_N=$((L_N + 1))
        if [[ "$nm" == "$CUR_NAME" || "${SCAN_ACTIVE[k]}" == 1 ]]; then
            if [[ "$nm" == "$CUR_NAME" && -n "${SCAN_DESC[k]}" ]]; then
                while IFS= read -r dline; do
                    L_TEXT[L_N]="  ${C_DIM}│ ${dline}${C_RESET}"
                    L_ITEM[L_N]=$N_ITEMS
                    L_FIRST[L_N]=0
                    L_N=$((L_N + 1))
                done < <(tui_wrap_text "$((COLS - 6))" "${SCAN_DESC[k]}")
            fi
            tui_append_children "${SCAN_ACT[k]}"
        fi
        N_ITEMS=$((N_ITEMS + 1))
    done
    for ((b = 0; b < SCAN_NB; b++)); do
        if [[ $had == 0 ]]; then
            I_TYPE[N_ITEMS]='sep'
            I_NAME[N_ITEMS]='@@sep'
            I_FIRSTLINE[N_ITEMS]=$L_N
            L_TEXT[L_N]="$(sep_line 'restore points')"
            L_ITEM[L_N]=$N_ITEMS
            L_FIRST[L_N]=1
            L_N=$((L_N + 1))
            N_ITEMS=$((N_ITEMS + 1))
            had=1
        fi
        I_TYPE[N_ITEMS]='backup'
        I_NAME[N_ITEMS]="@${SCAN_BDIR[b]}"
        I_FIRSTLINE[N_ITEMS]=$L_N
        L_TEXT[L_N]="$(backup_line "${SCAN_BDIR[b]}" "${SCAN_BCOUNT[b]}")"
        L_ITEM[L_N]=$N_ITEMS
        L_FIRST[L_N]=1
        L_N=$((L_N + 1))
        if [[ "@${SCAN_BDIR[b]}" == "$CUR_NAME" ]]; then
            tui_append_children "$(backup_activity_window "${SCAN_BFILES[b]}" \
                "$TUI_BACKUP_CHILD_ROWS" "${SCAN_BCOUNT[b]}")"
        fi
        N_ITEMS=$((N_ITEMS + 1))
    done
    return 0
}

tui_fix_cursor() {
    local k
    if [[ -n "$CUR_NAME" ]]; then
        for ((k = 0; k < N_ITEMS; k++)); do
            [[ "${I_NAME[$k]}" == "$CUR_NAME" ]] && {
                CURSOR=$k
                return
            }
        done
    fi
    [[ $CURSOR -ge $N_ITEMS ]] && CURSOR=$((N_ITEMS - 1))
    [[ $CURSOR -lt 0 ]] && CURSOR=0
    [[ "${I_TYPE[$CURSOR]:-}" == sep ]] && CURSOR=$((CURSOR - 1))
    [[ $CURSOR -lt 0 ]] && CURSOR=0
    [[ $N_ITEMS -gt 0 ]] && CUR_NAME="${I_NAME[$CURSOR]}"
    return 0
}

tui_move() {
    local delta="$1"
    CURSOR=$((CURSOR + delta))
    [[ $CURSOR -lt 0 ]] && CURSOR=0
    [[ $CURSOR -ge $N_ITEMS ]] && CURSOR=$((N_ITEMS - 1))
    if [[ "${I_TYPE[$CURSOR]:-}" == sep ]]; then
        [[ $delta -lt 0 ]] && CURSOR=$((CURSOR - 1)) || CURSOR=$((CURSOR + 1))
        [[ $CURSOR -lt 0 ]] && CURSOR=0
        [[ $CURSOR -ge $N_ITEMS ]] && CURSOR=$((N_ITEMS - 1))
    fi
    CUR_NAME="${I_NAME[$CURSOR]}"
    return 0
}

tui_toggle_selection() {
    [[ "${I_TYPE[$CURSOR]}" == tool ]] || return 0
    local name="${I_NAME[$CURSOR]}"
    if tui_selection_contains "$name"; then
        SEL="${SEL// $name / }"
    else
        SEL="${SEL}${name} "
    fi
    tui_move 1
}

tui_toggle_all() {
    local k all_selected=1
    for ((k = 0; k < N_ITEMS; k++)); do
        [[ "${I_TYPE[$k]}" == tool ]] || continue
        tui_selection_contains "${I_NAME[$k]}" || {
            all_selected=0
            break
        }
    done
    SEL=" "
    if [[ $all_selected == 0 ]]; then
        for ((k = 0; k < N_ITEMS; k++)); do
            [[ "${I_TYPE[$k]}" == tool ]] && SEL="${SEL}${I_NAME[$k]} "
        done
    fi
    return 0
}

tui_scroll_panel() {
    PANEL_SCROLL=$((PANEL_SCROLL + $1))
    [[ $PANEL_SCROLL -lt 0 ]] && PANEL_SCROLL=0
    PANEL_FOLLOW=0
    return 0
}
