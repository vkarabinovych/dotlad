# lib/resolvers/json.sh — recursively overlay repository values and union
# arrays.

# shellcheck disable=SC2016
JSON_MERGE_FILTER='
    def merge($a; $b):
        if ($a|type)=="object" and ($b|type)=="object" then
            reduce (($a+$b)|keys_unsorted[]) as $k ({};
                .[$k] = if ($a|has($k)) and ($b|has($k)) then merge($a[$k]; $b[$k])
                         elif ($b|has($k)) then $b[$k]
                         else $a[$k] end)
        elif ($a|type)=="array" and ($b|type)=="array" then $a + ($b - $a)
        else $b end;
    merge(.[0]; .[1])'

resolver_json_render() {  # <repo> <live>
    local base='{}'
    [[ -s "$2" && ! -L "$2" ]] && base="$(cat "$2")"
    jq -s "$JSON_MERGE_FILTER" <(printf '%s' "$base") "$1"
}

resolver_json_equal() {  # <repo> <live>
    [[ -f "$2" && ! -L "$2" ]] && command -v jq >/dev/null 2>&1 || return 1
    local merged
    merged="$(resolver_json_render "$1" "$2" 2>/dev/null)" || return 1
    [[ "$(jq -S . "$2" 2>/dev/null)" == "$(printf '%s' "$merged" | jq -S .)" ]]
}
