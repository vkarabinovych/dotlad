#!/usr/bin/env bash
# Stable entrypoint for dotlad's integration suite.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/bin/bash "$ROOT/tests/integration/installer.sh"
/bin/bash "$ROOT/tests/integration/install.sh"
