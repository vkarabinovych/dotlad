# lib/runtime.sh — canonical runtime load order for CLI and test probes.

# shellcheck source=lib/console.sh
. "$DOTLAD_RUNTIME_ROOT/lib/console.sh"
# shellcheck source=lib/resolvers.sh
. "$DOTLAD_RUNTIME_ROOT/lib/resolvers.sh"
# shellcheck source=lib/manifest.sh
. "$DOTLAD_RUNTIME_ROOT/lib/manifest.sh"
# shellcheck source=lib/brewfile.sh
. "$DOTLAD_RUNTIME_ROOT/lib/brewfile.sh"
# shellcheck source=lib/packages.sh
. "$DOTLAD_RUNTIME_ROOT/lib/packages.sh"
# shellcheck source=lib/backup.sh
. "$DOTLAD_RUNTIME_ROOT/lib/backup.sh"
# shellcheck source=lib/engine.sh
. "$DOTLAD_RUNTIME_ROOT/lib/engine.sh"
# shellcheck source=lib/plan.sh
. "$DOTLAD_RUNTIME_ROOT/lib/plan.sh"
# shellcheck source=lib/pick.sh
. "$DOTLAD_RUNTIME_ROOT/lib/pick.sh"
# shellcheck source=lib/runner.sh
. "$DOTLAD_RUNTIME_ROOT/lib/runner.sh"
# shellcheck source=lib/commands.sh
. "$DOTLAD_RUNTIME_ROOT/lib/commands.sh"
# shellcheck source=lib/tui.sh
. "$DOTLAD_RUNTIME_ROOT/lib/tui.sh"
