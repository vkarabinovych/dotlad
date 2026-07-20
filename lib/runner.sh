# lib/runner.sh — foreground execution and the serialized TUI worker.

# Update named tools and report one foreground batch (`all`, profiles, or
# explicit tool names).
run_selected() {
    N_UPDATED=0
    N_INSTALLED=0
    N_BACKED=0
    N_FAILED=0
    local name i parts=""
    preflight_selected "$@" || {
        err "preflight failed; no selected tool was changed"
        return 1
    }
    for name in "$@"; do
        i="$(tool_find "$name")" || continue
        tool_relevant "$i" || continue
        sync_tool "$i" || true
    done
    echo ""
    ((N_UPDATED)) && parts="${parts}, ${N_UPDATED} config(s) updated"
    ((N_INSTALLED)) && parts="${parts}, ${N_INSTALLED} package(s) installed"
    ((N_BACKED)) && parts="${parts}, ${N_BACKED} backed up"
    ((N_FAILED)) && parts="${parts}, ${N_FAILED} failed"
    parts="${parts#, }"
    if ((N_FAILED)); then
        err "finished${parts:+ — $parts}"
    else ok "done${parts:+ — $parts}"; fi
    [[ -n "$BACKUP_DIR" ]] && hint "replaced files saved in $(pretty_path "$BACKUP_DIR")"
    ((N_FAILED == 0))
}

# Many selections must not launch parallel package-manager operations. A
# session queue is guarded by a short mkdir lock and drained by one worker.
queue_has_tool() { # <run-dir> <name>
    local run="$1" wanted="$2" qmode qname tab
    [[ -f "$run/queue" ]] || return 1
    tab="$(printf '\t')"
    while IFS="$tab" read -r qmode qname; do
        [[ "$qname" == "$wanted" ]] && return 0
    done <"$run/queue"
    return 1
}

queue_lock() {
    local attempts=0
    until mkdir "$1/queue.lock" 2>/dev/null; do
        attempts=$((attempts + 1))
        [[ "$attempts" -gt 200 ]] && return 1
        sleep 0.02
    done
}

queue_unlock() { rmdir "$1/queue.lock" 2>/dev/null || true; }

runner_clear_result() { # <run-dir> <tool>
    local result
    rm -f "$1/$2.done" "$1/$2.failed" "$1/$2.stage"
    for result in "$1/$2".*.result; do
        [[ -e "$result" ]] && rm -f "$result"
    done
    return 0
}

# Terminate a worker process and all descendants, youngest first.
runner_kill_tree() { # <pid>
    local pid="$1" child
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        runner_kill_tree "$child"
    done
    kill "$pid" 2>/dev/null || true
}

runner_work_active() { # <run-dir>
    local run="$1" marker
    [[ -n "$run" ]] || return 1
    for marker in "$run"/*.running; do [[ -e "$marker" ]] && return 0; done
    [[ -s "$run/queue" ]]
}

runner_running_tool() { # <run-dir>
    local run="$1" marker name
    [[ -n "$run" ]] || return 1
    for marker in "$run"/*.running; do
        [[ -e "$marker" ]] || continue
        name="${marker##*/}"
        printf '%s' "${name%.running}"
        return 0
    done
    return 1
}

enqueue() { # <tool names...>
    local run="${DOTLAD_RUNDIR:-}" name tab
    [[ -n "$run" ]] || return 0
    preflight_selected "$@" >"$run/preflight.log" 2>&1 || return 1
    tab="$(printf '\t')"
    queue_lock "$run" || return 1
    for name in "$@"; do
        tool_find "$name" >/dev/null 2>&1 || continue
        [[ -f "$run/${name}.running" ]] && continue
        queue_has_tool "$run" "$name" && continue
        printf '%s%s%s\n' "$DOTLAD_MODE" "$tab" "$name" >>"$run/queue"
        runner_clear_result "$run" "$name"
    done
    queue_unlock "$run"
    nohup env DOTLAD_YES=1 "$DOTLAD_BIN" \
        -C "$ROOT" --backup-root "$BACKUP_ROOT" _worker \
        >/dev/null 2>&1 </dev/null &
}

worker() {
    local run="${DOTLAD_RUNDIR:-}" line qmode name i tab
    [[ -n "$run" ]] || return 0
    tab="$(printf '\t')"
    mkdir "$run/worker.lock" 2>/dev/null || return 0
    printf '%s' "$$" >"$run/worker.pid" 2>/dev/null || true
    while [[ -d "$run" ]]; do
        line=""
        qmode=""
        name=""
        if queue_lock "$run"; then
            if [[ -s "$run/queue" ]]; then
                line="$(head -1 "$run/queue" 2>/dev/null)"
                tail -n +2 "$run/queue" >"$run/queue.next" 2>/dev/null &&
                    mv "$run/queue.next" "$run/queue"
            fi
            queue_unlock "$run"
        fi
        if [[ -z "$line" ]]; then
            sleep 0.3
            continue
        fi
        IFS="$tab" read -r qmode name <<<"$line"
        mode_set "$qmode" || continue
        i="$(tool_find "$name")" || continue
        : >"$run/${name}.log"
        runner_clear_result "$run" "$name"
        : >"$run/${name}.running"
        if { preflight_tool "$i" && sync_tool "$i"; } >>"$run/${name}.log" 2>&1; then
            : >"$run/${name}.done"
        else
            printf '\n✗ %s failed (exit %s)\n' "$name" "$?" >>"$run/${name}.log"
            : >"$run/${name}.failed"
        fi
        rm -f "$run/${name}.running"
    done
    rmdir "$run/worker.lock" 2>/dev/null || true
}
