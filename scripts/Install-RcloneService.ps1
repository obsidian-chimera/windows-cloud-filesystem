[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RemoteName = 'gdrive',
    [ValidatePattern('^[A-Z]$')][string]$DriveLetter = 'G',
    [string]$RcloneExe = 'C:\Program Files\rclone\rclone.exe',
    [string]$ConfigPath = "$env:APPDATA\rclone\rclone.conf",
    [string]$CacheDirectory = 'C:\ProgramData\rclone\cache',
    [string]$CacheMaxSize = '50G',
    [string]$CacheMaxAge = '7d',
    [string]$WriteBack = '2s',
    [string]$PollInterval = '10s',
    [string]$VolumeName = 'Google Drive',
    [string]$ServiceName = 'RcloneGDrive',
    [string]$LogDirectory = 'C:\ProgramData\rclone\logs'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to install or update a Windows service.'
    }
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description was not found: $Path"
    }
}

function Assert-WinFspAvailable {
    $launcher = Get-Service -Name 'WinFsp.Launcher' -ErrorAction SilentlyContinue
    if (-not $launcher) {
        throw 'WinFsp.Launcher was not found. Install WinFsp before installing an rclone mount service.'
    }
    return $launcher
}

function Quote-CommandArgument {
    param([Parameter(Mandatory)][string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function New-RcloneImagePath {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Remote,
        [Parameter(Mandatory)][string]$MountDrive,
        [Parameter(Mandatory)][string]$Config,
        [Parameter(Mandatory)][string]$CacheDir,
        [Parameter(Mandatory)][string]$CacheSize,
        [Parameter(Mandatory)][string]$CacheAge,
        [Parameter(Mandatory)][string]$WriteBackDelay,
        [Parameter(Mandatory)][string]$RemotePollInterval,
        [Parameter(Mandatory)][string]$MountVolumeName,
        [Parameter(Mandatory)][string]$LogDir
    )

    $arguments = @(
        'mount',
        ("{0}:" -f $Remote.TrimEnd(':')),
        ("{0}:" -f $MountDrive),
        '--config', (Quote-CommandArgument $Config),
        '--cache-dir', (Quote-CommandArgument $CacheDir),
        '--vfs-cache-mode', 'full',
        '--vfs-cache-max-size', $CacheSize,
        '--vfs-cache-max-age', $CacheAge,
        '--vfs-write-back', $WriteBackDelay,
        '--dir-cache-time', '24h',
        '--poll-interval', $RemotePollInterval,
        '--volname', (Quote-CommandArgument $MountVolumeName),
        '--exclude', (Quote-CommandArgument 'desktop.ini'),
        '--exclude', (Quote-CommandArgument 'Thumbs.db'),
        '--ignore-case',
        '--log-file', (Quote-CommandArgument (Join-Path $LogDir 'mount.log')),
        '--log-level', 'INFO'
    )

    return (Quote-CommandArgument $Executable) + ' ' + ($arguments -join ' ')
}

function Invoke-Sc {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & sc.exe @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe failed with exit code $LASTEXITCODE: sc.exe $($Arguments -join ' ')"
    }
}

Assert-Administrator
Assert-PathExists -Path $RcloneExe -Description 'rclone executable'
Assert-PathExists -Path $ConfigPath -Description 'rclone configuration file'
$winFsp = Assert-WinFspAvailable

$imagePath = New-RcloneImagePath `
    -Executable $RcloneExe `
    -Remote $RemoteName `
    -MountDrive $DriveLetter `
    -Config $ConfigPath `
    -CacheDir $CacheDirectory `
    -CacheSize $CacheMaxSize `
    -CacheAge $CacheMaxAge `
    -WriteBackDelay $WriteBack `
    -RemotePollInterval $PollInterval `
    -MountVolumeName $VolumeName `
    -LogDir $LogDirectory

$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$action = if ($existing) { 'Update rclone mount service' } else { 'Create rclone mount service' }

if ($PSCmdlet.ShouldProcess($ServiceName, $action)) {
    New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

    if (-not $existing) {
        New-Service `
            -Name $ServiceName `
            -BinaryPathName $imagePath `
            -DisplayName 'rclone cloud filesystem mount' `
            -Description 'Mounts a configured rclone remote through WinFsp.' `
            -StartupType Manual `
            -DependsOn $winFsp.Name | Out-Null
    }
    else {
        if ($existing.Status -eq 'Running') {
            Write-Warning "$ServiceName is running. Stop it before restarting with the updated ImagePath."
        }
        $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
        Set-ItemProperty -Path $serviceKey -Name ImagePath -Value $imagePath
        Set-Service -Name $ServiceName -StartupType Manual
        Invoke-Sc -Arguments @('config', $ServiceName, 'depend=', $winFsp.Name)
    }

    Invoke-Sc -Arguments @('failure', $ServiceName, 'reset=', '86400', 'actions=', 'restart/5000/restart/15000/restart/60000')
    Invoke-Sc -Arguments @('failureflag', $ServiceName, '1')

    Write-Host "Configured $ServiceName as a manual/demand-start service."
    Write-Host 'The service was not started. Apply mount ACL hardening before normal use.'
}
else {
    Write-Host "Would configure service '$ServiceName' with ImagePath:"
    Write-Host $imagePath
}
