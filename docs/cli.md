# CLI reference

Dotlad reads module manifests from a project and applies their package and
configuration state to the current user's system.

## Invocation

Run Dotlad from the project root or select a project explicitly:

```bash
dotlad [OPTIONS] [COMMAND | MODULE…]
dotlad -C /path/to/project [OPTIONS] [COMMAND | MODULE…]
```

Options may appear before or after positional arguments. `-C` and
`--backup-root` are resolved before the runtime loads; all commands therefore
use the selected project and backup location consistently.

## Commands

| Command                       | Behavior                                                   |
| ----------------------------- | ---------------------------------------------------------- |
| `dotlad`                      | Open the picker, or print state when no TTY is available   |
| `dotlad <module>…`            | Preview and apply one or more named modules                |
| `dotlad profile <name>`       | Apply a profile after resolving inherited modules          |
| `dotlad all`                  | Apply every module relevant to the active mode             |
| `dotlad plan [target]`        | Produce a read-only plan; the default target is `all`      |
| `dotlad brewfile`             | Generate a Homebrew Bundle file                            |
| `dotlad backups`              | List restore points                                        |
| `dotlad restore <name>`       | Restore all files in a restore point                       |
| `dotlad backup delete <name>` | Permanently delete a restore point                         |
| `dotlad version`              | Print the installed version                                |
| `dotlad help`                 | Print built-in help                                        |

`--help` and `--version` are equivalent to the corresponding commands.

## Options

| Option                    | Scope                    | Behavior                                                  |
| ------------------------- | ------------------------ | --------------------------------------------------------- |
| `-C`, `--config PATH`     | all project commands     | Use `PATH` as the project root instead of `$PWD`          |
| `--backup-root PATH`      | config and backup tasks  | Use `PATH` instead of `~/.dotlad_backup`                  |
| `--plain`                 | display                  | Disable color and the interactive screen                 |
| `--yes`                   | mutating commands        | Accept confirmation prompts                               |
| `--packages-only`         | module/profile/all/plan  | Include package actions and omit config actions           |
| `--config-only`           | module/profile/all/plan  | Include config actions and omit package actions           |
| `--symlink`               | module/profile/all/plan  | Default modules without `RESOLVER` to `symlink`           |
| `--dry-run`               | module/profile/all       | Convert the requested action into a read-only plan        |
| `--json`                  | `plan` or `--dry-run`    | Emit the plan as JSON                                     |
| `--output PATH`           | `brewfile` only          | Write somewhere other than `./Brewfile`                   |

The two operation-mode flags are mutually exclusive in effect: if both are
present, the last one wins. Prefer passing only one so automation is obvious.
`--symlink` is independent of operation mode: it changes only modules that omit
`RESOLVER`; an explicit resolver in a manifest always takes precedence.
`--plain` is only a presentation flag: with no command it selects the read-only
state view, but it does not make a named module/profile/all action read-only.
Use `plan` or `--dry-run` for that guarantee. Options such as `--output` and
`--json` are rejected outside their documented command scope.

## Inspect and plan

`dotlad --plain` prints the same module and restore-point state as the picker
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

Valid plan targets are `all`, `profile NAME`, or one or more module names.
`dotlad plan` with no target means all modules relevant to the active mode.

Human plans use these package states:

- `install` — the declared installed state is missing;
- `already installed` — `CHECK` and every declared package are present; and
- `skipped by mode` — packages exist in the manifest but config-only mode is active.

Config states are `create`, `update`, `already up to date`, or `skipped by
mode`. Copy plans count files to sync or remove; symlink plans report the link
that will be synchronized.

### JSON plans

JSON output contains the active `mode` and a `modules` array. Each module
reports:

| Field                  | Meaning                                              |
| ---------------------- | ---------------------------------------------------- |
| `name`                 | Manifest name                                        |
| `packages`             | `none`, `ready`, `install`, or `skipped`             |
| `package_names`        | Space-separated Homebrew entries, when declared      |
| `install_url`          | HTTPS installer URL, when declared                   |
| `config`               | `none`, `ready`, `create`, `update`, or `skipped`    |
| `resolver`             | Effective resolver after applying CLI defaults       |
| `destination`          | Expanded destination path                            |
| `changes`              | Human-readable file-change count                     |
| `missing_requirements` | Commands required by config processing               |
| `blockers`             | Conditions that would prevent execution              |

For example, reject a reviewed automation step when any module is blocked:

```bash
plan="$(dotlad -C "$HOME/dotfiles" plan --json profile base)"
printf '%s\n' "$plan" | jq -e '[.modules[].blockers[]] | length == 0'
```

A successfully generated plan exits zero even when it reports blockers. This
lets callers inspect the complete batch; automation that requires an executable
plan must check `blockers`. Invalid options, targets, or manifests exit
non-zero.

## Apply modules and profiles

Direct module actions show their diffs and ask once before applying the batch:

```bash
dotlad starship git
dotlad profile base
dotlad all
```

Foreground execution preflights the complete selection before changing the
first module. The picker does the same before appending work to its serialized
queue. A blocker in a later module therefore prevents an earlier module from
partially applying.

In full mode, Dotlad can install missing `REQUIRES` entries through Homebrew
before processing config. Config-only mode never installs them and instead
reports them as blockers. An `INSTALL_URL` module displays its exact
`curl -fsSL URL | sh` action and asks for confirmation unless `--yes` is active.

## Operation modes

The default mode handles packages and config. Use `--packages-only` to omit
config or `--config-only` to omit packages:

```bash
dotlad --packages-only profile base
dotlad --config-only starship
```

Modules with no applicable action are hidden from the picker and excluded from
`all` and profiles. Naming an irrelevant module directly is an error. Press `m`
in the picker to cycle through the same three modes.

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

## Picker states

| Symbol | State                      | Meaning                                                |
| :----: | -------------------------- | ------------------------------------------------------ |
|  `✓`   | up to date / installed     | Config matches the project or all packages are present |
|  `↑`   | update available           | Applying the module would change its config            |
|  `+`   | not set up / not installed | Config or packages are missing                         |
|  `✗`   | failed                     | The latest queued operation failed                     |

## Keyboard controls

| Key                       | Action                                                   |
| ------------------------- | -------------------------------------------------------- |
| `↑` / `↓`, `j` / `k`      | Move in the tree, or scroll focused live output          |
| `Home` / `End`, `g` / `G` | Jump to the first or last item                           |
| `Space`                   | Select or deselect a module                              |
| `Enter`                   | Apply selected modules, retry, or restore a backup       |
| `a`                       | Select or clear all modules                              |
| `m`                       | Switch package/config operation mode                     |
| `d`                       | Show a config diff, operation log, or backup preview     |
| `Tab`                     | Move focus between the module tree and live output       |
| `x`                       | Delete the focused restore point after confirmation      |
| `q`                       | Quit; active work must be confirmed before it is stopped |

Letter shortcuts also follow the same physical keys on a Ukrainian layout:
`j/о`, `k/л`, `g/п`, `G/П`, `a/ф`, `m/ь`, `d/в`, `x/ч`, `q/й`, and `y/н`
in confirmation prompts.

## Generate a Brewfile

`brewfile` validates all project manifests and writes their formulae, casks,
and third-party taps without installing anything:

```bash
cd "$HOME/dotfiles"
dotlad brewfile
dotlad brewfile --output packaging/Brewfile
dotlad -C "$HOME/dotfiles" brewfile
```

The first and third examples write `Brewfile` in the shell's current working
directory. Relative `--output` paths are also resolved from the current working
directory, not the selected project root. Change package declarations in
`modules/*/module.conf` instead of editing generated output.

## Automation and exit status

Mutating commands refuse to prompt when stdin is not a terminal. Pass `--yes`
only after reviewing `plan`; it accepts package, remote-installer, restore, and
delete confirmations.

Dotlad exits zero after a completed command and after cancellation at a
top-level confirmation. It exits non-zero for invalid input, unsafe manifests,
preflight blockers, failed or skipped per-module installation/deployment, and
partial restore. As noted above, a valid plan uses its `blockers` data rather
than its process status to describe executability.
