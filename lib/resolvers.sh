# lib/resolvers.sh — load and dispatch named config resolvers.
#
# Every resolver implements `equal` plus either `apply` or `render`. Deployment
# resolvers may also override check, preview, changes, action, and supports.
# Render-only resolvers inherit the regular-file merge behavior.

resolver_method() { # <resolver> <method> — result in RESOLVER_METHOD
    RESOLVER_METHOD="resolver_${1//-/_}_$2"
}

resolver_known() {
    local apply render equal
    resolver_method "$1" apply
    apply="$RESOLVER_METHOD"
    resolver_method "$1" render
    render="$RESOLVER_METHOD"
    resolver_method "$1" equal
    equal="$RESOLVER_METHOD"
    declare -F "$equal" >/dev/null 2>&1 &&
        { declare -F "$apply" >/dev/null 2>&1 || declare -F "$render" >/dev/null 2>&1; }
}

resolver_has_method() { # <resolver> <method>
    resolver_method "$1" "$2"
    declare -F "$RESOLVER_METHOD" >/dev/null 2>&1
}

resolver_supports() { # <resolver> <file|directory>
    local fn
    resolver_method "$1" supports
    fn="$RESOLVER_METHOD"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$2"
    else [[ "$2" == file ]]; fi
}

resolver_requirements() { # <resolver> — zero or more command names
    local fn
    resolver_method "$1" requires
    fn="$RESOLVER_METHOD"
    if declare -F "$fn" >/dev/null 2>&1; then "$fn"; fi
}

resolver_action() { # <resolver> — copy|link
    local fn
    resolver_method "$1" action
    fn="$RESOLVER_METHOD"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn"
    else printf 'copy'; fi
}

resolver_render() { # <resolver> <repo-source> <live-destination>
    local fn
    resolver_method "$1" render
    fn="$RESOLVER_METHOD"
    shift
    "$fn" "$@"
}

resolver_equal() { # <resolver> <repo-source> <live-destination>
    local fn
    resolver_method "$1" equal
    fn="$RESOLVER_METHOD"
    shift
    "$fn" "$@"
}

# Print zero or more preflight blocker messages. Render-only resolvers inherit
# regular-file destination validation and a dry renderability probe.
resolver_check() { # <resolver> <repo-source> <live-destination>
    local resolver="$1" src="$2" dest="$3" fn rendered
    resolver_method "$resolver" check
    fn="$RESOLVER_METHOD"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$src" "$dest"
        return
    fi
    resolver_has_method "$resolver" render || return 0
    if [[ -d "$dest" && ! -L "$dest" ]]; then
        printf 'file destination is a directory\n'
        return
    fi
    rendered="$(mktemp)" || {
        printf 'cannot create resolver preview\n'
        return
    }
    if ! resolver_render "$resolver" "$src" "$dest" >"$rendered" 2>/dev/null; then
        printf "cannot resolve config with '%s'\n" "$resolver"
    fi
    rm -f "$rendered"
}

resolver_apply() { # <resolver> <repo-source> <live-destination>
    local resolver="$1" fn
    resolver_method "$resolver" apply
    fn="$RESOLVER_METHOD"
    shift
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$@"
    else apply_resolved_config "$resolver" "$@"; fi
}

resolver_preview() { # <resolver> <repo-source> <live-destination>
    local resolver="$1" src="$2" dest="$3" fn rendered
    resolver_method "$resolver" preview
    fn="$RESOLVER_METHOD"
    if declare -F "$fn" >/dev/null 2>&1; then
        "$fn" "$src" "$dest"
        return
    fi
    if ! resolver_has_method "$resolver" render; then
        hint "would apply resolver '$resolver'"
        return 0
    fi
    rendered="$(mktemp)" || return 1
    if resolver_render "$resolver" "$src" "$dest" >"$rendered" 2>/dev/null; then
        diff_file "$rendered" "$dest"
    else
        warn "cannot resolve config with '$resolver'"
    fi
    rm -f "$rendered"
}

resolver_changes() { # <resolver> <repo-source> <live-destination>
    local fn
    resolver_method "$1" changes
    fn="$RESOLVER_METHOD"
    if declare -F "$fn" >/dev/null 2>&1; then
        shift
        "$fn" "$@"
    else printf '1 file to sync'; fi
}

for resolver_file in "$DOTLAD_RUNTIME_ROOT"/lib/resolvers/*.sh; do
    [[ -f "$resolver_file" ]] || continue
    # shellcheck disable=SC1090
    . "$resolver_file"
done
unset resolver_file
