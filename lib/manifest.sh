# lib/manifest.sh — component loader. Each modules/<name>/module.conf
# is flat KEY="VALUE" and lives beside the files and tests it describes.

T_NAME=(); T_DESC=(); T_ICON=(); T_BREW=(); T_CASK=(); T_CHECK=()
T_SRC=(); T_DEST=(); T_RESOLVER=(); T_INSTALL_URL=()
T_REQUIRES=()
T_COUNT=0

# ASCII unit separator: a non-whitespace record delimiter so empty fields
# don't collapse (a tab would, via read's IFS whitespace folding).
US="$(printf '\037')"

manifest_parse_error() {
    err "$1" >&2
    return 1
}

manifest_trim() {
    MP_VALUE="$1"
    MP_VALUE="${MP_VALUE#"${MP_VALUE%%[![:space:]]*}"}"
    MP_VALUE="${MP_VALUE%"${MP_VALUE##*[![:space:]]}"}"
}

manifest_parse_value() {  # <raw-value> — result in MP_VALUE
    local raw ch next out="" i length backslash=$'\\'
    manifest_trim "$1"; raw="$MP_VALUE"
    [[ -n "$raw" ]] || { MP_VALUE=""; return 0; }
    # shellcheck disable=SC2016  # reject literal command-substitution syntax
    case "$raw" in *'$('*|*'`'*) return 1 ;; esac
    if [[ "${raw:0:1}" == '"' ]]; then
        [[ "${raw:$((${#raw} - 1)):1}" == '"' && ${#raw} -ge 2 ]] || return 1
        raw="${raw:1:$((${#raw} - 2))}"; length=${#raw}
        for (( i = 0; i < length; i++ )); do
            ch="${raw:$i:1}"
            [[ "$ch" != '"' ]] || return 1
            if [[ "$ch" != "$backslash" ]]; then out="$out$ch"; continue; fi
            i=$((i + 1)); [[ $i -lt $length ]] || return 1
            next="${raw:$i:1}"
            if [[ "$next" == "\"" || "$next" == "$backslash" \
               || "$next" == "\$" || "$next" == "\`" ]]; then
                out="$out$next"
            else
                out="$out\\$next"
            fi
        done
        MP_VALUE="$out"
    elif [[ "${raw:0:1}" == "'" ]]; then
        [[ "${raw:$((${#raw} - 1)):1}" == "'" && ${#raw} -ge 2 ]] || return 1
        MP_VALUE="${raw:1:$((${#raw} - 2))}"
        [[ "$MP_VALUE" != *"'"* ]] || return 1
    else
        case "$raw" in *[[:space:]]*) return 1 ;; esac
        MP_VALUE="$raw"
    fi
    [[ "$MP_VALUE" != *"$US"* ]] || return 1
    return 0
}

manifest_expand_home() {
    MP_VALUE="${MP_VALUE//\$\{HOME\}/$HOME}"
    MP_VALUE="${MP_VALUE//\$HOME/$HOME}"
}

# Parse the documented flat assignment formats without evaluating project
# code. The allowlist makes printf -v safe and lets modules/profiles share the
# same quoting, duplicate-field, and command-substitution rules.
assignment_field_allowed() {  # <module|profile> <key>
    case "$1:$2" in
        module:NAME|module:DESC|module:ICON|module:ORDER|module:BREW|module:CASK|\
        module:CHECK|module:SOURCE|module:DEST|module:RESOLVER|module:INSTALL_URL|\
        module:REQUIRES|profile:extends|profile:modules) return 0 ;;
        *) return 1 ;;
    esac
}

assignment_read_file() {  # <file> <module|profile> — populate caller variables
    local file="$1" kind="$2" line key raw value line_no=0 seen=$'\n'
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            manifest_parse_error "${file}:$line_no: expected KEY=VALUE"; return 1
        fi
        key="${BASH_REMATCH[1]}"; raw="${BASH_REMATCH[2]}"
        assignment_field_allowed "$kind" "$key" \
            || { manifest_parse_error "${file}:$line_no: unknown field '$key'"; return 1; }
        [[ "$seen" != *$'\n'"$key"$'\n'* ]] \
            || { manifest_parse_error "${file}:$line_no: duplicate field '$key'"; return 1; }
        seen+="$key"$'\n'
        manifest_parse_value "$raw" \
            || { manifest_parse_error "${file}:$line_no: invalid value for '$key'"; return 1; }
        value="$MP_VALUE"
        if [[ "$kind" == module && ( "$key" == DEST || "$key" == CHECK ) ]]; then
            MP_VALUE="$value"; manifest_expand_home; value="$MP_VALUE"
        fi
        printf -v "$key" '%s' "$value"
    done < "$file"
}

# A DEST must resolve to a strict descendant of $HOME — never $HOME itself,
# so a directory update/prune can't escape. We reject degenerate segments
# (. .. // trailing/) in the manifest-controlled tail rather than canonicalise.
dest_safe() {
    local d="$1" rest cur part i parts=()
    [[ -n "${HOME:-}" ]] || return 1
    case "$d" in "$HOME"/?*) ;; *) return 1 ;; esac
    rest="${d#"$HOME"/}"
    case "$rest" in
        "" | . | .. | */ | */. | */.. | *//* | */./* | */../* | ./* | ../*) return 1 ;;
    esac
    # Lexical containment is not enough: an existing parent symlink could
    # redirect writes outside HOME. The leaf itself may be a symlink because
    # file deployments deliberately replace it; every parent must be physical.
    IFS=/ read -ra parts <<< "$rest"
    cur="$HOME"
    for (( i = 0; i < ${#parts[@]} - 1; i++ )); do
        part="${parts[$i]}"; cur="$cur/$part"
        [[ ! -L "$cur" ]] || return 1
    done
    return 0
}

# SOURCE is module-local and may not traverse symlinks. Checking only the leaf
# is insufficient: modules/example/files -> /somewhere would make
# files/config look like a regular file while escaping the module directory.
source_path_safe() {  # <module-dir> <relative-source>
    local cur="$1" rel="$2" part i parts=()
    [[ ! -L "$cur" ]] || return 1
    IFS=/ read -ra parts <<< "$rel"
    for (( i = 0; i < ${#parts[@]}; i++ )); do
        part="${parts[$i]}"; cur="$cur/$part"
        [[ ! -L "$cur" ]] || return 1
    done
    return 0
}

manifest_load() {
    local f records=""
    # Loading is deliberately repeatable: probes and tests may refresh the
    # manifest after changing fixtures in the same shell.
    T_NAME=(); T_DESC=(); T_ICON=(); T_BREW=(); T_CASK=(); T_CHECK=()
    T_SRC=(); T_DEST=(); T_RESOLVER=(); T_INSTALL_URL=(); T_REQUIRES=()
    T_COUNT=0
    [[ -d "$ROOT/modules" ]] || fatal "no modules/ directory"
    [[ ! -L "$ROOT/modules" ]] || fatal "modules/ directory must not be a symlink"
    records="$(
        for f in "$ROOT/modules"/*/module.conf; do
            [[ -e "$f" ]] || continue
            [[ -f "$f" && ! -L "$f" && ! -L "${f%/module.conf}" ]] \
                || fatal "module manifests and directories must not be symlinks: $f"
            (
                NAME=""; DESC=""; ICON=""; ORDER="500"; BREW=""; CASK=""
                CHECK=""; SOURCE=""; DEST=""; RESOLVER=""; INSTALL_URL=""
                REQUIRES=""
                assignment_read_file "$f" module || exit 1
                printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\n' \
                    "$f" "$ORDER" "$NAME" "$DESC" "$ICON" "$BREW" "$CASK" \
                    "$CHECK" "$SOURCE" "$DEST" "$RESOLVER" "$INSTALL_URL" "$REQUIRES"
            ) || fatal "cannot read $f"
        done
    )"
    local file order name desc icon brew cask check source dest resolver url requires module_dir src
    local i prior token_chars='^[-[:space:]A-Za-z0-9@+._/]*$'
    local token_pattern='^[A-Za-z0-9][A-Za-z0-9@+._-]*(/[A-Za-z0-9][A-Za-z0-9@+._-]*)*$'
    local destinations=() destination_names=()
    while IFS="$US" read -r file order name desc icon brew cask check source dest resolver url requires; do
        [[ -n "$file" ]] || continue
        [[ -f "$file" ]] || fatal "corrupt manifest (newline in a value?)"
        module_dir="${file%/module.conf}"
        [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
            || fatal "modules/${module_dir##*/}: invalid NAME '$name'"
        [[ "${module_dir##*/}" == "$name" ]] \
            || fatal "modules/${module_dir##*/}: NAME must equal the directory name"
        [[ -n "$desc" ]] || fatal "modules/$name: DESC is required"
        [[ -n "$icon" ]] || fatal "modules/$name: ICON is required"
        [[ "$order" =~ ^[0-9]+$ ]] || fatal "modules/$name: ORDER must be numeric"
        case "$cask" in ""|0|1) ;; *) fatal "modules/$name: CASK must be 0 or 1" ;; esac
        cask="${cask:-0}"
        [[ "$cask" != "1" || -n "$brew" ]] || fatal "modules/$name: CASK requires BREW"
        [[ -z "$brew" || -z "$url" ]] || fatal "modules/$name: choose BREW or INSTALL_URL, not both"
        [[ -z "$url" || "$url" =~ ^https://[^[:space:]]+$ ]] \
            || fatal "modules/$name: INSTALL_URL must be a whitespace-free HTTPS URL"
        [[ "$brew" =~ $token_chars ]] || fatal "modules/$name: BREW contains invalid characters"
        [[ "$requires" =~ $token_chars ]] || fatal "modules/$name: REQUIRES contains invalid characters"
        for prior in $brew; do
            [[ "$prior" =~ $token_pattern ]] || fatal "modules/$name: invalid BREW package '$prior'"
        done
        for prior in $requires; do
            [[ "$prior" =~ $token_pattern ]] || fatal "modules/$name: invalid requirement '$prior'"
        done
        if [[ -n "$source" || -n "$dest" || -n "$resolver" ]]; then
            [[ -n "$source" && -n "$dest" ]] \
                || fatal "modules/$name: SOURCE and DEST must be declared together"
            case "$source" in
                ""|/*|.|..|*/|*//*|./*|../*|*/./*|*/../*|*/.|*/..)
                    fatal "modules/${name}/module.conf: bad SOURCE" ;;
            esac
            source_path_safe "$module_dir" "$source" \
                || fatal "modules/$name: SOURCE path contains a symlink"
            src="${module_dir#"$ROOT"/}/$source"
            [[ -e "$ROOT/$src" ]] || fatal "modules/${name}: SOURCE does not exist: '$source'"
            if [[ -d "$ROOT/$src" && ! -L "$ROOT/$src" ]]; then
                [[ -z "$resolver" ]] || fatal "modules/$name: RESOLVER requires a file SOURCE"
                prior="$(find "$ROOT/$src" ! -type d ! -type f -print 2>/dev/null)"
                [[ -z "$prior" ]] || fatal "modules/$name: directory SOURCE contains a non-regular entry"
            elif [[ -f "$ROOT/$src" && ! -L "$ROOT/$src" ]]; then
                if [[ -n "$resolver" ]]; then
                    [[ "$resolver" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
                        || fatal "modules/$name: invalid RESOLVER '$resolver'"
                    resolver_known "$resolver" \
                        || fatal "modules/$name: unknown RESOLVER '$resolver'"
                fi
            else
                fatal "modules/$name: SOURCE must be a real file or directory"
            fi
            dest_safe "$dest" \
                || fatal "modules/${name}: DEST must be safely inside \$HOME: '$dest'"
            for (( i = 0; i < ${#destinations[@]}; i++ )); do
                prior="${destinations[$i]}"
                if [[ "$dest" == "$prior" || "$dest" == "$prior"/* || "$prior" == "$dest"/* ]]; then
                    fatal "modules/$name: DEST overlaps modules/${destination_names[$i]}: '$dest'"
                fi
            done
            destinations+=("$dest"); destination_names+=("$name")
        else
            src=""
        fi
        [[ -n "$brew" || -n "$url" || -n "$src" ]] \
            || fatal "modules/$name: declare BREW, INSTALL_URL, or SOURCE and DEST"
        check="${check:-$name}"
        T_NAME+=("$name"); T_DESC+=("$desc"); T_ICON+=("$icon")
        T_BREW+=("$brew"); T_CASK+=("$cask"); T_CHECK+=("$check")
        T_SRC+=("$src"); T_DEST+=("$dest"); T_RESOLVER+=("$resolver")
        T_INSTALL_URL+=("$url")
        T_REQUIRES+=("$requires")
    done < <(printf '%s\n' "$records" | sort -t"$US" -k2,2n -k3,3)
    T_COUNT=${#T_NAME[@]}
    [[ "$T_COUNT" -gt 0 ]] || fatal "no modules found"
}

# Resolve profiles/<name>.conf recursively and validate every module. Output is
# de-duplicated in declaration order so profiles can safely extend each other.
profile_modules() {
    local name="$1" chain="${2:-}" file="$ROOT/profiles/$1.conf" extends="" modules="" item inherited seen=$'\n'
    [[ ! -L "$ROOT/profiles" && "$name" != */* && -f "$file" && ! -L "$file" ]] \
        || fatal "unknown or unsafe profile: $name"
    [[ " $chain " != *" $name "* ]] || fatal "profile inheritance cycle: ${chain}${name}"
    assignment_read_file "$file" profile || return 1
    if [[ -n "$extends" ]]; then
        inherited="$(profile_modules "$extends" "${chain}${name} ")" || return 1
        while IFS= read -r item; do
            [[ -n "$item" && "$seen" != *$'\n'"$item"$'\n'* ]] || continue
            printf '%s\n' "$item"; seen+="$item"$'\n'
        done <<< "$inherited"
    fi
    for item in $modules; do
        manifest_find "$item" >/dev/null || fatal "profile $name: unknown module '$item'"
        [[ "$seen" != *$'\n'"$item"$'\n'* ]] || continue
        printf '%s\n' "$item"; seen+="$item"$'\n'
    done
}

manifest_find() {
    local i
    for (( i = 0; i < T_COUNT; i++ )); do
        [[ "${T_NAME[$i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }
    done
    return 1
}
