# Security policy

## Supported versions

Security fixes are provided for the latest release only.

## Report a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
[security advisory form](https://github.com/vkarabinovych/dotlad/security/advisories/new)
and include:

- the affected version and command;
- the manifest or filesystem shape required to reproduce the issue;
- the expected and observed safety boundary; and
- a minimal reproduction with secrets and personal paths removed.

Reports involving destination escapes, symlink traversal, unsafe pruning,
backup corruption, remote installer execution, or manifest code execution are
especially important. You should receive an initial response within seven
days.

Please allow time for a fix and coordinated release before public disclosure.
