# Changelog

All notable user-facing changes are documented here.

## [Unreleased]

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
[Unreleased]: https://github.com/vkarabinovych/dotlad/compare/v0.4.0...HEAD
