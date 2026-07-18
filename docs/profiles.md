# Profiles

Profiles are optional, reusable tool selections. They provide named setups
for automation and onboarding while the interactive picker remains available
for one-off choices.

## File format

A profile is a strict assignment file under `profiles/`:

```bash
# profiles/workstation.conf
extends="base"
tools="ghostty nvim dev-tools"
```

Only two fields are accepted:

| Field     | Required | Meaning                                               |
| --------- | -------- | ----------------------------------------------------- |
| `extends` | no       | One parent profile name                               |
| `tools`   | no       | Space-separated tool names introduced by this profile |

Use an empty value when a root profile has no parent:

```bash
# profiles/base.conf
extends=""
tools="zsh git search-tools"
```

Profile files use the same non-executable value syntax as tool manifests.
Duplicate or unknown fields, command substitutions, and backticks are rejected.
Every listed tool must exist. A profile may introduce no tools when it only
inherits its parent's selection.

## Inheritance

Inheritance is single-parent and recursive. For example:

```text
base
└── workstation
    └── complete
```

Each file should list only the tools introduced at that level. When Dotlad
resolves `complete`, parent tools come first and duplicate names are removed
while preserving declaration order.

Choose names around user outcomes rather than Dotlad internals. A team might
use `base`, `developer`, and `ci`; a personal project might use `terminal` and
`desktop`. Dotlad does not assign special meaning to any profile name.

## Apply or plan a profile

```bash
dotlad -C /path/to/project plan profile workstation
dotlad -C /path/to/project profile workstation
```

The plan is read-only. Applying a profile shows one confirmation for the
resolved selection and then preflights the entire batch before making changes.

Operation modes filter the resolved tools:

```bash
dotlad -C /path/to/project plan profile workstation --packages-only
dotlad -C /path/to/project profile workstation --config-only
```

A tool that has no action in the active mode is omitted. A profile resolving
to no applicable tools is rejected instead of silently succeeding.

## Add a profile

1. Create `profiles/<name>.conf` with a short lowercase hyphenated name.
2. Set `extends` to one existing parent or an empty string.
3. List only tools introduced at this level.
4. Run `dotlad -C /path/to/project plan profile <name>`.
5. Apply it only in an isolated HOME or disposable machine during testing.
6. Document the profile in the consumer project's README when users should
   discover it.

Add a tool to the lowest profile whose users should receive it. Avoid
repeating inherited tools, even though resolution deduplicates them, because
repetition obscures ownership.

## Validation failures

Profile resolution fails for:

- a missing or symlinked profile file;
- a missing or symlinked `profiles/` directory;
- unknown fields or unsafe assignment syntax;
- an unknown tool;
- a missing parent profile; or
- an inheritance cycle.

For Dotlad runtime changes, add integration coverage when changing inheritance,
deduplication, tool validation, or mode filtering, then run:

```bash
/bin/bash scripts/check.sh
/bin/bash tests/run.sh
```
