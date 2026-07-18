# Architecture

Dotlad separates trusted installer code from the project that owns package
metadata and configuration payloads. That boundary lets one runtime serve many
projects without executing their manifests as shell code.

## Runtime and project roots

```text
DOTLAD_RUNTIME_ROOT/
├── VERSION
├── dotlad
├── bin/dotlad
└── lib/

DOTLAD_PROJECT_ROOT/
├── tools/<name>/tool.conf
├── tools/<name>/<payload>
└── profiles/<name>.conf
```

The root `dotlad` file is a stable repository/submodule entrypoint.
`bin/dotlad` resolves the runtime from its own location and selects the project
from `-C`, `--config`, or the current working directory. Resolver files always
come from the runtime; manifests, profiles, and config payloads always come
from the selected project.

The standalone installer copies the runtime to `<prefix>/libexec/dotlad` and
creates `<prefix>/bin/dotlad` as a managed launcher. The launcher resolves its
runtime relative to the prefix, so standalone and submodule commands execute
the same implementation.

Release archives are complete source bundles containing the runtime,
documentation, maintainer scripts, and isolated tests.

## Component map

`lib/runtime.sh` is the canonical loader for both production and test
probes. It sources libraries in dependency order:

```text
ui → resolvers → manifest → brewfile → packages → backup → engine
   → plan → picker model → runner → commands → TUI
```

| Component      | Responsibility                                                    |
| -------------- | ----------------------------------------------------------------- |
| `bin/dotlad`   | Bootstrap, global option extraction, argument parsing, dispatch   |
| `manifest.sh`  | Strict manifest/profile parsing, normalization, safety validation |
| `resolvers.sh` | Load and dispatch trusted runtime resolver implementations        |
| `packages.sh`  | Package, remote-installer, and requirement installation           |
| `backup.sh`    | Restore-point creation, listing, restoration, and deletion        |
| `engine.sh`    | State inspection, preflight, config transactions, synchronization |
| `plan.sh`      | Human and JSON projections of canonical preflight state           |
| `pick.sh`      | Presentation model shared by plain output and the TUI             |
| `runner.sh`    | Foreground batches and the serialized TUI queue                   |
| `commands.sh`  | Command implementations and tool selection                        |
| `tui.sh`       | Terminal input, rendering, focus, details, and live output        |

`commands.sh` and the TUI depend on lower layers; lower layers do not call into
presentation code. This keeps read-only probes and non-interactive commands
independent of terminal state.

## Manifest model and trust boundary

`manifest_load` parses every `tool.conf` through a field allowlist and a
strict assignment reader. Project files are data: they cannot source files,
run substitutions, or define executable hooks. Parsed values are normalized
into parallel `T_*` arrays ordered by numeric `ORDER` and then `NAME`.

A tool may declare packages, config, or both. No `SOURCE`/`DEST` pair means
package-only. Otherwise, the manifest normalizes an omitted `RESOLVER` to the
built-in `copy` resolver, or to `symlink` when the CLI exports that invocation
default. Explicit manifest values always win, and the worker inherits the
resolved default through the `DOTLAD_` environment contract.

`RESOLVER` is the deliberate extension boundary. A resolver is trusted runtime
code under `lib/resolvers/`, not code loaded from the project. Every resolver
implements semantic `equal` plus `apply` or `render`. The dispatcher supplies
shared fallbacks for render-based file resolvers, while deployment resolvers
own source support, preflight, apply, preview, and change-summary hooks. The
engine contains no copy-, link-, or format-specific selection branches.

Profiles use the same assignment reader with a smaller allowlist. Parent
profiles resolve recursively, and tools are deduplicated in declaration
order.

## State and preflight

Package and config state are tracked independently:

```text
package: installed | missing | not applicable
config:  ready | update | new | package-only | skipped
```

The active mode filters which side is relevant. State is semantic: a resolver
destination is ready when applying the repository overlay would make no
change, not necessarily when its bytes equal the repository file.

`preflight_inspect` produces the canonical read-only result for one tool. It
checks installed state, requirements, resolver renderability, destination
shape, and backup safety. Plans project this result; foreground batches and TUI
queueing enforce it. A full selection is preflighted before its first mutation.

```text
parse selection
      ↓
load and validate every manifest
      ↓
preflight complete selected batch
      ↓
install requirements/packages → deploy config → report result
```

Plans intentionally report all blockers as data. Execution converts those
blockers into a failed batch before any selected tool changes state.

## Deployment transactions

Destinations must be non-overlapping strict descendants of `$HOME`. Existing
parent symlinks are rejected, and source payloads may contain only real regular
files and directories.

For a rendered file deployment, Dotlad:

1. renders a resolver result when configured;
2. lazily creates one restore point for the run;
3. backs up an existing destination;
4. writes a sibling temporary file; and
5. atomically renames it over the destination.

For a directory deployment, Dotlad computes changed and stale leaves from the
same shared comparison helpers used by state and plan output. It backs up those
leaves, builds a complete sibling staging tree, and swaps the destination with
two renames. Signal/error rollback restores the previous tree during the swap
window. Empty source directories are preserved and stale destination entries
are pruned.

For a symlink deployment, Dotlad builds an absolute link in a sibling staging
directory, backs up the destination, and uses the same two-rename transaction
to swap the link into place. A directory destination is backed up leaf by leaf;
restore removes the managed parent link before rebuilding those leaves.

Restore follows the same safety direction: before an older version replaces a
current path, the current version is added to a new restore point.

## Interactive runtime

The TUI scans expensive tool state into a cache and rebuilds presentation
rows only when state changes. Cursor movement does not rerun filesystem or
resolver comparisons.

Selected work is appended to a per-session queue guarded by a short directory
lock. One detached worker process drains the queue serially so Homebrew and
config transactions never contend. The worker re-enters the same command with
the runtime root, project root, mode, and backup root exported explicitly.

Marker, result, stage, and log files under `DOTLAD_RUNDIR` drive live updates.
They are session-temporary coordination state, not project data.

## Test boundary

The integration suite creates a temporary project root, HOME, application
directory, and Homebrew prefix. A small orchestrator owns the fixture and
sources ordered cases for CLI/modes, engine/backups, manifest safety, and
guards.

Tests assert semantic state, filesystem effects, transactions, rollback,
resolvers, profiles, worker behavior, and exit codes. They never import or
modify a maintainer's live dotfiles. Runtime probes source
`lib/runtime.sh` unless they intentionally isolate one lower-level
component.
