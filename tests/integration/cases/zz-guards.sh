# shellcheck shell=bash
# shellcheck disable=SC2015,SC2154  # sourced integration cases share the orchestrator fixture
# --- guards -----------------------------------------------------------------
rc_is "unknown tool exits 1" 1 df nosuchtool
rc_is "unknown option exits 1" 1 df --bogus
rc_is "help rejects positional arguments" 1 df help extra
rc_is "version rejects positional arguments" 1 df version extra
rc_is "help command exits 0" 0 df help
rc_is "uppercase help flag exits 0" 0 df -H
rc_is "help flag rejects positional arguments" 1 df -H extra
rc_is "uppercase version flag exits 0" 0 df -V
rc_is "version flag rejects positional arguments" 1 df -V extra
help_output="$(df help)"
grep -q -- '--symlink' <<<"$help_output" && pass "help documents --symlink" ||
    fail "help omits --symlink"
grep -qF -- '-h, -H, --help' <<<"$help_output" && pass "help documents all help aliases" ||
    fail "help omits a help alias"
grep -qF -- '-v, -V, --version' <<<"$help_output" && pass "help documents all version aliases" ||
    fail "help omits a version alias"

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
    /bin/bash "$ROOT/dotlad" -C 2>&1 || true)"
[[ "$identity_error" == "mydots: -C needs a path" ]] &&
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
