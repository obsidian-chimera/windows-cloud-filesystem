# Run in an elevated PowerShell session after copying Start-RcloneAfterNetwork.ps1
# to a stable local path. This registers a machine-startup task under SYSTEM.
#
# If you opt into Windows Known Folder redirection, you may append a MountPath
# argument so the helper waits for a specific cloud-backed folder. That reduces
# the race but does not make early-logon redirection as robust as local NTFS.

$TaskName = 'Rclone Google Drive Early Mount'
$ScriptPath = 'C:\ProgramData\rclone\Start-RcloneAfterNetwork.ps1'
$ServiceName = 'RcloneGDrive'
# Optional example: $MountPath = '<DRIVE_LETTER>:\<PATH_THAT_MUST_EXIST>'

$arguments = @(
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle', 'Hidden',
    '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $ScriptPath),
    '-ServiceName', ('"{0}"' -f $ServiceName)
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Starts the rclone mount service after Google API connectivity is available.' `
    -Force
