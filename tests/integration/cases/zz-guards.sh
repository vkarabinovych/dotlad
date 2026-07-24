# shellcheck shell=bash
# shellcheck disable=SC2015,SC2154  # sourced integration cases share the orchestrator fixture
# --- guards -----------------------------------------------------------------
rc_is "unknown tool exits 1" 1 df nosuchtool
rc_is "unknown option exits 1" 1 df --bogus
rc_is "removed -C option exits 1" 1 df -C "$FAKE"
rc_is "removed --config option exits 1" 1 df --config "$FAKE"
rc_is "help rejects positional arguments" 1 df help extra
rc_is "version rejects positional arguments" 1 df version extra
rc_is "uninstall rejects a repository checkout" 1 df uninstall
rc_is "uninstall rejects positional arguments" 1 df uninstall extra
rc_is "update rejects a repository checkout" 1 df update
rc_is "update rejects positional arguments" 1 df update extra
direct_project_rc=0
(cd "$FAKE" && PATH="$SB/brewprefix/bin:$SB/bin:$PATH" HOME="$H" \
    DOTLAD_PLAIN=1 /bin/bash "$ROOT/dotlad" "$FAKE" --plain >/dev/null) ||
    direct_project_rc=$?
[[ "$direct_project_rc" == 0 ]] &&
    pass "direct project path selects the manifest root" ||
    fail "direct project path was not accepted (rc=$direct_project_rc)"
relative_project_rc=0
(cd "$SB" && PATH="$SB/brewprefix/bin:$SB/bin:$PATH" HOME="$H" \
    DOTLAD_PLAIN=1 /bin/bash "$ROOT/dotlad" repo --plain >/dev/null) ||
    relative_project_rc=$?
[[ "$relative_project_rc" == 0 ]] &&
    pass "relative project path selects the manifest root" ||
    fail "relative project path was not accepted (rc=$relative_project_rc)"
rc_is "help command exits 0" 0 df help
rc_is "uppercase help flag exits 0" 0 df -H
rc_is "help flag rejects positional arguments" 1 df -H extra
rc_is "uppercase version flag exits 0" 0 df -V
rc_is "version flag rejects positional arguments" 1 df -V extra
rc_is "Zsh completion command exits 0" 0 df completion zsh
rc_is "completion command rejects an unsupported shell" 1 df completion bash
help_output="$(df help)"
grep -qF -- 'dotlad /path/to/project' <<<"$help_output" &&
    pass "help documents direct project paths" ||
    fail "help omits direct project paths"
help_usage_line="$(printf '%s\n' "$help_output" | awk \
    '/^  dotlad \/path\/to\/project \[OPTIONS\] \[COMMAND \| TOOL…\]$/ { print NR; exit }')"
help_commands_line="$(printf '%s\n' "$help_output" | awk \
    '/^Commands:$/ { print NR; exit }')"
if [[ -n "$help_usage_line" && -n "$help_commands_line" &&
    "$help_usage_line" -lt "$help_commands_line" ]]; then
    pass "help presents PATH as an invocation form"
else
    fail "help omits the canonical PATH invocation form"
fi
grep -q -- '--symlink' <<<"$help_output" && pass "help documents --symlink" ||
    fail "help omits --symlink"
grep -qF -- '-h, -H, --help' <<<"$help_output" && pass "help documents all help aliases" ||
    fail "help omits a help alias"
grep -qF -- '-v, -V, --version' <<<"$help_output" && pass "help documents all version aliases" ||
    fail "help omits a version alias"
grep -qF -- 'completion zsh' <<<"$help_output" && pass "help documents Zsh completion" ||
    fail "help omits Zsh completion"
grep -qF -- 'uninstall' <<<"$help_output" &&
    fail "repository help exposes global uninstall" ||
    pass "repository help hides global uninstall"
grep -qF -- 'dotlad update' <<<"$help_output" &&
    fail "repository help exposes global update" ||
    pass "repository help hides global update"

completion_output="$(df completion zsh)"
completion_project_root="$(cd "$FAKE" && pwd)"
if grep -qF 'compadd ' <<<"$completion_output" &&
    grep -qF "_dotlad_register dotlad $completion_project_root $H/.dotlad_backup" \
        <<<"$completion_output"; then
    pass "Zsh completion preserves command and project identity"
else
    fail "Zsh completion omits compadd, compdef, or selected roots"
fi
completion_without_colorfgbg="$(cd "$FAKE" && env -u COLORFGBG \
    DOTLAD_FORCE_COLOR=1 HOME="$H" /bin/bash "$ROOT/dotlad" \
    "$FAKE" completion zsh)"
grep -qF '_dotlad_register dotlad' <<<"$completion_without_colorfgbg" &&
    pass "Zsh completion tolerates an unset COLORFGBG" ||
    fail "Zsh completion requires COLORFGBG when colour is forced"
wrapper_completion="$(cd "$FAKE" && HOME="$H" DOTLAD_COMMAND_NAME=mydots \
    /bin/bash "$ROOT/dotlad" "$FAKE" --backup "$H/.dotlad_backup" \
    completion zsh)"
if grep -qF "_dotlad_register mydots $completion_project_root $H/.dotlad_backup" \
    <<<"$wrapper_completion"; then
    pass "Zsh completion registers an embedded wrapper"
else
    fail "Zsh completion loses an embedded wrapper identity"
fi

dark_palette="$(DOTLAD_FORCE_COLOR=1 DOTLAD_COLOR_SCHEME=dark /bin/bash -c '
    . "$1/lib/console.sh"
    printf "%s|%s|%s" "$C_YELLOW" "$C_SKY_BLUE" "$C_HL"
' _ "$ROOT")"
light_palette="$(DOTLAD_FORCE_COLOR=1 DOTLAD_COLOR_SCHEME=light /bin/bash -c '
    . "$1/lib/console.sh"
    printf "%s|%s|%s" "$C_YELLOW" "$C_SKY_BLUE" "$C_HL"
' _ "$ROOT")"
auto_light_palette="$(DOTLAD_FORCE_COLOR=1 COLORFGBG='0;15' /bin/bash -c '
    . "$1/lib/console.sh"
    printf "%s|%s|%s" "$C_YELLOW" "$C_SKY_BLUE" "$C_HL"
' _ "$ROOT")"
if [[ "$dark_palette" != "$light_palette" &&
    "$auto_light_palette" == "$light_palette" ]]; then
    pass "console palette follows explicit and detected colour schemes"
else
    fail "console palette does not adapt to the terminal background"
fi

# Embedded wrappers have one command identity across CLI output and may use a
# separate human-readable brand across presentation output.
identity_help="$(cd "$FAKE" && HOME="$H" DOTLAD_PLAIN=1 \
    DOTLAD_COMMAND_NAME=mydots DOTLAD_DISPLAY_NAME='My Dotfiles' \
    /bin/bash "$ROOT/dotlad" help)"
if [[ "$identity_help" == My\ Dotfiles\ —* ]] &&
    grep -q '^  mydots profile NAME' <<<"$identity_help"; then
    pass "display and command names reach their help roles"
else
    fail "display and command names are inconsistent in help"
fi
help_pick_col="$(printf '%s\n' "$identity_help" | awk \
    'index($0, "Pick tools") { print index($0, "Pick tools"); exit }')"
help_delete_col="$(printf '%s\n' "$identity_help" | awk \
    'index($0, "Delete a restore") { print index($0, "Delete a restore"); exit }')"
help_option_first_col="$(printf '%s\n' "$identity_help" | awk \
    'index($0, "disable color") { print index($0, "disable color"); exit }')"
help_option_last_col="$(printf '%s\n' "$identity_help" | awk \
    'index($0, "print the installed version") { print index($0, "print the installed version"); exit }')"
if [[ -n "$help_pick_col" && "$help_pick_col" == "$help_delete_col" &&
    "$help_option_first_col" == "$help_option_last_col" ]] &&
    grep -Fqx '  ✓ up to date        the config matches the repo, or the package is installed' \
        <<<"$identity_help" &&
    grep -Fqx '  ↑ update available  the config differs — updating would change it' \
        <<<"$identity_help"; then
    pass "help descriptions use aligned columns"
else
    fail "help description columns are inconsistent"
fi
identity_version="$(cd "$FAKE" && HOME="$H" DOTLAD_COMMAND_NAME=mydots \
    DOTLAD_DISPLAY_NAME='My Dotfiles' \
    /bin/bash "$ROOT/dotlad" -v)"
identity_expected_version="$(cat "$ROOT/VERSION")"
[[ "$identity_version" == "My Dotfiles $identity_expected_version" ]] &&
    pass "display name reaches version output" ||
    fail "display name missing from version output: $identity_version"
identity_error="$(cd "$FAKE" && HOME="$H" DOTLAD_COMMAND_NAME=mydots \
    /bin/bash "$ROOT/dotlad" --backup 2>&1 || true)"
[[ "$identity_error" == "mydots: --backup needs a path" ]] &&
    pass "custom command name prefixes bootstrap errors" ||
    fail "custom command name missing from bootstrap error: $identity_error"
identity_labels="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" \
    DOTLAD_COMMAND_NAME=mydots DOTLAD_DISPLAY_NAME='My Dotfiles' /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"
    tui_init_labels; printf "%s" "$TUI_HEADER_TITLE"')"
[[ "$identity_labels" == "My Dotfiles" ]] &&
    pass "display name controls the TUI title" ||
    fail "display name missing from TUI title: $identity_labels"
identity_labels="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" \
    DOTLAD_COMMAND_NAME=mydots DOTLAD_DISPLAY_NAME='' /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"
    tui_init_labels; printf "%s" "$TUI_HEADER_TITLE"')"
[[ "$identity_labels" == mydots ]] &&
    pass "TUI title falls back to the command name" ||
    fail "TUI title fallback is inconsistent: $identity_labels"
identity_host_label="$(cd "$FAKE" && HOME="$H" ROOT="$FAKE" \
    DOTLAD_PLATFORM=linux /bin/bash -c '
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"
    hostname() { return 1; }
    tui_init_labels; printf "%s" "$TUI_HOST_LABEL"')"
[[ "$identity_host_label" == "this linux" ]] &&
    pass "TUI host label falls back to the detected platform" ||
    fail "TUI host label platform fallback is inconsistent: $identity_host_label"
