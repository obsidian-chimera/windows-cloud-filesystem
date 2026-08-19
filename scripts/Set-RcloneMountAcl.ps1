[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ServiceName = 'RcloneGDrive',
    [string]$UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
    [switch]$RestartService
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to change a service mount ACL.'
    }
}

Assert-Administrator

$account = New-Object System.Security.Principal.NTAccount($UserName)
try {
    $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
}
catch {
    throw "Could not resolve Windows account '$UserName' to a SID. $($_.Exception.Message)"
}

$descriptor = "D:P(A;;FA;;;SY)(A;;FA;;;$sid)"
$service = Get-Service -Name $ServiceName -ErrorAction Stop
$serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
$imagePath = (Get-ItemProperty -Path $serviceKey -Name ImagePath -ErrorAction Stop).ImagePath

$securityPattern = '-o\s+FileSecurity=(?:"[^"]*"|\S+)'
$replacement = '-o FileSecurity="{0}"' -f $descriptor

if ($imagePath -match $securityPattern) {
    $newImagePath = $imagePath -replace $securityPattern, $replacement
}
else {
    $newImagePath = "$imagePath $replacement"
}

Write-Host "Target account: $UserName"
Write-Host "FileSecurity: $descriptor"

if ($PSCmdlet.ShouldProcess($ServiceName, 'Restrict WinFsp mount ACL to SYSTEM and selected user')) {
    Set-ItemProperty -Path $serviceKey -Name ImagePath -Value $newImagePath
    Write-Host 'Service ImagePath updated. All unrelated mount arguments were preserved.'

    if ($RestartService) {
        if ($service.Status -eq 'Running') {
            Restart-Service -Name $ServiceName -Force -ErrorAction Stop
        }
        else {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }

        $deadline = (Get-Date).AddSeconds(20)
        do {
            Start-Sleep -Milliseconds 500
            $service.Refresh()
        } while ($service.Status -ne 'Running' -and (Get-Date) -lt $deadline)

        if ($service.Status -ne 'Running') {
            throw "Service '$ServiceName' did not reach Running state."
        }

        if ($newImagePath -match '\bmount\s+\S+\s+([A-Za-z]):') {
            $driveRoot = ('{0}:\' -f $Matches[1].ToUpperInvariant())
            $mountDeadline = (Get-Date).AddSeconds(20)
            while (-not (Test-Path -LiteralPath $driveRoot) -and (Get-Date) -lt $mountDeadline) {
                Start-Sleep -Milliseconds 500
            }

            if (Test-Path -LiteralPath $driveRoot) {
                $acl = Get-Acl -LiteralPath $driveRoot
                $principals = @($acl.Access | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
                $allowed = @('NT AUTHORITY\SYSTEM', $UserName)
                $unexpected = @($principals | Where-Object { $_ -notin $allowed })
                if ($unexpected.Count -gt 0) {
                    throw "Unexpected principals are visible on $driveRoot: $($unexpected -join ', ')"
                }
                Write-Host "Verified mount ACL principals on $driveRoot: $($principals -join ', ')"
            }
            else {
                Write-Warning "Service is running but $driveRoot was not reachable in time; ACL verification was skipped."
            }
        }
    }
}
