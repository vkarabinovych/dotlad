# shellcheck disable=SC2034  # colour vars are consumed by the sibling libs
# lib/ui.sh — colours, prompts, and diffs. Small on purpose.

ui_init_colors() {
    if [[ -z "${DOTLAD_PLAIN:-}" ]] \
       && { [[ -n "${DOTLAD_FORCE_COLOR:-}" ]] || [[ -t 1 && -z "${NO_COLOR:-}" ]]; }; then
        C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
        C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
        C_MAGENTA=$'\e[35m'; C_CYAN=$'\e[36m'
        C_HL=$'\e[48;2;68;71;90m'   # Dracula "current line" — the TUI cursor bar
        C_KEY_HL=$'\e[48;2;98;114;164m' # muted accent for demo key highlighting
    else
        C_RESET=''; C_BOLD=''; C_DIM=''
        C_RED=''; C_GREEN=''; C_YELLOW=''; C_MAGENTA=''; C_CYAN=''
        C_HL=''
        C_KEY_HL=''
    fi
}
ui_init_colors

ok()    { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
err()   { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$1"; }
hint()  { printf '%s%s%s\n' "$C_DIM" "$1" "$C_RESET"; }
title() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
fatal() { err "$1"; exit 1; }

file_noun() {
    if [[ "$1" == "1" ]]; then printf 'file'; else printf 'files'; fi
}

pretty_path() {
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *)         printf '%s' "$1" ;;
    esac
}

# 20260715_143005[-02] → "2026-07-15 14:30 [#2]"
fmt_backup_ts() {
    local n="$1"
    if [[ "$n" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})[0-9]{2}(-([0-9]+))?$ ]]; then
        printf '%s-%s-%s %s:%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}"
        [[ -n "${BASH_REMATCH[7]:-}" ]] && printf ' [#%s]' "$((10#${BASH_REMATCH[7]} + 1))"
    else
        printf '%s' "$n"
    fi
}

# confirm <prompt> — default no. Auto-yes with DOTLAD_YES=1; refuses no-TTY.
confirm() {
    [[ "${DOTLAD_YES:-}" == "1" ]] && return 0
    if [[ ! -t 0 ]]; then
        err "Refusing to run without a TTY (set DOTLAD_YES=1)."
        exit 1
    fi
    local a
    printf '%s%s%s [y/N] ' "$C_YELLOW" "$1" "$C_RESET"
    IFS= read -r a || a=""
    case "$a" in y|Y|н|Н) return 0 ;; *) return 1 ;; esac
}

# Show repo → system diff (git diff → delta → diff). Colour forced in previews.
# A not-yet-deployed file is diffed against /dev/null, so the preview shows the
# whole content that would be added rather than just "would be created".
diff_file() {
    local new="$1" cur="$2" c="auto" base="$2"
    [[ -n "${DOTLAD_FORCE_COLOR:-}" ]] && c="always"
    if [[ -L "$cur" ]]; then
        hint "replace symlink → $(pretty_path "$cur")"
        base="/dev/null"
    elif [[ ! -e "$cur" ]]; then
        hint "new file → $(pretty_path "$cur")"
        base="/dev/null"
    elif cmp -s "$new" "$cur"; then
        hint "already up to date"
        return 0
    fi
    if command -v git >/dev/null 2>&1; then
        git --no-pager diff --no-index --color="$c" -- "$base" "$new" || true
    elif command -v delta >/dev/null 2>&1; then
        diff -u "$base" "$new" | delta || true
    else
        diff -u "$base" "$new" || true
    fi
}
