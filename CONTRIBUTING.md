# Contributing

> [!IMPORTANT]
> Dotlad is a personal project maintained primarily for the author's own use.
>
> - It is not actively seeking public contributions.
> - There is no review or merge timeline.
> - Forks are welcome for different workflows or priorities.

This document records the development discipline used by the maintainer and
recommended for downstream changes.

## Development setup

Dotlad targets macOS, Linux, and WSL while retaining compatibility with the
stock macOS Bash 3.2. Maintainer checks additionally require ShellCheck,
shfmt, jq, yq, and Git.

```bash
git clone https://github.com/vkarabinovych/dotlad.git
cd dotlad
/bin/bash scripts/check.sh
/bin/bash tests/run.sh
```

The integration suite uses an isolated project, HOME, application directory,
and package prefix. Tests must not read or modify live user configuration.

## Making a change

1. Read [docs/architecture.md](docs/architecture.md) and the relevant reference
   documentation.
2. Add a semantic regression case for changes to manifests, resolvers,
   deployment, backups, workers, safety checks, or CLI exit behavior.
3. Keep macOS Bash 3.2, Linux, and WSL compatibility and shared code
   ShellCheck-clean.
4. Run the complete validation before considering the change complete.

Use four-space indentation and quote expansions unless splitting is
intentional. Public environment variables use the `DOTLAD_` prefix. Resolver
names are lowercase and hyphenated. Run `shfmt -w .` from the repository root
after editing shell sources; its project options live in `.editorconfig`.

## Change discipline

Use a concise Conventional Commit subject, such as
`fix(engine): preserve directory rollback`. A change should record:

- the user-visible behavior;
- compatibility or safety impact;
- validation performed; and
- any public contract or documentation changes.

Do not include credentials, live configs, restore points, generated archives,
or local test artifacts.
