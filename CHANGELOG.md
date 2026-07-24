# Changelog

All notable user-facing changes are documented here.

## [Unreleased]

### Breaking changes

- The project root is now passed as the first positional `PATH` (defaulting to
  the current directory); the `-C`/`--config` options have been removed.
- `--backup-root PATH` has been replaced by `--backup PATH`.

### Added

- `dotlad update` updates global curl installations to the latest verified
  release and prints the matching `brew upgrade dotlad` instruction for
  Homebrew installations.

## [0.9.0] - 2026-07-22

### Added

- A checksum-verifying curl installer installs tagged release archives on
  macOS, Linux, and WSL under the XDG-style user-local application layout.
- Homebrew distribution installs the complete runtime from tagged archives;
  global installations expose `dotlad uninstall`, and a standalone uninstaller
  safely distinguishes curl-managed and Homebrew layouts.
- `dotlad completion zsh` prints native, platform-aware Zsh completion for
  commands, options, tools, profiles, restore points, and hidden paths. Custom
  wrappers retain their command name and explicitly selected project roots.
- Installers show a ready-to-copy Zsh completion setup and report when it is
  already configured. Homebrew caveats provide the same guidance.

### Changed

- Help and Zsh completion share one command manifest. The complete CLI now
  lives in focused `lib/cli/` modules, leaving `bin/dotlad` as a thin
  executable entrypoint.

### Fixed

- Automatic colour-scheme detection no longer fails under `set -u` when a
  terminal does not export `COLORFGBG`.

## [0.8.0] - 2026-07-22

### Added

- Linux, WSL, and Linuxbrew are supported alongside macOS, with integration
  and release suites covering every platform projection.
- Tool manifests may declare `PLATFORMS="macos"`, `PLATFORMS="linux"`, or
  `PLATFORMS="wsl"`; omitted platform metadata remains `macos linux`, Linux
  tools also run on WSL, and inactive tools are excluded from selection,
  plans, profiles, and generated Brewfiles.

### Changed

- Checksum-pinned remote installers accept `sha256sum` or `shasum`, allowing
  the host platform's standard SHA-256 utility.
- The README demo follows the viewer's light or dark theme. Dotlad now adapts
  its semantic colours and TUI highlights to the terminal background, with a
  `DOTLAD_COLOR_SCHEME` override when automatic detection is unavailable.

### Fixed

- Background queue locks retain explicit process ownership, recover only locks
  left by dead processes, and clean up safely when a worker is interrupted.

## [0.7.0] - 2026-07-21

### Added

- Remote installer manifests may declare `INSTALL_SHA256`; Dotlad verifies the
  downloaded script before executing it.
- Tool manifests may declare multiple named `[config.<name>]` sections with
  independent sources, destinations, and resolvers; plans and picker activity
  expose every section separately.
- Release archives include a runnable example project with copy, mirror,
  merge, symlink, multi-config, and package-only manifests plus the `mydot`
  wrapper.
- The `inject` resolver maintains source-backed blocks inside larger local
  files, with tool/source metadata, extension-based comment detection,
  and optional custom comment delimiters.
- Resolver-specific manifest settings use generic `[config.<name>.options]`
  sections whose supported keys and validation belong to each resolver.

### Changed

- Shared CLI output now lives in `console.sh`, while TUI input, cached screen
  state, and rendering live under `lib/tui/`; worker lifecycle stays with the
  runner instead of the main event-loop implementation.
- Embedded wrappers use `DOTLAD_COMMAND_NAME` for shell invocations and
  `DOTLAD_DISPLAY_NAME` for help headings, version output, the TUI header, and
  generated-file attribution.
- Shell sources now share a checked `shfmt` profile through `.editorconfig`.
- Relative config destinations resolve from the project root while retaining
  the existing `$HOME` containment and symlink-safety checks.

### Fixed

- Restore points containing only directory-layout changes remain visible and
  restorable, while backup summaries continue to omit entries that already
  match the current filesystem.
- The `inject` resolver rejects malformed, duplicate, or cross-identity nested
  managed blocks during preflight instead of risking an incorrect replacement.
- Switching the picker to an operation mode with no relevant tools keeps a
  stable, non-actionable empty state instead of failing on a missing row.
- JSON plans escape every control character required by the JSON format.

## [0.6.0] - 2026-07-20

### Changed

- Built-in merge resolvers now declare their own `jq`, `yq`, or `git`
  requirement; manifest `REQUIRES` remains available for additional commands.
- Restore-point lists and counts exclude files and symlinks that already match
  the saved version, and restore skips those unchanged entries.
- Operation modes with no relevant tools now report an explicit error, and
  `all`, profile, and picker commands preserve failures in their exit status.
- Directory mirror plans and apply results count empty directories created or
  removed instead of reporting an unexplained update or `0 copied`.
- The picker accepts shortcut letters in either case and normalizes the full
  Ukrainian keyboard layout by physical key.
- Picker state labels use italic styling, and the header uses configurable
  application naming with updated terminal branding.
- Focused restore points fit their file list to the available picker height
  and summarize the remainder; the complete diff remains available through
  details.
- The live apply log fits its content, grows to one third of the terminal, and
  may use up to two thirds when focused while preserving space for the tree.
- The `copy` resolver can replace a previously deployed directory symlink,
  preserving the link in a restore point before materializing the directory.
- Missing packages and executables now lead picker headlines instead of being
  visually masked by an up-to-date config state.
- Applying tools from the picker now requires explicit confirmation before
  work is added to the background queue, with action text derived from the
  selected tools rather than only the global mode.

## [0.5.0] - 2026-07-18

### Added

- Built-in `symlink` resolver for deploying file and directory links to their
  repository sources.
- Global `--symlink` option for making that resolver the invocation default
  without overriding explicit tool resolvers.

### Changed

- Project entries consistently use the tool contract: `tools/<name>/tool.conf`,
  profile `tools=`, tool-oriented CLI terminology, and the JSON plan's `tools`
  array.
- Exact file copying and directory mirroring now use the explicit built-in
  `copy` resolver, which remains the default when `RESOLVER` is omitted.
- Merge resolvers now use the concise names `json`, `toml`, and `gitconfig`.

## [0.4.0] - 2026-07-18

### Added

- Interactive, plain-text, and JSON planning interfaces for manifest-driven
  package and config deployment.
- Package-only and config-only operation modes with profiles and inherited
  tool selections.
- Exact file and directory deployment with atomic writes, transactional
  directory swaps, restore points, and CLI restore management.
- JSON, TOML, and Git config resolvers that preserve unrelated machine-local
  values.
- Strict data-only manifest parsing, batch preflight, destination validation,
  and isolated integration coverage for safety contracts.
- Standalone installation, pinned-submodule usage, Brewfile generation, and
  reproducible release archives with SHA-256 checksums.

[0.4.0]: https://github.com/ter-sh/dotlad/releases/tag/v0.4.0
[0.5.0]: https://github.com/ter-sh/dotlad/releases/tag/v0.5.0
[0.6.0]: https://github.com/ter-sh/dotlad/releases/tag/v0.6.0
[0.7.0]: https://github.com/ter-sh/dotlad/releases/tag/v0.7.0
[0.8.0]: https://github.com/ter-sh/dotlad/releases/tag/v0.8.0
[Unreleased]: https://github.com/ter-sh/dotlad/compare/v0.8.0...HEAD
