# Adding or changing a tool

A tool is the smallest independently selectable unit in a Dotlad project. It
owns package metadata, an optional config payload, and the rules Dotlad uses to
recognize installed state.

## Choose the tool boundary

Create an individual tool when an application or command:

- deploys its own configuration;
- should be selected independently;
- has its own installation method or lifecycle; or
- represents a distinct ecosystem tool.

Use a package group only when its packages have no repository-managed config
and users would naturally install them together. Prefer focused names such as
`search-tools` or `data-tools`; split a group when its description needs more
than one purpose.

## Directory structure

```text
tools/example/
├── tool.conf
└── files/
    └── config.toml
```

Only `tool.conf` is always required. A config tool also needs the file or
directory named by `SOURCE`. Dotlad ignores other tool-local paths, so a
consumer project may add its own notes or tests without affecting runtime
loading.

## Manifest fields

```bash
NAME="example"
DESC="Short user-facing description of the tool and its value."
ICON="◆"
ORDER="500"
BREW="example"
CASK="0"
CHECK="example"
SOURCE="files/config.toml"
DEST="$HOME/.config/example/config.toml"
RESOLVER="toml"
```

| Field            | Required    | Meaning                                                                  |
| ---------------- | ----------- | ------------------------------------------------------------------------ |
| `NAME`           | yes         | Lowercase hyphenated identifier; must match the tool directory           |
| `DESC`           | yes         | Concise user-facing description shown in the picker                      |
| `ICON`           | yes         | Short glyph shown in the picker                                          |
| `ORDER`          | no          | Numeric manifest and batch order; defaults to `500`                      |
| `BREW`           | no          | Space-separated Homebrew formula or cask names                           |
| `CASK`           | no          | `1` when every `BREW` item is a cask; defaults to `0`                    |
| `CHECK`          | no          | Command or absolute path used to verify installation; defaults to `NAME` |
| `SOURCE`         | with config | File or directory path relative to the tool directory                    |
| `DEST`           | with config | Destination strictly below `$HOME`                                       |
| `RESOLVER`       | no          | Built-in deployment resolver; defaults to `copy`                         |
| `REQUIRES`       | no          | Additional commands needed before config deployment                      |
| `INSTALL_URL`    | no          | Whitespace-free HTTPS script installer used instead of `BREW`            |
| `INSTALL_SHA256` | no          | Optional 64-character SHA-256 digest for the downloaded installer        |

`BREW` and `INSTALL_URL` are mutually exclusive. A tool must declare at least
one package installer or a `SOURCE`/`DEST` pair. Package tokens may use fully
qualified names such as `owner/tap/formula`.

`tool.conf` is parsed as data and never executed as Bash. Only the documented
uppercase fields are accepted. Values may be double quoted, single quoted, or
unquoted when they contain no whitespace. Blank lines and full-line comments
are allowed. Duplicate or unknown fields, command substitutions, and backticks
are rejected. Values are always treated as text; `$HOME` and `${HOME}` are
expanded only in `DEST` and `CHECK`.

## Package state

`CHECK` is the primary installation probe. It may be a command name resolved
through `PATH` or an absolute filesystem path:

```bash
CHECK="starship"
CHECK="$HOME/.local/bin/example"
CHECK="/Applications/Example.app"
```

For Homebrew tools, Dotlad also verifies every declared formula under
Homebrew's `opt` directory or every cask under `Caskroom`. Installation is
reported as successful only when both `CHECK` and all declared packages are
present. Choose a `CHECK` that the installer makes available immediately.

### Formulae and casks

All entries in one tool use the same Homebrew kind:

```bash
BREW="fd ripgrep"
CASK="0"
```

```bash
BREW="ghostty font-example-nerd-font"
CASK="1"
CHECK="/Applications/Ghostty.app"
```

Split formulae and casks into separate tools when they cannot share one
`CASK` value.

### HTTPS installer

Use `INSTALL_URL` only when Homebrew is not an appropriate source:

```bash
CHECK="example"
INSTALL_URL="https://example.com/install.sh"
INSTALL_SHA256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
SOURCE="files/config.toml"
DEST="$HOME/.config/example/config.toml"
```

Dotlad downloads the script to a temporary file and asks for confirmation
unless `--yes` is active. When `INSTALL_SHA256` is present, the script runs
only after `shasum` verifies its contents. The URL must use HTTPS and the
digest must contain exactly 64 hexadecimal characters. Pin a digest whenever
the publisher provides an immutable installer artifact.

## Config deployment

`SOURCE` and `DEST` are always declared together. `RESOLVER` defaults to
`copy`, which copies a regular file or mirrors a directory exactly. A tool
without either field is package-only.

Passing `--symlink` changes the invocation-wide default to `symlink` for
tools that omit `RESOLVER`. Declare `RESOLVER="copy"` explicitly when a
tool must always copy even under that flag.

### Exact file copy

Use a file source when the live file should match the repository byte for byte:

```bash
SOURCE="files/config.toml"
DEST="$HOME/.config/example/config.toml"
```

An existing destination is backed up, and the replacement preserves the source
file mode.

### Exact directory mirror

Point `SOURCE` at a directory for an owned config tree:

```bash
SOURCE="files"
DEST="$HOME/.config/example"
```

The destination becomes an exact mirror: changed files are replaced, missing
files and empty directories are created, stale leaves are backed up, and stale
directories are removed. Do not mirror a directory shared with another tool
or application.

### Repository symlink

Use `symlink` when an application should read the repository source directly:

```bash
SOURCE="files/config.toml"
DEST="$HOME/.config/example/config.toml"
RESOLVER="symlink"
```

Both regular files and directories are supported. Dotlad creates an absolute
symlink to `SOURCE`, so moving or removing the project makes the deployed link
invalid until the tool is applied again from its new location. Existing
destination files, symlinks, and directory contents are backed up before the
link is swapped into place.

### Machine-local merge

Set `RESOLVER` when repository defaults must coexist with machine-local keys:

```bash
RESOLVER="json"
```

Built-in resolvers define both deployment and semantic equality:

| Resolver    | Source         | Requirement | Behavior                                                       |
| ----------- | -------------- | ----------- | -------------------------------------------------------------- |
| `copy`      | file/directory | none        | Exact file copy or exact directory mirror; the default         |
| `symlink`   | file/directory | none        | Absolute link from the destination to the repository source    |
| `json`      | file           | `jq`        | Recursive object merge and array union; repository scalars win |
| `toml`      | file           | `yq`        | Deep merge with repository values taking precedence            |
| `gitconfig` | file           | `git`       | Repository keys win while unrelated live keys remain           |

An explicitly declared JSON `null` is an overlay value and replaces the live
value. JSON array entries already present in the live file are retained; new
repository entries are appended.

Each resolver lives in `lib/resolvers/<name>.sh` and implements semantic
`equal` plus either `apply` or `render`, with hyphens converted to underscores.
Deployment resolvers may also define source support, preflight, preview, change
summary, action, and command-requirement hooks. A resolver is runtime code, not
project code; adding one requires shipping an updated Dotlad runtime.

Built-in resolvers declare the commands in the table automatically. Every
additional `REQUIRES` token is checked as a command name and, when missing in
full mode, installed as a Homebrew formula of the same name. Duplicate
resolver and manifest requirements are installed once. The field cannot map a
formula name to a differently named executable; preinstall that dependency or
avoid declaring an inaccurate requirement.

## Package-only tool

Omit `SOURCE`, `DEST`, and `RESOLVER` when a tool deploys no config:

```bash
NAME="search-tools"
DESC="Fast file and text search with fd and ripgrep."
ICON="⌕"
ORDER="200"
CHECK="fd"
BREW="fd ripgrep"
```

`CHECK` should represent the group clearly; every Homebrew entry is still
verified independently.

## Naming and ordering

- Use the public command or application name for individual tools.
- Use plural `<purpose>-tools` names for coherent package groups.
- Keep `DESC` to one sentence that explains value rather than installation.
- Choose an `ICON` that renders clearly in one terminal cell. Nerd Font icons
  are fine when the consumer project documents that font requirement.
- Use numeric gaps in `ORDER` so future tools can be inserted without a
  renumbering sweep. The picker may regroup tools by state.

## Add the tool to a profile

Profiles belong to the consumer project, so Dotlad does not prescribe names
such as `core` or `full`. Add the tool once to the lowest-level profile whose
users should receive it; inheritance supplies it to child profiles. See
[Profiles](profiles.md).

## Validate the change

Start with read-only project validation and planning:

```bash
dotlad -C /path/to/project --plain
dotlad -C /path/to/project plan example
dotlad -C /path/to/project brewfile
```

For changes to Dotlad itself, also run:

```bash
/bin/bash scripts/check.sh
/bin/bash tests/run.sh
```

Add or extend integration coverage when changing a manifest rule, resolver,
installed-state check, backup behavior, or installer path.

## Manifest safety rules

Loading fails before deployment when:

- required presentation metadata is missing;
- a tool declares neither packages nor deployable configuration;
- `NAME` does not match its directory;
- `SOURCE` and `DEST` are not declared together;
- a resolver is unknown or does not support the declared source type;
- a source path or payload contains symlinks or special filesystem entries;
- a destination is `$HOME`, escapes it, traverses a parent symlink, or overlaps
  another tool destination;
- a package token or installer URL is malformed; or
- Homebrew and an HTTPS installer are both declared.

See [Troubleshooting](troubleshooting.md) for common validation and preflight
failures.
