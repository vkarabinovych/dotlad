# Development and releases

## Requirements

Dotlad targets macOS Bash 3.2. Maintainer validation additionally uses
ShellCheck, jq, yq, Git, and standard archive/checksum tools. Run compatibility
tests with `/bin/bash`; a newer interactive Bash can hide 3.2 regressions.

## Standard validation

Run the source checks and isolated integration suite from the repository root:

```bash
/bin/bash scripts/check.sh
/bin/bash tests/run.sh
```

`scripts/check.sh` runs Bash syntax checks across every shell source,
ShellCheck with the Bash dialect, and `git diff --check`. Pass
`--syntax-only` when ShellCheck is unavailable and only parser compatibility is
being investigated.

`tests/run.sh` creates its own project root, HOME, application directory, and
package prefix. `tests/integration/installer.sh` owns the shared fixture and
sources ordered files under `tests/integration/cases/`. The suite must never
read or change a maintainer's live dotfiles.

Runtime probes should source `lib/runtime.sh` when they exercise multiple
layers. Source an individual library only for a deliberately isolated probe;
this keeps production and test load order aligned.

## Where changes belong

| Change                           | Primary location                 |
| -------------------------------- | -------------------------------- |
| CLI parsing or dispatch          | `bin/dotlad`                     |
| Command behavior and selections  | `lib/commands.sh`                |
| Manifest or profile contracts    | `lib/manifest.sh`                |
| Package/requirement installation | `lib/packages.sh`                |
| State, preflight, config writes  | `lib/engine.sh`                  |
| Restore-point behavior           | `lib/backup.sh`                  |
| Human or JSON plans              | `lib/plan.sh`                    |
| Plain/picker presentation model  | `lib/pick.sh`                    |
| Foreground and queued execution  | `lib/runner.sh`                  |
| Terminal interaction             | `lib/tui.sh`                     |
| Deployment and semantic resolving | `lib/resolvers/<name>.sh`       |
| Integration regression coverage  | `tests/integration/cases/*.sh`   |

Keep `lib/runtime.sh` as the single canonical load order. Avoid adding
command logic back to the entrypoint or filesystem state checks to
presentation code.

## Regression tests

Add a regression case for every change to:

- CLI option scope or exit status;
- manifest/profile parsing or validation;
- preflight and batch atomicity contracts;
- file/directory deployment or rollback;
- backup, restore, or delete behavior;
- resolver apply/render/equality semantics;
- installed-state checks and installer paths; or
- TUI worker coordination.

Assert semantic state, filesystem effects, and exit codes rather than complete
colored output. Reuse the shared fake project and fake Homebrew implementation
instead of consulting the host system.

## Test a consumer project

Read-only validation can safely target a real consumer checkout:

```bash
/path/to/dotlad/dotlad -C /path/to/project --plain
/path/to/dotlad/dotlad -C /path/to/project plan
```

For deployment tests, use a temporary HOME and config-only mode so package
installation cannot touch the host:

```bash
test_home="$(mktemp -d)"
HOME="$test_home" /path/to/dotlad/dotlad \
    -C /path/to/project --config-only --yes all
```

This still runs declared resolver commands from `PATH`. Stub external
requirements or use a disposable environment for a true end-to-end test.

## Standalone installation

Test the managed layout without touching the real user prefix:

```bash
test_prefix="$(mktemp -d)/prefix"
./install.sh --prefix "$test_prefix"
"$test_prefix/bin/dotlad" --version
./install.sh --prefix "$test_prefix" --uninstall
```

The prefix must be absolute. The installer refuses unmanaged command/runtime
targets, stages and self-checks a complete replacement, and rolls back if the
managed launcher cannot be committed.

## Generated Brewfile

Generate Homebrew Bundle metadata from a consumer project with:

```bash
dotlad -C /path/to/project brewfile
dotlad -C /path/to/project brewfile --output packaging/Brewfile
```

The default output is `Brewfile` in the current working directory. Relative
`--output` paths are resolved from that directory; absolute paths are
preserved. Generated files are derived data—change module manifests instead.

## Build a release archive

```bash
scripts/package.sh
```

The script creates `dist/dotlad-<version>.tar.gz` and a matching SHA-256 file.
Pass another output directory as its only argument when needed. The archive is
a complete source bundle and is validated by the installer integration suite.

`VERSION` is the single source of truth for the CLI and archive name.

## Publish a release

1. Set `VERSION` to the next semantic version.
2. Update user-facing documentation for the release contract.
3. Run `/bin/bash scripts/check.sh` and `/bin/bash tests/run.sh`.
4. Build and inspect the archive with `scripts/package.sh`.
5. Commit the complete release change.
6. Create and push an annotated matching tag:

   ```bash
   git tag -a "v$(cat VERSION)" -m "dotlad $(cat VERSION)"
   git push origin "v$(cat VERSION)"
   ```

The release workflow rejects a tag that differs from `VERSION`, reruns the
integration suite, and publishes the archive plus checksum. It never creates or
moves release tags.

## Change checklist

1. Preserve the trusted runtime / data-only project boundary.
2. Keep macOS Bash 3.2 and ShellCheck compatibility.
3. Preserve destination validation, backups, and transactional writes.
4. Add semantic integration coverage for behavior changes.
5. Update CLI, manifest, profile, resolver, or safety documentation as needed.
6. Run the standard validation.
7. Test both the standalone installer and a submodule consumer before release.
