# Troubleshooting

These cases come from the actual build/migration process. Diagnose the current state before changing architecture; several symptoms can have multiple causes.

## `Location is not available` at sign-in

**Symptom**

Windows reports a redirected Desktop/Documents path on the cloud drive as unavailable, then the folder begins working a few seconds later.

**Likely cause**

Explorer is resolving the Known Folder before the SYSTEM startup task has finished waiting for network connectivity and starting the rclone service.

**Diagnosis**

```powershell
Get-Service RcloneGDrive
Get-PSDrive '<DRIVE_LETTER>' -ErrorAction SilentlyContinue
Get-ScheduledTask | Where-Object TaskName -Match 'Rclone'
Get-Content 'C:\ProgramData\rclone\logs\startup.log' -Tail 30
```

**Fix**

Keep the service Manual/demand-start and use the network-aware SYSTEM startup task. For Known Folders, consider `-MountPath` or a synchronous computer/logon barrier. If the race remains unacceptable, restore the Known Folder to local NTFS.

---

## Google API DNS failure: `no such host`

**Symptom**

Service logs show a Google API request failing because DNS lookup returns `no such host` during boot.

**Likely cause**

The service is starting before Windows networking/DNS is usable.

**Diagnosis**

Compare service start time with startup/network logs. Test after login:

```powershell
Resolve-DnsName www.googleapis.com
Test-NetConnection www.googleapis.com -Port 443
```

**Fix**

Do not make the rclone mount service depend on wishful timing. Leave it Manual and let [`Start-RcloneAfterNetwork.ps1`](../scripts/Start-RcloneAfterNetwork.ps1) start it only after DNS + TCP 443 succeed.

---

## Manual mount works but boot mount fails

**Symptom**

The exact rclone command works interactively, but the service fails at boot.

**Likely cause**

Common causes are early networking, the service running as SYSTEM rather than the interactive user, inaccessible config/cache paths, or a versioned rclone executable path that later changed.

**Diagnosis**

Check:

```powershell
(Get-CimInstance Win32_Service -Filter "Name='RcloneGDrive'").PathName
Get-Service WinFsp.Launcher
Test-Path '<CONFIG_PATH>'
Test-Path 'C:\Program Files\rclone\rclone.exe'
```

Remember that SYSTEM does not automatically use the interactive user's default rclone config; the service command needs an explicit `--config` path.

**Fix**

Use a stable executable path, explicit config/cache/log paths, WinFsp dependency, and network-aware startup.

---

## `desktop.ini` is visible while hidden items are off

**Symptom**

Explorer displays `desktop.ini` in cloud-backed Desktop/Pictures/etc. even though hidden items are disabled.

**Likely cause**

The file is arriving through the cloud mount with ordinary/`Normal` attributes rather than NTFS Hidden/System attributes. Explorer therefore has no hidden attribute to honor.

**Diagnosis**

```powershell
Get-Item '<DRIVE_LETTER>:\Cloud\Desktop\desktop.ini' -Force |
    Select-Object Name,Attributes,Length
```

If `Attributes` is `Normal`, toggling Explorer's hidden-items setting will not help.

**Fix**

Filter the metadata file at the rclone mount layer:

```text
--exclude desktop.ini
--exclude Thumbs.db
--ignore-case
```

This hides the objects from the mounted view without needing Windows attributes to survive the cloud round-trip.

---

## `Access denied` when modifying an existing file

**Symptom**

Creating a file may work, but `Add-Content`, an editor save, or another modification fails with `Access denied` / `UnauthorizedAccessException`.

**Likely cause**

A mount created as SYSTEM is owned by SYSTEM. Default WinFsp compatibility permissions for other users may not include all Windows write permissions applications expect, including write extended attributes.

**Diagnosis**

```powershell
Get-Acl '<DRIVE_LETTER>:\' | Format-List Owner,AccessToString
```

**Fix**

Apply the protected SYSTEM + selected-user FileSecurity descriptor with [`Set-RcloneMountAcl.ps1`](../scripts/Set-RcloneMountAcl.ps1). `Everyone: FullControl` may prove the diagnosis temporarily, but should not remain the final ACL.

---

## OneDrive Personal Vault: `invalidResourceId`

**Symptom**

Migration/listing fails on Personal Vault with an error containing `invalidResourceId` or `ObjectHandle is Invalid`.

**Likely cause**

OneDrive's API traversal of Personal Vault is failing independently of ordinary folders.

**Diagnosis**

List the root and ordinary subfolders separately. If normal folders work and Vault traversal alone fails, isolate it from the main migration path.

**Fix**

For a root migration, explicitly exclude it:

```text
--exclude "/Personal Vault/**"
```

Then handle/verify Vault separately. Never use the exclusion without recording that data was intentionally omitted.

---

## OneDrive delta / malformed drive ID errors

**Symptom**

Deep recursive operations fail with malformed drive/resource IDs, while direct `rclone lsf` of the same folder succeeds.

**Likely cause**

The recursive ListR/delta path is the unstable part, not the directory's contents.

**Diagnosis**

Compare a recursive operation with a direct listing of the failing directory.

**Fix**

Retry the migration/listing with:

```text
--disable ListR
```

This can be slower but avoids the problematic recursive listing path.

---

## `No common hash found` during `rclone check`

**Symptom**

Cross-provider verification says `No common hash found`.

**Likely cause**

The two storage backends do not expose the same compatible checksum for all compared objects.

**Diagnosis**

Review each backend's documented hash support.

**Fix**

Use `rclone check --size-only` for path/size parity, understanding its limitation. For stronger validation of a sample, consider `--download` and accept the bandwidth/time cost.

---

## Mount works but a preview application fails

**Symptom**

Explorer can browse the mount and other applications open the file, but one preview/PDF/media application errors.

**Likely cause**

The application itself may have a compatibility/cache problem rather than the mount being broken.

**Diagnosis**

Open the same file with a second application and copy/read it through PowerShell. Check rclone logs for an actual filesystem error before changing mount options.

**Fix**

If multiple independent reads succeed and rclone logs are clean, troubleshoot the application first.

---

## Stale OneDrive shell extension after uninstall

**Symptom**

OneDrive is uninstalled but a DLL or shell integration remains locked by `explorer.exe`, preventing cleanup.

**Likely cause**

Explorer has loaded the old FileSync shell extension into its process.

**Diagnosis**

Use Windows process/module tools to identify whether Explorer owns the lock.

**Fix**

After confirming OneDrive itself is no longer running, restart Explorer (or reboot), then remove the stale application directory. Do not delete the old synced-data directory until the migrated cloud copy has been verified and observed in normal use.
