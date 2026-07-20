# lib/resolvers/inject.sh — maintain one source-backed block inside a file.
# The surrounding destination content remains untouched.

resolver_inject_action() { printf 'inject'; }

resolver_inject_source_name() { basename "$1"; }

resolver_inject_options() { printf 'COMMENT_PREFIX\nCOMMENT_SUFFIX\n'; }

resolver_inject_destination_key() {
    printf '%s:%s' "$RESOLVER_TOOL_NAME" "$(resolver_inject_source_name "$1")"
}

resolver_inject_present() {
    [[ "$(resolver_inject_block_state "$1" "$2")" != missing ]]
}

resolver_inject_comment_style() { # <destination> — populate INJECT_COMMENT_*
    local destination custom_prefix custom_suffix
    if resolver_option_get COMMENT_PREFIX; then
        custom_prefix="$RESOLVER_OPTION_VALUE"
        resolver_option_get COMMENT_SUFFIX || true
        custom_suffix="$RESOLVER_OPTION_VALUE"
        INJECT_COMMENT_PREFIX="$custom_prefix"
        INJECT_COMMENT_SUFFIX="$custom_suffix"
        return 0
    fi
    destination="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    INJECT_COMMENT_SUFFIX=""
    case "$destination" in
        *.html | *.htm | *.xml | *.svg | *.md | *.markdown)
            INJECT_COMMENT_PREFIX='<!--'
            INJECT_COMMENT_SUFFIX='-->'
            ;;
        *.css | *.scss | *.sass | *.less)
            INJECT_COMMENT_PREFIX='/*'
            INJECT_COMMENT_SUFFIX='*/'
            ;;
        *.js | *.jsx | *.ts | *.tsx | *.c | *.cc | *.cpp | *.h | *.hpp | \
            *.java | *.go | *.rs | *.swift | *.kt | *.kts | *.php)
            INJECT_COMMENT_PREFIX='//'
            ;;
        *.lua | *.sql)
            INJECT_COMMENT_PREFIX='--'
            ;;
        *.el | *.lisp | *.cl | *.scm)
            INJECT_COMMENT_PREFIX=';'
            ;;
        *.tex | *.sty)
            INJECT_COMMENT_PREFIX='%'
            ;;
        *.bat | *.cmd)
            INJECT_COMMENT_PREFIX='REM'
            ;;
        *.vim | */vimrc | */.vimrc)
            INJECT_COMMENT_PREFIX='"'
            ;;
        *) INJECT_COMMENT_PREFIX='#' ;;
    esac
}

resolver_inject_marker() { # <begin|end> <tool-name> <source-name>
    local kind="$1" metadata="tool=$2 source=$3"
    if [[ -n "$INJECT_COMMENT_SUFFIX" ]]; then
        printf '%s dotlad:%s %s %s' "$INJECT_COMMENT_PREFIX" "$kind" \
            "$metadata" "$INJECT_COMMENT_SUFFIX"
    else
        printf '%s dotlad:%s %s' "$INJECT_COMMENT_PREFIX" "$kind" "$metadata"
    fi
}

# Report missing, valid, or invalid for this source's managed block. The scan
# validates the complete destination, not only the requested identity: replacing
# one block must never consume a nested block owned by another config. Marker
# recognition is independent of comment style so changing delimiters updates an
# existing block instead of appending a second one.
resolver_inject_block_state() { # <source> <destination>
    local source_name metadata stats begins ends bad
    [[ -f "$2" && ! -L "$2" ]] || {
        printf 'missing'
        return 0
    }
    source_name="$(resolver_inject_source_name "$1")"
    metadata="tool=$RESOLVER_TOOL_NAME source=$source_name"
    stats="$(awk -v target="$metadata" '
        function inspect(line,    begin_at, end_at, at, tail, fields, count,
                         kind, key) {
            begin_at = index(line, "dotlad:begin")
            end_at = index(line, "dotlad:end")
            if (!begin_at && !end_at) return
            if (begin_at && end_at) {
                bad = 1
                return
            }
            if (begin_at) {
                at = begin_at
                kind = "begin"
            } else {
                at = end_at
                kind = "end"
            }
            tail = substr(line, at)
            count = split(tail, fields, /[[:space:]]+/)
            if (count < 3 || fields[1] != "dotlad:" kind ||
                fields[2] !~ /^tool=[a-z0-9][a-z0-9-]*$/ ||
                fields[3] !~ /^source=[A-Za-z0-9._-]+$/) {
                bad = 1
                return
            }
            key = fields[2] " " fields[3]
            if (kind == "begin") {
                begins[key]++
                if (begins[key] > 1 || open != "") bad = 1
                open = key
            } else {
                ends[key]++
                if (ends[key] > 1 || open != key) bad = 1
                open = ""
            }
        }
        { inspect($0) }
        END { print begins[target] + 0, ends[target] + 0, (bad || open != "") + 0 }
    ' "$2")" || {
        printf 'invalid'
        return 0
    }
    read -r begins ends bad <<<"$stats"
    if [[ "$begins" == 0 && "$ends" == 0 && "$bad" == 0 ]]; then
        printf 'missing'
    elif [[ "$begins" == 1 && "$ends" == 1 && "$bad" == 0 ]]; then
        printf 'valid'
    else
        printf 'invalid'
    fi
}

resolver_inject_render() { # <source> <destination>
    local src="$1" dest="$2" source_name metadata begin_marker end_marker state live_input
    source_name="$(resolver_inject_source_name "$src")"
    metadata="tool=$RESOLVER_TOOL_NAME source=$source_name"
    resolver_inject_comment_style "$dest"
    begin_marker="$(resolver_inject_marker begin "$RESOLVER_TOOL_NAME" "$source_name")"
    end_marker="$(resolver_inject_marker end "$RESOLVER_TOOL_NAME" "$source_name")"
    state="$(resolver_inject_block_state "$src" "$dest")"
    [[ "$state" != invalid ]] || return 1

    if [[ "$state" == missing ]]; then
        if [[ -f "$dest" && ! -L "$dest" ]]; then live_input="$dest"; else live_input=/dev/null; fi
        awk -v begin_marker="$begin_marker" -v end_marker="$end_marker" \
            -v source_file="$src" '
            function emit_source(line) {
                print begin_marker
                while ((getline line < source_file) > 0) print line
                close(source_file)
                print end_marker
            }
            { lines[++count] = $0 }
            END {
                for (i = 1; i <= count; i++) print lines[i]
                if (count) print ""
                emit_source()
            }
        ' "$live_input"
        return
    fi

    awk -v begin_key="dotlad:begin $metadata" \
        -v end_key="dotlad:end $metadata" \
        -v begin_marker="$begin_marker" -v end_marker="$end_marker" \
        -v source_file="$src" '
        function marker(line, key, next_char, position) {
            position = index(line, key)
            if (!position) return 0
            next_char = substr(line, position + length(key), 1)
            return next_char == "" || next_char == " "
        }
        function emit_source(line) {
            print begin_marker
            while ((getline line < source_file) > 0) print line
            close(source_file)
            print end_marker
        }
        marker($0, begin_key) {
            emit_source()
            managed = 1
            next
        }
        managed {
            if (marker($0, end_key)) managed = 0
            next
        }
        { print }
        END { if (managed) exit 1 }
    ' "$dest"
}

resolver_inject_equal() { # <source> <destination>
    local rendered rc=0
    [[ -f "$2" && ! -L "$2" ]] || return 1
    rendered="$(mktemp)" || return 1
    resolver_inject_render "$1" "$2" >"$rendered" 2>/dev/null || rc=1
    [[ "$rc" != 0 ]] || cmp -s "$rendered" "$2" || rc=1
    rm -f "$rendered"
    [[ "$rc" == 0 ]]
}

resolver_inject_check() { # <source> <destination>
    local source_name state comment_prefix="" comment_suffix="" backslash=$'\\'
    source_name="$(resolver_inject_source_name "$1")"
    [[ "$source_name" =~ ^[A-Za-z0-9._-]+$ ]] ||
        printf 'inject source filename contains unsupported metadata characters\n'
    if grep -F -e 'dotlad:begin' -e 'dotlad:end' "$1" >/dev/null 2>&1; then
        printf 'inject source contains a reserved dotlad marker\n'
    fi
    if resolver_option_get COMMENT_PREFIX; then comment_prefix="$RESOLVER_OPTION_VALUE"; fi
    if resolver_option_get COMMENT_SUFFIX; then comment_suffix="$RESOLVER_OPTION_VALUE"; fi
    if [[ -n "$comment_suffix" && -z "$comment_prefix" ]]; then
        printf 'COMMENT_SUFFIX requires COMMENT_PREFIX\n'
    fi
    if [[ "$comment_prefix" == *"$backslash"* || "$comment_suffix" == *"$backslash"* ]]; then
        printf 'inject comment delimiters cannot contain backslashes\n'
    fi
    if [[ "$comment_prefix" == *dotlad:* || "$comment_suffix" == *dotlad:* ]]; then
        printf 'inject comment delimiters contain reserved marker text\n'
    fi
    if [[ -d "$2" && ! -L "$2" ]]; then
        printf 'file destination is a directory\n'
        return 0
    elif [[ -e "$2" && ! -f "$2" && ! -L "$2" ]]; then
        printf 'file destination has an unsupported type\n'
        return 0
    fi
    state="$(resolver_inject_block_state "$1" "$2")"
    [[ "$state" != invalid ]] ||
        printf 'destination has malformed or duplicate managed blocks for %s\n' "$source_name"
}

resolver_inject_changes() { # <source> <destination>
    if [[ "$(resolver_inject_block_state "$1" "$2")" == missing ]]; then
        printf '1 managed block to add'
    else
        printf '1 managed block to update'
    fi
}
