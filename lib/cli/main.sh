# CLI composition root. The executable entrypoint only locates and calls this.

# shellcheck source=lib/cli/bootstrap.sh
. "$DOTLAD_RUNTIME_ROOT/lib/cli/bootstrap.sh"
# shellcheck source=lib/cli/spec.sh
. "$DOTLAD_RUNTIME_ROOT/lib/cli/spec.sh"
# shellcheck source=lib/cli/presentation.sh
. "$DOTLAD_RUNTIME_ROOT/lib/cli/presentation.sh"
# shellcheck source=lib/cli/dispatch.sh
. "$DOTLAD_RUNTIME_ROOT/lib/cli/dispatch.sh"

cli_main() {
    cli_bootstrap "$@" || return $?

    # shellcheck source=lib/runtime.sh
    . "$DOTLAD_RUNTIME_ROOT/lib/runtime.sh"

    set -- "${CLI_BOOTSTRAP_ARGS[@]}"
    shift
    cli_dispatch "$@"
}
