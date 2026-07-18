# Dotlad

[![CI](https://github.com/vkarabinovych/dotlad/actions/workflows/ci.yml/badge.svg)](https://github.com/vkarabinovych/dotlad/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/vkarabinovych/dotlad)](https://github.com/vkarabinovych/dotlad/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Dotlad is a manifest-driven macOS CLI for installing packages and deploying
dotfiles from a repository. It provides one interface for inspecting state,
previewing changes, applying modules, and restoring replaced files.

![Dotlad interactive module picker showing package and configuration state](.github/assets/demo/cli.gif)

## Why Dotlad

- Preview package and config actions before changing the machine.
- Apply every module, a reusable profile, or an explicit selection.
- Run package-only or config-only workflows from the same manifests.
- Preserve machine-local JSON, TOML, and Git values with named resolvers.
- Back up replaced files automatically and restore them from the CLI or picker.
- Use the same runtime as a standalone command or a pinned Git submodule.

Dotlad deploys in one direction: project → system. The repository remains the
source of truth; Dotlad never captures live configuration back into the project.

## Requirements

Dotlad targets the stock Bash 3.2 shipped with macOS and has no TUI framework
dependency. A real terminal enables the interactive picker; `--plain` provides
a read-only state view for scripts and non-interactive shells.

Runtime dependencies are driven by each module:

- Homebrew installs declared `BREW` packages and missing `REQUIRES` commands.
- `curl` is required when an HTTPS installer must run.
- `jq`, `yq`, or `git` is required only by the corresponding merge resolver.

Declare resolver commands in `REQUIRES` so Dotlad can report or install missing
requirements before config deployment.

## Install

Install the self-contained command under `~/.local`:

```bash
git clone https://github.com/vkarabinovych/dotlad.git
cd dotlad
./install.sh
export PATH="$HOME/.local/bin:$PATH"
dotlad --version
```

Add `~/.local/bin` to your shell startup file to keep it on `PATH`. After
updating the checkout, rerun `./install.sh` to replace the managed runtime.
`./install.sh --uninstall` removes only the managed command and runtime.

Use `./install.sh --prefix /absolute/path` to select another installation
prefix. The installer refuses to overwrite an unmanaged `bin/dotlad`.

## Create a first project

A Dotlad project needs a `modules/` directory. Each module has a strict,
non-executable `module.conf` and may include a config payload:

```bash
mkdir -p "$HOME/dotfiles/modules/starship/files"

cat > "$HOME/dotfiles/modules/starship/files/starship.toml" <<'EOF'
format = "$directory$character"
EOF

cat > "$HOME/dotfiles/modules/starship/module.conf" <<'EOF'
NAME="starship"
DESC="Cross-shell prompt configuration."
ICON="★"
BREW="starship"
SOURCE="files/starship.toml"
DEST="$HOME/.config/starship.toml"
EOF
```

Inspect the project and preview the exact action before applying it:

```bash
dotlad -C "$HOME/dotfiles" --plain
dotlad -C "$HOME/dotfiles" plan starship
dotlad -C "$HOME/dotfiles" starship
```

The first two commands are read-only. The final command shows a diff, asks for
confirmation, installs the package when missing, backs up an existing
destination, and deploys the config.

Run `dotlad -C "$HOME/dotfiles"` without a command to open the picker. `-C` is
optional when the current directory is already the project root.

## Project model

```text
my-dotfiles/
├── modules/
│   └── starship/
│       ├── module.conf
│       └── files/starship.toml
└── profiles/
    └── base.conf
```

Modules may declare packages, config, or both. `SOURCE` determines deployment
semantics: a file is copied to `DEST`, while a directory is mirrored exactly.
`RESOLVER` can merge a file with its live destination using `json-merge`,
`toml-merge`, `gitconfig-merge`, or a runtime extension.

Profiles are optional named module selections with single-parent inheritance:

```bash
# profiles/base.conf
extends=""
modules="starship git nvim"
```

See [Adding or changing a module](docs/adding-a-module.md) and
[Profiles](docs/profiles.md) for the complete schemas and validation rules.

## CLI at a glance

| Command                            | Purpose                                      |
| ---------------------------------- | -------------------------------------------- |
| `dotlad`                           | Open the interactive module picker           |
| `dotlad --plain`                   | Print read-only module and backup state       |
| `dotlad <module>…`                 | Apply named modules                           |
| `dotlad profile <name>`            | Apply a profile and inherited modules         |
| `dotlad all`                       | Apply every module                            |
| `dotlad plan [target]`             | Preview actions, requirements, and blockers   |
| `dotlad --dry-run <action>`        | Plan a normal module/profile/all action       |
| `dotlad brewfile`                  | Generate a Homebrew Bundle file               |
| `dotlad backups`                   | List available restore points                 |
| `dotlad restore <name>`            | Restore a restore point                       |
| `dotlad backup delete <name>`      | Delete a restore point                        |
| `dotlad --packages-only <action>`  | Install packages without deploying config     |
| `dotlad --config-only <action>`    | Deploy config without installing packages     |

See the [CLI reference](docs/cli.md) for option scope, JSON plans, picker
controls, automation behavior, and exit statuses.

## Use as a pinned submodule

A consumer project can pin Dotlad instead of requiring a global installation:

```bash
git submodule add https://github.com/vkarabinovych/dotlad.git vendor/dotlad
git submodule update --init --recursive
```

Expose a project-local wrapper:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/vendor/dotlad/dotlad" "$@" \
    -C "$ROOT" --backup-root "$HOME/.my-dotfiles-backup"
```

The standalone command and embedded entrypoint load the same runtime code.

## Safety model

Before deployment, Dotlad validates every manifest and the complete selected
batch. Destinations must be non-overlapping strict descendants of `$HOME`, and
existing parent symlinks cannot redirect writes outside it. Source payloads
cannot contain symlinks or special filesystem entries.

File writes are atomic. Directory modules are staged and swapped as a
transaction; their destinations are exact mirrors, so stale files are backed
up and pruned. Merge resolvers retain unrelated live values while
repository-declared values win. Restore operations back up the current version
before replacing it.

Use `dotlad plan` for a read-only preflight and keep `--yes` for reviewed
automation rather than exploratory runs.

## Documentation

- [CLI reference](docs/cli.md) — commands, options, plans, and picker controls
- [Adding or changing a module](docs/adding-a-module.md) — schema and deployment semantics
- [Profiles](docs/profiles.md) — reusable selections and inheritance
- [Troubleshooting](docs/troubleshooting.md) — common setup and preflight failures
- [Architecture](docs/architecture.md) — runtime boundaries and execution flow
- [Development and releases](docs/development.md) — validation, packaging, and release process

## Development

```bash
/bin/bash scripts/check.sh
/bin/bash tests/run.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and
[SECURITY.md](SECURITY.md) for private vulnerability reporting. Release notes
are maintained in [CHANGELOG.md](CHANGELOG.md).

Released under the [MIT License](LICENSE).
