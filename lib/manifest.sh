# lib/manifest.sh — component loader. Each tools/<name>/tool.conf contains
# top-level tool fields and zero or more named [config.<name>] sections.

T_NAME=()
T_DESC=()
T_ICON=()
T_BREW=()
T_CASK=()
T_CHECK=()
T_CONFIG_START=()
T_CONFIG_COUNT=()
C_NAME=()
C_SRC=()
C_DEST=()
C_RESOLVER=()
C_TOOL_NAME=()
C_RESOLVER_OPTIONS=()
C_COUNT=0
T_INSTALL_URL=()
T_INSTALL_SHA256=()
T_REQUIRES=()
T_COUNT=0
DOTLAD_DEFAULT_RESOLVER="${DOTLAD_DEFAULT_RESOLVER:-copy}"

# ASCII unit separator: a non-whitespace record delimiter so empty fields
# don't collapse (a tab would, via read's IFS whitespace folding).
US="$(printf '\037')"
# ASCII record separator: separates opaque resolver option keys and values
# inside one config record without teaching the manifest about either.
RS="$(printf '\036')"

manifest_parse_error() {
    err "$1" >&2
    return 1
}

manifest_trim() {
    MP_VALUE="$1"
    MP_VALUE="${MP_VALUE#"${MP_VALUE%%[![:space:]]*}"}"
    MP_VALUE="${MP_VALUE%"${MP_VALUE##*[![:space:]]}"}"
}

manifest_parse_value() { # <raw-value> — result in MP_VALUE
    local raw ch next out="" i length backslash=$'\\'
    manifest_trim "$1"
    raw="$MP_VALUE"
    [[ -n "$raw" ]] || {
        MP_VALUE=""
        return 0
    }
    # shellcheck disable=SC2016  # reject literal command-substitution syntax
    case "$raw" in *'$('* | *'`'*) return 1 ;; esac
    if [[ "${raw:0:1}" == '"' ]]; then
        [[ "${raw:$((${#raw} - 1)):1}" == '"' && ${#raw} -ge 2 ]] || return 1
        raw="${raw:1:$((${#raw} - 2))}"
        length=${#raw}
        for ((i = 0; i < length; i++)); do
            ch="${raw:$i:1}"
            [[ "$ch" != '"' ]] || return 1
            if [[ "$ch" != "$backslash" ]]; then
                out="$out$ch"
                continue
            fi
            i=$((i + 1))
            [[ $i -lt $length ]] || return 1
            next="${raw:$i:1}"
            if [[ "$next" == "\"" || "$next" == "$backslash" ||
                "$next" == "\$" || "$next" == "\`" ]]; then
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
    [[ "$MP_VALUE" != *"$US"* && "$MP_VALUE" != *"$RS"* ]] || return 1
    return 0
}

manifest_expand_home() {
    MP_VALUE="${MP_VALUE//\$\{HOME\}/$HOME}"
    MP_VALUE="${MP_VALUE//\$HOME/$HOME}"
}

# Parse the documented assignment formats without evaluating project code.
# Core-field allowlists make printf -v safe; resolver option sections accept
# opaque uppercase keys while sharing the same value and duplicate rules.
assignment_field_allowed() { # <tool|config|profile> <key>
    case "$1:$2" in
        tool:NAME | tool:DESC | tool:ICON | tool:ORDER | tool:BREW | tool:CASK | \
            tool:CHECK | tool:INSTALL_URL | tool:INSTALL_SHA256 | tool:REQUIRES | \
            config:SOURCE | config:DEST | config:RESOLVER | \
            profile:extends | profile:tools) return 0 ;;
        *) return 1 ;;
    esac
}

assignment_read_file() { # <file> <tool|profile> — populate caller variables/CONFIG_*
    local file="$1" kind="$2" line key raw value line_no=0 seen=$'\n' section="" section_key
    local option_index=-1 i
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^[[:space:]]*\[config\.([a-z0-9][a-z0-9-]*)\.options\][[:space:]]*$ ]]; then
            [[ "$kind" == tool ]] || {
                manifest_parse_error "${file}:$line_no: sections are not allowed in profiles"
                return 1
            }
            section="${BASH_REMATCH[1]}"
            option_index=-1
            for ((i = 0; i < ${#CONFIG_NAMES[@]}; i++)); do
                if [[ "${CONFIG_NAMES[$i]}" == "$section" ]]; then
                    option_index=$i
                    break
                fi
            done
            [[ "$option_index" -ge 0 ]] || {
                manifest_parse_error "${file}:$line_no: options precede '[config.$section]'"
                return 1
            }
            [[ "$seen" != *$'\n'"options:$section"$'\n'* ]] || {
                manifest_parse_error "${file}:$line_no: duplicate section '[config.$section.options]'"
                return 1
            }
            seen+="options:$section"$'\n'
            section_key=options
            continue
        elif [[ "$line" =~ ^[[:space:]]*\[config\.([a-z0-9][a-z0-9-]*)\][[:space:]]*$ ]]; then
            [[ "$kind" == tool ]] || {
                manifest_parse_error "${file}:$line_no: sections are not allowed in profiles"
                return 1
            }
            section="${BASH_REMATCH[1]}"
            [[ "$seen" != *$'\n'"section:$section"$'\n'* ]] || {
                manifest_parse_error "${file}:$line_no: duplicate section '[config.$section]'"
                return 1
            }
            seen+="section:$section"$'\n'
            CONFIG_NAMES+=("$section")
            CONFIG_SOURCES+=("")
            CONFIG_DESTS+=("")
            CONFIG_RESOLVERS+=("")
            CONFIG_OPTION_COUNTS+=(0)
            CONFIG_OPTIONS+=(".")
            option_index=$((${#CONFIG_NAMES[@]} - 1))
            section_key=config
            continue
        fi
        if [[ ! "$line" =~ ^[[:space:]]*([A-Za-z][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            manifest_parse_error "${file}:$line_no: expected KEY=VALUE or [config.name]"
            return 1
        fi
        key="${BASH_REMATCH[1]}"
        raw="${BASH_REMATCH[2]}"
        if [[ -z "$section" ]]; then section_key="$kind"; fi
        if [[ "$section_key" != options ]]; then
            assignment_field_allowed "$section_key" "$key" ||
                {
                    manifest_parse_error "${file}:$line_no: unknown field '$key'"
                    return 1
                }
        elif [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            {
                manifest_parse_error "${file}:$line_no: invalid resolver option '$key'"
                return 1
            }
        fi
        [[ "$seen" != *$'\n'"$section_key:${section:-top}:$key"$'\n'* ]] ||
            {
                manifest_parse_error "${file}:$line_no: duplicate field '$key'"
                return 1
            }
        seen+="$section_key:${section:-top}:$key"$'\n'
        manifest_parse_value "$raw" ||
            {
                manifest_parse_error "${file}:$line_no: invalid value for '$key'"
                return 1
            }
        value="$MP_VALUE"
        if [[ ("$section_key" == config && "$key" == DEST) ||
            ("$section_key" == tool && "$key" == CHECK) ]]; then
            MP_VALUE="$value"
            manifest_expand_home
            value="$MP_VALUE"
        fi
        if [[ "$section_key" == options ]]; then
            CONFIG_OPTIONS[option_index]="${CONFIG_OPTIONS[$option_index]%.}$key$RS$value$RS."
            CONFIG_OPTION_COUNTS[option_index]=$((${CONFIG_OPTION_COUNTS[$option_index]} + 1))
        elif [[ -n "$section" ]]; then
            case "$key" in
                SOURCE) CONFIG_SOURCES[${#CONFIG_SOURCES[@]} - 1]="$value" ;;
                DEST) CONFIG_DESTS[${#CONFIG_DESTS[@]} - 1]="$value" ;;
                RESOLVER) CONFIG_RESOLVERS[${#CONFIG_RESOLVERS[@]} - 1]="$value" ;;
            esac
        else
            printf -v "$key" '%s' "$value"
        fi
    done <"$file"
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
    IFS=/ read -ra parts <<<"$rest"
    cur="$HOME"
    for ((i = 0; i < ${#parts[@]} - 1; i++)); do
        part="${parts[$i]}"
        cur="$cur/$part"
        [[ ! -L "$cur" ]] || return 1
    done
    return 0
}

# SOURCE is tool-local and may not traverse symlinks. Checking only the leaf
# is insufficient: tools/example/files -> /somewhere would make
# files/config look like a regular file while escaping the tool directory.
source_path_safe() { # <tool-dir> <relative-source>
    local cur="$1" rel="$2" part i parts=()
    [[ ! -L "$cur" ]] || return 1
    IFS=/ read -ra parts <<<"$rel"
    for ((i = 0; i < ${#parts[@]}; i++)); do
        part="${parts[$i]}"
        cur="$cur/$part"
        [[ ! -L "$cur" ]] || return 1
    done
    return 0
}

manifest_load() {
    local f records=""
    resolver_known "$DOTLAD_DEFAULT_RESOLVER" ||
        fatal "unknown default resolver: '$DOTLAD_DEFAULT_RESOLVER'"
    # Loading is deliberately repeatable: probes and tests may refresh the
    # manifest after changing fixtures in the same shell.
    T_NAME=()
    T_DESC=()
    T_ICON=()
    T_BREW=()
    T_CASK=()
    T_CHECK=()
    T_CONFIG_START=()
    T_CONFIG_COUNT=()
    C_NAME=()
    C_SRC=()
    C_DEST=()
    C_RESOLVER=()
    C_TOOL_NAME=()
    C_RESOLVER_OPTIONS=()
    C_COUNT=0
    T_INSTALL_URL=()
    T_INSTALL_SHA256=()
    T_REQUIRES=()
    T_COUNT=0
    [[ -d "$ROOT/tools" ]] || fatal "no tools/ directory"
    [[ ! -L "$ROOT/tools" ]] || fatal "tools/ directory must not be a symlink"
    records="$(
        for f in "$ROOT/tools"/*/tool.conf; do
            [[ -e "$f" ]] || continue
            [[ -f "$f" && ! -L "$f" && ! -L "${f%/tool.conf}" ]] ||
                fatal "tool manifests and directories must not be symlinks: $f"
            (
                NAME=""
                DESC=""
                ICON=""
                ORDER="500"
                BREW=""
                CASK=""
                CHECK=""
                INSTALL_URL=""
                INSTALL_SHA256=""
                REQUIRES=""
                CONFIG_NAMES=()
                CONFIG_SOURCES=()
                CONFIG_DESTS=()
                CONFIG_RESOLVERS=()
                CONFIG_OPTION_COUNTS=()
                CONFIG_OPTIONS=()
                assignment_read_file "$f" tool || exit 1
                printf '%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s\037%s' \
                    "$f" "$ORDER" "$NAME" "$DESC" "$ICON" "$BREW" "$CASK" \
                    "$CHECK" "$INSTALL_URL" "$INSTALL_SHA256" "$REQUIRES" "${#CONFIG_NAMES[@]}"
                for ((config_i = 0; config_i < ${#CONFIG_NAMES[@]}; config_i++)); do
                    printf '\037%s\037%s\037%s\037%s\037%s' "${CONFIG_NAMES[$config_i]}" \
                        "${CONFIG_SOURCES[$config_i]}" "${CONFIG_DESTS[$config_i]}" \
                        "${CONFIG_RESOLVERS[$config_i]}" "${CONFIG_OPTION_COUNTS[$config_i]}"
                    IFS="$RS" read -ra config_options <<<"${CONFIG_OPTIONS[$config_i]}"
                    for ((option_i = 0; option_i < CONFIG_OPTION_COUNTS[config_i] * 2; option_i++)); do
                        printf '\037%s' "${config_options[$option_i]}"
                    done
                done
                # A terminal sentinel preserves an empty RESOLVER on Bash 3.2,
                # whose read -a otherwise drops trailing empty fields.
                printf '\037.\n'
            ) || fatal "cannot read $f"
        done
    )"
    local record fields=() file order name desc icon brew cask check url sha256 requires config_count
    local config_name source dest resolver option_count options option_key option_value tool_dir src
    local i j option_i field_i prior destination_key token_chars='^[-[:space:]A-Za-z0-9@+._/]*$'
    local token_pattern='^[A-Za-z0-9][A-Za-z0-9@+._-]*(/[A-Za-z0-9][A-Za-z0-9@+._-]*)*$'
    local destinations=() destination_names=() destination_resolvers=() destination_keys=()
    while IFS= read -r record; do
        IFS="$US" read -ra fields <<<"$record"
        file="${fields[0]:-}"
        [[ -n "$file" ]] || continue
        order="${fields[1]:-}"
        name="${fields[2]:-}"
        desc="${fields[3]:-}"
        icon="${fields[4]:-}"
        brew="${fields[5]:-}"
        cask="${fields[6]:-}"
        check="${fields[7]:-}"
        url="${fields[8]:-}"
        sha256="${fields[9]:-}"
        requires="${fields[10]:-}"
        config_count="${fields[11]:-}"
        [[ "$config_count" =~ ^[0-9]+$ ]] ||
            fatal "corrupt manifest (newline in a value?)"
        [[ -f "$file" ]] || fatal "corrupt manifest (newline in a value?)"
        tool_dir="${file%/tool.conf}"
        [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
            fatal "tools/${tool_dir##*/}: invalid NAME '$name'"
        [[ "${tool_dir##*/}" == "$name" ]] ||
            fatal "tools/${tool_dir##*/}: NAME must equal the directory name"
        [[ -n "$desc" ]] || fatal "tools/$name: DESC is required"
        [[ -n "$icon" ]] || fatal "tools/$name: ICON is required"
        [[ "$order" =~ ^[0-9]+$ ]] || fatal "tools/$name: ORDER must be numeric"
        case "$cask" in "" | 0 | 1) ;; *) fatal "tools/$name: CASK must be 0 or 1" ;; esac
        cask="${cask:-0}"
        [[ "$cask" != "1" || -n "$brew" ]] || fatal "tools/$name: CASK requires BREW"
        [[ -z "$brew" || -z "$url" ]] || fatal "tools/$name: choose BREW or INSTALL_URL, not both"
        [[ -z "$url" || "$url" =~ ^https://[^[:space:]]+$ ]] ||
            fatal "tools/$name: INSTALL_URL must be a whitespace-free HTTPS URL"
        [[ -z "$sha256" || -n "$url" ]] ||
            fatal "tools/$name: INSTALL_SHA256 requires INSTALL_URL"
        [[ -z "$sha256" || "$sha256" =~ ^[[:xdigit:]]{64}$ ]] ||
            fatal "tools/$name: INSTALL_SHA256 must be 64 hexadecimal characters"
        if [[ -n "$sha256" ]]; then
            sha256="$(printf '%s' "$sha256" | tr '[:upper:]' '[:lower:]')"
        fi
        [[ "$brew" =~ $token_chars ]] || fatal "tools/$name: BREW contains invalid characters"
        [[ "$requires" =~ $token_chars ]] || fatal "tools/$name: REQUIRES contains invalid characters"
        for prior in $brew; do
            [[ "$prior" =~ $token_pattern ]] || fatal "tools/$name: invalid BREW package '$prior'"
        done
        for prior in $requires; do
            [[ "$prior" =~ $token_pattern ]] || fatal "tools/$name: invalid requirement '$prior'"
        done
        T_CONFIG_START+=("$C_COUNT")
        T_CONFIG_COUNT+=("$config_count")
        field_i=12
        for ((j = 0; j < config_count; j++)); do
            config_name="${fields[$field_i]}"
            source="${fields[$((field_i + 1))]}"
            dest="${fields[$((field_i + 2))]}"
            resolver="${fields[$((field_i + 3))]}"
            option_count="${fields[$((field_i + 4))]}"
            [[ "$option_count" =~ ^[0-9]+$ ]] || fatal "corrupt manifest (newline in a value?)"
            options="."
            field_i=$((field_i + 5))
            for ((option_i = 0; option_i < option_count; option_i++)); do
                option_key="${fields[$field_i]:-}"
                option_value="${fields[$((field_i + 1))]:-}"
                [[ -n "$option_key" ]] || fatal "corrupt manifest (newline in a value?)"
                options="${options%.}$option_key$RS$option_value$RS."
                field_i=$((field_i + 2))
            done
            [[ -n "$source" && -n "$dest" ]] ||
                fatal "tools/$name [config.$config_name]: SOURCE and DEST are required"
            resolver="${resolver:-$DOTLAD_DEFAULT_RESOLVER}"
            [[ "$resolver" =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
                fatal "tools/$name [config.$config_name]: invalid RESOLVER '$resolver'"
            resolver_known "$resolver" ||
                fatal "tools/$name [config.$config_name]: unknown RESOLVER '$resolver'"
            # shellcheck disable=SC2034  # consumed by resolver option helpers
            RESOLVER_OPTIONS="$options"
            for ((option_i = 0; option_i < option_count; option_i++)); do
                resolver_option_at "$option_i"
                resolver_option_supported "$resolver" "$RESOLVER_OPTION_KEY" ||
                    fatal "tools/$name [config.$config_name.options]: unknown option '$RESOLVER_OPTION_KEY' for RESOLVER '$resolver'"
            done
            case "$source" in
                "" | /* | . | .. | */ | *//* | ./* | ../* | */./* | */../* | */. | */..)
                    fatal "tools/${name}/tool.conf: bad SOURCE"
                    ;;
            esac
            source_path_safe "$tool_dir" "$source" ||
                fatal "tools/$name: SOURCE path contains a symlink"
            src="${tool_dir#"$ROOT"/}/$source"
            [[ -e "$ROOT/$src" ]] || fatal "tools/${name}: SOURCE does not exist: '$source'"
            if [[ -d "$ROOT/$src" && ! -L "$ROOT/$src" ]]; then
                resolver_supports "$resolver" directory ||
                    fatal "tools/$name [config.$config_name]: RESOLVER '$resolver' does not support a directory SOURCE"
                prior="$(find "$ROOT/$src" ! -type d ! -type f -print 2>/dev/null)"
                [[ -z "$prior" ]] || fatal "tools/$name: directory SOURCE contains a non-regular entry"
            elif [[ -f "$ROOT/$src" && ! -L "$ROOT/$src" ]]; then
                resolver_supports "$resolver" file ||
                    fatal "tools/$name [config.$config_name]: RESOLVER '$resolver' does not support a file SOURCE"
            else
                fatal "tools/$name: SOURCE must be a real file or directory"
            fi
            # shellcheck disable=SC2034  # consumed by resolver context hooks
            RESOLVER_TOOL_NAME="$name"
            destination_key="$(resolver_destination_key "$resolver" "$ROOT/$src")"
            if [[ "$dest" != /* ]]; then
                dest="$ROOT/$dest"
            fi
            dest_safe "$dest" ||
                fatal "tools/${name}: DEST must be safely inside \$HOME: '$dest'"
            for ((i = 0; i < ${#destinations[@]}; i++)); do
                prior="${destinations[$i]}"
                if [[ "$dest" == "$prior" ]]; then
                    if [[ -n "$destination_key" && "$resolver" == "${destination_resolvers[$i]}" ]]; then
                        [[ "$destination_key" != "${destination_keys[$i]}" ]] ||
                            fatal "tools/$name [config.$config_name]: resolver destination key collides with ${destination_names[$i]}: '$destination_key'"
                        continue
                    fi
                    fatal "tools/$name [config.$config_name]: DEST overlaps ${destination_names[$i]}: '$dest'"
                elif [[ "$dest" == "$prior"/* || "$prior" == "$dest"/* ]]; then
                    fatal "tools/$name [config.$config_name]: DEST overlaps ${destination_names[$i]}: '$dest'"
                fi
            done
            destinations+=("$dest")
            destination_names+=("tools/$name [config.$config_name]")
            destination_resolvers+=("$resolver")
            destination_keys+=("$destination_key")
            C_NAME+=("$config_name")
            C_SRC+=("$src")
            C_DEST+=("$dest")
            C_RESOLVER+=("$resolver")
            C_TOOL_NAME+=("$name")
            C_RESOLVER_OPTIONS+=("$options")
            C_COUNT=$((C_COUNT + 1))
        done
        [[ ${#fields[@]} -eq $((field_i + 1)) && "${fields[$field_i]}" == . ]] ||
            fatal "corrupt manifest (newline in a value?)"
        [[ -n "$brew" || -n "$url" || "$config_count" -gt 0 ]] ||
            fatal "tools/$name: declare BREW, INSTALL_URL, or a [config.name] section"
        check="${check:-$name}"
        T_NAME+=("$name")
        T_DESC+=("$desc")
        T_ICON+=("$icon")
        T_BREW+=("$brew")
        T_CASK+=("$cask")
        T_CHECK+=("$check")
        T_INSTALL_URL+=("$url")
        T_INSTALL_SHA256+=("$sha256")
        T_REQUIRES+=("$requires")
    done < <(printf '%s\n' "$records" | sort -t"$US" -k2,2n -k3,3)
    T_COUNT=${#T_NAME[@]}
    [[ "$T_COUNT" -gt 0 ]] || fatal "no tools found"
}

# Resolve profiles/<name>.conf recursively and validate every tool. Output is
# de-duplicated in declaration order so profiles can safely extend each other.
profile_tools() {
    local name="$1" chain="${2:-}" file="$ROOT/profiles/$1.conf" extends="" tools="" item inherited seen=$'\n'
    [[ ! -L "$ROOT/profiles" && "$name" != */* && -f "$file" && ! -L "$file" ]] ||
        fatal "unknown or unsafe profile: $name"
    [[ " $chain " != *" $name "* ]] || fatal "profile inheritance cycle: ${chain}${name}"
    assignment_read_file "$file" profile || return 1
    if [[ -n "$extends" ]]; then
        inherited="$(profile_tools "$extends" "${chain}${name} ")" || return 1
        while IFS= read -r item; do
            [[ -n "$item" && "$seen" != *$'\n'"$item"$'\n'* ]] || continue
            printf '%s\n' "$item"
            seen+="$item"$'\n'
        done <<<"$inherited"
    fi
    for item in $tools; do
        tool_find "$item" >/dev/null || fatal "profile $name: unknown tool '$item'"
        [[ "$seen" != *$'\n'"$item"$'\n'* ]] || continue
        printf '%s\n' "$item"
        seen+="$item"$'\n'
    done
}

tool_find() {
    local i
    for ((i = 0; i < T_COUNT; i++)); do
        [[ "${T_NAME[$i]}" == "$1" ]] && {
            printf '%s' "$i"
            return 0
        }
    done
    return 1
}

# Resolver requirements are intrinsic to the selected implementation;
# manifest REQUIRES adds tool-specific commands. Emit each command once.
tool_requirements() { # <idx>
    local i="$1" req requirements="" seen=" " j start count
    start="${T_CONFIG_START[$i]}"
    count="${T_CONFIG_COUNT[$i]}"
    for ((j = start; j < start + count; j++)); do
        req="$(resolver_requirements "${C_RESOLVER[$j]}")"
        requirements="${requirements}${requirements:+ }$req"
    done
    requirements="${requirements}${requirements:+ }${T_REQUIRES[$i]}"
    for req in $requirements; do
        [[ "$seen" == *" $req "* ]] && continue
        printf '%s\n' "$req"
        seen="${seen}${req} "
    done
}
