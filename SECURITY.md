# Security Policy

This repository intentionally contains **no live cloud credentials**. Treat the rclone configuration as a secret-bearing file even when individual password fields appear obscured.

## Never publish

Do not commit or paste any of the following into issues, pull requests, screenshots, logs, or examples:

- `rclone.conf`;
- OAuth access or refresh tokens;
- Google/Microsoft client secrets;
- OneDrive or Google Drive credentials;
- private cloud paths that reveal personal information;
- Windows account SIDs or machine-specific identifiers;
- raw logs containing account names, paths, remote IDs, or tokens.

The `.gitignore` is a convenience guard, not a substitute for reviewing staged changes before every public push.

## If a credential is exposed

Deleting the file or rewriting the Git commit is **not enough**. Assume the secret may already have been copied. Revoke/rotate the affected OAuth token or client secret first, then purge the secret from Git history and any downstream mirrors.

## Local hardening

The reference build restricts the mounted filesystem and rclone configuration to the intended Windows user plus `NT AUTHORITY\SYSTEM`. This reduces accidental access by other local accounts, but a local administrator can still take ownership or change ACLs. Local ACLs are also separate from Google Drive sharing permissions.

For the hardening procedure, see [`docs/SECURITY-HARDENING.md`](docs/SECURITY-HARDENING.md).
