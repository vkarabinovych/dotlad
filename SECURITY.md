# Security policy

## Supported versions

No version is formally supported. Security fixes may be published for the
current development line at the maintainer's discretion, without a response,
remediation, or release timeline.

## Report a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
[security advisory form](https://github.com/ter-sh/dotlad/security/advisories/new)
and include:

- the affected version and command;
- the manifest or filesystem shape required to reproduce the issue;
- the expected and observed safety boundary; and
- a minimal reproduction with secrets and personal paths removed.

Reports involving destination escapes, symlink traversal, unsafe pruning,
backup corruption, remote installer execution, or manifest code execution are
especially important. Reports are reviewed on a best-effort basis.

Please allow time for a fix and coordinated release before public disclosure.
