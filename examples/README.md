# Example Dotlad project

This directory is a complete, read-only-friendly Dotlad project showing the
main manifest patterns:

- `copy-file` copies one file exactly;
- `directory-mirror` owns and mirrors a directory tree;
- `json-merge` overlays repository JSON while retaining machine-local keys;
- `multi-config` deploys two files from one tool with different resolvers;
- `package-only` installs packages without managing configuration.

Use `examples/.tmp` as the example project's isolated home. The directory is
ignored by the local `.gitignore`:

```bash
example_home="$(cd examples && pwd)/.tmp"
HOME="$example_home" examples/mydot --plain
HOME="$example_home" examples/mydot plan profile base
HOME="$example_home" examples/mydot plan multi-config --json
```

The local `mydot` wrapper sets the command name to `mydot`, the display name to
`My Dotfiles`, the project root to this directory, and the backup root to
`examples/.tmp/backups`. Set `DOTLAD_EXAMPLE_BIN` only when the runtime is
somewhere other than `../dotlad`.

With that `HOME`, every manifest destination resolves below
`examples/.tmp/output`. To try deployment:

```bash
HOME="$example_home" examples/mydot --config-only --yes multi-config
find "$example_home/output" -maxdepth 3 -print
```

The `json-merge` example requires `jq`. The package-only example is intended
for planning and documentation; applying it asks Homebrew to install its
declared formulae.
