# Windows Integration Checklist

Use this on a disposable/tested Windows 11 machine before treating the mount as a daily-driver filesystem. Repository tests intentionally require no live cloud credentials; this checklist covers the real integration boundary.

## Environment

- [ ] Windows 11 machine is fully updated enough for the intended rclone/WinFsp versions.
- [ ] rclone is installed at a **stable path** (not a versioned temporary/package directory).
- [ ] `rclone version` reports the expected build.
- [ ] WinFsp is installed.
- [ ] `Get-Service WinFsp.Launcher` returns the launcher service.
- [ ] Google Drive remote is configured privately with `rclone config`.
- [ ] `rclone.conf` is not inside the Git repository.

## Foreground proof

- [ ] `rclone lsd '<RCLONE_REMOTE>:'` succeeds.
- [ ] `rclone about '<RCLONE_REMOTE>:'` succeeds.
- [ ] Foreground `rclone mount` succeeds before any service is created.
- [ ] Drive letter appears in Explorer.
- [ ] Disposable file can be created, edited, read and deleted.

## Service

- [ ] `Install-RcloneService.ps1 -WhatIf` shows only the intended changes.
- [ ] Service installs without being started automatically.
- [ ] Service startup type is Manual/demand-start.
- [ ] Service ImagePath contains the explicit config/cache/log paths.
- [ ] WinFsp dependency is configured.
- [ ] Recovery actions are configured.

## ACL hardening

- [ ] `Set-RcloneMountAcl.ps1 -WhatIf` resolves the intended user.
- [ ] Final mount descriptor grants Full Control only to SYSTEM + the selected user.
- [ ] `Get-Acl '<DRIVE_LETTER>:\'` shows SYSTEM and the intended account, with no `Everyone` FullControl entry.
- [ ] `Protect-RcloneConfig.ps1 -WhatIf` shows the expected config path.
- [ ] rclone config directory/file are restricted to SYSTEM + selected user.

## Network-aware startup

- [ ] Startup helper is copied to a stable local path.
- [ ] SYSTEM startup task is registered at highest privileges.
- [ ] Startup log shows DNS + TCP 443 readiness before service start.
- [ ] Reboot test: service reaches Running state without manual intervention.
- [ ] `<DRIVE_LETTER>:` appears after reboot.

## Read/write behaviour

- [ ] `Test-RcloneMount.ps1` create/write/append/read/delete smoke test succeeds.
- [ ] A locally created file becomes visible in Google Drive after write-back plus API/network latency.
- [ ] A locally edited closed file becomes visible remotely.
- [ ] A file created remotely becomes visible through the mount after poll interval plus API/network latency.
- [ ] A remote edit is visible after refreshing/reopening the local application where necessary.
- [ ] The test does **not** assume character-by-character collaborative editing.

## Deletion recovery

- [ ] Delete a disposable file through the mount.
- [ ] Confirm Google Drive Bin/Trash receives the normal deletion.
- [ ] Restore the disposable file from Drive Bin and confirm it returns.
- [ ] No `--drive-use-trash=false` setting is present unless permanent deletion is intentionally required.

## Windows integration

- [ ] `desktop.ini` is filtered from the mount view.
- [ ] `Thumbs.db` is filtered from the mount view.
- [ ] Existing files can be modified without `Access denied`.
- [ ] Multiple applications can open representative documents from the mount.

## Optional Known Folders

Only continue if you explicitly want Known Folder redirection.

- [ ] Normal mount has survived several successful reboots first.
- [ ] Original Known Folder registry values are recorded.
- [ ] Local rollback directories exist.
- [ ] One non-critical folder is redirected first and tested.
- [ ] No `Location is not available` error appears at sign-in.
- [ ] If using a mount-path barrier, timeout behaviour has been tested with networking unavailable.
- [ ] Rollback procedure in [`KNOWN-FOLDERS.md`](KNOWN-FOLDERS.md) is understood before redirecting Desktop/Documents.

## Removal safety

- [ ] `Remove-RcloneService.ps1 -WhatIf` shows service removal without deleting cloud data.
- [ ] Default removal leaves config and cache untouched.
- [ ] `-RemoveConfig` and `-RemoveCache` are only used when those local artifacts are intentionally being destroyed.
- [ ] Source-cloud cleanup is never coupled to service removal.
