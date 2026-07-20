# shellcheck disable=SC2153,SC2034  # T_* are manifest arrays; UTD_CACHE lives in engine.sh
# lib/tui.sh — full-screen tool tree and interaction. Enter starts queued
# work in the background or restores the focused restore point. The tree is the
# whole UI; press `d` for a tool diff or running log.
#
# Coordinator state is global so actions and the event loop can share it with
# the sourced input, model, and screen modules.
TOAST=""
FRAME_I=0
GRACE=0
NEED_SCAN=1
LAST_RUN=""
LAST_SIG=""

# shellcheck source=lib/tui/input.sh
. "$DOTLAD_RUNTIME_ROOT/lib/tui/input.sh"
# shellcheck source=lib/tui/model.sh
. "$DOTLAD_RUNTIME_ROOT/lib/tui/model.sh"
# shellcheck source=lib/tui/screen.sh
. "$DOTLAD_RUNTIME_ROOT/lib/tui/screen.sh"

# --- actions ----------------------------------------------------------------

tui_init_labels() {
    TUI_HEADER_TITLE="${DOTLAD_DISPLAY_NAME:-$DOTLAD_COMMAND_NAME}"
    TUI_HOST_LABEL="$(hostname -s 2>/dev/null || printf 'this mac')"
}

tui_cleanup() {
    tui_screen_teardown
    local run="${DOTLAD_RUNDIR:-}" worker_pid
    if [[ -n "$run" && -f "$run/worker.pid" ]]; then
        worker_pid="$(cat "$run/worker.pid" 2>/dev/null || true)"
        [[ -n "$worker_pid" ]] && runner_kill_tree "$worker_pid"
    fi
    [[ -n "$run" ]] && rm -rf "$run"
    DOTLAD_RUNDIR=""
}

tui_cycle_mode() {
    local run="${DOTLAD_RUNDIR:-}" f
    if runner_work_active "$run"; then
        TOAST="finish the current run before switching mode"
        return 0
    fi
    case "$DOTLAD_MODE" in
        full) mode_set packages ;;
        packages) mode_set config ;;
        *) mode_set full ;;
    esac
    # Completed rows and logs describe the old mode and would be misleading in
    # the newly filtered view. They are session-only files, so discard them.
    if [[ -n "$run" ]]; then
        for f in "$run"/*.done "$run"/*.failed "$run"/*.result "$run"/*.stage "$run"/*.log; do
            [[ -e "$f" ]] && rm -f "$f"
        done
    fi
    SEL=" "
    CURSOR=0
    CUR_NAME=""
    TOP=0
    LAST_RUN=""
    LAST_SIG=""
    PANEL_ON=0
    FOCUS_ZONE="tree"
    UTD_CACHE=()
    NEED_SCAN=1
}

tui_enter() {
    case "${I_TYPE[$CURSOR]:-}" in
        backup)
            tui_restore "${I_NAME[$CURSOR]#@}"
            return 0
            ;;
        tool) ;;
        *)
            TOAST="no tools for $(mode_label) mode"
            return 0
            ;;
    esac
    local names=() x target
    for x in $SEL; do names+=("$x"); done
    [[ ${#names[@]} -eq 0 ]] && names=("${I_NAME[$CURSOR]}")
    if [[ ${#names[@]} -eq 1 ]]; then
        target="'${names[0]}'"
    else target="${#names[@]} selected tools"; fi
    if ! tui_confirm "$(selection_prompt "$target" "${names[@]}")"; then
        TOAST="apply cancelled"
        return 0
    fi
    if enqueue "${names[@]}"; then
        SEL=" "
        GRACE=6
        NEED_SCAN=1
    else
        TOAST="preflight failed · no changes queued"
    fi
}

tui_confirm() { # <msg> → 0/1 (drawn on the footer row)
    local rows cols a
    read -r rows cols < <(stty size 2>/dev/null) || true
    : "${rows:=24}"
    printf '\e[%d;1H\e[K %s%s%s [y/N] ' "$rows" "$C_YELLOW" "$1" "$C_RESET"
    if tui_read_key; then
        tui_normalize_key
        a="$TUI_KEY"
    else a=""; fi
    case "$a" in y | Y) return 0 ;; *) return 1 ;; esac
}

tui_restore() { # <dirname>
    local dir="$1" files directories
    files="$(backup_count "$dir")"
    directories="$(backup_directory_count "$dir")"
    if [[ "$files" -eq 0 && "$directories" -eq 0 ]]; then
        TOAST="everything already matches this backup"
        return 0
    fi
    if tui_confirm "Restore $(backup_change_summary "$files" "$directories") from $(fmt_backup_ts "$dir")? (current versions backed up)"; then
        if restore_backup "$dir" >/dev/null 2>&1; then
            TOAST="✓ restored $(backup_change_summary "$RESTORE_N_RESTORED" "$RESTORE_N_DIRECTORIES")"
        else
            TOAST="✗ restored $(backup_change_summary "$RESTORE_N_RESTORED" "$RESTORE_N_DIRECTORIES") · ${RESTORE_N_FAILED} failed"
        fi
    else
        TOAST="restore cancelled"
    fi
    NEED_SCAN=1
}

tui_delete_backup() {
    [[ "${I_TYPE[$CURSOR]:-}" == backup ]] || return 0
    local dir="${I_NAME[$CURSOR]#@}"
    if tui_confirm "Delete backup $(fmt_backup_ts "$dir")? Cannot be undone."; then
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
        cat
        printf '\n%s[press Enter]%s ' "$C_DIM" "$C_RESET"
        IFS= read -r _ || true
    fi
}

tui_details() { # focused tool's diff, or a running/failed tool's log, or a backup's contents
    local it="${I_TYPE[$CURSOR]}" nm="${I_NAME[$CURSOR]}" i run="${DOTLAD_RUNDIR:-}"
    if [[ "$it" != tool && "$it" != backup ]]; then
        TOAST="nothing to show for $(mode_label) mode"
        return 0
    fi
    # An up-to-date / installed tool with no live log has nothing to page — say
    # so on the footer instead of dropping into an empty pager.
    if [[ "$it" == tool ]] &&
        ! { [[ -n "$run" && -f "$run/${nm}.log" ]] && { [[ -f "$run/${nm}.running" ]] || [[ -f "$run/${nm}.failed" ]]; }; }; then
        i="$(tool_find "$nm")" || return 0
        compute_row "$i"
        if [[ "$RS_LABEL" == "up to date" || "$RS_LABEL" == "installed" ]]; then
            TOAST="✓ ${nm} — nothing to show"
            return 0
        fi
    fi
    tui_screen_teardown
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
                printf '%s— %s —%s\n\n' "$C_BOLD" "$nm" "$C_RESET"
                tool_diff "$i"
            fi
        ) | tui_pager
    } || true
    # Re-enter the screen and repaint immediately (details is read-only, so the
    # scan cache is still valid — just reassemble).
    tui_screen_setup
    tui_build
    tui_fix_cursor
    tui_render
}

# The restore-point details (shown by `d` on a backup): the diff each file
# would undergo if restored — current → this backup's version, which is exactly
# what restoring changes. Unchanged files are skipped; missing ones show the
# whole content that would be recreated.
tui_backup_preview() { # <dirname>
    local dir="$1" bdir tab mark rel cur src changed=0
    tab="$(printf '\t')"
    bdir="$BACKUP_ROOT/$dir"
    printf '%s⏮ restore · %s%s\n' "$C_MAGENTA" "$(fmt_backup_ts "$dir")" "$C_RESET"
    printf '%sdiff is current → this backup (what restoring would change; your%s\n' "$C_DIM" "$C_RESET"
    printf '%scurrent versions are backed up first). enter on the row to restore.%s\n' "$C_DIM" "$C_RESET"
    while IFS="$tab" read -r mark rel; do
        cur="$HOME/$rel"
        src="$bdir/$rel"
        case "$mark" in
            '+')
                printf '\n%s— %s %s(recreated)%s —\n' "$C_BOLD" "$rel" "$C_DIM" "$C_RESET"
                diff_file "$src" "$cur"
                changed=$((changed + 1))
                ;;
            *)
                printf '\n%s— %s —%s\n' "$C_BOLD" "$rel" "$C_RESET"
                diff_file "$src" "$cur"
                changed=$((changed + 1))
                ;;
        esac
    done < <(backup_entries "$dir")
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        printf '\n%s— %s/ %s(directory restored)%s —\n' \
            "$C_BOLD" "$rel" "$C_DIM" "$C_RESET"
        changed=$((changed + 1))
    done < <(backup_directory_entries "$dir")
    if [[ "$changed" == 0 ]]; then
        printf '\n%severything already matches this backup — nothing to restore%s\n' "$C_DIM" "$C_RESET"
    else
        printf '\n%s%s change(s) would be restored%s\n' "$C_DIM" "$changed" "$C_RESET"
    fi
}

# --- main loop --------------------------------------------------------------

tui_run() {
    tui_init_labels
    DOTLAD_RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/dotlad-run.XXXXXX")"
    export DOTLAD_RUNDIR
    SEL=" "
    CURSOR=0
    CUR_NAME=""
    TOP=0
    TOAST=""
    KEYCAST=""
    FRAME_I=0
    GRACE=0
    NEED_SCAN=1
    LAST_RUN=""
    LAST_SIG=""
    FOCUS_ZONE="tree"
    PANEL_ON=0
    PANEL_SCROLL=0
    PANEL_FOLLOW=1

    trap 'tui_cleanup' EXIT
    trap 'exit 130' INT TERM
    tui_screen_setup

    local active key seq sig f srows scols
    while true; do
        # Activity rows are cached, so a terminal resize must invalidate the
        # scan before package lists can be rewrapped to the new width.
        read -r srows scols < <(stty size 2>/dev/null) || true
        : "${scols:=$COLS}"
        if [[ "$scols" != "$COLS" ]]; then
            COLS="$scols"
            NEED_SCAN=1
        fi
        ACTIVITY_WIDTH=$((COLS - 4))
        [[ "$ACTIVITY_WIDTH" -lt 16 ]] && ACTIVITY_WIDTH=16

        # A cheap marker signature (no forks): a change is a real state
        # transition (a run started/finished/queued) that warrants a full scan.
        sig=""
        if [[ -n "${DOTLAD_RUNDIR:-}" ]]; then
            for f in "$DOTLAD_RUNDIR"/*.running "$DOTLAD_RUNDIR"/*.done "$DOTLAD_RUNDIR"/*.failed; do
                [[ -e "$f" ]] && sig="${sig} ${f##*/}"
            done
            [[ -s "$DOTLAD_RUNDIR/queue" ]] && sig="${sig} Q"
        fi
        [[ "$sig" != "$LAST_SIG" ]] && {
            NEED_SCAN=1
            LAST_SIG="$sig"
        }

        active=0
        if runner_work_active "$DOTLAD_RUNDIR"; then
            active=1
            GRACE=6
        elif [[ $GRACE -gt 0 ]]; then
            GRACE=$((GRACE - 1))
            active=1
            [[ $GRACE -eq 0 ]] && NEED_SCAN=1
        fi

        # Full scan (expensive) only on a real change; during a run just animate
        # the one running row; assemble (cheap, focus-aware) every frame.
        if [[ $NEED_SCAN == 1 ]]; then
            tui_scan "${SPIN[$FRAME_I]}"
            NEED_SCAN=0
        elif [[ $active == 1 ]]; then
            tui_refresh_running "${SPIN[$FRAME_I]}"
        fi
        tui_build
        tui_fix_cursor
        tui_render

        if [[ $active == 1 ]]; then
            FRAME_I=$(((FRAME_I + 1) % 10))
            # IFS= so Tab/Space (IFS whitespace) aren't stripped to an empty key
            tui_read_key "$TUI_FRAME_TIMEOUT" || { continue; } # timeout → animate
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
                if [[ "$FOCUS_ZONE" == tree ]]; then
                    FOCUS_ZONE=panel
                    PANEL_FOLLOW=1
                else FOCUS_ZONE=tree; fi
            fi
            continue
        fi

        # --- output pane focused: keys scroll the log ---
        if [[ "$FOCUS_ZONE" == panel ]]; then
            if [[ "$key" == $'\e' ]]; then
                read -rsn2 -t "$TUI_SEQUENCE_TIMEOUT" seq || seq=""
                case "$seq" in
                    '[A')
                        KEYCAST="↑↓"
                        tui_scroll_panel -1
                        ;;
                    '[B')
                        KEYCAST="↑↓"
                        tui_scroll_panel 1
                        ;;
                esac
                continue
            fi
            case "$key" in
                k | K)
                    KEYCAST="↑↓"
                    tui_scroll_panel -1
                    ;;
                j | J)
                    KEYCAST="↑↓"
                    tui_scroll_panel 1
                    ;;
                g)
                    KEYCAST="g/G"
                    PANEL_SCROLL=0
                    PANEL_FOLLOW=0
                    ;;
                G)
                    KEYCAST="g/G"
                    PANEL_FOLLOW=1
                    ;;
                q | Q) tui_should_quit && break ;;
                *) : ;;
            esac
            continue
        fi

        # --- tree focused (default) ---
        if [[ "$key" == $'\e' ]]; then
            read -rsn2 -t "$TUI_SEQUENCE_TIMEOUT" seq || seq=""
            case "$seq" in
                '[A')
                    KEYCAST="↑↓"
                    tui_move -1
                    ;;
                '[B')
                    KEYCAST="↑↓"
                    tui_move 1
                    ;;
                '[H')
                    KEYCAST="g/G"
                    CURSOR=0
                    CUR_NAME="${I_NAME[0]}"
                    ;;
                '[F')
                    KEYCAST="g/G"
                    CURSOR=$((N_ITEMS - 1))
                    CUR_NAME="${I_NAME[$CURSOR]}"
                    ;;
            esac
            continue
        fi
        case "$key" in
            k | K)
                KEYCAST="↑↓"
                tui_move -1
                ;;
            j | J)
                KEYCAST="↑↓"
                tui_move 1
                ;;
            g)
                KEYCAST="g/G"
                CURSOR=0
                CUR_NAME="${I_NAME[0]}"
                ;;
            G)
                KEYCAST="g/G"
                CURSOR=$((N_ITEMS - 1))
                CUR_NAME="${I_NAME[$CURSOR]}"
                ;;
            ' ')
                KEYCAST="space"
                tui_toggle_selection
                ;;
            a | A)
                KEYCAST="a"
                tui_toggle_all
                ;;
            m | M)
                KEYCAST="m"
                tui_cycle_mode
                ;;
            d | D)
                KEYCAST="d"
                tui_details
                ;;
            x | X)
                KEYCAST="x"
                tui_delete_backup
                ;;
            q | Q) tui_should_quit && break ;;
            '')
                KEYCAST="⏎"
                tui_enter
                ;; # Enter
            *) : ;;
        esac
    done

    tui_cleanup
    trap - EXIT INT TERM
}

# rc 0 = OK to quit. Quitting stops the background worker, so confirm mid-run.
tui_should_quit() {
    runner_work_active "${DOTLAD_RUNDIR:-}" || return 0
    tui_confirm "Install still running — quit and stop it?"
}

# Entry point: interactive TUI on a real terminal, plain list otherwise.
cmd_pick() {
    selection_all
    selection_require_any || return 1
    if [[ -n "${DOTLAD_PLAIN:-}" || ! -t 0 || ! -t 1 ]]; then
        print_list
        return 0
    fi
    tui_run
}
