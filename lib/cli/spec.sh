# shellcheck disable=SC2034  # parallel arrays are consumed by CLI presentation
# Canonical command and option names, help usage, aliases, and descriptions.

CLI_COMMAND_NAMES=(
    "" "" profile all brewfile plan backups restore backup completion uninstall version help
)
CLI_COMMAND_USAGE=(
    ""
    "<tool>…"
    "profile NAME"
    "all"
    "brewfile"
    "plan [TARGET]"
    "backups"
    "restore NAME"
    "backup delete NAME"
    "completion zsh"
    "uninstall"
    "version"
    "help"
)
CLI_COMMAND_DESCRIPTIONS=(
    "Pick tools interactively (plain state without a TTY)"
    "Preview and apply named tools"
    "Apply a named profile and its inherited tools"
    "Apply every tool relevant to the active mode"
    "Generate a Homebrew Bundle file from the project"
    "Show a read-only plan (all, profile NAME, or tool names)"
    "List restore points"
    "Restore a restore point"
    "Delete a restore point"
    "Print native Zsh completion"
    "Remove the global installation"
    "Print the installed version"
    "Print this help"
)

CLI_OPTION_NAMES=(
    config backup-root output packages-only config-only symlink dry-run json yes plain help version
)
CLI_OPTION_USAGE=(
    "-C, --config PATH"
    "--backup-root PATH"
    "--output PATH"
    "--packages-only"
    "--config-only"
    "--symlink"
    "--dry-run"
    "--json"
    "--yes"
    "--plain"
    "-h, -H, --help"
    "-v, -V, --version"
)
CLI_OPTION_ALIASES=(
    "-C --config --config="
    "--backup-root --backup-root="
    "--output --output="
    "--packages-only"
    "--config-only"
    "--symlink"
    "--dry-run"
    "--json"
    "--yes"
    "--plain"
    "-h -H --help"
    "-v -V --version"
)
CLI_OPTION_DESCRIPTIONS=(
    "select the manifest project (defaults to current directory)"
    "select the backup location (defaults to ~/.dotlad_backup)"
    "select the generated Brewfile path (defaults to ./Brewfile)"
    "install packages without deploying config"
    "deploy config without installing packages"
    "default omitted resolvers to symlink"
    "plan the requested action without changing state"
    "emit JSON with plan or --dry-run"
    "accept mutation confirmation prompts"
    "disable color and the interactive screen"
    "print help"
    "print the installed version"
)
