# shellcheck shell=bash
# lib/packages.sh — package and command-level requirement installation.

sha256_available() {
    command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1
}

sha256_file() { # <file> — print only the lowercase digest
    local output
    if command -v sha256sum >/dev/null 2>&1; then
        output="$(sha256sum "$1" 2>/dev/null)" || return 1
    elif command -v shasum >/dev/null 2>&1; then
        output="$(shasum -a 256 "$1" 2>/dev/null)" || return 1
    else
        return 127
    fi
    printf '%s' "${output%% *}"
}

run_remote_installer() ( # <idx>
    local i="$1" installer="" actual
    trap '[[ -z "$installer" ]] || rm -f "$installer"' EXIT
    installer="$(mktemp "${TMPDIR:-/tmp}/dotlad-installer.XXXXXX")" || {
        err "${T_NAME[$i]}: cannot create installer file"
        return 1
    }
    if ! curl -fsSL "${T_INSTALL_URL[$i]}" >"$installer"; then
        err "${T_NAME[$i]}: installer download failed"
        return 1
    fi
    if [[ -n "${T_INSTALL_SHA256[$i]}" ]]; then
        actual="$(sha256_file "$installer")" || actual=""
        if [[ "$actual" != "${T_INSTALL_SHA256[$i]}" ]]; then
            err "${T_NAME[$i]}: installer checksum mismatch"
            return 1
        fi
    fi
    /bin/sh "$installer" || {
        err "${T_NAME[$i]}: installer failed"
        return 1
    }
)

install_tool() {
    local i="$1" p pkgs=()
    tool_installed "$i" && return 0
    if [[ -n "${T_BREW[$i]}" ]]; then
        command -v brew >/dev/null 2>&1 || {
            warn "${T_NAME[$i]}: Homebrew not installed"
            return 1
        }
        for p in ${T_BREW[$i]}; do pkgs+=("$p"); done
        if [[ "${T_CASK[$i]}" == "1" ]]; then brew install --cask "${pkgs[@]}"; else brew install "${pkgs[@]}"; fi ||
            {
                err "${T_NAME[$i]}: install failed"
                return 1
            }
    elif [[ -n "${T_INSTALL_URL[$i]}" ]]; then
        warn "${T_NAME[$i]} runs a remote installer: ${T_INSTALL_URL[$i]}"
        confirm "Run it?" || {
            hint "skipped"
            return 1
        }
        run_remote_installer "$i" || return 1
    else
        err "${T_NAME[$i]}: no installer defined"
        return 1
    fi
    hash -r 2>/dev/null || true
    tool_installed "$i" ||
        {
            err "${T_NAME[$i]}: installer finished but the declared installed state is still missing"
            return 1
        }
    if [[ -n "${T_BREW[$i]}" ]]; then
        N_INSTALLED=$((N_INSTALLED + ${#pkgs[@]}))
    else
        N_INSTALLED=$((N_INSTALLED + 1))
    fi
    return 0
}

tool_missing_requirements() { # <idx>
    local req
    while IFS= read -r req; do
        [[ -n "$req" ]] || continue
        command -v "$req" >/dev/null 2>&1 || printf '%s\n' "$req"
    done < <(tool_requirements "$1")
}

ensure_requirements() {
    local i="$1" req
    while IFS= read -r req; do
        # An earlier formula may provide more than one required command.
        command -v "$req" >/dev/null 2>&1 && continue
        if ! mode_packages_enabled; then
            warn "${T_NAME[$i]}: needs $req (config-only mode does not install packages)"
            return 1
        fi
        command -v brew >/dev/null 2>&1 ||
            {
                warn "${T_NAME[$i]}: needs $req (Homebrew unavailable)"
                return 1
            }
        printf '%s▸%s installing requirement: %s\n' "$C_CYAN" "$C_RESET" "$req"
        brew install "$req" || {
            err "${T_NAME[$i]}: failed to install requirement $req"
            return 1
        }
        N_INSTALLED=$((N_INSTALLED + 1))
    done < <(tool_missing_requirements "$i")
}
