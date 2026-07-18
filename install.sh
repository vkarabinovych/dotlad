#!/usr/bin/env bash
# Stable entrypoint for installing the standalone command.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts/install.sh" "$@"
