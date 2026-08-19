# Optional Windows Known Folder Redirection

> [!WARNING]
> This is the most fragile part of the design. Prove the rclone mount across normal writes, remote changes and multiple reboots **before** redirecting Desktop, Documents, Pictures, Music or Videos.

## What this changes

Windows stores paths for shell Known Folders in the current user's profile configuration. Redirecting a folder such as Desktop to the mounted cloud drive means Explorer and applications expect that mount to exist during logon.

A generic target might look like:

```text
<DRIVE_LETTER>:\Cloud\Desktop
```

The reference build redirected several Known Folders only after the mount itself was stable.

## The early-logon race

The important failure mode is:

```text
Windows logon / Explorer
        ↓
resolve Desktop path
        ↓
cloud drive not mounted yet
        ↓
"Location is not available"
```

A few seconds later the mount may appear and the Desktop may then work, but the error is still a sign that startup ordering is wrong.

The repository's [`Start-RcloneAfterNetwork.ps1`](../scripts/Start-RcloneAfterNetwork.ps1) waits for DNS and HTTPS connectivity before starting the rclone service. Its optional `-MountPath` barrier can then wait for a specific path to appear.

This reduces timing problems but does not make a network/cloud mount as early-boot-safe as local NTFS.

## Recommended sequence

1. Keep Known Folders local during initial setup.
2. Verify foreground mount.
3. Verify service mount.
4. Verify SYSTEM + user ACL.
5. Verify network-aware startup after several reboots.
6. Verify local → cloud and cloud → local updates.
7. Create the intended remote folder structure.
8. Redirect **one** non-critical Known Folder first.
9. Reboot and test before redirecting more.

## Inspect current Known Folder paths

Common values live under:

```text
HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders
```

Useful value names include:

```text
Desktop
Personal        # Documents
My Pictures
My Music
My Video
```

Record the original values before modifying anything.

## Example redirection pattern

Use your own intended path; do not copy this literally:

```powershell
$Base = '<DRIVE_LETTER>:\Cloud'
$Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'

Set-ItemProperty $Key -Name 'Desktop' -Value (Join-Path $Base 'Desktop')
Set-ItemProperty $Key -Name 'Personal' -Value (Join-Path $Base 'Documents')
```

Sign out/restart Explorer or reboot to let shell components re-read the values.

## Stronger startup coordination

For a redirected Desktop, configure the startup helper with a mount-path barrier such as:

```text
<DRIVE_LETTER>:\Cloud\Desktop
```

The helper has a finite timeout so a cloud outage does not block startup forever. If Windows still initializes Explorer before the barrier has taken effect, use a computer-startup/logon policy that explicitly waits for the mount or reconsider redirecting that folder.

## Rollback: restore local Known Folders

Keep this procedure available before you redirect anything.

Typical local targets are:

```text
%USERPROFILE%\Desktop
%USERPROFILE%\Documents
%USERPROFILE%\Pictures
%USERPROFILE%\Music
%USERPROFILE%\Videos
```

A generic rollback in PowerShell:

```powershell
$Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'

Set-ItemProperty $Key -Name 'Desktop' -Value '%USERPROFILE%\Desktop'
Set-ItemProperty $Key -Name 'Personal' -Value '%USERPROFILE%\Documents'
Set-ItemProperty $Key -Name 'My Pictures' -Value '%USERPROFILE%\Pictures'
Set-ItemProperty $Key -Name 'My Music' -Value '%USERPROFILE%\Music'
Set-ItemProperty $Key -Name 'My Video' -Value '%USERPROFILE%\Videos'
```

Ensure the local directories exist, then sign out/reboot. Verify each folder resolves locally before disabling/removing the cloud mount.

### Data rollback is separate from path rollback

Changing the registry path does not automatically copy cloud files back to local storage. If you want a full local copy, copy/download it deliberately **before** removing the mount. Do not assume a path change migrates data.
