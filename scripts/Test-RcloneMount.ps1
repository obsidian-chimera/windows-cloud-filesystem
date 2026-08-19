[CmdletBinding()]
param(
    [ValidatePattern('^[A-Z]$')][string]$DriveLetter = 'G',
    [string]$ServiceName = 'RcloneGDrive',
    [ValidateRange(0, 120)][int]$UploadObservationSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$service = Get-Service -Name $ServiceName -ErrorAction Stop
if ($service.Status -ne 'Running') {
    throw "Service '$ServiceName' exists but is not Running (status: $($service.Status))."
}

$driveRoot = ('{0}:\' -f $DriveLetter)
if (-not (Test-Path -LiteralPath $driveRoot)) {
    throw "Mounted drive root is not reachable: $driveRoot"
}

$testFile = Join-Path $driveRoot ('.rclone-mount-test-{0}.txt' -f ([guid]::NewGuid().ToString('N')))
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $first = 'first write: {0:o}' -f (Get-Date)
    Set-Content -LiteralPath $testFile -Value $first -Encoding UTF8

    $second = 'second write: {0:o}' -f (Get-Date)
    Add-Content -LiteralPath $testFile -Value $second -Encoding UTF8

    $content = @(Get-Content -LiteralPath $testFile)
    if ($content -notcontains $first -or $content -notcontains $second) {
        throw 'Local read-back did not contain both written lines.'
    }

    Write-Host ('Create/append/read succeeded in {0:N0} ms.' -f $stopwatch.Elapsed.TotalMilliseconds)

    if ($UploadObservationSeconds -gt 0) {
        Write-Host "Waiting $UploadObservationSeconds seconds as an observation window for VFS write-back."
        Start-Sleep -Seconds $UploadObservationSeconds
    }

    Write-Host 'Local mount smoke test passed. This does not independently prove remote upload or trash behaviour.'
}
finally {
    if (Test-Path -LiteralPath $testFile) {
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path -LiteralPath $testFile) {
    throw "Temporary test file still exists after deletion: $testFile"
}

Write-Host 'Temporary test file disappeared from the mounted view.'
