#compdef dotlad

# Native Zsh completion for Dotlad and project-specific wrappers.
typeset -gA _dotlad_project_roots _dotlad_backup_roots
typeset -ga _dotlad_root_commands _dotlad_root_descriptions
typeset -ga _dotlad_option_alias_groups _dotlad_option_group_descriptions

_dotlad_register() {
    emulate -L zsh
    local command_name="$1" project_root="$2" backup_root="$3"

    [[ -z "$project_root" ]] || _dotlad_project_roots[$command_name]="$project_root"
    [[ -z "$backup_root" ]] || _dotlad_backup_roots[$command_name]="$backup_root"
    compdef _dotlad "$command_name"
}

_dotlad() {
    emulate -L zsh
    setopt local_options null_glob extended_glob glob_dots

    local service_name="${service:-${words[1]:t}}"
    local project_root="${_dotlad_project_roots[$service_name]:-${DOTLAD_PROJECT_ROOT:-$PWD}}"
    local backup_root="${_dotlad_backup_roots[$service_name]:-${DOTLAD_BACKUP_ROOT:-$HOME/.dotlad_backup}}"
    local current="${words[CURRENT]:-}" value_option="" word entry name
    local metadata kind field1 field2 detail parent direct_tools icon
    local -a positional candidates descriptions tools profiles backups aliases
    local -a tool_display profile_display
    local -A tool_icons tool_details profile_parents profile_direct_tools
    local i width mixed_width

    for ((i = 2; i < CURRENT; i++)); do
        word="${words[i]}"
        if [[ -n "$value_option" ]]; then
            case "$value_option" in
                project) project_root="$word" ;;
                backup) backup_root="$word" ;;
            esac
            value_option=""
            continue
        fi
        case "$word" in
            -C | --config) value_option="project" ;;
            --backup-root) value_option="backup" ;;
            --output) value_option="output" ;;
            --config=*) project_root="${word#*=}" ;;
            --backup-root=*) backup_root="${word#*=}" ;;
            --output=*) ;;
            -*) ;;
            *) positional+=("$word") ;;
        esac
    done

    case "$value_option" in
        project | backup)
            _directories
            return
            ;;
        output)
            _files
            return
            ;;
    esac
    case "$current" in
        --config=*)
            compset -P '*\='
            _directories
            return
            ;;
        --backup-root=*)
            compset -P '*\='
            _directories
            return
            ;;
        --output=*)
            compset -P '*\='
            _files
            return
            ;;
    esac

    if [[ "$current" == -* ]]; then
        for ((i = 1; i <= ${#_dotlad_option_alias_groups}; i++)); do
            IFS=' ' read -rA aliases <<<"${_dotlad_option_alias_groups[i]}"
            for word in "${aliases[@]}"; do
                candidates+=("$word")
                descriptions+=("${_dotlad_option_group_descriptions[i]}")
            done
        done
        width=0
        for word in "${candidates[@]}"; do
            ((${#word} > width)) && width=${#word}
        done
        for ((i = 1; i <= ${#candidates}; i++)); do
            descriptions[i]="$(printf '%-*s -- %s' \
                "$width" "${candidates[i]}" "${descriptions[i]}")"
        done
        compadd -J options -d descriptions -- "${candidates[@]}"
        return
    fi

    case "$project_root" in
        "~") project_root="$HOME" ;;
        "~/"*) project_root="$HOME/${project_root#\~/}" ;;
    esac
    case "$backup_root" in
        "~") backup_root="$HOME" ;;
        "~/"*) backup_root="$HOME/${backup_root#\~/}" ;;
    esac
    [[ "$project_root" == /* ]] || project_root="$PWD/$project_root"
    [[ "$backup_root" == /* ]] || backup_root="$PWD/$backup_root"

    for entry in "$backup_root"/*(N/); do
        name="${entry:t}"
        [[ "$name" =~ "^[0-9]{8}_[0-9]{6}(-[0-9]{2})?$" ]] || continue
        backups+=("$name")
    done

    metadata="$(DOTLAD_PLAIN=1 "${words[1]}" -C "$project_root" \
        completion _metadata 2>/dev/null)" || metadata=""
    while IFS=$'\x1f' read -r kind name field1 field2; do
        [[ -n "$name" ]] || continue
        case "$kind" in
            tool)
                tools+=("$name")
                tool_icons[$name]="$field1"
                tool_details[$name]="$field2"
                ;;
            profile)
                profiles+=("$name")
                profile_parents[$name]="$field1"
                profile_direct_tools[$name]="$field2"
                ;;
        esac
    done <<<"$metadata"

    mixed_width=0
    for name in "${_dotlad_root_commands[@]}" "${tools[@]}"; do
        ((${#name} > mixed_width)) && mixed_width=${#name}
    done
    for ((i = 1; i <= ${#tools}; i++)); do
        icon="${tool_icons[${tools[i]}]:-}"
        detail="${tool_details[${tools[i]}]:-}"
        tool_display[i]="$(printf '%-*s -- %s' \
            "$mixed_width" "${tools[i]}" "${icon:-•}")"
        [[ -z "$detail" ]] || tool_display[i]+=" $detail"
    done
    width=0
    for name in "${profiles[@]}"; do
        ((${#name} > width)) && width=${#name}
    done
    for ((i = 1; i <= ${#profiles}; i++)); do
        parent="${profile_parents[${profiles[i]}]:-}"
        direct_tools="${profile_direct_tools[${profiles[i]}]:-}"
        if [[ -n "$parent" ]]; then
            detail="↳ $parent"
            [[ -z "$direct_tools" ]] || detail+=" + $direct_tools"
        else
            detail="${direct_tools:-none}"
        fi
        profile_display[i]="$(printf '%-*s -- %s' \
            "$width" "${profiles[i]}" "$detail")"
    done

    if ((${#positional} == 0)); then
        candidates=("${_dotlad_root_commands[@]}")
        descriptions=("${_dotlad_root_descriptions[@]}")
        for ((i = 1; i <= ${#candidates}; i++)); do
            descriptions[i]="$(printf '%-*s -- %s' \
                "$mixed_width" "${candidates[i]}" "${descriptions[i]}")"
        done
        compadd -J commands -d descriptions -- "${candidates[@]}"
        ((${#tools} == 0)) ||
            compadd -J tools -X tools -d tool_display -- "${tools[@]}"
        return
    fi

    case "${positional[1]}" in
        profile)
            ((${#positional} == 1 && ${#profiles} > 0)) &&
                compadd -J profiles -X profiles \
                    -d profile_display -- "${profiles[@]}"
            ;;
        restore)
            ((${#positional} == 1 && ${#backups} > 0)) &&
                compadd -J backups -X "restore points" -- "${backups[@]}"
            ;;
        backup)
            if ((${#positional} == 1)); then
                compadd -J commands -X "backup actions" -- delete
            elif [[ "${positional[2]}" == delete ]] &&
                ((${#positional} == 2 && ${#backups} > 0)); then
                compadd -J backups -X "restore points" -- "${backups[@]}"
            fi
            ;;
        plan)
            if ((${#positional} == 1)); then
                candidates=(all profile)
                descriptions=("plan every relevant tool" "plan a named profile")
                for ((i = 1; i <= ${#candidates}; i++)); do
                    descriptions[i]="$(printf '%-*s -- %s' \
                        "$mixed_width" "${candidates[i]}" "${descriptions[i]}")"
                done
                compadd -J targets -d descriptions -- "${candidates[@]}"
                ((${#tools} == 0)) ||
                    compadd -J tools -X tools \
                        -d tool_display -- "${tools[@]}"
            elif [[ "${positional[2]}" == profile ]] &&
                ((${#positional} == 2 && ${#profiles} > 0)); then
                compadd -J profiles -X profiles \
                    -d profile_display -- "${profiles[@]}"
            elif [[ "${positional[2]}" != all ]] && ((${#tools} > 0)); then
                compadd -J tools -X tools \
                    -d tool_display -- "${tools[@]}"
            fi
            ;;
        completion)
            ((${#positional} == 1)) && compadd -J shells -X shells -- zsh
            ;;
        all | brewfile | backups | uninstall | version | help) ;;
        *)
            ((${#tools} == 0)) ||
                compadd -J tools -X tools \
                    -d tool_display -- "${tools[@]}"
            ;;
    esac
}
