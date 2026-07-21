# CLI reference

Dotlad reads tool manifests from a project and applies their package and
configuration state to the current user's system. It detects `macos` or
`linux` from the host and excludes tools whose `PLATFORMS` do not match.

## Invocation

Run Dotlad from the project root or select a project explicitly:

```bash
dotlad [OPTIONS] [COMMAND | TOOL…]
dotlad -C /path/to/project [OPTIONS] [COMMAND | TOOL…]
```

Options may appear before or after positional arguments. `-C` and
`--backup-root` are resolved before the runtime loads; all commands therefore
use the selected project and backup location consistently.

## Commands

| Command                       | Behavior                                                 |
| ----------------------------- | -------------------------------------------------------- |
| `dotlad`                      | Open the picker, or print state when no TTY is available |
| `dotlad <tool>…`              | Preview and apply one or more named tools                |
| `dotlad profile <name>`       | Apply a profile after resolving inherited tools          |
| `dotlad all`                  | Apply every tool relevant to the active mode             |
| `dotlad plan [target]`        | Produce a read-only plan; the default target is `all`    |
| `dotlad brewfile`             | Generate a Homebrew Bundle file                          |
| `dotlad backups`              | List restore points                                      |
| `dotlad restore <name>`       | Restore every differing entry in a restore point         |
| `dotlad backup delete <name>` | Permanently delete a restore point                       |
| `dotlad version`              | Print the installed version                              |
| `dotlad help`                 | Print built-in help                                      |

`-h`/`-H`/`--help` and `-v`/`-V`/`--version` are equivalent to the
corresponding commands.

## Options

| Option                  | Scope                   | Behavior                                           |
| ----------------------- | ----------------------- | -------------------------------------------------- |
| `-C`, `--config PATH`   | all project commands    | Use `PATH` as the project root instead of `$PWD`   |
| `--backup-root PATH`    | config and backup tasks | Use `PATH` instead of `~/.dotlad_backup`           |
| `--plain`               | display                 | Disable color and the interactive screen           |
| `--yes`                 | mutating commands       | Accept confirmation prompts                        |
| `--packages-only`       | tool/profile/all/plan   | Include package actions and omit config actions    |
| `--config-only`         | tool/profile/all/plan   | Include config actions and omit package actions    |
| `--symlink`             | tool/profile/all/plan   | Default omitted config resolvers to `symlink`      |
| `--dry-run`             | tool/profile/all        | Convert the requested action into a read-only plan |
| `--json`                | `plan` or `--dry-run`   | Emit the plan as JSON                              |
| `--output PATH`         | `brewfile` only         | Write somewhere other than `./Brewfile`            |
| `-h`, `-H`, `--help`    | global                  | Print built-in help                                |
| `-v`, `-V`, `--version` | global                  | Print the installed version                        |

The two operation-mode flags are mutually exclusive in effect: if both are
present, the last one wins. Prefer passing only one so automation is obvious.
`--symlink` is independent of operation mode: it changes only config sections
that omit `RESOLVER`; an explicit section resolver always takes precedence.
`--plain` is only a presentation flag: with no command it selects the read-only
state view, but it does not make a named tool/profile/all action read-only.
Use `plan` or `--dry-run` for that guarantee. Options such as `--output` and
`--json` are rejected outside their documented command scope.

## Inspect and plan

`dotlad --plain` prints the same tool and restore-point state as the picker
without changing anything. With no command, Dotlad also chooses this view
automatically when stdin or stdout is not a terminal.

`plan` performs the execution preflight and reports package/config actions,
directory change counts, missing requirements, and blockers:

```bash
dotlad plan
dotlad plan starship git
dotlad plan profile base --config-only
dotlad --dry-run all
dotlad --dry-run --json profile base
```

Valid plan targets are `all`, `profile NAME`, or one or more tool names.
`dotlad plan` with no target means all tools relevant to the active mode.

Human plans use these package states:

- `install` — the declared installed state is missing;
- `already installed` — `CHECK` and every declared package are present; and
- `skipped by mode` — packages exist in the manifest but config-only mode is active.

Config states are `create`, `update`, `already up to date`, or `skipped by
mode`. Copy plans count files to sync or remove; symlink plans report the link
that will be synchronized.

### JSON plans

JSON output contains the active `platform`, `mode`, and a `tools` array. Each
tool reports:

| Field                  | Meaning                                         |
| ---------------------- | ----------------------------------------------- |
| `name`                 | Manifest name                                   |
| `packages`             | `none`, `ready`, `install`, or `skipped`        |
| `package_names`        | Space-separated Homebrew entries, when declared |
| `install_url`          | HTTPS installer URL, when declared              |
| `configs`              | One object for every named config section       |
| `missing_requirements` | Commands required by config processing          |
| `blockers`             | Conditions that would prevent execution         |

Every `configs` entry reports:

| Field         | Meaning                                                       |
| ------------- | ------------------------------------------------------------- |
| `name`        | Config section name                                           |
| `state`       | `ready`, `create`, `update`, or `skipped`                     |
| `resolver`    | Effective resolver after applying CLI defaults                |
| `destination` | Expanded destination path                                     |
| `changes`     | Human-readable change summary; empty when no action is needed |

For example, reject a reviewed automation step when any tool is blocked:

```bash
plan="$(dotlad -C "$HOME/dotfiles" plan --json profile base)"
printf '%s\n' "$plan" | jq -e '[.tools[].blockers[]] | length == 0'
```

A successfully generated plan exits zero even when it reports blockers. This
lets callers inspect the complete batch; automation that requires an executable
plan must check `blockers`. Invalid options, targets, or manifests exit
non-zero.

## Apply tools and profiles

Direct tool actions show their diffs and ask once before applying the batch:

```bash
dotlad starship git
dotlad profile base
dotlad all
```

Foreground execution preflights the complete selection before changing the
first tool. The picker does the same before appending work to its serialized
queue. A blocker in a later tool therefore prevents an earlier tool from
partially applying.

In full mode, Dotlad can install missing resolver-owned and manifest
`REQUIRES` entries through Homebrew before processing config. Config-only mode
never installs them and instead reports them as blockers. An `INSTALL_URL` tool
downloads its script to a temporary file and asks for confirmation unless
`--yes` is active. When the manifest declares `INSTALL_SHA256`, the downloaded
file must match that digest before it can execute.

## Operation modes

The default mode handles packages and config. Use `--packages-only` to omit
config or `--config-only` to omit packages:

```bash
dotlad --packages-only profile base
dotlad --config-only starship
```

Tools with no applicable action are hidden from the picker and excluded from
`all` and profiles. Naming an irrelevant tool directly is an error. Press `m`
in the picker to cycle through the same three modes.

Platform filtering happens before operation-mode filtering. A tool omitted
from the current host by `PLATFORMS` is also excluded from plans and reports a
platform-specific error when named explicitly.

## Restore points

Replaced files are stored under `~/.dotlad_backup` by default. Restore points
can be inspected in the picker or managed directly:

```bash
dotlad backups
dotlad restore 20260718_120000
dotlad backup delete 20260718_120000
```

Restore and delete require confirmation unless `--yes` is active. Restore
first backs up the current versions, which makes the operation reversible. A
partial restore exits non-zero and reports restored and failed entry counts.
Restore-point counts and file lists include only entries that differ from the
current filesystem. Directory-layout changes are counted separately so a
snapshot containing only empty directories remains restorable. Identical
files, symlinks, and physical directory nodes are skipped during restore.

## Picker states

| Symbol | State                      | Meaning                                                    |
| :----: | -------------------------- | ---------------------------------------------------------- |
|  `✓`   | up to date / installed     | Config matches the project or all packages are present     |
|  `↑`   | update available           | Applying the tool would change its config                  |
|  `+`   | not set up / not installed | Config or packages are missing                             |
|  `!`   | tool not found             | Config exists, but no installer or executable is available |
|  `✗`   | failed                     | The latest queued operation failed                         |

In full mode, a missing package or executable takes priority over a ready
config. The config state remains visible as a secondary coloured note.

Pressing `Enter` on a tool asks for confirmation before anything is added to
the apply queue. The prompt lists only actions supported by the selected tools,
so package-only and config-only selections are described accurately. Cancelling
preserves the current selection.

## Keyboard controls

| Key                       | Action                                                   |
| ------------------------- | -------------------------------------------------------- |
| `↑` / `↓`, `j` / `k`      | Move in the tree, or scroll focused live output          |
| `Home` / `End`, `g` / `G` | Jump to the first or last item                           |
| `Space`                   | Select or deselect a tool                                |
| `Enter`                   | Confirm and apply selected tools, retry, or restore      |
| `a`                       | Select or clear all tools                                |
| `m`                       | Switch package/config operation mode                     |
| `d`                       | Show a config diff, operation log, or backup preview     |
| `Tab`                     | Move focus between the tool tree and live output         |
| `x`                       | Delete the focused restore point after confirmation      |
| `q`                       | Quit; active work must be confirmed before it is stopped |

Letter shortcuts are case-insensitive except for the distinct `g`/`G` jump
directions. The picker normalizes the full Ukrainian layout by physical key,
so shortcuts work without switching layouts; confirmation accepts `y`/`Y` and
`н`/`Н`.

A focused restore point fits its changed-entry list to the available tree
height and reports how many entries remain. Press `d` to inspect the complete
paged restore diff.

The live apply log shrinks to its content and grows up to one third of the
available terminal height. Focusing it with `Tab` raises that limit to two
thirds. At least four rows remain visible for the tool tree.

When embedding the runtime, set `DOTLAD_COMMAND_NAME` to the wrapper's shell
command. Usage, errors, and command hints use that value. Set
`DOTLAD_DISPLAY_NAME` for the human-readable brand used by help headings,
version output, the interactive title, and generated-file attribution. It
defaults to `DOTLAD_COMMAND_NAME`.

```bash
export DOTLAD_COMMAND_NAME="my-dotfiles"
export DOTLAD_DISPLAY_NAME="My Dotfiles"
```

## Generate a Brewfile

`brewfile` validates all project manifests and writes the active platform's
formulae, casks, and third-party taps without installing anything:

```bash
cd "$HOME/dotfiles"
dotlad brewfile
dotlad brewfile --output packaging/Brewfile
dotlad -C "$HOME/dotfiles" brewfile
```

The first and third examples write `Brewfile` in the shell's current working
directory. Relative `--output` paths are also resolved from the current working
directory, not the selected project root. Change package declarations in
`tools/*/tool.conf` instead of editing generated output.

## Automation and exit status

Mutating commands refuse to prompt when stdin is not a terminal. Pass `--yes`
only after reviewing `plan`; it accepts package, remote-installer, restore, and
delete confirmations.

Dotlad exits zero after a completed command and after cancellation at a
top-level confirmation. It exits non-zero for invalid input, unsafe manifests,
preflight blockers, failed or skipped per-tool installation/deployment, and
partial restore. As noted above, a valid plan uses its `blockers` data rather
than its process status to describe executability.

An operation mode with no relevant tools also exits non-zero instead of
prompting for an empty apply.
