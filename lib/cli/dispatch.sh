# CLI option parsing and command dispatch after the runtime has loaded.

# shellcheck disable=SC2034 # Globals are consumed by sibling runtime modules.

cli_dispatch() {
    local cmd="" arg tool_index name position
    local pos=() plan_pos=() names=()
    for arg in "$@"; do
        case "$arg" in
            --plain) DOTLAD_PLAIN=1 ;;
            --yes) DOTLAD_YES=1 ;;
            --dry-run) DOTLAD_DRY_RUN=1 ;;
            --json) DOTLAD_PLAN_JSON=1 ;;
            --symlink)
                DOTLAD_DEFAULT_RESOLVER=symlink
                export DOTLAD_DEFAULT_RESOLVER
                ;;
            --packages-only) mode_set packages ;;
            --config-only) mode_set config ;;
            -h | -H | --help) cmd="help" ;;
            -v | -V | --version) cmd="version" ;;
            -*)
                err "unknown option: $arg"
                return 1
                ;;
            *) pos+=("$arg") ;;
        esac
    done
    mode_set "$DOTLAD_MODE" || {
        err "unknown mode: $DOTLAD_MODE"
        return 1
    }
    if [[ "$cmd" == "version" ]]; then
        [[ ${#pos[@]} -eq 0 ]] || {
            err "usage: $DOTLAD_COMMAND_NAME version"
            return 1
        }
        printf '%s %s\n' "$DOTLAD_DISPLAY_NAME" "$DOTLAD_VERSION"
        return 0
    fi
    case "${pos[0]:-}" in
        help)
            [[ ${#pos[@]} -eq 1 ]] || {
                err "usage: $DOTLAD_COMMAND_NAME help"
                return 1
            }
            cli_usage
            return 0
            ;;
        version)
            [[ ${#pos[@]} -eq 1 ]] || {
                err "usage: $DOTLAD_COMMAND_NAME version"
                return 1
            }
            printf '%s %s\n' "$DOTLAD_DISPLAY_NAME" "$DOTLAD_VERSION"
            return 0
            ;;
        completion)
            if [[ ${#pos[@]} -eq 2 && "${pos[1]}" == zsh ]]; then
                cli_print_zsh_completion
            elif [[ ${#pos[@]} -eq 2 && "${pos[1]}" == _metadata ]]; then
                manifest_load
                cli_print_completion_metadata
            else
                err "usage: $DOTLAD_COMMAND_NAME completion zsh"
                return 1
            fi
            return 0
            ;;
        uninstall)
            [[ ${#pos[@]} -eq 1 ]] || {
                err "usage: $DOTLAD_COMMAND_NAME uninstall"
                return 1
            }
            cli_uninstall
            return $?
            ;;
    esac
    console_init_colors
    if [[ "$cmd" == "help" ]]; then
        [[ ${#pos[@]} -eq 0 ]] || {
            err "usage: $DOTLAD_COMMAND_NAME help"
            return 1
        }
        cli_usage
        return 0
    fi
    if [[ "${pos[0]:-}" == "brewfile" ]]; then
        [[ ${#pos[@]} -eq 1 ]] || {
            err "usage: $DOTLAD_COMMAND_NAME brewfile [--output PATH]"
            return 1
        }
        cmd_brewfile
        return 0
    fi
    [[ -z "$DOTLAD_BREWFILE_OUT" ]] || {
        err "--output is only valid with the brewfile command"
        return 1
    }
    [[ -z "${DOTLAD_PLAN_JSON:-}" || -n "${DOTLAD_DRY_RUN:-}" || "${pos[0]:-}" == "plan" ]] || {
        err "--json is only valid with plan or --dry-run"
        return 1
    }

    if [[ -z "${DOTLAD_DRY_RUN:-}" && "${pos[0]:-}" == "backups" ]]; then
        [[ ${#pos[@]} -eq 1 ]] || {
            err "usage: $DOTLAD_COMMAND_NAME backups"
            return 1
        }
        cmd_backups
        return $?
    fi
    if [[ -z "${DOTLAD_DRY_RUN:-}" && "${pos[0]:-}" == "restore" ]]; then
        [[ ${#pos[@]} -eq 2 ]] || {
            err "usage: $DOTLAD_COMMAND_NAME restore NAME"
            return 1
        }
        cmd_restore_cli "${pos[1]}"
        return $?
    fi
    if [[ -z "${DOTLAD_DRY_RUN:-}" && "${pos[0]:-}" == "backup" ]]; then
        [[ ${#pos[@]} -eq 3 && "${pos[1]}" == "delete" ]] || {
            err "usage: $DOTLAD_COMMAND_NAME backup delete NAME"
            return 1
        }
        cmd_backup_delete_cli "${pos[2]}"
        return $?
    fi

    manifest_load

    if [[ "${pos[0]:-}" == "plan" ]]; then
        if [[ ${#pos[@]} -eq 1 ]]; then
            cmd_plan
            return $?
        fi
        for ((position = 1; position < ${#pos[@]}; position++)); do
            plan_pos+=("${pos[$position]}")
        done
        cmd_plan "${plan_pos[@]}"
        return $?
    fi
    if [[ -n "${DOTLAD_DRY_RUN:-}" ]]; then
        if [[ ${#pos[@]} -eq 0 ]]; then cmd_plan; else cmd_plan "${pos[@]}"; fi
        return $?
    fi

    # No positional argument opens the interactive picker.
    if [[ ${#pos[@]} -eq 0 ]]; then
        cmd_pick
        return $?
    fi

    case "${pos[0]}" in
        all)
            cmd_all
            return $?
            ;;
        profile)
            [[ ${#pos[@]} -eq 2 ]] || {
                err "usage: $DOTLAD_COMMAND_NAME profile NAME"
                return 1
            }
            cmd_profile "${pos[1]}"
            return $?
            ;;
        # Hidden helper: the background install/update worker the TUI spawns.
        _worker)
            worker
            return $?
            ;;
    esac

    selection_explicit "${pos[@]}" || {
        hint "run $DOTLAD_COMMAND_NAME to see the list"
        return 1
    }
    names=("${SELECTED_NAMES[@]}")
    title "$(selection_action "${names[@]}") ${names[*]}"
    for name in "${names[@]}"; do
        tool_index="$(tool_find "$name")"
        printf '\n%s— %s —%s\n' "$C_BOLD" "$name" "$C_RESET"
        tool_diff "$tool_index"
    done
    echo ""
    confirm "$(selection_prompt "${#names[@]} tool(s)" "${names[@]}")" || {
        hint "cancelled"
        return 0
    }
    selection_has_packages "${names[@]}" && ensure_brew
    run_selected "${names[@]}"
}
