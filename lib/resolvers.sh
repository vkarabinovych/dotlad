# lib/resolvers.sh — load and dispatch named config resolvers.
# Each resolver lives in resolvers/<name>.sh and implements render + equal.

resolver_function() {  # <resolver> <method>
    local name="${1//-/_}"
    printf 'resolver_%s_%s' "$name" "$2"
}

resolver_known() {
    local render equal
    render="$(resolver_function "$1" render)"
    equal="$(resolver_function "$1" equal)"
    declare -F "$render" >/dev/null 2>&1 && declare -F "$equal" >/dev/null 2>&1
}

resolver_render() {  # <resolver> <repo-source> <live-destination>
    local fn
    fn="$(resolver_function "$1" render)"
    shift
    "$fn" "$@"
}

resolver_equal() {  # <resolver> <repo-source> <live-destination>
    local fn
    fn="$(resolver_function "$1" equal)"
    shift
    "$fn" "$@"
}

for resolver_file in "$DOTLAD_RUNTIME_ROOT"/lib/resolvers/*.sh; do
    [[ -f "$resolver_file" ]] || continue
    # shellcheck disable=SC1090
    . "$resolver_file"
done
unset resolver_file
