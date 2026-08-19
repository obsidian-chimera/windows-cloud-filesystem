# Security Hardening

The reference architecture mounts Google Drive from a Windows service running as **LocalSystem**. That makes the drive available system-wide, but it changes which Windows principal owns the filesystem view.

## Why the ACL needs explicit attention

Rclone's Windows mount documentation notes two relevant behaviours:

1. a mount created by SYSTEM can be visible to all users on the machine;
2. WinFsp's default compatibility permissions for non-owner accounts may omit Windows permissions such as write extended attributes, which can make otherwise normal applications fail with `Access denied` when modifying existing files.

WinFsp's `FileSecurity` FUSE option allows an explicit Windows SDDL security descriptor to be presented by the mount.

Official rclone Windows mount notes: <https://rclone.org/commands/rclone_mount/>

## Final mount ACL

The recommended final descriptor is conceptually:

```text
D:P(A;;FA;;;SY)(A;;FA;;;<USER_SID>)
```

Where:

- `D:P` — protected DACL;
- `FA` — Full Access;
- `SY` — LocalSystem;
- `<USER_SID>` — the intended Windows user's SID.

Use the repository helper rather than hand-editing a long service command:

```powershell
.\scripts\Set-RcloneMountAcl.ps1 `
  -ServiceName 'RcloneGDrive' `
  -UserName '<WINDOWS_USER>' `
  -WhatIf

.\scripts\Set-RcloneMountAcl.ps1 `
  -ServiceName 'RcloneGDrive' `
  -UserName '<WINDOWS_USER>' `
  -RestartService
```

The script resolves the username to a SID locally and does not need a hardcoded public SID.

## Why `Everyone: FullControl` is not the final state

A temporary descriptor such as:

```text
D:P(A;;FA;;;WD)
```

can be useful **only as a diagnostic** when proving that a permission-denied error comes from WinFsp mount ACL behaviour. `WD` means Everyone, so leaving it in place gives all normal local accounts broad access to the mounted filesystem.

Once diagnosis is complete, replace it with SYSTEM + the intended user only.

## Protect `rclone.conf`

`rclone.conf` can contain OAuth token material. Even when password-like fields are obscured, filesystem access to the config should be treated as sensitive.

Use:

```powershell
.\scripts\Protect-RcloneConfig.ps1 `
  -ConfigPath '<CONFIG_PATH>' `
  -UserName '<WINDOWS_USER>' `
  -WhatIf

.\scripts\Protect-RcloneConfig.ps1 `
  -ConfigPath '<CONFIG_PATH>' `
  -UserName '<WINDOWS_USER>'
```

The script:

- disables inherited ACL entries on the config directory and file;
- grants Full Control only to SYSTEM and the selected user;
- sets the selected user as owner;
- never reads or prints the config contents.

Hardening the directory as well as the current file matters because applications can rewrite configuration via temporary/replacement files that would otherwise inherit weaker directory permissions.

## Local ACLs are not cloud permissions

These controls only govern normal access through the local Windows filesystem and to the local config file. They do **not** change:

- who a Google Drive file is shared with;
- Google account security;
- OAuth scope already granted to rclone.

Review cloud sharing separately.

## Administrator caveat

A local administrator can take ownership, reset ACLs, dump process memory, or otherwise bypass ordinary discretionary access controls. This hardening protects against accidental/casual access by other local accounts; it is not a boundary against a hostile local administrator.

## Credential exposure response

If a token or client secret is ever committed publicly, revoke/rotate it first. Removing it from the latest Git revision is not sufficient because Git history and forks may retain it. See [`../SECURITY.md`](../SECURITY.md).
