# lib/resolvers/toml-merge.sh — use live TOML as a base and repository values as
# the overlay. A missing destination resolves to the repository document itself.

resolver_toml_merge_render() {  # <repo> <live>
    if [[ -f "$2" && ! -L "$2" ]]; then
        yq eval-all 'select(fileIndex==0) * select(fileIndex==1)' "$2" "$1" -o=toml
    else
        yq -p=toml -o=json -I=0 . "$1" >/dev/null || return 1
        cat "$1"
    fi
}

resolver_toml_merge_equal() {  # <repo> <live>
    [[ -f "$2" && ! -L "$2" ]] || return 1
    cmp -s "$1" "$2" && return 0
    command -v yq >/dev/null 2>&1 || return 1
    local merged temp actual expected
    merged="$(resolver_toml_merge_render "$1" "$2" 2>/dev/null)" || return 1
    temp="$(mktemp)" || return 1
    printf '%s\n' "$merged" > "$temp"
    actual="$(yq -p=toml -o=json -I=0 . "$2" 2>/dev/null)"
    expected="$(yq -p=toml -o=json -I=0 . "$temp" 2>/dev/null)"
    rm -f "$temp"
    [[ -n "$actual" && "$actual" == "$expected" ]]
}
