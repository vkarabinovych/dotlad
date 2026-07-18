# shellcheck shell=bash
# shellcheck disable=SC2015,SC2154  # sourced integration cases share the orchestrator fixture
# --- guards -----------------------------------------------------------------
rc_is "unknown tool exits 1" 1 df nosuchtool
rc_is "unknown option exits 1" 1 df --bogus
rc_is "help rejects positional arguments" 1 df help extra
rc_is "version rejects positional arguments" 1 df version extra
rc_is "help command exits 0" 0 df help
