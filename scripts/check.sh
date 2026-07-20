#!/usr/bin/env bash
# Canonical local/CI source validation. Runs on macOS Bash 3.2.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SOURCES=(
    dotlad install.sh bin/dotlad
    .github/assets/demo/setup.sh
    scripts/*.sh
    lib/*.sh lib/resolvers/*.sh lib/tui/*.sh
    tests/run.sh tests/integration/*.sh tests/integration/cases/*.sh
)

bash -n "${SOURCES[@]}"
[[ "${1:-}" == --syntax-only ]] && exit 0
[[ $# -eq 0 ]] || {
    printf 'Usage: %s [--syntax-only]\n' "$0" >&2
    exit 1
}

shellcheck -s bash "${SOURCES[@]}"
command -v shfmt >/dev/null 2>&1 ||
    {
        printf 'shfmt is required for source formatting checks.\n' >&2
        exit 1
    }
shfmt -d .
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git diff --check
else
    printf 'Skipping git diff --check outside a Git worktree.\n'
fi
