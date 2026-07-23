# CLI environment and early global-option extraction. Runs before runtime.sh.

# shellcheck disable=SC2034 # Globals are consumed by sibling CLI/runtime modules.

cli_bootstrap() {
    local candidate i project_candidate
    local -a project_args
    DOTLAD_BIN="$DOTLAD_RUNTIME_ROOT/dotlad"
    DOTLAD_PROJECT_ROOT_EXPLICIT=0
    DOTLAD_BACKUP_ROOT_EXPLICIT=0
    [[ -z "${DOTLAD_PROJECT_ROOT+x}" ]] || DOTLAD_PROJECT_ROOT_EXPLICIT=1
    [[ -z "${DOTLAD_BACKUP_ROOT+x}" ]] || DOTLAD_BACKUP_ROOT_EXPLICIT=1
    DOTLAD_PROJECT_ROOT="${DOTLAD_PROJECT_ROOT:-$PWD}"
    DOTLAD_BACKUP_ROOT="${DOTLAD_BACKUP_ROOT:-$HOME/.dotlad_backup}"
    DOTLAD_COMMAND_NAME="${DOTLAD_COMMAND_NAME:-$(basename "$0")}"
    DOTLAD_DISPLAY_NAME="${DOTLAD_DISPLAY_NAME:-$DOTLAD_COMMAND_NAME}"
    DOTLAD_VERSION="$(cat "$DOTLAD_RUNTIME_ROOT/VERSION" 2>/dev/null || printf 'development')"
    DOTLAD_BREWFILE_OUT="${DOTLAD_BREWFILE_OUT:-}"

    # Bash 3.2 with nounset cannot expand an empty array. Keep a removable
    # sentinel so a no-argument invocation follows the same bootstrap path.
    CLI_BOOTSTRAP_ARGS=("")
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backup)
                [[ $# -gt 1 ]] || {
                    printf '%s: --backup needs a path\n' "$DOTLAD_COMMAND_NAME" >&2
                    return 1
                }
                DOTLAD_BACKUP_ROOT="$2"
                DOTLAD_BACKUP_ROOT_EXPLICIT=1
                shift 2
                ;;
            --backup=*)
                DOTLAD_BACKUP_ROOT="${1#*=}"
                DOTLAD_BACKUP_ROOT_EXPLICIT=1
                shift
                ;;
            --output)
                [[ $# -gt 1 ]] || {
                    printf '%s: --output needs a path\n' "$DOTLAD_COMMAND_NAME" >&2
                    return 1
                }
                DOTLAD_BREWFILE_OUT="$2"
                shift 2
                ;;
            --output=*)
                DOTLAD_BREWFILE_OUT="${1#*=}"
                shift
                ;;
            *)
                CLI_BOOTSTRAP_ARGS+=("$1")
                shift
                ;;
        esac
    done
    candidate="${CLI_BOOTSTRAP_ARGS[1]:-}"
    project_candidate=0
    [[ -d "$candidate" ]] && project_candidate=1
    case "$candidate" in
        . | .. | ./* | ../* | */*) project_candidate=1 ;;
    esac
    if [[ "$project_candidate" == 1 ]]; then
        DOTLAD_PROJECT_ROOT="$candidate"
        DOTLAD_PROJECT_ROOT_EXPLICIT=1
        project_args=("")
        for ((i = 2; i < ${#CLI_BOOTSTRAP_ARGS[@]}; i++)); do
            project_args+=("${CLI_BOOTSTRAP_ARGS[$i]}")
        done
        CLI_BOOTSTRAP_ARGS=("${project_args[@]}")
    fi
    [[ -d "$DOTLAD_PROJECT_ROOT" ]] || {
        printf '%s: project root does not exist: %s\n' \
            "$DOTLAD_COMMAND_NAME" "$DOTLAD_PROJECT_ROOT" >&2
        return 1
    }
    ROOT="$(cd "$DOTLAD_PROJECT_ROOT" && pwd)"
    export DOTLAD_RUNTIME_ROOT DOTLAD_PROJECT_ROOT="$ROOT" DOTLAD_BACKUP_ROOT DOTLAD_BIN
    export DOTLAD_COMMAND_NAME DOTLAD_DISPLAY_NAME DOTLAD_VERSION DOTLAD_BREWFILE_OUT
}
