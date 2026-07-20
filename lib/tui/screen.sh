# shellcheck shell=bash disable=SC2034
# lib/tui/screen.sh — terminal screen lifecycle, layout, and rendering.

SAVED_STTY=""
COLS=80
# Tab moves focus between the tree and the output pane.
FOCUS_ZONE="tree"
PANEL_ON=0
PANEL_SCROLL=0
PANEL_FOLLOW=1
# Row budget for a focused restore point, recalculated from each rendered tree.
TUI_BACKUP_CHILD_ROWS=0

tui_screen_setup() {
    SAVED_STTY="$(stty -g 2>/dev/null || true)"
    stty -echo -icanon 2>/dev/null || true
    printf '\e[?1049h\e[?7l\e[?25l\e[2J'
}

tui_screen_teardown() {
    printf '\e[?7h\e[?25h\e[?1049l'
    if [[ -n "$SAVED_STTY" ]]; then
        stty "$SAVED_STTY" 2>/dev/null || true
    fi
}

# tui_wrap_text <width> <text…> — word-wrap to <width> columns.
tui_wrap_text() {
    local width="$1"
    shift
    local text="$*" line="" word
    [[ $width -lt 12 ]] && width=12
    for word in $text; do
        if [[ -z "$line" ]]; then
            line="$word"
        elif [[ $((${#line} + 1 + ${#word})) -le $width ]]; then
            line="$line $word"
        else
            printf '%s\n' "$line"
            line="$word"
        fi
    done
    [[ -n "$line" ]] && printf '%s\n' "$line"
    return 0
}

# Fit the panel to its content while preserving at least four tree rows.
tui_log_height() {
    local available=$(($1 - 3)) content="$2" focused="${3:-0}" cap max height
    [[ "$available" -gt 4 ]] || return 1
    max=$((available - 4))
    if [[ "$focused" == 1 ]]; then
        cap=$((available * 2 / 3))
    else cap=$((available / 3)); fi
    [[ "$cap" -gt "$max" ]] && cap="$max"
    [[ "$content" -lt 1 ]] && content=1
    if [[ "$content" -lt "$cap" ]]; then height="$content"; else height="$cap"; fi
    [[ "$height" -gt 0 ]] || return 1
    printf '%s' "$height"
}

tui_gutter() {
    if [[ "$1" == 1 ]]; then printf '%s●%s ' "$C_GREEN" "$C_RESET"; else printf '  '; fi
}

tui_line() {
    local j="$1" item first text foc=0 sel=0 line
    item=${L_ITEM[$j]}
    first=${L_FIRST[$j]}
    text=${L_TEXT[$j]}
    if [[ "${I_TYPE[$item]}" == sep ]]; then
        printf '%s\e[K' "$text"
        return 0
    fi
    [[ $item -eq $CURSOR ]] && foc=1
    if [[ $first == 1 ]]; then
        [[ "${I_TYPE[$item]}" == tool ]] &&
            tui_selection_contains "${I_NAME[$item]}" && sel=1
        line="$(tui_gutter "$sel")${text:2}"
    else
        line="$text"
    fi
    if [[ $foc == 1 && -n "$C_HL" ]]; then
        printf '%s\e[K%s%s' "$C_HL" "${line//$C_RESET/$C_RESET$C_HL}" "$C_RESET"
    else
        printf '%s\e[K' "$line"
    fi
}

tui_keybar() {
    local first=1 key label
    while [[ $# -ge 2 ]]; do
        key="$1"
        label="$2"
        [[ $first == 1 ]] && first=0 || printf '  '
        if [[ -n "${DOTLAD_SHOW_KEYS:-}" && "$KEYCAST" == "$key" ]]; then
            printf '%s%s%s%s %s%s%s' "$C_KEY_HL" "$C_BOLD" "$key" \
                "$C_RESET$C_KEY_HL" "$C_DIM" "$label" "$C_RESET"
        else
            printf '%s%s%s %s%s%s' "$C_BOLD" "$key" "$C_RESET" "$C_DIM" "$label" "$C_RESET"
        fi
        shift 2
    done
    return 0
}

tui_render() {
    local rows cols bodyrows backup_rows r j cfirst clast n run="${DOTLAD_RUNDIR:-}" rt
    local ptool="" panel_log=0 log_lines=0 log_focused=0 label_row log_top ln
    local logb=()
    read -r rows cols < <(stty size 2>/dev/null) || true
    : "${rows:=24}" "${cols:=80}"
    COLS=$cols

    rt="$(runner_running_tool "$run" || true)"
    [[ -n "$rt" ]] && LAST_RUN="$rt"
    if [[ "${I_TYPE[$CURSOR]:-}" == tool && -n "$run" && -f "$run/${CUR_NAME}.log" ]]; then
        ptool="$CUR_NAME"
    elif [[ -n "$rt" ]]; then
        ptool="$rt"
    elif [[ ${GRACE:-0} -gt 0 && -n "${LAST_RUN:-}" ]]; then
        ptool="$LAST_RUN"
    fi
    [[ -n "$ptool" && -n "$run" && -f "$run/${ptool}.log" ]] || ptool=""
    if [[ -n "$ptool" ]]; then
        read -r log_lines < <(wc -l <"$run/${ptool}.log" 2>/dev/null) || log_lines=0
        [[ "$FOCUS_ZONE" == panel ]] && log_focused=1
        panel_log="$(tui_log_height "$rows" "$log_lines" "$log_focused" || true)"
        [[ -n "$panel_log" ]] || ptool=""
    fi
    if [[ -n "$ptool" ]]; then PANEL_ON=1; else PANEL_ON=0; fi
    [[ $PANEL_ON == 0 && "$FOCUS_ZONE" == panel ]] && FOCUS_ZONE=tree

    if [[ -n "$ptool" ]]; then bodyrows=$((rows - 3 - panel_log)); else bodyrows=$((rows - 2)); fi
    [[ $bodyrows -lt 1 ]] && bodyrows=1

    if [[ "${I_TYPE[$CURSOR]:-}" == backup ]]; then
        backup_rows=$((bodyrows - 1))
        [[ "$backup_rows" -lt 0 ]] && backup_rows=0
        if [[ "$TUI_BACKUP_CHILD_ROWS" -ne "$backup_rows" ]]; then
            TUI_BACKUP_CHILD_ROWS="$backup_rows"
            tui_build
            tui_fix_cursor
        fi
    fi

    cfirst=${I_FIRSTLINE[$CURSOR]:-0}
    if [[ $((CURSOR + 1)) -lt $N_ITEMS ]]; then
        clast=$((${I_FIRSTLINE[$((CURSOR + 1))]} - 1))
    else
        clast=$((L_N - 1))
    fi
    [[ $cfirst -lt $TOP ]] && TOP=$cfirst
    [[ $clast -ge $((TOP + bodyrows)) ]] && TOP=$((clast - bodyrows + 1))
    [[ $TOP -lt 0 ]] && TOP=0

    printf '\e[1;1H\e[K %s󰆧 %s %s· %s ·%s %s%s%s' \
        "$C_BOLD" "$TUI_HEADER_TITLE" "$C_RESET$C_BOLD$C_DIM" "$TUI_HOST_LABEL" "$C_RESET" \
        "$C_SKY_BLUE" "<$(mode_label)>" "$C_RESET"
    n="$(tui_selection_count)"
    [[ "$n" -gt 0 ]] && printf '   %s● %s selected%s' "$C_GREEN" "$n" "$C_RESET"

    for ((r = 0; r < bodyrows; r++)); do
        j=$((TOP + r))
        printf '\e[%d;1H' "$((r + 2))"
        if [[ $j -lt $L_N ]]; then tui_line "$j"; else printf '\e[K'; fi
    done

    if [[ -n "$ptool" ]]; then
        label_row=$((bodyrows + 2))
        log_top=$((label_row + 1))
        local rule pglyph pcolor plabel focp=0 total=0 winbase=0 maxs=0 idx
        [[ "$FOCUS_ZONE" == panel ]] && focp=1
        if [[ -f "$run/${ptool}.running" ]]; then
            pglyph="${SPIN[$FRAME_I]}"
            pcolor="$C_CYAN"
            plabel='live output'
        elif [[ -f "$run/${ptool}.failed" ]]; then
            pglyph='✗'
            pcolor="$C_RED"
            plabel='failed'
        elif [[ -f "$run/${ptool}.done" ]]; then
            pglyph='✓'
            pcolor="$C_GREEN"
            plabel='done'
        else
            pglyph="${SPIN[$FRAME_I]}"
            pcolor="$C_CYAN"
            plabel='output'
        fi
        logb=()
        if [[ $focp == 1 ]]; then
            while IFS= read -r ln || [[ -n "$ln" ]]; do logb+=("$ln"); done \
                < <(cat "$run/${ptool}.log" 2>/dev/null || true)
            total=${#logb[@]}
            maxs=$((total - panel_log))
            [[ $maxs -lt 0 ]] && maxs=0
            [[ "$PANEL_FOLLOW" == 1 ]] && PANEL_SCROLL=$maxs
            [[ $PANEL_SCROLL -gt $maxs ]] && PANEL_SCROLL=$maxs
            [[ $PANEL_SCROLL -lt 0 ]] && PANEL_SCROLL=0
            winbase=$PANEL_SCROLL
        else
            while IFS= read -r ln; do logb+=("$ln"); done \
                < <(tail -n "$panel_log" "$run/${ptool}.log" 2>/dev/null || true)
            total=${#logb[@]}
            winbase=0
        fi
        printf -v rule '%*s' "$cols" ''
        rule="${rule// /─}"
        printf '\e[%d;1H\e[K%s%s%s' "$label_row" "$C_DIM" "$rule" "$C_RESET"
        if [[ $focp == 1 ]]; then
            printf '\e[%d;3H %s%s %s%s%s %s· scroll %s–%s/%s · ↑↓ · tab tree%s ' "$label_row" \
                "$C_CYAN" "$pglyph" "$C_BOLD" "$ptool" "$C_RESET" "$C_CYAN" \
                "$((winbase + 1))" "$((winbase + panel_log < total ? winbase + panel_log : total))" "$total" "$C_RESET"
        else
            printf '\e[%d;3H %s%s%s %s%s%s %s· %s · tab to scroll%s ' "$label_row" \
                "$pcolor" "$pglyph" "$C_RESET" "$C_BOLD" "$ptool" "$C_RESET" \
                "$C_DIM" "$plabel" "$C_RESET"
        fi
        for ((r = 0; r < panel_log; r++)); do
            printf '\e[%d;1H\e[K' "$((log_top + r))"
            idx=$((winbase + r))
            [[ $idx -lt $total ]] && printf '  %s%s' "${logb[$idx]}" "$C_RESET"
        done
    fi

    printf '\e[%d;1H\e[K ' "$rows"
    if [[ -n "$TOAST" ]]; then
        printf '%s%s%s' "$C_GREEN" "$TOAST" "$C_RESET"
    elif [[ "$FOCUS_ZONE" == panel ]]; then
        tui_keybar '↑↓' scroll 'g/G' top/bottom tab tree q quit
    elif [[ "${I_TYPE[$CURSOR]:-}" == backup ]]; then
        tui_keybar '↑↓' move '⏎' restore d diff x delete q quit
    elif [[ "${I_TYPE[$CURSOR]:-}" == empty || "${I_TYPE[$CURSOR]:-}" == sep ]]; then
        tui_keybar m mode q quit
    else
        tui_keybar '↑↓' move 'g/G' jump space pick '⏎' run d diff a all m mode q quit
    fi
    printf '\e[J'
}
