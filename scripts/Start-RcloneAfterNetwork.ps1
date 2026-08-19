[CmdletBinding()]
param(
    [string]$ServiceName = 'RcloneGDrive',
    [string]$ApiHost = 'www.googleapis.com',
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 120,
    [string]$MountPath,
    [string]$LogPath = 'C:\ProgramData\rclone\logs\startup.log'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-StartupLog {
    param([Parameter(Mandatory)][string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

$logDirectory = Split-Path -Parent $LogPath
if ($logDirectory) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
Write-StartupLog "Startup network check started for $ApiHost."

$networkReady = $false
while ((Get-Date) -lt $deadline) {
    $dnsReady = $false
    $httpsReady = $false

    try {
        $dnsReady = [bool](Resolve-DnsName -Name $ApiHost -ErrorAction Stop | Select-Object -First 1)
    }
    catch {
        $dnsReady = $false
    }

    if ($dnsReady) {
        try {
            $httpsReady = [bool](Test-NetConnection -ComputerName $ApiHost -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue)
        }
        catch {
            $httpsReady = $false
        }
    }

    if ($dnsReady -and $httpsReady) {
        $networkReady = $true
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $networkReady) {
    Write-StartupLog "Timed out after $TimeoutSeconds seconds waiting for DNS and TCP 443 to $ApiHost."
    exit 1
}

Write-StartupLog 'Google API endpoint is reachable.'

try {
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($service.Status -ne 'Running') {
        Start-Service -Name $ServiceName -ErrorAction Stop
        Write-StartupLog "Start requested for service $ServiceName."
    }
    else {
        Write-StartupLog "Service $ServiceName is already running."
    }
}
catch {
    Write-StartupLog "Failed to start service $ServiceName: $($_.Exception.Message)"
    exit 1
}

if ($MountPath) {
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $MountPath) {
            Write-StartupLog "Mount barrier is ready: $MountPath"
            exit 0
        }
        Start-Sleep -Milliseconds 500
    }

    Write-StartupLog "Timed out waiting for mount path: $MountPath"
    exit 1
}

Write-StartupLog 'Startup completed successfully.'
exit 0
