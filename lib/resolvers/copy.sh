# lib/resolvers/copy.sh — exact file copy or exact directory mirror.
# shellcheck disable=SC2034  # Deployment counters are consumed by engine.sh.

resolver_copy_supports() { [[ "$1" == file || "$1" == directory ]]; }

resolver_copy_action() { printf 'copy'; }

resolver_copy_file_equal() {  # <repo> <live>
    [[ -f "$2" && ! -L "$2" ]] && cmp -s "$1" "$2"
}

resolver_copy_files_to_sync() {  # <source-dir> <destination-dir>
    local src="$1" dest="$2" file rel
    while IFS= read -r file; do
        rel="${file#"$src"/}"
        [[ ! -L "$dest" && -f "$dest/$rel" && ! -L "$dest/$rel" ]] \
            && cmp -s "$file" "$dest/$rel" && continue
        printf '%s\n' "$rel"
    done < <(find "$src" -type f | sort)
}

resolver_copy_directories_to_create() {  # <source-dir> <destination-dir>
    local src="$1" dest="$2" directory rel
    [[ -d "$dest" && ! -L "$dest" ]] || printf '.\n'
    while IFS= read -r directory; do
        rel="${directory#"$src"/}"
        [[ ! -L "$dest" && -d "$dest/$rel" && ! -L "$dest/$rel" ]] && continue
        printf '%s\n' "$rel"
    done < <(find "$src" -mindepth 1 -type d | sort)
}

resolver_copy_directories_to_remove() {  # <source-dir> <destination-dir>
    local src="$1" dest="$2" directory rel
    [[ -d "$dest" && ! -L "$dest" ]] || return 0
    while IFS= read -r directory; do
        rel="${directory#"$dest"/}"
        [[ -d "$src/$rel" && ! -L "$src/$rel" ]] && continue
        printf '%s\n' "$rel"
    done < <(find "$dest" -mindepth 1 -type d | sort)
}

resolver_copy_leaves_to_backup() {  # <source-dir> <destination-dir>
    local src="$1" dest="$2" file rel
    [[ -d "$dest" && ! -L "$dest" ]] || return 0
    while IFS= read -r file; do
        rel="${file#"$dest"/}"
        [[ -f "$src/$rel" && -f "$file" && ! -L "$file" ]] \
            && cmp -s "$src/$rel" "$file" && continue
        printf '%s\n' "$rel"
    done < <(find "$dest" \( -type f -o -type l \) | sort)
}

resolver_copy_no_entries() {
    local entry
    while IFS= read -r entry; do [[ -n "$entry" ]] && return 1; done
    return 0
}

resolver_copy_directory_equal() {  # <repo> <live>
    local src="$1" dest="$2"
    [[ -d "$dest" && ! -L "$dest" ]] || return 1
    resolver_copy_no_entries < <(resolver_copy_directories_to_create "$src" "$dest") \
        && resolver_copy_no_entries < <(resolver_copy_files_to_sync "$src" "$dest") \
        && resolver_copy_no_entries < <(resolver_copy_leaves_to_backup "$src" "$dest") \
        && resolver_copy_no_entries < <(resolver_copy_directories_to_remove "$src" "$dest")
}

resolver_copy_equal() {  # <repo> <live>
    if [[ -d "$1" && ! -L "$1" ]]; then resolver_copy_directory_equal "$1" "$2"
    else resolver_copy_file_equal "$1" "$2"; fi
}

resolver_copy_check() {  # <repo> <live>
    local bad
    if [[ -d "$1" && ! -L "$1" ]]; then
        if [[ -e "$2" && ! -d "$2" && ! -L "$2" ]]; then
            printf 'directory destination is not a directory\n'
        elif [[ -d "$2" && ! -L "$2" ]]; then
            bad="$(find "$2" ! -type d ! -type f ! -type l -print 2>/dev/null)"
            [[ -z "$bad" ]] || printf 'directory destination contains an unsupported entry\n'
        fi
    elif [[ -d "$2" && ! -L "$2" ]]; then
        printf 'file destination is a directory\n'
    fi
    return 0
}

resolver_copy_apply_directory() {  # <repo> <live>
    local src="$1" dest="$2" parent stage staged rel
    dest_safe "$dest" || { err "unsafe directory destination"; return 1; }
    parent="$(dirname "$dest")"
    mkdir -p "$parent" || { err "cannot create $parent"; return 1; }
    stage="$(mktemp -d "$parent/.dotlad-dir.XXXXXX")" \
        || { err "cannot stage directory in $parent"; return 1; }
    staged="$stage/payload"
    if ! cp -R -p "$src" "$staged"; then rm -rf "$stage"; err "cannot stage $src"; return 1; fi

    if [[ -L "$dest" ]]; then
        backup_path "$dest" || { rm -rf "$stage"; return 1; }
    fi

    while IFS= read -r rel; do
        [[ -n "$rel" ]] && AP_DEPLOYED=$((AP_DEPLOYED + 1))
    done < <(resolver_copy_files_to_sync "$src" "$dest")
    while IFS= read -r rel; do
        [[ -n "$rel" ]] && AP_CREATED_DIRS=$((AP_CREATED_DIRS + 1))
    done < <(resolver_copy_directories_to_create "$src" "$dest")
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        backup_path "$dest/$rel" || { rm -rf "$stage"; return 1; }
        [[ -f "$src/$rel" ]] || AP_REMOVED=$((AP_REMOVED + 1))
    done < <(resolver_copy_leaves_to_backup "$src" "$dest")
    while IFS= read -r rel; do
        [[ -n "$rel" ]] && AP_REMOVED_DIRS=$((AP_REMOVED_DIRS + 1))
    done < <(resolver_copy_directories_to_remove "$src" "$dest")
    replace_path_transaction "$stage" "$staged" "$dest" \
        || { err "failed to replace directory: $dest"; return 1; }
}

resolver_copy_apply() {  # <repo> <live>
    if [[ -d "$1" && ! -L "$1" ]]; then
        resolver_copy_apply_directory "$1" "$2"
    else
        write_file "$1" "$2" || return 1
        AP_DEPLOYED=1
    fi
}

resolver_copy_preview() {  # <repo> <live>
    local src="$1" dest="$2" rel shown=0
    if [[ -d "$src" && ! -L "$src" ]]; then
        if [[ -L "$dest" ]]; then
            warn "would replace symlink with directory copy: $(pretty_path "$dest")"
            return 0
        fi
        while IFS= read -r rel; do
            [[ -n "$rel" ]] || continue
            printf '%s— %s —%s\n' "$C_DIM" "$rel" "$C_RESET"
            diff_file "$src/$rel" "$dest/$rel"; shown=1
        done < <(resolver_copy_files_to_sync "$src" "$dest")
        while IFS= read -r rel; do
            [[ -n "$rel" && ! -f "$src/$rel" ]] || continue
            warn "would remove stale: $rel"; shown=1
        done < <(resolver_copy_leaves_to_backup "$src" "$dest")
        [[ "$shown" == 0 ]] && hint "already up to date"
    else
        diff_file "$src" "$dest"
    fi
    return 0
}

resolver_copy_changes() {  # <repo> <live>
    local src="$1" dest="$2" copied=0 removed=0 created_dirs=0 removed_dirs=0 rel counts=''
    if [[ -d "$src" && ! -L "$src" ]]; then
        while IFS= read -r rel; do [[ -n "$rel" ]] && copied=$((copied + 1)); done \
            < <(resolver_copy_files_to_sync "$src" "$dest")
        while IFS= read -r rel; do [[ -n "$rel" ]] && created_dirs=$((created_dirs + 1)); done \
            < <(resolver_copy_directories_to_create "$src" "$dest")
        while IFS= read -r rel; do
            [[ -n "$rel" && ! -f "$src/$rel" ]] && removed=$((removed + 1))
        done < <(resolver_copy_leaves_to_backup "$src" "$dest")
        while IFS= read -r rel; do [[ -n "$rel" ]] && removed_dirs=$((removed_dirs + 1)); done \
            < <(resolver_copy_directories_to_remove "$src" "$dest")
    else
        copied=1
    fi
    [[ "$copied" -gt 0 ]] && counts="${copied} $(file_noun "$copied") to sync"
    [[ "$created_dirs" -gt 0 ]] \
        && counts="${counts:+${counts} · }${created_dirs} $(directory_noun "$created_dirs") to create"
    [[ "$removed" -gt 0 ]] \
        && counts="${counts:+${counts} · }${removed} $(file_noun "$removed") to remove"
    [[ "$removed_dirs" -gt 0 ]] \
        && counts="${counts:+${counts} · }${removed_dirs} $(directory_noun "$removed_dirs") to remove"
    printf '%s' "$counts"
}
