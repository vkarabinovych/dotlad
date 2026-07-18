# shellcheck shell=bash
# lib/backup.sh — restore-point creation, inspection, restoration, and deletion.
# Names may carry a numeric suffix when two runs start within the same second.

RESTORE_N_RESTORED=0
RESTORE_N_FAILED=0

backup_root_safe() {
    local rest
    [[ "$BACKUP_ROOT" == /* && "$BACKUP_ROOT" != / ]] || return 1
    [[ ! -L "$BACKUP_ROOT" ]] || return 1
    case "$BACKUP_ROOT" in
        "$HOME"/?*) dest_safe "$BACKUP_ROOT" || return 1 ;;
        *)
            rest="${BACKUP_ROOT#/}"
            case "$rest" in ""|.|..|*/|*//*|*/./*|*/../*|./*|../*|*/.|*/..) return 1 ;; esac
            ;;
    esac
    return 0
}

backup_name_valid() {
    [[ "$1" =~ ^[0-9]{8}_[0-9]{6}(-[0-9]{2})?$ ]]
}

new_backup_dir() {
    backup_root_safe || { err "unsafe backup root: $BACKUP_ROOT" >&2; return 1; }
    mkdir -p "$BACKUP_ROOT" || { err "cannot create backup root: $BACKUP_ROOT" >&2; return 1; }
    local stamp candidate attempt=0
    stamp="$(date +%Y%m%d_%H%M%S)"
    while [[ $attempt -lt 100 ]]; do
        if [[ $attempt -eq 0 ]]; then candidate="$BACKUP_ROOT/$stamp"
        else candidate="$BACKUP_ROOT/$stamp-$(printf '%02d' "$attempt")"; fi
        if mkdir "$candidate" 2>/dev/null; then printf '%s' "$candidate"; return 0; fi
        [[ -e "$candidate" ]] || { err "cannot create backup: $candidate" >&2; return 1; }
        attempt=$((attempt + 1))
    done
    err "cannot allocate a unique backup directory" >&2
    return 1
}

# Preserve the first version seen in a run. Both regular files and symlinks are
# restorable; directories are never leaf entries in a snapshot.
backup_path() {
    local target="$1" dest
    [[ -e "$target" || -L "$target" ]] || return 0
    dest_safe "$target" || { err "unsafe backup source: $target"; return 1; }
    [[ ! -d "$target" || -L "$target" ]] \
        || { err "cannot back up directory as a file: $target"; return 1; }
    [[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$(new_backup_dir)" || return 1
    dest="$BACKUP_DIR/${target#"$HOME"/}"
    [[ ! -e "$dest" && ! -L "$dest" ]] || return 0
    mkdir -p "$(dirname "$dest")" \
        && cp -a "$target" "$dest" \
        && N_BACKED=$((N_BACKED + 1))
}

backup_paths_equal() {
    if [[ -L "$1" || -L "$2" ]]; then
        [[ -L "$1" && -L "$2" && "$(readlink "$1")" == "$(readlink "$2")" ]]
    else
        cmp -s "$1" "$2"
    fi
}

list_backups() {
    local d name
    if ! backup_root_safe || [[ ! -d "$BACKUP_ROOT" ]]; then return 0; fi
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        name="${d##*/}"; backup_name_valid "$name" || continue
        printf '%s\t%s\n' "$name" "$(backup_count "$name")"
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
}

backup_entries() {
    local dir="$BACKUP_ROOT/$1" f rel cur mark
    if ! backup_root_safe || ! backup_name_valid "$1" || [[ ! -d "$dir" ]]; then return 0; fi
    while IFS= read -r f; do
        rel="${f#"$dir"/}"; cur="$HOME/$rel"
        if [[ ! -e "$cur" && ! -L "$cur" ]]; then mark='+'
        elif backup_paths_equal "$f" "$cur"; then mark='='
        else mark='~'; fi
        printf '%s\t%s\n' "$mark" "$rel"
    done < <(find "$dir" \( -type f -o -type l \) 2>/dev/null | sort)
}

backup_count() {
    local dir="$BACKUP_ROOT/$1" n=0 f
    if ! backup_root_safe || ! backup_name_valid "$1" || [[ ! -d "$dir" ]]; then
        printf '0'; return 0
    fi
    while IFS= read -r f; do [[ -n "$f" ]] && n=$((n + 1)); done \
        < <(find "$dir" \( -type f -o -type l \) 2>/dev/null)
    printf '%s' "$n"
}

restore_backup() {
    local dir="$BACKUP_ROOT/$1" f rel cur
    RESTORE_N_RESTORED=0; RESTORE_N_FAILED=0
    backup_root_safe || { err "unsafe backup root: $BACKUP_ROOT"; return 1; }
    if ! backup_name_valid "$1" || [[ ! -d "$dir" ]]; then
        err "no such backup: $1"
        return 1
    fi
    while IFS= read -r f; do
        rel="${f#"$dir"/}"; cur="$HOME/$rel"
        if ! dest_safe "$cur"; then
            err "unsafe restore destination: $rel"; RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1)); continue
        fi
        if [[ -d "$cur" && ! -L "$cur" ]]; then
            err "cannot replace directory: $rel"; RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1)); continue
        fi
        if ! backup_path "$cur"; then
            err "cannot preserve current ${rel}"; RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1)); continue
        fi
        if ! mkdir -p "$(dirname "$cur")"; then
            err "cannot restore ${rel}"; RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1)); continue
        fi
        if [[ -e "$cur" || -L "$cur" ]] && ! rm -f "$cur"; then
            err "cannot replace ${rel}"; RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1)); continue
        fi
        if cp -a "$f" "$cur"; then
            RESTORE_N_RESTORED=$((RESTORE_N_RESTORED + 1))
        else
            err "failed to restore ${rel}"; RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
        fi
    done < <(find "$dir" \( -type f -o -type l \) 2>/dev/null | sort)
    if [[ "$RESTORE_N_FAILED" -gt 0 ]]; then
        err "restored ${RESTORE_N_RESTORED} file(s), ${RESTORE_N_FAILED} failed from ${1}"
        return 1
    fi
    ok "restored ${RESTORE_N_RESTORED} file(s) from ${1}"
}

delete_backup() {
    local dir="$1"
    backup_root_safe || { err "unsafe backup root: $BACKUP_ROOT"; return 1; }
    backup_name_valid "$dir" || { err "bad backup name: $dir"; return 1; }
    [[ -d "$BACKUP_ROOT/$dir" ]] || { err "no such backup: $dir"; return 1; }
    rm -rf "${BACKUP_ROOT:?}/$dir"
}
