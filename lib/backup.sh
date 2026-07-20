# shellcheck shell=bash
# lib/backup.sh — restore-point creation, inspection, restoration, and deletion.
# Names may carry a numeric suffix when two runs start within the same second.

RESTORE_N_RESTORED=0
RESTORE_N_DIRECTORIES=0
RESTORE_N_FAILED=0
BACKUP_META_NAME=".dotlad-meta"
BACKUP_DIRECTORY_NODES_NAME="directory-nodes"

backup_root_safe() {
    local rest
    [[ "$BACKUP_ROOT" == /* && "$BACKUP_ROOT" != / ]] || return 1
    [[ ! -L "$BACKUP_ROOT" ]] || return 1
    case "$BACKUP_ROOT" in
        "$HOME"/?*) dest_safe "$BACKUP_ROOT" || return 1 ;;
        *)
            rest="${BACKUP_ROOT#/}"
            case "$rest" in "" | . | .. | */ | *//* | */./* | */../* | ./* | ../* | */. | */..) return 1 ;; esac
            ;;
    esac
    return 0
}

backup_name_valid() {
    [[ "$1" =~ ^[0-9]{8}_[0-9]{6}(-[0-9]{2})?$ ]]
}

backup_exists() {
    backup_root_safe && backup_name_valid "$1" && [[ -d "$BACKUP_ROOT/$1" ]]
}

new_backup_dir() {
    backup_root_safe || {
        err "unsafe backup root: $BACKUP_ROOT" >&2
        return 1
    }
    mkdir -p "$BACKUP_ROOT" || {
        err "cannot create backup root: $BACKUP_ROOT" >&2
        return 1
    }
    local stamp candidate attempt=0
    stamp="$(date +%Y%m%d_%H%M%S)"
    while [[ $attempt -lt 100 ]]; do
        if [[ $attempt -eq 0 ]]; then
            candidate="$BACKUP_ROOT/$stamp"
        else candidate="$BACKUP_ROOT/$stamp-$(printf '%02d' "$attempt")"; fi
        if mkdir "$candidate" 2>/dev/null; then
            printf '%s' "$candidate"
            return 0
        fi
        [[ -e "$candidate" ]] || {
            err "cannot create backup: $candidate" >&2
            return 1
        }
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
    dest_safe "$target" || {
        err "unsafe backup source: $target"
        return 1
    }
    [[ ! -d "$target" || -L "$target" ]] ||
        {
            err "cannot back up directory as a file: $target"
            return 1
        }
    [[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$(new_backup_dir)" || return 1
    dest="$BACKUP_DIR/${target#"$HOME"/}"
    [[ ! -e "$dest" && ! -L "$dest" ]] || return 0
    mkdir -p "$(dirname "$dest")" &&
        cp -a "$target" "$dest" &&
        N_BACKED=$((N_BACKED + 1))
}

backup_paths_equal() {
    if [[ -L "$1" || -L "$2" ]]; then
        [[ -L "$1" && -L "$2" && "$(readlink "$1")" == "$(readlink "$2")" ]]
    else
        [[ -f "$1" && -f "$2" ]] && cmp -s "$1" "$2"
    fi
}

list_backups() {
    local d name
    if ! backup_root_safe || [[ ! -d "$BACKUP_ROOT" ]]; then return 0; fi
    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        name="${d##*/}"
        backup_name_valid "$name" || continue
        printf '%s\t%s\t%s\n' "$name" "$(backup_count "$name")" \
            "$(backup_directory_count "$name")"
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r)
}

backup_entries() {
    local dir="$BACKUP_ROOT/$1" f rel cur mark
    backup_exists "$1" || return 0
    while IFS= read -r f; do
        rel="${f#"$dir"/}"
        cur="$HOME/$rel"
        if [[ ! -e "$cur" && ! -L "$cur" ]]; then
            mark='+'
        elif backup_paths_equal "$f" "$cur"; then
            continue
        else mark='~'; fi
        printf '%s\t%s\n' "$mark" "$rel"
    done < <(find "$dir" -path "$dir/$BACKUP_META_NAME" -prune -o \
        \( -type f -o -type l \) -print 2>/dev/null | sort)
}

backup_count() {
    local n=0 mark rel tab
    tab="$(printf '\t')"
    while IFS="$tab" read -r mark rel; do
        [[ -n "$rel" ]] && n=$((n + 1))
    done < <(backup_entries "$1")
    printf '%s' "$n"
}

# Directory nodes are metadata rather than file entries. They still represent
# restore work when the current path is missing, is a symlink, or traverses a
# symlinked parent. Keep their count separate so file-only backup views remain
# accurate while directory-only snapshots are no longer mistaken for no-ops.
backup_directory_entries() { # <snapshot-name>
    local dir="$BACKUP_ROOT/$1" marker rel cur
    backup_exists "$1" || return 0
    marker="$dir/$BACKUP_META_NAME/$BACKUP_DIRECTORY_NODES_NAME"
    [[ -f "$marker" ]] || return 0
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        cur="$HOME/$rel"
        if dest_safe "$cur" && [[ -d "$cur" && ! -L "$cur" ]]; then
            continue
        fi
        printf '%s\n' "$rel"
    done <"$marker"
}

backup_directory_count() {
    local n=0 rel
    while IFS= read -r rel; do [[ -n "$rel" ]] && n=$((n + 1)); done \
        < <(backup_directory_entries "$1")
    printf '%s' "$n"
}

backup_change_summary() { # <file-count> <directory-count>
    local files="$1" directories="$2" summary=""
    if [[ "$files" -gt 0 || "$directories" -eq 0 ]]; then
        summary="$files $(file_noun "$files")"
    fi
    if [[ "$directories" -gt 0 ]]; then
        summary="${summary:+${summary} · }$directories $(directory_noun "$directories")"
    fi
    printf '%s' "$summary"
}

# Directory nodes replaced by a symlink are recorded as metadata. Prepare them
# before restoring leaves so the managed parent link is never traversed and
# empty directories are reconstructed too.
restore_directory_nodes() { # <snapshot-dir>
    local marker="$1/$BACKUP_META_NAME/$BACKUP_DIRECTORY_NODES_NAME" rel cur
    [[ -f "$marker" ]] || return 0
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        cur="$HOME/$rel"
        if ! dest_safe "$cur"; then
            err "unsafe restore destination: $rel"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
            continue
        fi
        if [[ -d "$cur" && ! -L "$cur" ]]; then continue; fi
        if [[ -e "$cur" || -L "$cur" ]]; then
            if ! backup_path "$cur" || ! rm -f "$cur"; then
                err "cannot prepare directory restore: $rel"
                RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
                continue
            fi
        fi
        if ! mkdir -p "$cur"; then
            err "cannot restore directory: $rel"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
        else
            RESTORE_N_DIRECTORIES=$((RESTORE_N_DIRECTORIES + 1))
        fi
    done <"$marker"
}

restore_backup() {
    local dir="$BACKUP_ROOT/$1" f rel cur mark tab
    RESTORE_N_RESTORED=0
    RESTORE_N_DIRECTORIES=0
    RESTORE_N_FAILED=0
    backup_root_safe || {
        err "unsafe backup root: $BACKUP_ROOT"
        return 1
    }
    if ! backup_name_valid "$1" || [[ ! -d "$dir" ]]; then
        err "no such backup: $1"
        return 1
    fi
    restore_directory_nodes "$dir"
    tab="$(printf '\t')"
    while IFS="$tab" read -r mark rel; do
        [[ -n "$rel" ]] || continue
        f="$dir/$rel"
        cur="$HOME/$rel"
        if ! dest_safe "$cur"; then
            err "unsafe restore destination: $rel"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
            continue
        fi
        if [[ -d "$cur" && ! -L "$cur" ]]; then
            err "cannot replace directory: $rel"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
            continue
        fi
        if ! backup_path "$cur"; then
            err "cannot preserve current ${rel}"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
            continue
        fi
        if ! mkdir -p "$(dirname "$cur")"; then
            err "cannot restore ${rel}"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
            continue
        fi
        if [[ -e "$cur" || -L "$cur" ]] && ! rm -f "$cur"; then
            err "cannot replace ${rel}"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
            continue
        fi
        if cp -a "$f" "$cur"; then
            RESTORE_N_RESTORED=$((RESTORE_N_RESTORED + 1))
        else
            err "failed to restore ${rel}"
            RESTORE_N_FAILED=$((RESTORE_N_FAILED + 1))
        fi
    done < <(backup_entries "$1")
    if [[ "$RESTORE_N_FAILED" -gt 0 ]]; then
        err "restored $(backup_change_summary "$RESTORE_N_RESTORED" "$RESTORE_N_DIRECTORIES"), ${RESTORE_N_FAILED} failed from ${1}"
        return 1
    fi
    ok "restored $(backup_change_summary "$RESTORE_N_RESTORED" "$RESTORE_N_DIRECTORIES") from ${1}"
}

delete_backup() {
    local dir="$1"
    backup_root_safe || {
        err "unsafe backup root: $BACKUP_ROOT"
        return 1
    }
    backup_name_valid "$dir" || {
        err "bad backup name: $dir"
        return 1
    }
    [[ -d "$BACKUP_ROOT/$dir" ]] || {
        err "no such backup: $dir"
        return 1
    }
    rm -rf "${BACKUP_ROOT:?}/$dir"
}
