# lib/resolvers/symlink.sh — point a destination at its repository source.
# shellcheck disable=SC2034  # Deployment counters are consumed by engine.sh.

resolver_symlink_supports() { [[ "$1" == file || "$1" == directory ]]; }

resolver_symlink_action() { printf 'link'; }

resolver_symlink_canonical_path() { # <existing-path>
    local dir base
    dir="$(dirname "$1")"
    base="$(basename "$1")"
    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s' "$dir" "$base"
}

resolver_symlink_equal() { # <repo> <live>
    local expected target
    [[ -L "$2" ]] || return 1
    expected="$(resolver_symlink_canonical_path "$1")" || return 1
    target="$(readlink "$2")"
    case "$target" in /*) ;; *) target="$(dirname "$2")/$target" ;; esac
    target="$(resolver_symlink_canonical_path "$target")" || return 1
    [[ "$target" == "$expected" ]]
}

resolver_symlink_check() { # <repo> <live>
    local bad
    if [[ -d "$2" && ! -L "$2" ]]; then
        bad="$(find "$2" ! -type d ! -type f ! -type l -print 2>/dev/null)"
        [[ -z "$bad" ]] || printf 'link destination contains an unsupported entry\n'
    elif [[ -e "$2" && ! -f "$2" && ! -L "$2" ]]; then
        printf 'link destination has an unsupported type\n'
    fi
    return 0
}

resolver_symlink_backup_destination() { # <destination>
    local dest="$1" leaf marker rel directory
    if [[ -d "$dest" && ! -L "$dest" ]]; then
        [[ -n "$BACKUP_DIR" ]] || BACKUP_DIR="$(new_backup_dir)" || return 1
        marker="$BACKUP_DIR/$BACKUP_META_NAME/$BACKUP_DIRECTORY_NODES_NAME"
        mkdir -p "${marker%/*}" || return 1
        while IFS= read -r directory; do
            rel="${directory#"$HOME"/}"
            printf '%s\n' "$rel" >>"$marker" || return 1
        done < <(find "$dest" -type d | sort)
        while IFS= read -r leaf; do
            [[ -n "$leaf" ]] || continue
            backup_path "$leaf" || return 1
        done < <(find "$dest" \( -type f -o -type l \) | sort)
    else
        backup_path "$dest"
    fi
}

resolver_symlink_apply() {
    local source dest="$2" parent stage staged
    source="$(resolver_symlink_canonical_path "$1")" || return 1
    [[ -e "$source" && ! -L "$source" ]] ||
        {
            err "cannot link missing or unsafe source: $source"
            return 1
        }
    dest_safe "$dest" || {
        err "unsafe destination: $dest"
        return 1
    }
    parent="$(dirname "$dest")"
    mkdir -p "$parent" || {
        err "cannot create $parent"
        return 1
    }
    stage="$(mktemp -d "$parent/.dotlad-link.XXXXXX")" ||
        {
            err "cannot stage symlink in $parent"
            return 1
        }
    staged="$stage/payload"
    if ! ln -s "$source" "$staged"; then
        rm -rf "$stage"
        err "cannot create symlink to $source"
        return 1
    fi
    if ! resolver_symlink_backup_destination "$dest"; then
        rm -rf "$stage"
        return 1
    fi
    replace_path_transaction "$stage" "$staged" "$dest" ||
        {
            err "failed to replace path with symlink: $dest"
            return 1
        }
    AP_DEPLOYED=1
}

resolver_symlink_preview() {
    local source dest="$2"
    source="$(resolver_symlink_canonical_path "$1")" || return 1
    if [[ -L "$dest" ]]; then
        warn "would relink: $(pretty_path "$dest") → $source"
    elif [[ -e "$dest" ]]; then
        warn "would replace with symlink: $(pretty_path "$dest") → $source"
    else
        hint "would create symlink: $(pretty_path "$dest") → $source"
    fi
}

resolver_symlink_changes() { printf '1 link to sync'; }
