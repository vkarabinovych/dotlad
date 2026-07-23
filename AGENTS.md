# Repository Guidelines

## Project Structure & Tool Organization

`dotlad` is the stable entrypoint and `bin/dotlad` owns argument parsing.
`lib/runtime.sh` defines the canonical library load order. Runtime code
lives in `lib/`; each named resolver has one file under
`lib/resolvers/`. Integration fixtures are created dynamically by
`tests/integration/installer.sh`. Maintainer documentation lives in `docs/`.

## Build, Test, and Development Commands

- `/bin/bash tests/run.sh` runs the isolated engine and installed-command suites.
- `/bin/bash scripts/check.sh` runs syntax, ShellCheck, and whitespace checks.
- `/bin/bash scripts/check.sh --syntax-only` checks the same files without linting.
- `scripts/package.sh` builds the versioned release archive and checksum.
- `dotlad /path/to/project brewfile` regenerates a consumer's Homebrew Bundle metadata.

## Coding Style & Naming Conventions

Use four-space indentation, quote expansions unless splitting is intentional,
and keep shared code ShellCheck-clean. Public environment variables use the
`DOTLAD_` prefix. Resolver names use lowercase hyphenated identifiers and map to
`resolver_<name>_<method>` hooks. Every resolver implements `equal` plus either
`apply` or `render`; deployment resolvers may implement the optional contract
hooks documented in `docs/adding-a-tool.md`.

## Testing Guidelines

Tests must use a temporary project root, HOME, and package prefix. Do not depend
on a maintainer's dotfiles or modify live configuration. Cover semantic state,
filesystem effects, and exit codes rather than complete coloured output. Add a
regression case for every manifest, resolver, worker, or safety contract change.

## Commit & Pull Request Guidelines

Use concise Conventional Commit subjects such as `feat(cli): add project-root
selection`. Keep commits focused. Pull requests should describe user-visible
behavior, compatibility impact, validation performed, and any project contract
changes.

## Safety & Configuration

Dotlad writes from a project into `$HOME` and can prune mirrored directories.
Keep destination validation, atomic writes, backups, and fake-HOME coverage
intact. Never commit credentials, backup directories, or test artifacts.
