# Changelog

All notable user-facing changes are documented here.

## [Unreleased]

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

[0.4.0]: https://github.com/vkarabinovych/dotlad/releases/tag/v0.4.0
[0.5.0]: https://github.com/vkarabinovych/dotlad/releases/tag/v0.5.0
[0.6.0]: https://github.com/vkarabinovych/dotlad/releases/tag/v0.6.0
[Unreleased]: https://github.com/vkarabinovych/dotlad/compare/v0.6.0...HEAD
