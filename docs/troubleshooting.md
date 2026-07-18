# Troubleshooting

Start with the read-only state view and plan. They usually identify whether a
problem is project selection, manifest validation, installed-state detection,
or execution preflight:

```bash
dotlad -C /path/to/project --plain
dotlad -C /path/to/project plan
dotlad -C /path/to/project plan --json
```

## `no modules/ directory`

Dotlad is using the wrong project root. Run it from the directory that owns
`modules/`, or pass that directory explicitly:

```bash
dotlad -C "$HOME/dotfiles" --plain
```

The standalone installation contains only the runtime; it does not create or
embed a dotfiles project.

## `dotlad: command not found`

The default installer writes `~/.local/bin/dotlad`. Add that directory to the
current shell and then persist it in the appropriate shell startup file:

```bash
export PATH="$HOME/.local/bin:$PATH"
dotlad --version
```

For a custom prefix, use its `bin/` directory instead.

## A non-interactive command refuses to run

Mutating commands require confirmation and refuse to prompt when stdin is not a
terminal. Review a plan, then opt into automation explicitly:

```bash
dotlad -C /path/to/project plan profile base
dotlad -C /path/to/project --yes profile base
```

Use `--plain` for a read-only state listing. `--plain` changes presentation; it
does not turn a named module, profile, or `all` action into a dry run. Use
`plan` or `--dry-run` for that guarantee.

## `Homebrew is required`

The selected mode includes a missing module with `BREW` packages, but `brew` is
not available. Install Homebrew, exclude package actions with `--config-only`,
or remove `BREW` only when the consumer project intentionally manages that
package elsewhere.

Interactive apply commands can offer to install Homebrew. Plans never install
it.

## `missing requirement: jq` (or `yq` / `git`)

A config resolver or other config step declares a command in `REQUIRES`.

- In the default mode, Dotlad can install a missing requirement through a
  same-named Homebrew formula.
- In `--config-only` mode, package installation is disabled and the missing
  command is a blocker.

Install the command first or run the full package + config mode. Confirm that
the `REQUIRES` token is both the executable name and the Homebrew formula name.

## A module is missing from a profile or picker

Operation modes hide modules that have no relevant action:

- `--packages-only` hides config-only modules;
- `--config-only` hides package-only modules.

Run without a mode flag or inspect the module directly in a matching mode. If
the module should be in a profile, check the resolved parent chain and ensure
the module name exactly matches its directory and `NAME`.

## A package installs but remains `not installed`

Dotlad verifies more than the installer exit code. `CHECK` must resolve to a
command or absolute path, and every `BREW` entry must exist in Homebrew's
formula or cask location.

Typical fixes are:

- set `CHECK` to the actual installed command;
- use an absolute application path for a cask without a CLI; or
- split unrelated packages when one `CHECK` cannot represent the module.

Do not weaken the check merely to hide a failed or incomplete installation.

## Config always shows `update available`

Run a plan and inspect the module diff in the picker with `d`.

- Exact file modules compare bytes.
- Directory modules compare the complete tree, including empty directories and
  stale destination entries.
- Resolver modules compare the semantic merged result.

For resolver modules, verify the declared requirement is installed and that
both repository and live documents are valid. For directory modules, remember
that the destination is exclusively owned and mirrored exactly.

## Destination validation fails

`DEST` must expand to a strict descendant of the active `$HOME`. Dotlad rejects
`$HOME` itself, `..`, duplicate separators, overlapping module destinations,
and any existing parent symlink.

Prefer a direct path such as:

```bash
DEST="$HOME/.config/example/config.toml"
```

Do not assign both a directory and a file inside it to different modules. If a
parent below `$HOME` is a symlink, choose the real in-home destination or manage
that path outside Dotlad.

## Directory deployment would remove files

A directory `SOURCE` is an exact mirror, not an overlay. Extra destination
files and symlinks are backed up and pruned. Use `dotlad plan <module>` and the
picker diff before applying.

If the application shares that directory with machine-local state, narrow the
module to individual file sources or use a file resolver where appropriate.

## Restore or delete cannot find a backup

List restore points using the same backup root used during deployment:

```bash
dotlad --backup-root "$HOME/.my-backups" backups
```

Backup names are directory timestamps exactly as printed by `backups`; the
friendly date shown in the picker is not the CLI argument. Empty or manually
renamed backup directories are ignored or rejected.

## Collect maintainer diagnostics

For a runtime checkout, capture these read-only checks before reporting a bug:

```bash
/bin/bash --version | head -1
./dotlad --version
/bin/bash scripts/check.sh --syntax-only
git status --short
```

Include the failing command, its complete error output, the relevant manifest
with secrets removed, and whether the same target appears blocked in
`plan --json`. Never attach live config containing credentials or backup
contents.
