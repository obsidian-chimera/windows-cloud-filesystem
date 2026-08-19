# Setup Guide

This guide builds the same **mount + VFS cache** architecture used by the case study. It does not create an `rclone bisync` pair and it does not require a full local mirror of Google Drive.

> [!IMPORTANT]
> Test the mount thoroughly before redirecting Windows Known Folders. Keep a normal local Desktop/Documents setup until the service, startup task, writes, remote updates and reboot behaviour are all proven stable.

## 1. Prerequisites

Reference environment:

- Windows 11;
- an administrator account for service/task/ACL setup;
- a normal interactive Windows account, represented below as `<WINDOWS_USER>`;
- Google Drive;
- rclone;
- WinFsp.

Placeholders used throughout the guide:

| Placeholder | Example meaning |
|---|---|
| `<WINDOWS_USER>` | the interactive Windows account to grant access to |
| `<RCLONE_REMOTE>` | the rclone remote name, e.g. `gdrive` |
| `<DRIVE_LETTER>` | one unused drive letter such as `G` |
| `<CONFIG_PATH>` | private path to `rclone.conf` |
| `<CACHE_DIR>` | local VFS cache directory |

Do not paste credentials, OAuth tokens or your real `rclone.conf` into a public terminal capture or repository.

## 2. Install rclone

The official Windows options include downloading the portable executable or using Winget:

```powershell
winget install Rclone.Rclone
```

Official installation documentation: <https://rclone.org/install/>

For a long-lived Windows service, copy the executable to a stable path rather than relying on a versioned package-manager subdirectory:

```powershell
New-Item -ItemType Directory -Force 'C:\Program Files\rclone' | Out-Null
Copy-Item '<PATH_TO_DOWNLOADED_RCLONE_EXE>' 'C:\Program Files\rclone\rclone.exe'
```

Verify:

```powershell
& 'C:\Program Files\rclone\rclone.exe' version
```

## 3. Install WinFsp

`rclone mount` on Windows requires WinFsp. Install WinFsp using its normal installer/package manager, then verify the launcher service exists:

```powershell
Get-Service WinFsp.Launcher
```

The service should be present. It may be running already depending on the installation.

Rclone's Windows mount notes: <https://rclone.org/commands/rclone_mount/>

## 4. Create the private Google Drive remote

Run:

```powershell
rclone config
```

Create a Google Drive remote called `<RCLONE_REMOTE>`. The normal full Drive scope is required if you want the mount to create, edit and delete normal Drive files.

Then verify the remote privately:

```powershell
rclone lsd '<RCLONE_REMOTE>:'
rclone about '<RCLONE_REMOTE>:'
```

Find the config location with:

```powershell
rclone config file
```

Treat the resulting file as `<CONFIG_PATH>`. **Never commit it.**

Google Drive backend documentation: <https://rclone.org/drive/>

## 5. Create cache and log directories

The reference build uses local ProgramData directories so the SYSTEM service can reach them independently of the interactive user's profile:

```powershell
$CacheDir = '<CACHE_DIR>'
$LogDir = 'C:\ProgramData\rclone\logs'

New-Item -ItemType Directory -Force $CacheDir, $LogDir | Out-Null
```

A practical reference value for `<CACHE_DIR>` is `C:\ProgramData\rclone\cache`.

## 6. Test a foreground mount first

Before creating any service, open a normal PowerShell session and test the mount interactively:

```powershell
rclone mount '<RCLONE_REMOTE>:' '<DRIVE_LETTER>:' `
  --config '<CONFIG_PATH>' `
  --cache-dir '<CACHE_DIR>' `
  --vfs-cache-mode full `
  --vfs-cache-max-size 50G `
  --vfs-cache-max-age 7d `
  --vfs-write-back 2s `
  --dir-cache-time 24h `
  --poll-interval 10s `
  --exclude 'desktop.ini' `
  --exclude 'Thumbs.db' `
  --ignore-case `
  --volname 'Google Drive'
```

Open `<DRIVE_LETTER>:` in Explorer and test creating, editing and deleting a disposable text file.

### What the tuning values do

- `--vfs-cache-mode full` — uses local cached files to improve compatibility with applications that seek/read/write like they are using a normal disk.
- `--vfs-cache-max-size 50G` — target ceiling for cached file data; rclone can temporarily exceed this while files are open/in use.
- `--vfs-cache-max-age 7d` — allows inactive cached objects to age out.
- `--vfs-write-back 2s` — after a cached file is closed/inactive, it becomes eligible for write-back after two seconds.
- `--dir-cache-time 24h` — long directory-cache lifetime, with remote polling used to invalidate/update it on supported backends.
- `--poll-interval 10s` — asks supported remotes such as Google Drive for remote changes every ten seconds.

The **2 s and 10 s values are configuration targets, not guarantees**. Application file handles, network/API latency, quotas and server-side processing can add delay.

Stop the foreground mount with `Ctrl+C` before continuing.

## 7. Install the Windows service

Copy the repository's [`scripts/Install-RcloneService.ps1`](../scripts/Install-RcloneService.ps1) to the machine, then run an elevated PowerShell session:

```powershell
.\scripts\Install-RcloneService.ps1 `
  -RemoteName '<RCLONE_REMOTE>' `
  -DriveLetter '<DRIVE_LETTER>' `
  -RcloneExe 'C:\Program Files\rclone\rclone.exe' `
  -ConfigPath '<CONFIG_PATH>' `
  -CacheDirectory '<CACHE_DIR>' `
  -CacheMaxSize '50G' `
  -CacheMaxAge '7d' `
  -WriteBack '2s' `
  -PollInterval '10s'
```

Preview first if desired:

```powershell
.\scripts\Install-RcloneService.ps1 ... -WhatIf
```

The installer intentionally leaves the service as **Manual/demand-start** and does not start it.

## 8. Apply the SYSTEM + user mount ACL

A SYSTEM-hosted WinFsp mount is system-wide, but default compatibility permissions can prevent the normal user from modifying existing files. Restrict the final mount to SYSTEM plus `<WINDOWS_USER>`:

```powershell
.\scripts\Set-RcloneMountAcl.ps1 `
  -ServiceName 'RcloneGDrive' `
  -UserName '<WINDOWS_USER>' `
  -WhatIf

.\scripts\Set-RcloneMountAcl.ps1 `
  -ServiceName 'RcloneGDrive' `
  -UserName '<WINDOWS_USER>'
```

The final WinFsp descriptor grants Full Control to SYSTEM and the selected user's SID only. See [Security hardening](SECURITY-HARDENING.md).

## 9. Protect `rclone.conf`

Run:

```powershell
.\scripts\Protect-RcloneConfig.ps1 `
  -ConfigPath '<CONFIG_PATH>' `
  -UserName '<WINDOWS_USER>' `
  -WhatIf

.\scripts\Protect-RcloneConfig.ps1 `
  -ConfigPath '<CONFIG_PATH>' `
  -UserName '<WINDOWS_USER>'
```

This restricts the config directory/file to the selected user plus SYSTEM without printing the config contents.

## 10. Install network-aware startup

Copy [`scripts/Start-RcloneAfterNetwork.ps1`](../scripts/Start-RcloneAfterNetwork.ps1) to a stable local path such as `C:\ProgramData\rclone\Start-RcloneAfterNetwork.ps1`.

Then adapt and run [`examples/startup-task.example.ps1`](../examples/startup-task.example.ps1) from an elevated PowerShell session. The task runs as SYSTEM at machine startup, waits for DNS and TCP 443 reachability to the Google API endpoint, then starts the manual service.

This avoids a common boot failure where the service starts before DNS/network connectivity is usable.

## 11. Start and verify the mount

Start the service manually once:

```powershell
Start-Service RcloneGDrive
Get-Service RcloneGDrive
Get-PSDrive '<DRIVE_LETTER>'
```

Then run the smoke test:

```powershell
.\scripts\Test-RcloneMount.ps1 `
  -DriveLetter '<DRIVE_LETTER>' `
  -ServiceName 'RcloneGDrive'
```

## 12. Cross-device create/edit test

Create a disposable file on the mounted drive:

```powershell
$TestFile = '<DRIVE_LETTER>:\rclone-cross-device-test.txt'
"Created $(Get-Date -Format o)" | Set-Content $TestFile
"Edited $(Get-Date -Format o)" | Add-Content $TestFile
Get-Content $TestFile
```

After the file is closed and write-back/network processing completes, refresh Google Drive on a phone or in the web UI. Then make a separate remote-side change and allow at least the poll interval plus API/network latency before expecting the mounted view to update.

This is near-real-time file synchronisation, **not collaborative character-by-character editing** like a shared online document editor.

## 13. Delete and recovery behaviour

Google Drive's rclone backend sends deletions to Drive Trash/Bin by default. Keep that default. Do **not** set `--drive-use-trash=false` unless permanent deletion is explicitly intended.

Test with a disposable file and confirm it appears in Google Drive Bin before depending on the behaviour for valuable data.

## 14. Optional Known Folder redirection

Only after several successful boots and write tests, read [`KNOWN-FOLDERS.md`](KNOWN-FOLDERS.md). It includes the startup-race risks and rollback steps.

## 15. Removal / rollback

Preview service removal:

```powershell
.\scripts\Remove-RcloneService.ps1 -WhatIf
```

By default the removal script leaves cloud data, `rclone.conf` and the VFS cache untouched. Optional switches exist for config/cache cleanup and are deliberately separate.

See [`INTEGRATION-CHECKLIST.md`](INTEGRATION-CHECKLIST.md) before treating the setup as production-ready.
