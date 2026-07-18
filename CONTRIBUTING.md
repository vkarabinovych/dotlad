# Contributing

Contributions are welcome. Keep changes focused, preserve the safety contracts,
and include regression coverage for behavior changes.

## Development setup

Dotlad targets the stock macOS Bash 3.2. Maintainer checks additionally require
ShellCheck, jq, yq, and Git.

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
3. Keep macOS Bash 3.2 compatibility and shared code ShellCheck-clean.
4. Run the complete validation before opening a pull request.

Use four-space indentation and quote expansions unless splitting is
intentional. Public environment variables use the `DOTLAD_` prefix. Resolver
names are lowercase and hyphenated.

## Pull requests

Use a concise Conventional Commit subject, such as
`fix(engine): preserve directory rollback`. A pull request should describe:

- the user-visible behavior;
- compatibility or safety impact;
- validation performed; and
- any public contract or documentation changes.

Do not include credentials, live configs, restore points, generated archives,
or local test artifacts.
