# shellcheck disable=SC2153,SC2034  # T_* are manifest arrays; UTD_CACHE lives in engine.sh
# lib/tui.sh — full-screen tool tree and interaction. Enter starts queued
# work in the background or restores the focused restore point. The tree is the
# whole UI; press `d` for a tool diff or running log.
#
# State is kept in globals (not locals) so the small helper functions can share
# it: the item/line model (I_*, L_*), the cursor, selection, viewport and the
# animation/redraw bookkeeping.

# scan cache (the expensive pass: tool state + activity). Rebuilt only on a
# state change or while a run is in flight — never on a plain cursor move.
SCAN_NAME=(); SCAN_DESC=(); SCAN_HEAD=(); SCAN_ACT=(); SCAN_ACTIVE=(); SCAN_N=0
SCAN_BDIR=(); SCAN_BCOUNT=(); SCAN_BFILES=(); SCAN_NB=0
# item model (assembled cheaply from the scan cache every frame)
I_TYPE=(); I_NAME=(); I_FIRSTLINE=(); N_ITEMS=0
L_TEXT=(); L_ITEM=(); L_FIRST=(); L_N=0
# interaction state
SEL=" "; CURSOR=0; CUR_NAME=""; TOP=0; TOAST=""
FRAME_I=0; GRACE=0; NEED_SCAN=1; SAVED_STTY=""; LAST_RUN=""; LAST_SIG=""; COLS=80
TUI_KEY=""
# Bash 3.2 accepts only whole seconds for `read -t`.
TUI_FRAME_TIMEOUT="0.15"; TUI_SEQUENCE_TIMEOUT="0.05"
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then TUI_FRAME_TIMEOUT=1; TUI_SEQUENCE_TIMEOUT=1; fi
# output-pane focus/scroll: Tab moves between the tree and the log pane.
FOCUS_ZONE="tree"; PANEL_ON=0; PANEL_SCROLL=0; PANEL_FOLLOW=1

# --- terminal setup / teardown ---------------------------------------------

# Stock macOS Bash 3.2 reads Cyrillic as two bytes even in a UTF-8 locale.
# Join that pair so the Ukrainian aliases in the key dispatch can match.
tui_read_key() {
    local timeout="${1:-}" first="" second=""
    TUI_KEY=""
    if [[ -n "$timeout" ]]; then
        IFS= read -rsn1 -t "$timeout" first || return 1
    else
        IFS= read -rsn1 first || return 1
    fi
    TUI_KEY="$first"
    case "$first" in
        $'\320'|$'\321')
            IFS= read -rsn1 second || { TUI_KEY=""; return 1; }
            TUI_KEY+="$second"
            ;;
    esac
    return 0
}

# Normalize Ukrainian-layout characters by their physical Latin key so every
# letter shortcut works without switching layouts.
tui_normalize_key() {
    case "$TUI_KEY" in
        о) TUI_KEY="j" ;;
        л) TUI_KEY="k" ;;
        п) TUI_KEY="g" ;;
        П) TUI_KEY="G" ;;
        ф) TUI_KEY="a" ;;
        ь) TUI_KEY="m" ;;
        в) TUI_KEY="d" ;;
        ч) TUI_KEY="x" ;;
        й) TUI_KEY="q" ;;
        н) TUI_KEY="y" ;;
        Н) TUI_KEY="Y" ;;
    esac
}

tui_setup() {
    SAVED_STTY="$(stty -g 2>/dev/null || true)"
    stty -echo -icanon 2>/dev/null || true
    printf '\e[?1049h\e[?7l\e[?25l\e[2J'   # alt screen, no wrap, hide cursor, clear
}
tui_teardown() {
    printf '\e[?7h\e[?25h\e[?1049l'        # wrap on, cursor on, leave alt screen
    if [[ -n "$SAVED_STTY" ]]; then
        stty "$SAVED_STTY" 2>/dev/null || true
    fi
}
# Terminate a process and all its descendants (the background worker plus any
# brew / curl it launched), youngest first.
tui_kill_tree() {  # <pid>
    local pid="$1" child
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do tui_kill_tree "$child"; done
    kill "$pid" 2>/dev/null || true
}

tui_cleanup() {
    tui_teardown
    local run="${DOTLAD_RUNDIR:-}" wp
    if [[ -n "$run" && -f "$run/worker.pid" ]]; then
        wp="$(cat "$run/worker.pid" 2>/dev/null || true)"
        [[ -n "$wp" ]] && tui_kill_tree "$wp"
    fi
    [[ -n "$run" ]] && rm -rf "$run"
    DOTLAD_RUNDIR=""
}

# --- build the item / line model from current state ------------------------

# tui_scan [frame] — the expensive pass: for each tool (in display order)
# compute its headline and its activity subtree, and note whether it's mid-run.
# Everything is cached so the per-frame assembly and cursor moves are instant.
tui_scan() {
    local frame="${1:-}" i k=0 nm run="${DOTLAD_RUNDIR:-}" tab bdir bcount
    tab="$(printf '\t')"
    UTD_CACHE=()   # fresh up-to-date results for this pass
    SCAN_NAME=(); SCAN_DESC=(); SCAN_HEAD=(); SCAN_ACT=(); SCAN_ACTIVE=(); SCAN_N=0
    while read -r i; do
        [[ -n "$i" ]] || continue
        nm="${T_NAME[$i]}"
        SCAN_NAME[k]="$nm"; SCAN_DESC[k]="${T_DESC[$i]}"
        SCAN_HEAD[k]="$(headline_line "$i" "$frame")"
        SCAN_ACT[k]="$(tool_activity "$i" "$frame")"
        if [[ -n "$run" ]] && { [[ -f "$run/${nm}.running" ]] || [[ -f "$run/${nm}.failed" ]] || queue_has_tool "$run" "$nm"; }; then
            SCAN_ACTIVE[k]=1
        else
            SCAN_ACTIVE[k]=0
        fi
        k=$((k + 1))
    done < <(tool_order)
    SCAN_N=$k
    SCAN_BDIR=(); SCAN_BCOUNT=(); SCAN_BFILES=(); SCAN_NB=0
    if mode_config_enabled; then
        while IFS="$tab" read -r bdir bcount; do
            [[ -n "$bdir" ]] || continue
            SCAN_BDIR[SCAN_NB]="$bdir"; SCAN_BCOUNT[SCAN_NB]="$bcount"
            SCAN_BFILES[SCAN_NB]="$(backup_activity "$bdir")"
            SCAN_NB=$((SCAN_NB + 1))
        done < <(list_backups)
    fi
    [[ -z "$CUR_NAME" && $SCAN_N -gt 0 ]] && CUR_NAME="${SCAN_NAME[0]}"
    return 0
}

# tui_refresh_running [frame] — cheap per-tick update while an install runs: no
# full state scan, just re-render the running tool's cached lines with the new
# spinner frame. (A running row's glyph/activity come straight from markers, so
# this touches only one tool and no eq_* / find / jq.)
tui_refresh_running() {
    local frame="${1:-}" rt k i
    rt="$(tui_running_tool || true)"; [[ -n "$rt" ]] || return 0
    for (( k = 0; k < SCAN_N; k++ )); do
        [[ "${SCAN_NAME[k]}" == "$rt" ]] || continue
        i="$(tool_find "$rt")" || return 0
        SCAN_HEAD[k]="$(headline_line "$i" "$frame")"
        SCAN_ACT[k]="$(tool_activity "$i" "$frame")"
        return 0
    done
    return 0
}

# _append_children <multiline-activity> — attach child rows (with ├/└
# connectors) to the current item. Shared by tool activity and a focused
# backup's file list.
_append_children() {
    local acts="$1" kb
    [[ -n "$acts" ]] || return 0
    while IFS= read -r kb; do
        L_TEXT[L_N]="$kb"
        L_ITEM[L_N]=$N_ITEMS; L_FIRST[L_N]=0; L_N=$((L_N + 1))
    done < <(tree_activity_lines <<< "$acts")
    return 0
}

# tui_build — assemble the on-screen item/line model from the scan cache. Each
# tool (and each restore point) is one item; its subtree — a tool's activity or
# a backup's file list — shows only when it's focused (or mid-run). Pure string
# work, no state probing, so it runs every frame.
tui_build() {
    local k nm b had=0 dline
    I_TYPE=(); I_NAME=(); I_FIRSTLINE=(); N_ITEMS=0
    L_TEXT=(); L_ITEM=(); L_FIRST=(); L_N=0
    for (( k = 0; k < SCAN_N; k++ )); do
        nm="${SCAN_NAME[k]}"
        I_TYPE[N_ITEMS]='tool'; I_NAME[N_ITEMS]="$nm"; I_FIRSTLINE[N_ITEMS]=$L_N
        L_TEXT[L_N]="${SCAN_HEAD[k]}"; L_ITEM[L_N]=$N_ITEMS; L_FIRST[L_N]=1; L_N=$((L_N + 1))
        if [[ "$nm" == "$CUR_NAME" || "${SCAN_ACTIVE[k]}" == 1 ]]; then
            # the focused tool shows its description (word-wrapped, each line
            # carrying the │ so the tree's left edge stays unbroken), then its
            # activity.
            if [[ "$nm" == "$CUR_NAME" && -n "${SCAN_DESC[k]}" ]]; then
                while IFS= read -r dline; do
                    L_TEXT[L_N]="  ${C_DIM}│ ${dline}${C_RESET}"; L_ITEM[L_N]=$N_ITEMS; L_FIRST[L_N]=0; L_N=$((L_N + 1))
                done < <(wrap_text "$(( COLS - 6 ))" "${SCAN_DESC[k]}")
            fi
            _append_children "${SCAN_ACT[k]}"
        fi
        N_ITEMS=$((N_ITEMS + 1))
    done
    for (( b = 0; b < SCAN_NB; b++ )); do
        if [[ $had == 0 ]]; then
            # a non-selectable divider so restore points read as their own
            # group, not another tool (navigation skips it — see tui_move).
            I_TYPE[N_ITEMS]='sep'; I_NAME[N_ITEMS]='@@sep'; I_FIRSTLINE[N_ITEMS]=$L_N
            L_TEXT[L_N]="$(sep_line 'restore points')"; L_ITEM[L_N]=$N_ITEMS; L_FIRST[L_N]=1
            L_N=$((L_N + 1)); N_ITEMS=$((N_ITEMS + 1)); had=1
        fi
        I_TYPE[N_ITEMS]='backup'; I_NAME[N_ITEMS]="@${SCAN_BDIR[b]}"; I_FIRSTLINE[N_ITEMS]=$L_N
        L_TEXT[L_N]="$(backup_line "${SCAN_BDIR[b]}" "${SCAN_BCOUNT[b]}")"; L_ITEM[L_N]=$N_ITEMS; L_FIRST[L_N]=1
        L_N=$((L_N + 1))
        [[ "@${SCAN_BDIR[b]}" == "$CUR_NAME" ]] && _append_children "${SCAN_BFILES[b]}"
        N_ITEMS=$((N_ITEMS + 1))
    done
    return 0
}

# Keep the cursor on the same named item across rebuilds (order/count shift as
# runs finish); clamp if it vanished.
tui_fix_cursor() {
    local k
    if [[ -n "$CUR_NAME" ]]; then
        for (( k = 0; k < N_ITEMS; k++ )); do
            [[ "${I_NAME[$k]}" == "$CUR_NAME" ]] && { CURSOR=$k; return; }
        done
    fi
    [[ $CURSOR -ge $N_ITEMS ]] && CURSOR=$((N_ITEMS - 1))
    [[ $CURSOR -lt 0 ]] && CURSOR=0
    [[ "${I_TYPE[$CURSOR]:-}" == sep ]] && CURSOR=$((CURSOR - 1))
    [[ $CURSOR -lt 0 ]] && CURSOR=0
    [[ $N_ITEMS -gt 0 ]] && CUR_NAME="${I_NAME[$CURSOR]}"
    return 0
}

# --- rendering --------------------------------------------------------------

is_selected() { [[ "$SEL" == *" $1 "* ]]; }
sel_count()   { local c=0 x; for x in $SEL; do c=$((c + 1)); done; printf '%s' "$c"; }

tui_gutter() {  # <selected 0|1> — two visible columns (marker + space)
    if [[ "$1" == 1 ]]; then printf '%s●%s ' "$C_GREEN" "$C_RESET"; else printf '  '; fi
}

tui_line() {  # <line-index> — print one body row (already positioned)
    local j="$1" item first text foc=0 sel=0 line
    item=${L_ITEM[$j]}; first=${L_FIRST[$j]}; text=${L_TEXT[$j]}
    if [[ "${I_TYPE[$item]}" == sep ]]; then printf '%s\e[K' "$text"; return 0; fi
    [[ $item -eq $CURSOR ]] && foc=1
    if [[ $first == 1 ]]; then
        [[ "${I_TYPE[$item]}" == tool ]] && is_selected "${I_NAME[$item]}" && sel=1
        line="$(tui_gutter "$sel")${text:2}"
    else
        line="$text"
    fi
    # the cursor is shown by the highlight bar below — no pointer glyph
    if [[ $foc == 1 && -n "$C_HL" ]]; then
        # Paint the whole row with the cursor bar: set bg, erase-to-EOL, then
        # re-apply bg after every inner reset so colours don't punch holes.
        printf '%s\e[K%s%s' "$C_HL" "${line//$C_RESET/$C_RESET$C_HL}" "$C_RESET"
    else
        printf '%s\e[K' "$line"
    fi
}

# tui_keybar <key> <label> [<key> <label> …] — a footer hint bar with uniform
# styling. Each key is bold and each label dim, with a reset after EVERY token
# so bold never bleeds into the next label (C_DIM/\e[2m does not cancel
# C_BOLD/\e[1m).
# wrap_text <width> <text…> — word-wrap to <width> columns, one line per printf.
wrap_text() {
    local width="$1"; shift
    local text="$*" line="" word
    [[ $width -lt 12 ]] && width=12
    for word in $text; do
        if [[ -z "$line" ]]; then line="$word"
        elif [[ $(( ${#line} + 1 + ${#word} )) -le $width ]]; then line="$line $word"
        else printf '%s\n' "$line"; line="$word"; fi
    done
    [[ -n "$line" ]] && printf '%s\n' "$line"
    return 0
}

# scroll the output pane by <delta> lines (clamped in tui_render); any manual
# scroll drops out of tail-follow.
tui_pscroll() {
    PANEL_SCROLL=$((PANEL_SCROLL + $1))
    [[ $PANEL_SCROLL -lt 0 ]] && PANEL_SCROLL=0
    PANEL_FOLLOW=0
    return 0
}

tui_keybar() {
    local first=1 key label
    while [[ $# -ge 2 ]]; do
        key="$1"; label="$2"
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
    local rows cols bodyrows r j cfirst clast n run="${DOTLAD_RUNDIR:-}" rt
    local ptool="" panel_log=0 label_row log_top ln
    local logb=()
    read -r rows cols < <(stty size 2>/dev/null) || true
    : "${rows:=24}" "${cols:=80}"
    COLS=$cols   # published for tui_build's description wrapping

    # Output panel: which tool's log to tail at the bottom, in priority —
    #   1. the focused tool, if it ran this session (running / done / failed);
    #   2. otherwise the tool being installed right now (live);
    #   3. otherwise the one that just finished (during the grace ticks).
    rt="$(tui_running_tool || true)"; [[ -n "$rt" ]] && LAST_RUN="$rt"
    if [[ "${I_TYPE[$CURSOR]:-}" == tool && -n "$run" && -f "$run/${CUR_NAME}.log" ]]; then
        ptool="$CUR_NAME"
    elif [[ -n "$rt" ]]; then
        ptool="$rt"
    elif [[ ${GRACE:-0} -gt 0 && -n "${LAST_RUN:-}" ]]; then
        ptool="$LAST_RUN"
    fi
    [[ -n "$ptool" && -n "$run" && -f "$run/${ptool}.log" ]] || ptool=""
    if [[ -n "$ptool" ]]; then
        panel_log=8
        [[ $((rows - 3 - panel_log)) -lt 4 ]] && panel_log=$((rows - 3 - 4))
        [[ $panel_log -lt 1 ]] && ptool=""
    fi
    if [[ -n "$ptool" ]]; then PANEL_ON=1; else PANEL_ON=0; fi
    [[ $PANEL_ON == 0 && "$FOCUS_ZONE" == panel ]] && FOCUS_ZONE=tree   # pane vanished

    if [[ -n "$ptool" ]]; then bodyrows=$((rows - 3 - panel_log)); else bodyrows=$((rows - 2)); fi
    [[ $bodyrows -lt 1 ]] && bodyrows=1

    # keep the focused item's lines within the viewport
    cfirst=${I_FIRSTLINE[$CURSOR]:-0}
    if [[ $((CURSOR + 1)) -lt $N_ITEMS ]]; then clast=$(( ${I_FIRSTLINE[$((CURSOR + 1))]} - 1 )); else clast=$((L_N - 1)); fi
    [[ $cfirst -lt $TOP ]] && TOP=$cfirst
    [[ $clast -ge $((TOP + bodyrows)) ]] && TOP=$((clast - bodyrows + 1))
    [[ $TOP -lt 0 ]] && TOP=0

    # header
    printf '\e[1;1H\e[K %sdotlad%s %s· %s ·%s %s%s%s' \
        "$C_BOLD" "$C_RESET" "$C_DIM" "$HOSTNAME_S" "$C_RESET" \
        "$C_BOLD$C_CYAN" "$(mode_label)" "$C_RESET"
    n="$(sel_count)"; [[ "$n" -gt 0 ]] && printf '   %s● %s selected%s' "$C_GREEN" "$n" "$C_RESET"

    # body (the tree)
    for (( r = 0; r < bodyrows; r++ )); do
        j=$((TOP + r))
        printf '\e[%d;1H' "$((r + 2))"
        if [[ $j -lt $L_N ]]; then tui_line "$j"; else printf '\e[K'; fi
    done

    # output panel: a labelled rule, then a window into the tool's log. In tree
    # focus it auto-tails; when Tab-focused (FOCUS_ZONE=panel) it scrolls.
    if [[ -n "$ptool" ]]; then
        label_row=$((bodyrows + 2)); log_top=$((label_row + 1))
        local rule pglyph pcolor plabel focp=0 total=0 winbase=0 maxs=0 idx
        [[ "$FOCUS_ZONE" == panel ]] && focp=1
        if [[ -f "$run/${ptool}.running" ]]; then pglyph="${SPIN[$FRAME_I]}"; pcolor="$C_CYAN"; plabel='live output'
        elif [[ -f "$run/${ptool}.failed" ]]; then pglyph='✗'; pcolor="$C_RED"; plabel='failed'
        elif [[ -f "$run/${ptool}.done" ]]; then pglyph='✓'; pcolor="$C_GREEN"; plabel='done'
        else pglyph="${SPIN[$FRAME_I]}"; pcolor="$C_CYAN"; plabel='output'; fi
        logb=()
        if [[ $focp == 1 ]]; then
            # focused: whole log, windowed by the scroll offset (tail-follow if
            # the user hasn't scrolled up)
            while IFS= read -r ln || [[ -n "$ln" ]]; do logb+=("$ln"); done < <(cat "$run/${ptool}.log" 2>/dev/null || true)
            total=${#logb[@]}; maxs=$(( total - panel_log )); [[ $maxs -lt 0 ]] && maxs=0
            [[ "$PANEL_FOLLOW" == 1 ]] && PANEL_SCROLL=$maxs
            [[ $PANEL_SCROLL -gt $maxs ]] && PANEL_SCROLL=$maxs
            [[ $PANEL_SCROLL -lt 0 ]] && PANEL_SCROLL=0
            winbase=$PANEL_SCROLL
        else
            # tree focus: just the tail
            while IFS= read -r ln; do logb+=("$ln"); done < <(tail -n "$panel_log" "$run/${ptool}.log" 2>/dev/null || true)
            total=${#logb[@]}; winbase=0
        fi
        printf -v rule '%*s' "$cols" ''; rule="${rule// /─}"
        printf '\e[%d;1H\e[K%s%s%s' "$label_row" "$C_DIM" "$rule" "$C_RESET"
        if [[ $focp == 1 ]]; then
            printf '\e[%d;3H %s%s %s%s%s %s· scroll %s–%s/%s · ↑↓ · tab tree%s ' "$label_row" \
                "$C_CYAN" "$pglyph" "$C_BOLD" "$ptool" "$C_RESET" "$C_CYAN" \
                "$(( winbase + 1 ))" "$(( winbase + panel_log < total ? winbase + panel_log : total ))" "$total" "$C_RESET"
        else
            printf '\e[%d;3H %s%s%s %s%s%s %s· %s · tab to scroll%s ' "$label_row" \
                "$pcolor" "$pglyph" "$C_RESET" "$C_BOLD" "$ptool" "$C_RESET" "$C_DIM" "$plabel" "$C_RESET"
        fi
        for (( r = 0; r < panel_log; r++ )); do
            printf '\e[%d;1H\e[K' "$((log_top + r))"
            idx=$(( winbase + r ))
            [[ $idx -lt $total ]] && printf '  %s%s' "${logb[$idx]}" "$C_RESET"
        done
    fi

    # footer — a uniformly-styled hint bar (bold keys, dim labels)
    printf '\e[%d;1H\e[K ' "$rows"
    if [[ -n "$TOAST" ]]; then
        printf '%s%s%s' "$C_GREEN" "$TOAST" "$C_RESET"
    elif [[ "$FOCUS_ZONE" == panel ]]; then
        tui_keybar '↑↓' scroll 'g/G' top/bottom tab tree q quit
    elif [[ "${I_TYPE[$CURSOR]:-}" == backup ]]; then
        tui_keybar '↑↓' move '⏎' restore d diff x delete q quit
    else
        tui_keybar '↑↓' move 'g/G' jump space pick '⏎' run d diff a all m mode q quit
    fi
    printf '\e[J'
}

# --- actions ----------------------------------------------------------------

tui_move() {  # <delta>
    local d="$1"
    CURSOR=$((CURSOR + d))
    [[ $CURSOR -lt 0 ]] && CURSOR=0
    [[ $CURSOR -ge $N_ITEMS ]] && CURSOR=$((N_ITEMS - 1))
    # step over the (non-selectable) section divider in the travel direction
    if [[ "${I_TYPE[$CURSOR]:-}" == sep ]]; then
        [[ $d -lt 0 ]] && CURSOR=$((CURSOR - 1)) || CURSOR=$((CURSOR + 1))
        [[ $CURSOR -lt 0 ]] && CURSOR=0
        [[ $CURSOR -ge $N_ITEMS ]] && CURSOR=$((N_ITEMS - 1))
    fi
    CUR_NAME="${I_NAME[$CURSOR]}"
    return 0
}

tui_toggle_sel() {
    [[ "${I_TYPE[$CURSOR]}" == tool ]] || return 0
    local nm="${I_NAME[$CURSOR]}"
    if is_selected "$nm"; then SEL="${SEL// $nm / }"; else SEL="${SEL}${nm} "; fi
    tui_move 1
}

tui_toggle_all() {
    local k allsel=1
    for (( k = 0; k < N_ITEMS; k++ )); do
        [[ "${I_TYPE[$k]}" == tool ]] || continue
        is_selected "${I_NAME[$k]}" || { allsel=0; break; }
    done
    SEL=" "
    if [[ $allsel == 0 ]]; then
        for (( k = 0; k < N_ITEMS; k++ )); do
            [[ "${I_TYPE[$k]}" == tool ]] && SEL="${SEL}${I_NAME[$k]} "
        done
    fi
    return 0
}

tui_cycle_mode() {
    local run="${DOTLAD_RUNDIR:-}" f
    if tui_work_active; then
        TOAST="finish the current run before switching mode"
        return 0
    fi
    case "$DOTLAD_MODE" in
        full)     mode_set packages ;;
        packages) mode_set config ;;
        *)        mode_set full ;;
    esac
    # Completed rows and logs describe the old mode and would be misleading in
    # the newly filtered view. They are session-only files, so discard them.
    if [[ -n "$run" ]]; then
        for f in "$run"/*.done "$run"/*.failed "$run"/*.result "$run"/*.stage "$run"/*.log; do
            [[ -e "$f" ]] && rm -f "$f"
        done
    fi
    SEL=" "; CURSOR=0; CUR_NAME=""; TOP=0; LAST_RUN=""; LAST_SIG=""
    PANEL_ON=0; FOCUS_ZONE="tree"; UTD_CACHE=(); NEED_SCAN=1
}

tui_enter() {
    if [[ "${I_TYPE[$CURSOR]}" == backup ]]; then
        tui_restore "${I_NAME[$CURSOR]#@}"; return 0
    fi
    local names=() x
    for x in $SEL; do names+=("$x"); done
    [[ ${#names[@]} -eq 0 ]] && names=("${I_NAME[$CURSOR]}")
    if enqueue "${names[@]}"; then
        SEL=" "; GRACE=6; NEED_SCAN=1
    else
        TOAST="preflight failed · no changes queued"
    fi
}

tui_confirm() {  # <msg> → 0/1 (drawn on the footer row)
    local rows cols a
    read -r rows cols < <(stty size 2>/dev/null) || true; : "${rows:=24}"
    printf '\e[%d;1H\e[K %s%s%s [y/N] ' "$rows" "$C_YELLOW" "$1" "$C_RESET"
    if tui_read_key; then tui_normalize_key; a="$TUI_KEY"; else a=""; fi
    case "$a" in y|Y) return 0 ;; *) return 1 ;; esac
}

tui_restore() {  # <dirname>
    local dir="$1" n
    n="$(backup_count "$dir")"
    if tui_confirm "Restore ${n} file(s) from $(fmt_backup_ts "$dir")? (current versions backed up)"; then
        if restore_backup "$dir" >/dev/null 2>&1; then
            TOAST="✓ restored ${RESTORE_N_RESTORED} file(s)"
        else
            TOAST="✗ restored ${RESTORE_N_RESTORED} · ${RESTORE_N_FAILED} failed"
        fi
    else
        TOAST="restore cancelled"
    fi
    NEED_SCAN=1
}

tui_delete_backup() {
    [[ "${I_TYPE[$CURSOR]:-}" == backup ]] || return 0
    local dir="${I_NAME[$CURSOR]#@}" n
    n="$(backup_count "$dir")"
    if tui_confirm "Delete backup $(fmt_backup_ts "$dir") — ${n} file(s)? Cannot be undone."; then
        if delete_backup "$dir" >/dev/null 2>&1; then TOAST="✓ deleted backup $(fmt_backup_ts "$dir")"; else TOAST="✗ delete failed"; fi
    else
        TOAST="delete cancelled"
    fi
    NEED_SCAN=1
}

tui_pager() {
    if command -v less >/dev/null 2>&1; then
        less -R
    else
        cat; printf '\n%s[press Enter]%s ' "$C_DIM" "$C_RESET"; IFS= read -r _ || true
    fi
}

tui_details() {  # focused tool's diff, or a running/failed tool's log, or a backup's contents
    local it="${I_TYPE[$CURSOR]}" nm="${I_NAME[$CURSOR]}" i run="${DOTLAD_RUNDIR:-}"
    # An up-to-date / installed tool with no live log has nothing to page — say
    # so on the footer instead of dropping into an empty pager.
    if [[ "$it" == tool ]] \
       && ! { [[ -n "$run" && -f "$run/${nm}.log" ]] && { [[ -f "$run/${nm}.running" ]] || [[ -f "$run/${nm}.failed" ]]; }; }; then
        i="$(tool_find "$nm")" || return 0
        compute_row "$i"
        if [[ "$RS_LABEL" == "up to date" || "$RS_LABEL" == "installed" ]]; then
            TOAST="✓ ${nm} — nothing to show"; return 0
        fi
    fi
    tui_teardown
    printf '\e[2J\e[H'
    # `|| true`: if the pager quits before reading all input the writer takes a
    # SIGPIPE, which set -o pipefail would otherwise turn into a script abort.
    {
        (
            export DOTLAD_FORCE_COLOR=1
            if [[ -n "${DOTLAD_SHOW_KEYS:-}" ]]; then
                tui_keybar d diff
                printf '\n\n'
            fi
            if [[ "$it" == backup ]]; then
                tui_backup_preview "${nm#@}"
            elif [[ -n "$run" && -f "$run/${nm}.log" ]] && { [[ -f "$run/${nm}.running" ]] || [[ -f "$run/${nm}.failed" ]]; }; then
                cat "$run/${nm}.log"
            elif i="$(tool_find "$nm")"; then
                printf '%s— %s —%s\n\n' "$C_BOLD" "$nm" "$C_RESET"; tool_diff "$i"
            fi
        ) | tui_pager
    } || true
    # Re-enter the screen and repaint immediately (details is read-only, so the
    # scan cache is still valid — just reassemble).
    tui_setup
    tui_build; tui_fix_cursor; tui_render
}

# The restore-point details (shown by `d` on a backup): the diff each file
# would undergo if restored — current → this backup's version, which is exactly
# what restoring changes. Unchanged files are skipped; missing ones show the
# whole content that would be recreated.
tui_backup_preview() {  # <dirname>
    local dir="$1" bdir tab mark rel cur src n=0 changed=0
    tab="$(printf '\t')"; bdir="$BACKUP_ROOT/$dir"
    printf '%s⏮ restore · %s%s\n' "$C_MAGENTA" "$(fmt_backup_ts "$dir")" "$C_RESET"
    printf '%sdiff is current → this backup (what restoring would change; your%s\n' "$C_DIM" "$C_RESET"
    printf '%scurrent versions are backed up first). enter on the row to restore.%s\n' "$C_DIM" "$C_RESET"
    while IFS="$tab" read -r mark rel; do
        n=$((n + 1))
        cur="$HOME/$rel"; src="$bdir/$rel"
        case "$mark" in
            '=') ;;   # identical to current — nothing to show
            '+') printf '\n%s— %s %s(recreated)%s —\n' "$C_BOLD" "$rel" "$C_DIM" "$C_RESET"
                 diff_file "$src" "$cur"; changed=$((changed + 1)) ;;
            *)   printf '\n%s— %s —%s\n' "$C_BOLD" "$rel" "$C_RESET"
                 diff_file "$src" "$cur"; changed=$((changed + 1)) ;;
        esac
    done < <(backup_entries "$dir")
    if [[ "$changed" == 0 ]]; then
        printf '\n%severything already matches this backup — nothing to restore%s\n' "$C_DIM" "$C_RESET"
    else
        printf '\n%s%s of %s file(s) would change%s\n' "$C_DIM" "$changed" "$n" "$C_RESET"
    fi
}

# --- main loop --------------------------------------------------------------

tui_run() {
    HOSTNAME_S="$(hostname -s 2>/dev/null || printf 'this mac')"
    DOTLAD_RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-run.XXXXXX")"; export DOTLAD_RUNDIR
    SEL=" "; CURSOR=0; CUR_NAME=""; TOP=0; TOAST=""; KEYCAST=""; FRAME_I=0; GRACE=0; NEED_SCAN=1; LAST_RUN=""; LAST_SIG=""
    FOCUS_ZONE="tree"; PANEL_ON=0; PANEL_SCROLL=0; PANEL_FOLLOW=1

    trap 'tui_cleanup' EXIT
    trap 'exit 130' INT TERM
    tui_setup

    local active key seq sig f srows scols
    while true; do
        # Activity rows are cached, so a terminal resize must invalidate the
        # scan before package lists can be rewrapped to the new width.
        read -r srows scols < <(stty size 2>/dev/null) || true
        : "${scols:=$COLS}"
        if [[ "$scols" != "$COLS" ]]; then COLS="$scols"; NEED_SCAN=1; fi
        ACTIVITY_WIDTH=$((COLS - 4)); [[ "$ACTIVITY_WIDTH" -lt 16 ]] && ACTIVITY_WIDTH=16

        # A cheap marker signature (no forks): a change is a real state
        # transition (a run started/finished/queued) that warrants a full scan.
        sig=""
        if [[ -n "${DOTLAD_RUNDIR:-}" ]]; then
            for f in "$DOTLAD_RUNDIR"/*.running "$DOTLAD_RUNDIR"/*.done "$DOTLAD_RUNDIR"/*.failed; do
                [[ -e "$f" ]] && sig="${sig} ${f##*/}"
            done
            [[ -s "$DOTLAD_RUNDIR/queue" ]] && sig="${sig} Q"
        fi
        [[ "$sig" != "$LAST_SIG" ]] && { NEED_SCAN=1; LAST_SIG="$sig"; }

        active=0
        if tui_work_active; then active=1; GRACE=6
        elif [[ $GRACE -gt 0 ]]; then GRACE=$((GRACE - 1)); active=1; [[ $GRACE -eq 0 ]] && NEED_SCAN=1; fi

        # Full scan (expensive) only on a real change; during a run just animate
        # the one running row; assemble (cheap, focus-aware) every frame.
        if [[ $NEED_SCAN == 1 ]]; then
            tui_scan "${SPIN[$FRAME_I]}"; NEED_SCAN=0
        elif [[ $active == 1 ]]; then
            tui_refresh_running "${SPIN[$FRAME_I]}"
        fi
        tui_build; tui_fix_cursor
        tui_render

        if [[ $active == 1 ]]; then
            FRAME_I=$(( (FRAME_I + 1) % 10 ))
            # IFS= so Tab/Space (IFS whitespace) aren't stripped to an empty key
            tui_read_key "$TUI_FRAME_TIMEOUT" || { continue; }   # timeout → animate
        else
            # Enter arrives as an empty key with rc 0; a read failure is EOF —
            # quit cleanly rather than mistaking it for Enter (an install).
            tui_read_key || break
        fi
        tui_normalize_key
        key="$TUI_KEY"

        TOAST=""
        # Tab moves focus between the tree and the output pane (when present).
        if [[ "$key" == $'\t' ]]; then
            KEYCAST="tab"
            if [[ $PANEL_ON == 1 ]]; then
                if [[ "$FOCUS_ZONE" == tree ]]; then FOCUS_ZONE=panel; PANEL_FOLLOW=1; else FOCUS_ZONE=tree; fi
            fi
            continue
        fi

        # --- output pane focused: keys scroll the log ---
        if [[ "$FOCUS_ZONE" == panel ]]; then
            if [[ "$key" == $'\e' ]]; then
                read -rsn2 -t "$TUI_SEQUENCE_TIMEOUT" seq || seq=""
                case "$seq" in
                    '[A') KEYCAST="↑↓"; tui_pscroll -1 ;;
                    '[B') KEYCAST="↑↓"; tui_pscroll 1 ;;
                esac
                continue
            fi
            case "$key" in
                k) KEYCAST="↑↓"; tui_pscroll -1 ;;
                j) KEYCAST="↑↓"; tui_pscroll 1 ;;
                g) KEYCAST="g/G"; PANEL_SCROLL=0; PANEL_FOLLOW=0 ;;
                G) KEYCAST="g/G"; PANEL_FOLLOW=1 ;;
                q) tui_should_quit && break ;;
                *)   : ;;
            esac
            continue
        fi

        # --- tree focused (default) ---
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 -t "$TUI_SEQUENCE_TIMEOUT" seq || seq=""
            case "$seq" in
                '[A') KEYCAST="↑↓"; tui_move -1 ;;
                '[B') KEYCAST="↑↓"; tui_move 1 ;;
                '[H') KEYCAST="g/G"; CURSOR=0; CUR_NAME="${I_NAME[0]}" ;;
                '[F') KEYCAST="g/G"; CURSOR=$((N_ITEMS - 1)); CUR_NAME="${I_NAME[$CURSOR]}" ;;
            esac
            continue
        fi
        case "$key" in
            k)   KEYCAST="↑↓"; tui_move -1 ;;
            j)   KEYCAST="↑↓"; tui_move 1 ;;
            g)   KEYCAST="g/G"; CURSOR=0; CUR_NAME="${I_NAME[0]}" ;;
            G)   KEYCAST="g/G"; CURSOR=$((N_ITEMS - 1)); CUR_NAME="${I_NAME[$CURSOR]}" ;;
            ' ') KEYCAST="space"; tui_toggle_sel ;;
            a)   KEYCAST="a"; tui_toggle_all ;;
            m)   KEYCAST="m"; tui_cycle_mode ;;
            d)   KEYCAST="d"; tui_details ;;
            x)   KEYCAST="x"; tui_delete_backup ;;
            q)   tui_should_quit && break ;;
            '')  KEYCAST="⏎"; tui_enter ;;      # Enter
            *)   : ;;
        esac
    done

    tui_cleanup
    trap - EXIT INT TERM
}

tui_work_active() {
    local run="${DOTLAD_RUNDIR:-}" f
    [[ -n "$run" ]] || return 1
    for f in "$run"/*.running; do [[ -e "$f" ]] && return 0; done
    [[ -s "$run/queue" ]] && return 0
    return 1
}

# rc 0 = OK to quit. Quitting stops the background worker, so confirm mid-run.
tui_should_quit() {
    tui_work_active || return 0
    tui_confirm "Install still running — quit and stop it?"
}

# The tool currently being installed/updated (the single worker's `.running`
# marker), or empty. Drives the live output panel.
tui_running_tool() {
    local run="${DOTLAD_RUNDIR:-}" f nm
    [[ -n "$run" ]] || return 1
    for f in "$run"/*.running; do
        [[ -e "$f" ]] || continue
        nm="${f##*/}"; printf '%s' "${nm%.running}"; return 0
    done
    return 1
}

# Entry point: interactive TUI on a real terminal, plain list otherwise.
cmd_pick() {
    if [[ -n "${DOTLAD_PLAIN:-}" || ! -t 0 || ! -t 1 ]]; then
        print_list
        return 0
    fi
    tui_run
}
