# lib/resolvers/gitconfig.sh — repository keys win; unrelated live keys
# survive.

resolver_gitconfig_render() {  # <repo> <live>
    local repo="$1" live="$2" out records rec key value seen=$'\n' rc=0
    out="$(mktemp)" || return 1
    records="$(mktemp)" || { rm -f "$out"; return 1; }
    if [[ -f "$live" && ! -L "$live" ]]; then cp "$live" "$out" || rc=1
    else : > "$out" || rc=1; fi
    [[ $rc == 0 ]] && git config --file "$repo" --list -z > "$records" || rc=1
    [[ $rc == 0 ]] || { rm -f "$out" "$records"; return 1; }
    while IFS= read -r -d '' rec; do
        if [[ "$rec" == *$'\n'* ]]; then key="${rec%%$'\n'*}"; value="${rec#*$'\n'}"
        else key="$rec"; value="true"; fi
        if [[ "$seen" == *$'\n'"$key"$'\n'* ]]; then
            git config --file "$out" --add "$key" "$value" || { rc=1; break; }
        else
            git config --file "$out" --replace-all "$key" "$value" || { rc=1; break; }
            seen+="$key"$'\n'
        fi
    done < "$records" || rc=1
    [[ $rc == 0 ]] && cat "$out" || rc=1
    rm -f "$out" "$records"
    return "$rc"
}

resolver_gitconfig_equal() {  # <repo> <live>
    [[ -f "$2" && ! -L "$2" ]] && command -v git >/dev/null 2>&1 || return 1
    local temp actual expected
    temp="$(mktemp)" || return 1
    resolver_gitconfig_render "$1" "$2" > "$temp" 2>/dev/null \
        || { rm -f "$temp"; return 1; }
    actual="$(git config --file "$2" --list -z 2>/dev/null | sort -z | tr '\0' '\n')"
    expected="$(git config --file "$temp" --list -z 2>/dev/null | sort -z | tr '\0' '\n')"
    rm -f "$temp"
    [[ "$actual" == "$expected" ]]
}
