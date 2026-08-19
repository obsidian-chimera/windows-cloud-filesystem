[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [string]$ServiceName = 'RcloneGDrive',
    [string]$StartupTaskName = 'Rclone Google Drive Early Mount',
    [switch]$RemoveStartupTask,
    [switch]$RemoveConfig,
    [switch]$RemoveCache,
    [string]$ConfigPath = "$env:APPDATA\rclone\rclone.conf",
    [string]$CacheDirectory = 'C:\ProgramData\rclone\cache'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to remove a Windows service or SYSTEM task.'
    }
}

function Invoke-ScDelete {
    param([Parameter(Mandatory)][string]$Name)
    & sc.exe delete $Name | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe delete failed for '$Name' with exit code $LASTEXITCODE."
    }
}

Assert-Administrator

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    if ($PSCmdlet.ShouldProcess($ServiceName, 'Stop and delete rclone mount service')) {
        if ($service.Status -ne 'Stopped') {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
        }
        Invoke-ScDelete -Name $ServiceName
    }
}
else {
    Write-Host "Service '$ServiceName' was not found."
}

if ($RemoveStartupTask) {
    $task = Get-ScheduledTask -TaskName $StartupTaskName -ErrorAction SilentlyContinue
    if ($task -and $PSCmdlet.ShouldProcess($StartupTaskName, 'Unregister SYSTEM startup task')) {
        Unregister-ScheduledTask -TaskName $StartupTaskName -Confirm:$false
    }
}

if ($RemoveConfig) {
    Write-Warning "-RemoveConfig will delete the rclone configuration file: $ConfigPath"
    if ((Test-Path -LiteralPath $ConfigPath) -and $PSCmdlet.ShouldProcess($ConfigPath, 'Delete rclone configuration file')) {
        Remove-Item -LiteralPath $ConfigPath -Force
    }
}

if ($RemoveCache) {
    Write-Warning "-RemoveCache will recursively delete the rclone cache directory: $CacheDirectory"
    if ((Test-Path -LiteralPath $CacheDirectory) -and $PSCmdlet.ShouldProcess($CacheDirectory, 'Delete rclone cache directory recursively')) {
        Remove-Item -LiteralPath $CacheDirectory -Recurse -Force
    }
}

if (-not $RemoveConfig -and -not $RemoveCache) {
    Write-Host 'Configuration and cache were preserved. No cloud data was deleted by this script.'
}
